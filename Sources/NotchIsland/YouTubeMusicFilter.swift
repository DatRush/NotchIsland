import AppKit

final class YouTubeMusicFilter: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let browsers: Set<String> = ["com.google.Chrome", "ru.yandex.desktop.yandex-browser", "com.apple.Safari"]

    // Called from the playback queue. Cache by video ID, never by title.
    private let lock = NSLock()
    private var cache: [String: (music: Bool, expires: Date)] = [:]
    private var pending = Set<String>()

    static func videoID(_ raw: String) -> String? {
        guard let url = URLComponents(string: raw), url.scheme == "https",
              ["www.youtube.com", "youtube.com", "m.youtube.com", "music.youtube.com"].contains(url.host),
              url.path == "/watch", let id = url.queryItems?.first(where: { $0.name == "v" })?.value,
              id.range(of: #"^[a-zA-Z0-9_-]{11}$"#, options: .regularExpression) != nil else { return nil }
        return id
    }

    static func matches(tabTitle: String, mediaTitle: String) -> Bool {
        for suffix in ["", " - YouTube", " - YouTube Music"] {
            let expected = mediaTitle + suffix
            if tabTitle == expected { return true }
            if tabTitle.hasSuffix(expected) {
                let prefix = String(tabTitle.dropLast(expected.count))
                if prefix.range(of: #"^\([0-9]+\) $"#, options: .regularExpression) != nil { return true }
            }
        }
        return false
    }

    private func tabID(for track: PlayingTrack) -> String? {
        guard Self.browsers.contains(track.source) else { return nil }
        // Encode untrusted media titles as data rather than AppleScript source.
        let title = track.title.utf16.map { String(format: "%04x", $0) }.joined()
        let property = track.source == "com.apple.Safari" ? "name" : "title"
        let script = """
        set wanted to «data utxt\(title)» as Unicode text
        set hits to {}
        with timeout of 2 seconds
            tell application id "\(track.source)"
                repeat with w in windows
                    set matches to (every tab of w whose \(property) ends with wanted or \(property) ends with (wanted & " - YouTube") or \(property) ends with (wanted & " - YouTube Music"))
                    repeat with t in matches
                        set end of hits to {\(property) of t, URL of t}
                    end repeat
                end repeat
            end tell
        end timeout
        return hits
        """
        guard let hits = NSAppleScript(source: script)?.executeAndReturnError(nil), hits.numberOfItems > 0 else { return nil }
        var ids = Set<String>()
        for index in 1...hits.numberOfItems {
            guard let item = hits.atIndex(index), let label = item.atIndex(1)?.stringValue,
                  Self.matches(tabTitle: label, mediaTitle: track.title),
                  let raw = item.atIndex(2)?.stringValue else { continue }
            guard let id = Self.videoID(raw) else { return nil }
            ids.insert(id)
        }
        return ids.count == 1 ? ids.first : nil
    }

    func allows(_ track: PlayingTrack) -> Bool {
        guard Self.browsers.contains(track.source) else { return true }
        let id: String?
        if let page = track.artworkPage, page.host == "i.ytimg.com" {
            id = Self.videoID("https://www.youtube.com/watch?v=" + page.deletingLastPathComponent().lastPathComponent)
        } else {
            id = tabID(for: track)
        }
        guard let id else { return false }
        lock.lock()
        defer { lock.unlock() }
        if let entry = cache[id], entry.expires > Date() { return entry.music }
        guard pending.count < 3, pending.insert(id).inserted else { return false }
        Task {
            let result = await self.category(id: id)
            self.store(result, for: id)
        }
        return false
    }

    private func store(_ result: Bool?, for id: String) {
        lock.lock()
        defer { lock.unlock() }
        pending.remove(id)
        if cache.count >= 256 { cache.removeAll() }
        cache[id] = (result == true, Date().addingTimeInterval(result == nil ? 60 : 3600))
    }

    static func classification(html: String, id: String) -> Bool? {
        guard html.contains("<link rel=\"canonical\" href=\"https://www.youtube.com/watch?v=\(id)\">"),
              let tag = html.range(of: #"<meta itemprop="genre" content="[^"]+">"#, options: .regularExpression)
        else { return nil }
        if html[tag] == #"<meta itemprop="genre" content="Music">"# { return true }
        // Some uploaders categorize full music mixes as Entertainment. Require both
        // music tags and a description identifying the video itself as a collection.
        guard html[tag] == #"<meta itemprop="genre" content="Entertainment">"#,
              let description = html.range(of: #"<meta property="og:description" content="[^"]*">"#, options: .regularExpression),
              html.range(of: #"<meta property="og:video:tag" content="(?:music|songs?|музыка|песни)">"#,
                         options: [.regularExpression, .caseInsensitive]) != nil else { return false }
        return html[description].range(
            of: #"\b(?:compilation of (?:sounds|songs|music|tracks)|(?:music|song|ambient|lofi|lo-fi|dj) (?:mix|compilation|playlist)|сборник (?:музыки|песен|треков)|музыкальная подборка)\b"#,
            options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func category(id: String) async -> Bool? {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.timeoutIntervalForResource = 10
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let url = URL(string: "https://www.youtube.com/watch?v=\(id)&hl=en")!
            let (bytes, response) = try await session.bytes(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 4 * 1024 * 1024 else { return nil }
                data.append(byte)
            }
            return Self.classification(html: String(decoding: data, as: UTF8.self), id: id)
        } catch { return nil }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let original = task.originalRequest?.url?.absoluteString,
              let next = request.url?.absoluteString,
              let id = Self.videoID(original), Self.videoID(next) == id else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
