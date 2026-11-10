import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Combine
import Sparkle

enum IslandSection: String, CaseIterable {
    case home, clipboard, shelf, gpt, screenshot, focus, reminders, music
    var title: String {
        switch self {
        case .music: return L("Музыка", "Music")
        case .reminders: return L("Напоминания", "Reminders")
        case .focus: return L("Фокус", "Focus")
        case .home: return L("Главная", "Home")
        case .clipboard: return L("Буфер", "Clipboard")
        case .shelf: return L("Полка", "Shelf")
        case .gpt: return "ChatGPT"
        case .screenshot: return L("Скриншот", "Screenshot")
        }
    }
    var icon: String {
        switch self {
        case .music: return "music.note"
        case .reminders: return "bell"
        case .focus: return "timer"
        case .home: return "house"
        case .clipboard: return "clipboard"
        case .shelf: return "square.3.layers.3d"
        case .gpt: return "bubble.left"
        case .screenshot: return "viewfinder"
        }
    }
}

final class Model: ObservableObject {
    @Published var displayedSize = CGSize(width: 160, height: 32)
    @Published var headerHeight: CGFloat = 32
    var notchWidth: CGFloat = 160
    @Published var section: IslandSection = IslandSection(rawValue: UserDefaults.standard.string(forKey: "selectedSection") ?? "") ?? .home
    @Published var draft = ""
    @Published var screenshotURL: URL?
    @Published var screenshotMessage = ""
    @Published var screenshotNeedsPermission = false
    var takeScreenshot: ((Bool) -> Void)?
    @Published var clipboardTitle: String?
    @Published var clipboardIcon = "doc.on.clipboard"
    private var clipboardItems: [[NSPasteboard.PasteboardType: Data]] = []
    private let shelf = ShelfWorker()
    let focusTimer = FocusTimer()
    let music = MusicPlayback.shared
    private var musicSubscription: AnyCancellable?
    @Published private var sectionOrder = TabOrder.normalized(UserDefaults.standard.stringArray(forKey: "sectionOrder") ?? [], available: IslandSection.allCases.map(\.rawValue))
    var visibleSections: [IslandSection] { sectionOrder.compactMap(IslandSection.init(rawValue:)) }
    func moveSection(_ source: String, to target: IslandSection) {
        sectionOrder = TabOrder.moving(source, to: target.rawValue, in: sectionOrder)
        UserDefaults.standard.set(sectionOrder, forKey: "sectionOrder")
    }
    let reminderNotifications = SystemReminderNotifications()
    lazy var reminders = AppleReminderStore(cancelLegacy: reminderNotifications.cancel)
    private var focusSubscription: AnyCancellable?
    private var shelfTimer: Timer?
    private var shelfWakeObserver: NSObjectProtocol?
    @Published var timerNotice = false
    private var noticeDismissal: DispatchWorkItem?
    private var timerNoticeGate = TimerNoticeGate()
    func beginCapture() {
        timerNoticeGate.beginCapture()
        toggle(false)
    }
    func finishCapture(showingResult: Bool) {
        if timerNoticeGate.finishCapture(showingResult: showingResult) { showTimerNotice() }
    }
    init() {
        focusTimer.onExpired = { [weak self] in self?.showTimerNotice() }
        musicSubscription = music.$track.map { $0?.playing == true }.removeDuplicates().sink { [weak self] playing in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.objectWillChange.send(); self.change?()
            }
        }
        focusSubscription = Publishers.CombineLatest(focusTimer.$state, focusTimer.$remainingSeconds)
            .map { state, seconds in
                let text = seconds >= 3600 ? FocusTimer.format(seconds) : String(format: "%d:%02d", seconds / 60, seconds % 60)
                return FocusCompactLayout(text: text, active: state != .idle)
            }.removeDuplicates().dropFirst()
            .sink { [weak self] _ in
                // Published emits before storage changes; resize on the next main-loop turn.
                DispatchQueue.main.async { [weak self] in
                    self?.objectWillChange.send()
                    self?.change?()
                }
            }
        shelf.run(.restore) { [weak self] snapshot in
            self?.files = snapshot.files
            if let error = snapshot.error { self?.message = L("Не удалось восстановить полку: \(error.localizedDescription)", "Could not restore shelf: \(error.localizedDescription)") }
        }
        shelfTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refreshShelf() }
        shelfTimer?.tolerance = 5
        shelfWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.refreshShelf() }
    }
    deinit {
        shelfTimer?.invalidate()
        if let observer = shelfWakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
    func refreshShelf() {
        shelf.run(.expire) { [weak self] snapshot in
            self?.files = snapshot.files
            if let error = snapshot.error { self?.message = L("Не удалось очистить полку: \(error.localizedDescription)", "Could not clean up shelf: \(error.localizedDescription)") }
        }
    }
    func removeFile(_ url: URL) {
        shelf.run(.remove(url)) { [weak self] snapshot in
            self?.files = snapshot.files
            self?.message = snapshot.error.map { L("Не удалось удалить копию: \($0.localizedDescription)", "Could not remove copy: \($0.localizedDescription)") } ?? L("Файл убран с полки", "File removed from shelf")
        }
    }
    func showTimerNotice() {
        guard !Preferences.shared.blocksCurrentApp, timerNoticeGate.request() else { return }
        noticeDismissal?.cancel()
        timerNotice = true
        section = .focus
        UserDefaults.standard.set(section.rawValue, forKey: "selectedSection")
        expanded = true
        change?()
        let dismissal = DispatchWorkItem { [weak self] in self?.toggle(false) }
        noticeDismissal = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: dismissal)
    }
    var surfaceSize: CGSize {
        if timerNotice { return CGSize(width: max(280, notchWidth + 40), height: headerHeight + 48) }
        guard expanded else {
            return CGSize(width: notchWidth + (music.isPlaying ? 88 : focusTimer.compactLayout.timeWidth + focusTimer.compactLayout.symbolWidth), height: headerHeight)
        }
        return section == .gpt ? CGSize(width: 460, height: 340 + headerHeight - 32) : CGSize(width: 405, height: 240 + headerHeight - 32)
    }
    func select(_ section: IslandSection) {
        if section == .screenshot { takeScreenshot?(false); return }
        guard self.section != section else { return }
        self.section = section
        UserDefaults.standard.set(section.rawValue, forKey: "selectedSection")
        change?()
    }
    func refreshClipboard() {
        let board = NSPasteboard.general
        guard ClipboardHistory.shared.canShowCurrentClipboard else {
            clipboardTitle = nil
            clipboardIcon = "lock"
            clipboardItems = []
            return
        }
        clipboardItems = (board.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            clipboardTitle = urls.map(\.lastPathComponent).joined(separator: ", ")
            clipboardIcon = "doc"
        } else if board.availableType(from: [.png, .tiff]) != nil {
            clipboardTitle = L("Изображение", "Image")
            clipboardIcon = "photo"
        } else if let text = board.string(forType: .string), !text.isEmpty {
            clipboardTitle = text
            clipboardIcon = "text.alignleft"
        } else {
            clipboardTitle = nil
            clipboardItems = []
        }
    }
    func reminderClipboard() -> String? {
        guard ClipboardHistory.shared.canShowCurrentClipboard,
              let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
    func copyClipboard() {
        guard !clipboardItems.isEmpty else { return }
        let items = clipboardItems.map { snapshot -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in snapshot { item.setData(data, forType: type) }
            return item
        }
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.writeObjects(items) { toggle(false) }
    }

    @Published var expanded = false
    @Published var files: [URL] = []
    @Published var message = L("Перетащи файл к камере", "Drag a file to the camera")
    var change: (() -> Void)?
    var beginFileDrag: (() -> Void)?
    func toggle(_ value: Bool) {
        let dismissedNotice = timerNotice
        if timerNotice { timerNotice = false; noticeDismissal?.cancel() }
        if !value && timerNoticeGate.consume() { showTimerNotice(); return }
        guard value != expanded else {
            if dismissedNotice { change?() }
            return
        }
        if value && Preferences.shared.blocksCurrentApp { return }
        if value { refreshClipboard(); refreshShelf() }
        expanded = value; change?()
    }
    func accept(_ providers: [NSItemProvider]) -> Bool {
        guard !Preferences.shared.blocksCurrentApp else { return false }
        let matching = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !matching.isEmpty else { return false }
        var pending = matching.count
        var failures = 0
        message = L("Добавляем файлы…", "Adding files…")
        // Counters and all published state are confined to the main queue.
        func finished(_ failed: Bool) {
            dispatchPrecondition(condition: .onQueue(.main))
            if failed { failures += 1 }
            pending -= 1
            if pending == 0 {
                if failures == 0 { self.message = L("Файлы сохранены на полке", "Files saved to shelf"); self.toggle(false) }
                else { self.message = L("Не удалось добавить файлов: \(failures). Остальные сохранены.", "Could not add \(failures) file(s). The others were saved.") }
            }
        }
        for provider in matching {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                let source = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                DispatchQueue.main.async {
                    guard error == nil, let source = source, source.isFileURL else { finished(true); return }
                    self.shelf.run(.add(source)) { snapshot in
                        self.files = snapshot.files
                        finished(snapshot.error != nil)
                    }
                }
            }
        }
        return true
    }

}
// Concave shoulders join the screen edge; the lower corners remain rounded.
struct IslandOutline: Shape {
    var expansion: CGFloat
    func path(in rect: CGRect) -> Path {
        let shoulder = 12 * expansion
        let bottom = 12 + 12 * expansion
        let left = rect.minX + shoulder
        let right = rect.maxX - shoulder
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: right, y: rect.minY + shoulder),
                         control: CGPoint(x: right, y: rect.minY))
        path.addLine(to: CGPoint(x: right, y: rect.maxY - bottom))
        path.addQuadCurve(to: CGPoint(x: right - bottom, y: rect.maxY),
                         control: CGPoint(x: right, y: rect.maxY))
        path.addLine(to: CGPoint(x: left + bottom, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: left, y: rect.maxY - bottom),
                         control: CGPoint(x: left, y: rect.maxY))
        path.addLine(to: CGPoint(x: left, y: rect.minY + shoulder))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY),
                         control: CGPoint(x: left, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct IslandHeader: View {
    @ObservedObject var model: Model
    @ObservedObject var timer: FocusTimer
    @ObservedObject var music: MusicPlayback
    var body: some View {
        Button {
            if !model.expanded {
                if timer.state == .completed { model.select(.focus) }
                else if music.isPlaying { model.select(.music) }
                else if timer.isVisible { model.select(.focus) }
            }
            model.toggle(!model.expanded)
        } label: {
            HStack(spacing: 0) {
                if model.expanded && !model.timerNotice {
                    WeatherHeader()
                        .frame(width: max(0, (model.displayedSize.width - model.notchWidth) / 2 - 24), alignment: .leading)
                        .clipped().padding(.leading, 20)
                }
                if !model.expanded && music.isPlaying {
                    MusicArtwork(music: music).frame(width: 24, height: 24).frame(width: 44, height: model.headerHeight)
                } else if !model.expanded && timer.isVisible {
                    FocusTimerIndicator(timer: timer)
                        .frame(width: timer.compactLayout.timeWidth, height: model.headerHeight)
                }
                Color.black.frame(maxWidth: .infinity)
                if !model.expanded && music.isPlaying {
                    if timer.isVisible {
                        FocusProgressRing(timer: timer).frame(width: 20, height: 20)
                            .frame(width: 44, height: model.headerHeight)
                    } else {
                        MusicWaveform(playing: true).frame(width: 44, height: model.headerHeight)
                    }
                } else if !model.expanded && timer.isVisible {
                    FocusProgressRing(timer: timer).frame(width: 20, height: 20)
                        .frame(width: timer.compactLayout.symbolWidth, height: model.headerHeight)
                }
            }.frame(height: model.headerHeight).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityValue(!model.expanded && music.isPlaying && timer.isVisible ?
                (timer.state == .completed ? L("Таймер завершён", "Timer finished") : L("Таймер: ", "Timer: ") + timer.timeText + (timer.state == .paused ? L(", пауза", ", paused") : "")) : "")
            .accessibilityLabel(model.expanded ? L("Закрыть островок", "Close island") : timer.state == .completed ? L("Открыть завершённый таймер", "Open completed timer") : music.isPlaying ? L("Открыть музыку", "Open music") : timer.isVisible ?
                L("Открыть таймер: ", "Open timer: ") + (timer.state == .completed ? L("завершён", "finished") : timer.timeText) + (timer.state == .paused ? L(", пауза", ", paused") : "") : L("Открыть островок", "Open island"))
    }
}

struct IslandView: View {
    @ObservedObject var model: Model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hover = false
    @State private var targeted = false
    private var outline: IslandOutline {
        IslandOutline(expansion: min(1, max(0, (model.displayedSize.height - model.headerHeight) / 208)))
    }
    var body: some View {
        VStack(spacing: 0) {
            IslandHeader(model: model, timer: model.focusTimer, music: model.music)
            if model.timerNotice {
                Text(L("Таймер завершился", "Timer finished")).font(.system(size: 15, weight: .medium))
                    .frame(height: 48).frame(maxWidth: .infinity)
            } else if model.expanded {
                VStack(alignment: .leading, spacing: 5) {
                    IslandTabBar(model: model)
                    content
                    Spacer(minLength: 0)
                }.padding(.horizontal, 28).padding(.bottom, 12)
                    .frame(width: model.surfaceSize.width, height: model.surfaceSize.height - model.headerHeight, alignment: .top)
                    .opacity(Double(min(1, max(0, (model.displayedSize.height - 60) / 100))))
            }
        }
        .frame(width: model.displayedSize.width, height: model.displayedSize.height, alignment: .top)
        .background(Color.black).clipShape(outline)
        .shadow(color: .white.opacity(!model.expanded && hover ? 0.28 : 0), radius: 6, y: 2)
        .shadow(color: .white.opacity(!model.expanded && hover ? 0.16 : 0), radius: 14, y: 4)
        .animation(reduceMotion || model.expanded ? nil : .easeOut(duration: 0.18), value: hover)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        // A blur has a long tail: fade it to zero inside the transparent margin,
        // before WindowServer clips the panel. Keep the island itself fully opaque.
        .mask {
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .white], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 16)
                Color.white
                LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 16)
            }
        }
        .mask {
            VStack(spacing: 0) {
                Color.white
                LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onHover { hover = $0 }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $targeted) { providers in
            guard !model.expanded || model.section != .gpt else { return false }
            return model.accept(providers)
        }
        .onChange(of: targeted) { value in
            if value && (!model.expanded || model.section != .gpt) { model.select(.shelf); model.toggle(true) }
        }
        .foregroundColor(.white).preferredColorScheme(.dark)
    }
    @ViewBuilder private var content: some View {
        switch model.section {
        case .music:
            MusicPlayerView(music: model.music)
        case .reminders:
            RemindersView(store: model.reminders)
        case .focus:
            FocusTimerView(timer: model.focusTimer)
        case .home:
            caption(L("Последнее скопированное", "Last copied"))
            clipboardRow
            HomeReminderView(store: model.reminders) { reminder in
                if let reminder { model.reminders.show(reminder.id) }
                model.select(.reminders)
            }
            HStack(spacing: 0) {
                Button { model.select(.gpt) } label: {
                    Text(L("Спросить GPT…", "Ask GPT…")).foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(11)
                }
                Button { model.takeScreenshot?(true) } label: {
                    Image(systemName: "viewfinder").frame(width: 38, height: 38)
                }.help(L("Скриншот для вопроса", "Screenshot for question"))
                    .accessibilityLabel(L("Скриншот для вопроса", "Screenshot for question"))
            }.buttonStyle(.plain).background(Color.white.opacity(0.12)).cornerRadius(12)
        case .clipboard:
            ClipboardHistoryView { model.toggle(false) }
        case .shelf:
            if model.files.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "square.3.layers.3d").font(.system(size: 26))
                    Text(L("Перетащи сюда файл", "Drop a file here"))
                }.foregroundColor(.gray).frame(maxWidth: .infinity, minHeight: 115)
            } else { fileStrip(compact: false) }
            caption(model.files.isEmpty ? L("Полка для временных копий файлов", "Shelf for temporary file copies") : L("Перетащи файл в нужное приложение", "Drag a file into another app"))
            if model.message.hasPrefix(L("Не удалось", "Could not")) { caption(model.message) }
        case .gpt:
            ChatGPTIslandView(screenshot: { model.takeScreenshot?(true) },
                              collapse: { model.toggle(false) })
        case .screenshot:
            VStack(spacing: 8) {
                Image(systemName: model.screenshotURL == nil ? "viewfinder" : "checkmark.circle")
                    .font(.system(size: 24))
                Text(model.screenshotMessage.isEmpty ? L("Выдели область мышью · Esc или правая кнопка — отмена", "Select an area · Esc or right-click to cancel") : model.screenshotMessage)
                    .font(.caption).multilineTextAlignment(.center)
                if model.screenshotNeedsPermission {
                    HStack {
                        Button(L("Разрешить запись экрана…", "Allow Screen Recording…")) {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        Button(L("Показать приложение", "Show app in Finder")) {
                            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                        }
                    }.buttonStyle(.plain)
                }
                if let url = model.screenshotURL {
                    Button(L("Показать в Finder", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        .buttonStyle(.plain)
                }
                Button(L("Новый снимок", "New screenshot")) { model.takeScreenshot?(false) }.buttonStyle(.plain)
            }.frame(maxWidth: .infinity, minHeight: 130)

        }
    }
    private func caption(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundColor(.gray)
    }
    private var clipboardRow: some View {
        Button { model.copyClipboard() } label: {
            HStack(spacing: 10) {
                Image(systemName: model.clipboardIcon)
                Text(model.clipboardTitle ?? (model.clipboardIcon == "lock" ? L("Содержимое скрыто", "Content hidden") : L("Нет текста, изображения или файла", "No text, image or file")))
                    .font(.system(size: 12)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                if model.clipboardTitle != nil { Image(systemName: "doc.on.doc") }
            }.padding(11).frame(height: 36).background(Color.white.opacity(0.09)).cornerRadius(10)
        }.buttonStyle(.plain).disabled(model.clipboardTitle == nil)
            .help(L("Копировать и закрыть островок", "Copy and close island"))
    }
    private func fileStrip(compact: Bool) -> some View {
        ScrollViewReader { proxy in
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(model.files, id: \.self) { url in
                    shelfCard(url, compact: compact).id(url)
                }
            }
            .background(HorizontalWheelSupport())
        }.frame(height: compact ? 34 : 115)
            .onChange(of: model.files.first) { first in
                if let first = first { proxy.scrollTo(first, anchor: .leading) }
            }
        }
    }
    private func shelfCard(_ url: URL, compact: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.09))
            if compact {
                HStack(spacing: 7) {
                    FileThumbnail(url: url, size: 22)
                    Text(url.lastPathComponent).font(.system(size: 11)).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.horizontal, 10)
            } else {
                VStack(spacing: 6) {
                    FileThumbnail(url: url, size: 62)
                    Text(url.lastPathComponent).font(.caption).lineLimit(1).frame(width: 90)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: compact ? 160 : 110, height: compact ? 34 : 105)
        .fixedSize()
        .contentShape(Rectangle())
        .onDrag {
            let provider = NSItemProvider(contentsOf: url) ?? NSItemProvider()
            model.beginFileDrag?()
            return provider
        }
        .overlay(alignment: .topTrailing) {
            if !compact {
                Button { model.removeFile(url) } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .medium))
                        .frame(width: 22, height: 22)
                        .background(Color.black.opacity(0.65)).clipShape(Circle())
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).padding(4)
                    .help(L("Убрать с полки", "Remove from shelf")).accessibilityLabel(L("Убрать \(url.lastPathComponent) с полки", "Remove \(url.lastPathComponent) from shelf"))
            }
        }
        .help(url.lastPathComponent).accessibilityLabel(L("Перетащить \(url.lastPathComponent)", "Drag \(url.lastPathComponent)"))
    }

}
final class Panel: NSPanel {
    var dismissIsland: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { dismissIsland?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { dismissIsland?() }
        else { super.keyDown(with: event) }
    }
}
// A menu-like dismissal surface consumes the first outside click, so macOS
// does not also reveal the desktop or activate the window underneath.
final class DismissalView: NSView {
    var dismiss: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    // Retain the shield for the entire down/up sequence. Removing it on down
    // can let the release reach the desktop underneath.
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { dismiss?() }
    override func rightMouseUp(with event: NSEvent) { dismiss?() }
    override func otherMouseUp(with event: NSEvent) { dismiss?() }
}
final class DismissalPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class Delegate: NSObject, NSApplicationDelegate {
    private var updates: SPUStandardUpdaterController?
    private var checkUpdatesItem: NSMenuItem?
    private var automaticUpdatesItem: NSMenuItem?

    let model = Model()
    var panel: Panel!
    var item: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private let capture = ScreenshotCapture()
    private var capturing = false
    private var dismissalPanels: [DismissalPanel] = []
    var localMonitor: Any?
    var globalMonitor: Any?
    private var resizeTimer: Timer?
    private var wasExpanded = false
    private var displayedCenterOffset: CGFloat = 0
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = EditingMenu.make()
        #if DEBUG
        if ChatGPTSession.auditHostsOnLaunch {
            DispatchQueue.main.async { ChatGPTSession.shared.showWindow() }
        }
        #endif
        _ = ClipboardHistory.shared
        _ = WeatherStore.shared
        panel = Panel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.dismissIsland = { [weak self] in self?.model.toggle(false) }
        let hostingView = NSHostingView(rootView: LocalizedRoot { IslandView(model: self.model) })
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        model.takeScreenshot = { [weak self] forGPT in self?.startScreenshot(forGPT: forGPT) }
        model.change = { [weak self] in self?.updatePanel(animated: true) }
        model.beginFileDrag = { [weak self] in
            self?.hideDismissalPanels()
            // Let SwiftUI create its dragging session before collapsing the source.
            DispatchQueue.main.async { [weak self] in self?.model.toggle(false) }
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = BrandIcon.image(size: 24, template: true)
        let menu = NSMenu()
        menu.addItem(withTitle: L("О проекте…", "About…"), action: #selector(about), keyEquivalent: "").target = self
        menu.addItem(withTitle: L("Настройки…", "Settings…"), action: #selector(openSettings), keyEquivalent: ",").target = self
        if Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil {
            let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            updates = controller
            let entry = menu.addItem(withTitle: L("Проверить обновления…", "Check for Updates…"),
                                     action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
            entry.target = controller
            checkUpdatesItem = entry
            let automatic = menu.addItem(withTitle: L("Проверять обновления автоматически", "Automatically Check for Updates"),
                                         action: #selector(toggleUpdateChecks(_:)), keyEquivalent: "")
            automatic.target = self
            automatic.state = controller.updater.automaticallyChecksForUpdates ? .on : .off
            automaticUpdatesItem = automatic
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: L("Завершить", "Quit"), action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        NotificationCenter.default.addObserver(self, selector: #selector(updateLanguage), name: AppLanguage.changed, object: nil)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            guard let self = self else { return event }
            if event.type == .keyDown && event.keyCode == 53 && self.model.expanded && event.window === self.panel { self.model.toggle(false); return nil }
            if event.window is DismissalPanel { return event }
            if event.type == .leftMouseDown && event.window !== self.panel { self.model.toggle(false) }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in self?.model.toggle(false) }
        NotificationCenter.default.addObserver(self, selector: #selector(position), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        model.reminders.refresh()
        position()
    }
    @objc func position() { updatePanel(animated: false) }

    private func updatePanel(animated: Bool) {
        guard !capturing else { return }
        resizeTimer?.invalidate()
        resizeTimer = nil
        hideDismissalPanels()
        guard let screen = NSScreen.screens.first(where: { s in
            guard let id = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(id.uint32Value) != 0
        }) else { panel.orderOut(nil); return }
        let geometry = FocusIslandGeometry(frame: screen.frame, leftArea: screen.auxiliaryTopLeftArea,
                                           rightArea: screen.auxiliaryTopRightArea, topInset: screen.safeAreaInsets.top)
        model.notchWidth = geometry.notchWidth
        if model.headerHeight != geometry.headerHeight { model.headerHeight = geometry.headerHeight }
        let destination = model.surfaceSize
        let destinationOffset = model.expanded || model.music.isPlaying ? 0 : model.focusTimer.compactLayout.centerOffset
        let startOffset = displayedCenterOffset
        let start = model.displayedSize
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && (start != destination || startOffset != destinationOffset) {
            let began = ProcessInfo.processInfo.systemUptime
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
                guard let self = self else { timer.invalidate(); return }
                let progress = min(1, (ProcessInfo.processInfo.systemUptime - began) / 0.28)
                let eased = progress * progress * (3 - 2 * progress)
                let size = CGSize(width: start.width + (destination.width - start.width) * eased,
                                  height: start.height + (destination.height - start.height) * eased)
                self.applySize(size, centerOffset: startOffset + (destinationOffset - startOffset) * eased, centerX: geometry.centerX, on: screen)
                if progress >= 1 { timer.invalidate(); self.resizeTimer = nil }
            }
            resizeTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        } else {
            applySize(destination, centerOffset: destinationOffset, centerX: geometry.centerX, on: screen)
        }
        if model.expanded { showDismissalPanels() }
        panel.orderFrontRegardless()
        let opening = model.expanded && !wasExpanded
        wasExpanded = model.expanded
        if opening {
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(panel.contentView)
            // Menu tracking and the SwiftUI click can finish after this callback.
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.model.expanded else { return }
                self.panel.makeKeyAndOrderFront(nil)
                self.panel.makeFirstResponder(self.panel.contentView)
            }
        } else if !model.expanded && panel.isKeyWindow {
            panel.resignKey()
        }
    }
    private func hideDismissalPanels() {
        dismissalPanels.forEach { $0.orderOut(nil) }
    }
    private func showDismissalPanels() {
        if dismissalPanels.count != NSScreen.screens.count {
            dismissalPanels.removeAll()
            dismissalPanels = NSScreen.screens.map { _ in
                let window = DismissalPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                window.isOpaque = false
                // Fully transparent pixels can be excluded from WindowServer hit testing.
                window.backgroundColor = NSColor.black.withAlphaComponent(0.01)
                window.ignoresMouseEvents = false
                window.hasShadow = false
                window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                window.hidesOnDeactivate = false
                let view = DismissalView()
                view.dismiss = { [weak self] in self?.model.toggle(false) }
                window.contentView = view
                return window
            }
        }
        for (window, screen) in zip(dismissalPanels, NSScreen.screens) {
            window.setFrame(screen.frame, display: false)
            window.orderFrontRegardless()
        }
    }
    private func applySize(_ size: CGSize, centerOffset: CGFloat, centerX: CGFloat, on screen: NSScreen) {
        displayedCenterOffset = centerOffset
        model.displayedSize = size
        let width = size.width + 32
        let height = size.height + 16
        // Keep the physical camera between independently sized time and dial wings.
        panel.setFrame(NSRect(x: centerX + centerOffset - width / 2,
                              y: screen.frame.maxY - height,
                              width: width, height: height), display: true)
    }
    private func startScreenshot(forGPT: Bool) {
        guard !capturing else { return }
        if forGPT && !ChatGPTSession.shared.confirmScreenshotSharing() { return }
        model.screenshotNeedsPermission = false
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            model.section = .screenshot
            model.screenshotNeedsPermission = true
            model.screenshotMessage = L("Разреши запись экрана для NotchIsland в Системных настройках → Конфиденциальность и безопасность → Запись экрана. Затем при необходимости перезапусти приложение.", "Allow Screen Recording for NotchIsland in System Settings → Privacy & Security → Screen Recording. Then restart the app if needed.")
            model.toggle(true)
            return
        }
        let previousSection = model.section
        model.beginCapture()
        capturing = true
        resizeTimer?.invalidate(); resizeTimer = nil
        hideDismissalPanels()
        panel.orderOut(nil)
        let folder = URL(fileURLWithPath: Preferences.shared.folder, isDirectory: true)
        // Allow the window server to remove the island before selection starts.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self else { return }
            self.capture.start(folder: folder) { [weak self] result in
                guard let self = self else { return }
                self.capturing = false
                let showingResult: Bool
                switch result {
                case .success(let url): showingResult = url != nil
                case .failure: showingResult = true
                }
                self.model.finishCapture(showingResult: showingResult)
                switch result {
                case .success(let url):
                    if let url = url {
                        self.model.screenshotURL = url
                        self.model.screenshotMessage = L("Снимок сохранён и скопирован", "Screenshot saved and copied")
                        self.model.section = forGPT ? .gpt : .screenshot
                        self.model.toggle(true)
                        if forGPT {
                            DispatchQueue.main.async {
                                ChatGPTSession.shared.attachScreenshot(url)
                            }
                        }
                    } else {
                        self.model.section = previousSection
                        self.position()
                    }
                case .failure(let error):
                    self.model.section = .screenshot
                    self.model.screenshotMessage = L("Не удалось сохранить снимок: \(error.localizedDescription)", "Could not save screenshot: \(error.localizedDescription)")
                    self.model.toggle(true)
                }
                // Capture hid the panel independently of expanded; always restore it.
                self.position()
            }
        }
    }
    @objc private func toggleUpdateChecks(_ sender: NSMenuItem) {
        guard let updater = updates?.updater else { return }
        updater.automaticallyChecksForUpdates.toggle()
        sender.state = updater.automaticallyChecksForUpdates ? .on : .off
    }
    @objc private func updateLanguage() {
        item.menu?.items.first?.title = L("О проекте…", "About…")
        item.menu?.items.dropFirst().first?.title = L("Настройки…", "Settings…")
        item.menu?.items.last?.title = L("Завершить", "Quit")
        automaticUpdatesItem?.title = L("Проверять обновления автоматически", "Automatically Check for Updates")
        checkUpdatesItem?.title = L("Проверить обновления…", "Check for Updates…")
        settingsWindow?.title = L("Настройки NotchIsland", "NotchIsland Settings")
        aboutWindow?.title = L("О проекте", "About")
        NSApp.mainMenu = EditingMenu.make()
        model.refreshClipboard()
    }
    @objc func openSettings() {
        model.toggle(false)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 560), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = L("Настройки NotchIsland", "NotchIsland Settings")
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: LocalizedRoot { PreferencesView() })
            window.center()
            settingsWindow = window
        }
        Preferences.shared.refreshLogin()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    @objc func openShelf() { model.toggle(true) }
    @objc func about() {
        model.toggle(false)
        if aboutWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 540),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = L("О проекте", "About")
            window.minSize = NSSize(width: 400, height: 400)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: LocalizedRoot { AboutProjectView() })
            window.center()
            aboutWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        aboutWindow?.makeKeyAndOrderFront(nil)
    }
    @objc func quit() { NSApp.terminate(nil) }
}
let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.run()
