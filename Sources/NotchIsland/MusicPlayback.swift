import AppKit
import ApplicationServices
import Combine
import os

struct PlayingTrack: Equatable {
    var source: String
    var title: String
    var artist: String
    var playing: Bool
    var elapsed: Double
    var duration: Double
    var artwork: Data? = nil
    var artworkPage: URL? = nil
    var captureTarget: MusicArtworkTarget? = nil
    var canSeek: Bool { source == "com.apple.Music" }
    var key: String { source + "|" + title + "|" + artist }
    static func seconds(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":")
        guard (2...3).contains(parts.count), parts.allSatisfy({ Int($0) != nil }) else { return nil }
        return parts.reduce(0) { $0 * 60 + Double($1)! }
    }
}
enum MusicCommand { case toggle, next, previous, seek(Double) }

// Each adapter uses the player's own supported interface. No MediaRemote entitlement spoofing.
final class AppleMusicAdapter {
    private var denied = false
    private var coverKey = ""
    private var coverData: Data?
    private var coverRetry = Date.distantPast
    func resetPermission() { denied = false }
    func read() -> PlayingTrack? {
        guard !denied else { return nil }
        let script = """
        with timeout of 2 seconds
          tell application id "com.apple.Music"
            if player state is stopped then return {"Apple Music", "", "stopped", 0, 0}
            set t to current track
            return {name of t, artist of t, player state as string, player position, duration of t}
          end tell
        end timeout
        """
        guard let result = run(script), result.numberOfItems >= 5 else { return nil }
        let key = (result.atIndex(1)?.stringValue ?? "") + "|" + (result.atIndex(2)?.stringValue ?? "")
        if key != coverKey || (coverData == nil && Date() >= coverRetry) {
            coverKey = key; coverRetry = Date().addingTimeInterval(8)
            let cover = run("with timeout of 2 seconds\ntell application id \"com.apple.Music\" to get raw data of artwork 1 of current track\nend timeout")
            coverData = cover?.data
            if coverData.flatMap(NSImage.init(data:)) == nil { coverData = nil }
        }
        return PlayingTrack(source: "com.apple.Music", title: result.atIndex(1)?.stringValue ?? "", artist: result.atIndex(2)?.stringValue ?? "",
                            playing: result.atIndex(3)?.stringValue == "playing", elapsed: result.atIndex(4)?.doubleValue ?? 0,
                            duration: result.atIndex(5)?.doubleValue ?? 0, artwork: coverData)
    }
    func command(_ command: MusicCommand) {
        let action: String
        switch command {
        case .toggle: action = "playpause"
        case .next: action = "next track"
        case .previous: action = "back track"
        case .seek(let seconds): guard seconds.isFinite else { return }; action = "set player position to \(max(0, seconds))"
        }
        _ = run("with timeout of 2 seconds\ntell application id \"com.apple.Music\" to \(action)\nend timeout")
    }
    private func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if (error?[NSAppleScript.errorNumber] as? Int) == -1743 { denied = true }
        return error == nil ? result : nil
    }
}

final class AccessibleMusicAdapter {
    private var roots: [String: AXUIElement] = [:]
    private let logger = Logger(subsystem: "NotchIsland", category: "Music")
    private var lastDiagnostic = ""
    private var diagnosticTimes: [String: Date] = [:]
    private var activatedPIDs = Set<pid_t>()
    private func diagnose(_ message: String) {
        guard lastDiagnostic != message, Date().timeIntervalSince(diagnosticTimes[message] ?? .distantPast) >= 30 else { return }
        diagnosticTimes[message] = Date()
        lastDiagnostic = message
        logger.notice("\(message, privacy: .public)")
    }
    private var processIDs: [String: pid_t] = [:]
    private var discoveryRetry: [String: Date] = [:]
    private var controls: [String: [String: AXUIElement]] = [:]
    private func value(_ node: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(node, key as CFString, &result) == .success else { return nil }
        return result
    }
    private func text(_ node: AXUIElement) -> String {
        [kAXDescriptionAttribute, kAXTitleAttribute, kAXValueAttribute].compactMap { value(node, $0) as? String }.first { !$0.isEmpty } ?? ""
    }
    private func nodes(_ root: AXUIElement, limit: Int, fromEnd: Bool = false) -> [AXUIElement] {
        var pending = [root], result: [AXUIElement] = []
        let deadline = Date().addingTimeInterval(0.4)
        while !pending.isEmpty && result.count < limit && Date() < deadline {
            let node = pending.removeLast(); result.append(node)
            let children = (value(node, kAXChildrenAttribute) as? [AXUIElement]) ?? []
            pending += fromEnd ? children : Array(children.reversed())
        }
        return result
    }
    func read(id: String, pid: pid_t) -> PlayingTrack? {
        guard AXIsProcessTrusted() else { diagnose("AX permission denied"); return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        let yandex = id == "ru.yandex.desktop.music"
        if processIDs[id] != pid {
            roots[id] = nil; controls[id] = nil; discoveryRetry[id] = nil
            processIDs[id] = pid
        }
        if roots[id] == nil {
            guard Date() >= (discoveryRetry[id] ?? .distantPast) else { return nil }
            discoveryRetry[id] = Date().addingTimeInterval(2)
            let windows = (value(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
            if yandex && !activatedPIDs.contains(pid) {
                // Request Chromium's complete native accessibility mode once per process.
                // https://www.chromium.org/developers/design-documents/accessibility/
                _ = value(app, kAXRoleAttribute)
                let manual = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
                let enhanced = AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
                for window in windows {
                    AXUIElementSetAttributeValue(window, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
                }
                diagnose("Yandex activation manual=\(manual.rawValue) enhanced=\(enhanced.rawValue)")
                if manual == .success || enhanced == .success { activatedPIDs.insert(pid) }
                // Renderer builds its tree asynchronously; read it on the next poll.
                return nil
            }
            for window in windows {
                let all = nodes(window, limit: 2200, fromEnd: true)
                if yandex { diagnose("Yandex discovery nodes: \(all.count)") }
                if yandex {
                    roots[id] = all.first { text($0) == "Плеер" && (value($0, kAXRoleAttribute) as? String) != kAXStaticTextRole }
                } else {
                    roots[id] = all.first {
                        guard let url = value($0, kAXURLAttribute) as? URL else { return false }
                        return ["www.youtube.com", "youtube.com", "m.youtube.com"].contains(url.host ?? "") && url.path == "/watch"
                    }
                }
                if roots[id] != nil { break }
            }
        }
        guard let root = roots[id] else { if yandex { diagnose("Yandex player root missing") }; return nil }
        let all = nodes(root, limit: yandex ? 160 : 1800)
        guard all.count > 1 else { roots[id] = nil; controls[id] = nil; return nil }
        if yandex { diagnose("Yandex player nodes: \(all.count)") }
        let buttons = all.filter { (value($0, kAXRoleAttribute) as? String) == kAXButtonRole }
        let pause = buttons.first { yandex ? text($0) == "Пауза" : ["Pause (k)", "Пауза (k)"].contains(text($0)) }
        let play = buttons.first { yandex ? text($0) == "Воспроизведение" : ["Play (k)", "Смотреть (k)", "Воспроизвести (k)"].contains(text($0)) }
        guard let toggle = pause ?? play else { roots[id] = nil; controls[id] = nil; return nil }
        var title = "", artist = "", page: URL?
        var duration: Double = 0, elapsed: Double = 0
        var captureTarget: MusicArtworkTarget?
        if yandex {
            if let cover = buttons.first(where: { text($0) == "На весь экран" }),
               let rawPoint = value(cover, kAXPositionAttribute), let rawSize = value(cover, kAXSizeAttribute),
               CFGetTypeID(rawPoint) == AXValueGetTypeID(), CFGetTypeID(rawSize) == AXValueGetTypeID() {
                var point = CGPoint.zero, size = CGSize.zero
                if AXValueGetValue(rawPoint as! AXValue, .cgPoint, &point), AXValueGetValue(rawSize as! AXValue, .cgSize, &size) {
                    let rect = CGRect(origin: point, size: size)
                    if MusicArtworkTarget.valid(rect) { captureTarget = MusicArtworkTarget(pid: pid, rect: rect) }
                }
            }
            let links = all.filter { (value($0, kAXRoleAttribute) as? String) == "AXLink" }
            if let track = links.first(where: { text($0).hasPrefix("Трек ") }) {
                title = String(text(track).dropFirst(5)).trimmingCharacters(in: .whitespaces)

            }
            artist = links.filter { text($0).hasPrefix("Артист ") }.map { String(text($0).dropFirst(7)) }.joined(separator: ", ")
            let times = all.filter { (value($0, kAXRoleAttribute) as? String) == kAXStaticTextRole }.compactMap { PlayingTrack.seconds(text($0)) }
            if times.count >= 2 { elapsed = times[0]; duration = times[1] }
        } else {
            let headings = all.filter { (value($0, kAXRoleAttribute) as? String) == "AXHeading" }
            title = headings.map(text).first { !$0.isEmpty } ?? "YouTube"
            if let url = value(root, kAXURLAttribute) as? URL,
               let video = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value,
               video.count == 11, video.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) {
                page = URL(string: "https://i.ytimg.com/vi/\(video)/hqdefault.jpg")
            }
            artist = "YouTube"
        }
        if title.isEmpty && yandex { title = "Яндекс Музыка" }
        guard !title.isEmpty else { return nil }
        var actions = ["toggle": toggle]
        if let next = buttons.first(where: { yandex ? text($0) == "Следующая песня" : text($0).hasPrefix("Next (") || text($0).hasPrefix("Следующее (") }) { actions["next"] = next }
        if let previous = buttons.first(where: { text($0) == "Предыдущая песня" }) { actions["previous"] = previous }
        if yandex, let slider = all.first(where: { text($0) == "Управление таймкодом" }) { actions["seek"] = slider }
        controls[id] = actions
        return PlayingTrack(source: id, title: title, artist: artist, playing: pause != nil, elapsed: elapsed, duration: duration, artworkPage: page, captureTarget: captureTarget)
    }
    func command(_ command: MusicCommand, source: String) {
        let key: String
        switch command {
        case .toggle: key = "toggle"
        case .next: key = "next"
        case .previous: key = "previous"
        case .seek:
            return
        }
        if let button = controls[source]?[key] { AXUIElementPerformAction(button, kAXPressAction as CFString) }
    }
    func clearMissing(_ running: Set<String>) {
        roots = roots.filter { running.contains($0.key) }; controls = controls.filter { running.contains($0.key) }
        processIDs = processIDs.filter { running.contains($0.key) }
        discoveryRetry = discoveryRetry.filter { running.contains($0.key) }
        activatedPIDs.formIntersection(Set(processIDs.values))
    }
}

final class MusicPlayback: ObservableObject {
    static let shared = MusicPlayback()
    @Published private(set) var track: PlayingTrack?
    @Published private(set) var artwork: NSImage?
    @Published var enabled = true
    @Published private(set) var resumeMessage: String?
    private var resumeRequest: (source: String, deadline: Date)?
    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "NotchIsland.music", qos: .utility)
    private let apple = AppleMusicAdapter()
    private let accessible = AccessibleMusicAdapter()
    private var timer: Timer?
    private var polling = false
    private var artworkKey = ""
    private var artworkRetry = Date.distantPast
    private var artworkTask: RemoteArtworkRequest?
    private var artworkAttempt = UUID()
    private var remoteArtworkVisible = false
    private var lastRemoteArtworkEnabled = false
    private var defaultsObserver: NSObjectProtocol?
    private var previous: [String: Bool] = [:]
    var isPlaying: Bool { enabled && track?.playing == true }
    init(automatic: Bool = true, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let saved = defaults.dictionary(forKey: "lastMusicTrack"),
           let source = saved["source"] as? String, let title = saved["title"] as? String {
            track = PlayingTrack(source: source, title: title, artist: saved["artist"] as? String ?? "", playing: false, elapsed: 0, duration: 0)
        }
        defaults.register(defaults: ["musicCaptureArtwork": true])
        lastRemoteArtworkEnabled = remoteArtworkEnabled
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                                 object: defaults, queue: .main) { [weak self] _ in
            self?.remoteArtworkPreferenceChanged()
        }
        if automatic {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
            poll()
        }
    }
    deinit {
        timer?.invalidate(); artworkTask?.cancel()
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
    }
    var remoteArtworkEnabled: Bool { defaults.bool(forKey: RemoteArtworkPolicy.preferenceKey) }
    func remoteArtworkPreferenceChanged() {
        guard lastRemoteArtworkEnabled != remoteArtworkEnabled else { return }
        lastRemoteArtworkEnabled = remoteArtworkEnabled
        if !remoteArtworkEnabled {
            artworkAttempt = UUID()
            artworkTask?.cancel(); artworkTask = nil
            if remoteArtworkVisible { artwork = nil; remoteArtworkVisible = false }
        }
        artworkRetry = .distantPast
    }
    static func choose(_ samples: [PlayingTrack], current: String?, previous: [String: Bool]) -> PlayingTrack? {
        samples.first { $0.playing && previous[$0.source] != true } ?? samples.first { $0.playing && $0.source == current } ?? samples.first { $0.playing } ?? samples.first { $0.source == current }
    }
    func connect() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        if defaults.bool(forKey: "musicCaptureArtwork") { CGRequestScreenCaptureAccess() }
        queue.async { self.apple.resetPermission() }
        poll()
    }
    func poll() {
        guard enabled, !polling else { return }; polling = true
        let ids = ["com.apple.Music", "ru.yandex.desktop.music", "com.google.Chrome", "ru.yandex.desktop.yandex-browser", "com.apple.Safari"]
        let running = NSWorkspace.shared.runningApplications.compactMap { app -> (String, pid_t)? in
            guard let id = app.bundleIdentifier, ids.contains(id) else { return nil }; return (id, app.processIdentifier)
        }
        queue.async {
            self.accessible.clearMissing(Set(running.map(\.0)))
            let samples = running.compactMap { id, pid in id == "com.apple.Music" ? self.apple.read() : self.accessible.read(id: id, pid: pid) }
            DispatchQueue.main.async {
                self.polling = false
                if let chosen = Self.choose(samples, current: self.track?.source, previous: self.previous) {
                    self.track = chosen
                    if chosen.playing { self.resumeMessage = nil }
                    self.defaults.set(["source": chosen.source, "title": chosen.title, "artist": chosen.artist], forKey: "lastMusicTrack")
                } else if var last = self.track {
                    last.playing = false; self.track = last
                }
                if let request = self.resumeRequest {
                    if let sample = samples.first(where: { $0.source == request.source }) {
                        self.resumeRequest = nil
                        self.track = sample
                        if !sample.playing { self.send(.toggle) }
                    } else if Date() > request.deadline {
                        self.resumeRequest = nil
                        self.resumeMessage = L("Откройте последний трек в плеере и проверьте доступ в настройках.", "Open the last track in your player and check permissions in Settings.")
                    }
                }
                self.previous = Dictionary(uniqueKeysWithValues: samples.map { ($0.source, $0.playing) })
                self.loadArtwork()
            }
        }
    }
    func resumeLast(source: String? = nil) {
        let source = source ?? track?.source ?? "com.apple.Music"
        let allowed = ["com.apple.Music", "ru.yandex.desktop.music", "com.google.Chrome", "ru.yandex.desktop.yandex-browser", "com.apple.Safari"]
        guard allowed.contains(source), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source) else {
            resumeMessage = L("Плеер не найден на этом Mac.", "Player not found on this Mac."); return
        }
        if source != "com.apple.Music" && !AXIsProcessTrusted() {
            resumeMessage = L("Разрешите NotchIsland в настройках macOS → Универсальный доступ, затем перезапустите островок.", "Allow NotchIsland in macOS Settings → Accessibility, then restart the app.")
            return
        }
        resumeMessage = nil
        resumeRequest = (source, Date().addingTimeInterval(10))
        if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == source }) { poll(); return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
            DispatchQueue.main.async {
                if error != nil { self?.resumeRequest = nil; self?.resumeMessage = L("Не удалось открыть плеер.", "Could not open the player.") }
                else { self?.poll() }
            }
        }
    }
    func send(_ command: MusicCommand) {
        guard let source = track?.source else { return }
        queue.async {
            if source == "com.apple.Music" { self.apple.command(command) }
            else { self.accessible.command(command, source: source) }
            DispatchQueue.main.async { self.poll() }
        }
    }
    private func loadArtwork() {
        guard let track else {
            artworkAttempt = UUID()
            artworkTask?.cancel(); artworkTask = nil
            artwork = nil; artworkKey = ""; remoteArtworkVisible = false
            return
        }
        let newTrack = artworkKey != track.key
        guard newTrack || (artwork == nil && artworkTask == nil && Date() >= artworkRetry) else { return }
        artworkKey = track.key; artworkRetry = Date().addingTimeInterval(8)
        artworkAttempt = UUID()
        let attempt = artworkAttempt
        artworkTask?.cancel(); artworkTask = nil
        if newTrack || artwork == nil {
            artwork = track.artwork.flatMap(NSImage.init(data:)); remoteArtworkVisible = false
        }
        let key = track.key
        if let target = track.captureTarget, defaults.bool(forKey: "musicCaptureArtwork"), artwork == nil {
            MusicArtworkCapture.capture(target) { [weak self] image in
                DispatchQueue.main.async {
                    guard let self, self.artworkKey == key, self.artworkAttempt == attempt else { return }
                    self.artwork = image
                }
            }
            return
        }
        guard remoteArtworkEnabled, artwork == nil, let page = track.artworkPage else { return }
        artworkTask = RemoteArtworkRequest.start(page) { [weak self] data in
            guard let self, self.artworkAttempt == attempt else { return }
            self.artworkTask = nil
            guard self.remoteArtworkEnabled, self.artworkKey == key,
                  let data, let image = NSImage(data: data) else { return }
            self.artwork = image
            self.remoteArtworkVisible = true
        }
    }
}
