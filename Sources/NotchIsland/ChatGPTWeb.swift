import AppKit
import SwiftUI
import WebKit

/// One live page, moved between the island and its expanded window.
/// WebKit owns authentication; no cookies or credentials are exported.
final class ChatGPTSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    static let shared = ChatGPTSession()
    @Published private(set) var isResetting = false
    @Published private(set) var needsRestart = false
    @Published private(set) var resetMessage: String?
    private let websiteDataStore: WKWebsiteDataStore
    private var storedWebView: WKWebView?
    private var dataGeneration = UUID()
    private var approvedNavigationHosts: Set<String> = []
    private var confirmingNavigation = false
    init(websiteDataStore: WKWebsiteDataStore = .default()) {
        self.websiteDataStore = websiteDataStore
        super.init()
    }
    func confirmScreenshotSharing() -> Bool {
        guard !isResetting, !needsRestart else { return false }
        if UserDefaults.standard.bool(forKey: "chatGPTScreenshotSharingExplained") { return true }
        let alert = NSAlert()
        alert.messageText = L("Передать снимок в ChatGPT?", "Share a screenshot with ChatGPT?")
        alert.informativeText = L("После выбора области снимок сохранится на Mac и прикрепится к ChatGPT. OpenAI может получить изображение уже при прикреплении, до нажатия «Отправить». Не включайте данные, которыми не хотите делиться. Сообщение автоматически не отправляется.", "After you select an area, the screenshot will be saved on your Mac and attached to ChatGPT. OpenAI may receive the image when it is attached, before you press Send. Exclude anything you do not want to share. The message is not sent automatically.")
        alert.addButton(withTitle: L("Продолжить", "Continue"))
        alert.addButton(withTitle: L("Отмена", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        UserDefaults.standard.set(true, forKey: "chatGPTScreenshotSharingExplained")
        return true
    }
    func confirmReset() {
        guard !isResetting else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("Очистить данные ChatGPT на этом Mac?", "Clear ChatGPT data on this Mac?")
        alert.informativeText = L("Закроются окна ChatGPT, пропадут локальные черновики и вход в аккаунты встроенного браузера. Будут удалены cookies, кэш и данные всех сайтов внутри NotchIsland, включая сайты входа. Переписка в аккаунте OpenAI, сохранённые снимки и данные Safari/Chrome останутся. Очистка не отменяет уже переданные файлы.", "ChatGPT windows will close and local drafts and embedded-browser sign-ins will be lost. Cookies, cache and data for all websites inside NotchIsland, including sign-in sites, will be removed. OpenAI account conversations, saved screenshots and Safari/Chrome data will remain. Clearing does not undo files already uploaded.")
        alert.addButton(withTitle: L("Отмена", "Cancel"))
        alert.addButton(withTitle: L("Очистить данные", "Clear data"))
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        clearWebsiteData()
    }
    func clearWebsiteData(completion: (() -> Void)? = nil) {
        guard !isResetting else { return }
        isResetting = true
        approvedNavigationHosts.removeAll()
        dataGeneration = UUID()
        needsRestart = true
        resetMessage = nil
        dismissScreenshotStatus()
        resetTextOperation()
        errorMessage = nil
        for window in popups {
            if let child = window.contentView as? WKWebView {
                child.stopLoading(); child.navigationDelegate = nil; child.uiDelegate = nil
                child.removeFromSuperview()
            }
            window.delegate = nil
            window.close()
        }
        popups.removeAll()
        if let page = storedWebView {
            page.stopLoading(); page.navigationDelegate = nil; page.uiDelegate = nil
            page.configuration.userContentController.removeAllUserScripts()
            page.removeFromSuperview()
        }
        storedWebView = nil
        largeWindow?.close()
        started = false
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        websiteDataStore.removeData(ofTypes: types, modifiedSince: .distantPast) { [weak self] in
            guard let self else { return }
            self.websiteDataStore.fetchDataRecords(ofTypes: types) { [weak self] records in
                guard let self else { return }
                self.isResetting = false
                self.resetMessage = records.isEmpty
                    ? L("Локальные данные очищены. Откройте ChatGPT заново, когда будете готовы.", "Local data cleared. Reopen ChatGPT when you are ready.")
                    : L("Остались данные сайтов. Повторите очистку; полный сброс пока не подтверждён.", "Website data remains. Clear again; a complete reset has not been confirmed.")
                completion?()
            }
        }
    }
    @Published var textStatus: String?
    private var textAttempt = UUID()
    func copyResponse(selectionOnly: Bool) {
        guard !isResetting, !needsRestart else { return }
        let attempt = textAttempt
        webView.callAsyncJavaScript(ChatGPTTextBridge.copy, arguments: ["selectionOnly": selectionOnly], in: nil, in: .page) { [weak self] result in
            guard let self = self, self.textAttempt == attempt else { return }
            let value = try? result.get() as? [String: Any]
            guard value?["status"] as? String == "copied", let text = value?["text"] as? String, !text.isEmpty else {
                self.textStatus = value?["status"] as? String == "busy"
                    ? L("Дождись завершения ответа или останови генерацию.", "Wait for the response to finish or stop generation.")
                    : L("Ответ не распознан. Выдели нужный текст и скопируй через ⌘C.", "Response not recognized. Select the text and copy with ⌘C.")
                return
            }
            NSPasteboard.general.clearContents()
            self.textStatus = NSPasteboard.general.setString(text, forType: .string)
                ? L("Скопировано. Вставь в нужное приложение через ⌘V.", "Copied. Paste into another app with ⌘V.")
                : L("Не удалось скопировать ответ.", "Could not copy the response.")
        }
    }
    private func resetTextOperation() {
        textAttempt = UUID()
        textStatus = nil
    }
    @Published var detached = false
    @Published var errorMessage: String?
    @Published var screenshotURL: URL?
    @Published var screenshotStatus: String?
    @Published var attachingScreenshot = false
    private var screenshotAttempt = UUID()

    func attachScreenshot(_ url: URL) {
        guard !isResetting, !needsRestart, !attachingScreenshot else { return }
        screenshotURL = url
        screenshotStatus = L("Добавляем снимок…", "Adding screenshot…")
        guard !webView.isLoading, webView.url?.host == "chatgpt.com" else {
            screenshotStatus = L("Дождись загрузки чата и сделай снимок ещё раз.", "Wait for the chat to load, then take another screenshot.")
            return
        }
        let attempt = UUID()
        screenshotAttempt = attempt
        attachingScreenshot = true
        // Read the selected PNG off the UI thread; never read arbitrary page-provided paths.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { () throws -> Data in
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size > 0, size <= 20 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
                let data = try Data(contentsOf: url)
                guard data.starts(with: [137,80,78,71,13,10,26,10]) else { throw CocoaError(.fileReadCorruptFile) }
                return data
            }
            DispatchQueue.main.async {
                guard let self = self, self.screenshotAttempt == attempt else { return }
                guard case .success(let data) = result else {
                    self.attachingScreenshot = false
                    self.screenshotStatus = L("Не удалось прочитать PNG (до 20 МБ). Файл сохранён.", "Could not read the PNG (up to 20 MB). The file was saved.")
                    return
                }
                self.webView.callAsyncJavaScript(ChatGPTScreenshot.script,
                    arguments: ["png": data.base64EncodedString(), "name": url.lastPathComponent],
                    in: nil, in: .page) { [weak self] result in
                    guard let self = self, self.screenshotAttempt == attempt else { return }
                    self.attachingScreenshot = false
                    switch result {
                    case .success(let value) where value as? String == "handled":
                        self.screenshotStatus = L("Дождись миниатюры в поле GPT перед отправкой.", "Wait for the thumbnail in the GPT composer before sending.")
                    case .success(let value) where value as? String == "unavailable":
                        self.screenshotStatus = L("Открой чат и сделай снимок ещё раз.", "Open the chat and take another screenshot.")
                    default:
                        self.screenshotStatus = L("Если миниатюры нет, вставь снимок в поле через ⌘V.", "If there is no thumbnail, paste the screenshot with ⌘V.")
                    }
                }
            }
        }
    }
    func dismissScreenshotStatus() {
        screenshotAttempt = UUID()
        attachingScreenshot = false
        screenshotURL = nil
        screenshotStatus = nil
    }
    private func interruptScreenshotAttachment() {
        // Invalidate callbacks from the old document without losing the user's retry source.
        screenshotAttempt = UUID()
        attachingScreenshot = false
        if screenshotURL != nil {
            screenshotStatus = L("Снимок сохранён. Если вложения нет, после загрузки чата сделай снимок ещё раз.", "Screenshot saved. If the attachment is missing, take another screenshot once the chat loads.")
        } else {
            screenshotStatus = nil
        }
    }
    private var largeWindow: NSWindow?
    private var popups: [NSWindow] = []
    private var started = false
    var webView: WKWebView {
        if let storedWebView { return storedWebView }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = websiteDataStore
        configuration.userContentController.addUserScript(WKUserScript(
            source: ChatGPTCompact.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        #if DEBUG
        if Self.auditHostsOnLaunch {
            configuration.userContentController.addUserScript(WKUserScript(
                source: "performance.setResourceTimingBufferSize(4000)",
                injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .defaultClient))
        }
        #endif
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        storedWebView = view
        return view
    }

    func start() {
        guard !started, !isResetting, !needsRestart else { return }
        started = true
        newChat()
    }
    func newChat() {
        guard !isResetting else { return }
        needsRestart = false
        started = true
        resetMessage = nil
        dismissScreenshotStatus()
        resetTextOperation()
        errorMessage = nil
        webView.load(URLRequest(url: URL(string: "https://chatgpt.com/")!))
    }
    #if DEBUG
    static let auditHostsOnLaunch = CommandLine.arguments.contains("--audit-chatgpt-hosts")
    private var didSampleHosts = false

    private func sampleResourceHosts(from view: WKWebView) {
        guard Self.auditHostsOnLaunch, !didSampleHosts,
              view === storedWebView, view.url?.host == "chatgpt.com" else { return }
        didSampleHosts = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self, weak view] in
            guard let self, let view, view === self.storedWebView,
                  !self.isResetting, view.url?.host == "chatgpt.com" else { return }
            view.evaluateJavaScript("""
                (() => {
                  if (location.origin !== 'https://chatgpt.com') return null;
                  const hosts = performance.getEntriesByType('resource').flatMap(entry => {
                    try { const u = new URL(entry.name); return u.protocol === 'https:' ? [u.hostname] : []; }
                    catch { return []; }
                  });
                  return { count: hosts.length, hosts: [...new Set(hosts)].sort() };
                })()
                """, in: nil, in: .defaultClient) { result in
                guard case .success(let value) = result, let sample = value as? [String: Any],
                      let count = sample["count"] as? Int, let hosts = sample["hosts"] as? [String]
                else { return }
                print("NOTCH_HOST_AUDIT count=\(count) hosts=\(hosts.joined(separator: ","))")
                fflush(stdout)
            }
        }
    }

    func saveLayoutDiagnostics() {
        webView.evaluateJavaScript(ChatGPTLayoutDiagnostics.script) { [weak self] result, error in
            guard error == nil, let json = result as? String else {
                self?.errorMessage = L("Не удалось снять диагностику страницы.", "Could not collect page diagnostics.")
                return
            }
            let file = URL(fileURLWithPath: "/private/tmp/notch-chatgpt-layout.json")
            do {
                try json.write(to: file, atomically: true, encoding: .utf8)
                NSWorkspace.shared.activateFileViewerSelecting([file])
            } catch { self?.errorMessage = L("Не удалось сохранить диагностику страницы.", "Could not save page diagnostics.") }
        }
    }
    #endif
    func reload() { guard !isResetting, !needsRestart else { return }; errorMessage = nil; webView.reload() }
    func openBrowser() {
        guard let url = webView.url, url.scheme == "https", url.host == "chatgpt.com" else { return }
        NSWorkspace.shared.open(url)
    }
    func showWindow() {
        start()
        if let window = largeWindow { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        detached = true
        webView.removeFromSuperview()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "ChatGPT — NotchIsland"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: LocalizedRoot { ChatGPTWindowView(session: self) })
        largeWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === largeWindow {
            webView.removeFromSuperview()
            largeWindow = nil
            detached = false
        } else { popups.removeAll { $0 === window } }
    }
    func webView(_ view: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if view === webView { errorMessage = nil; interruptScreenshotAttachment(); resetTextOperation() }
    }
    func webView(_ view: WKWebView, didFinish navigation: WKNavigation!) {
        #if DEBUG
        sampleResourceHosts(from: view)
        #endif
        if view === webView { errorMessage = nil }
        else { view.window?.title = view.url?.host ?? "ChatGPT" }
    }
    func webView(_ view: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { report(error, from: view) }
    func webView(_ view: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { report(error, from: view) }
    private func report(_ error: Error, from view: WKWebView) {
        guard let message = ChatGPTNavigationError.message(for: error) else { return }
        // A failed login popup must not masquerade as a failed conversation load.
        errorMessage = view === webView ? message : L("Ошибка окна входа. Закрой его и повтори вход из большого окна.", "Sign-in window error. Close it and sign in again from the full window.")
    }
    func webViewWebContentProcessDidTerminate(_ view: WKWebView) {
        if view === webView {
            resetTextOperation()
            interruptScreenshotAttachment()
            errorMessage = L("Страница остановлена. Нажми обновление.", "The page stopped. Click reload.")
        } else {
            errorMessage = L("Окно входа остановлено. Закрой его и повтори вход из большого окна.", "The sign-in window stopped. Close it and try again from the full window.")
        }
    }
    func webView(_ view: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard !isResetting, !needsRestart, let url = action.request.url else { decisionHandler(.cancel); return }
        switch ChatGPTNavigationPolicy.decision(url, mainFrame: action.targetFrame?.isMainFrame ?? true,
                                               approvedHosts: approvedNavigationHosts) {
        case .allow: decisionHandler(.allow)
        case .cancel: decisionHandler(.cancel)
        case .confirm(let host):
            guard !confirmingNavigation else { decisionHandler(.cancel); return }
            confirmingNavigation = true
            let generation = dataGeneration
            let alert = NSAlert()
            let copy = ChatGPTNavigationPolicy.alert(for: host)
            alert.messageText = copy.0
            alert.informativeText = copy.1
            alert.addButton(withTitle: L("Отмена", "Cancel"))
            alert.addButton(withTitle: L("Открыть здесь", "Open here"))
            // Never replay POST data or automatically send redirect URLs to another app.
            let canOpenBrowser = action.navigationType == .linkActivated &&
                (action.request.httpMethod ?? "GET") == "GET"
            if canOpenBrowser { alert.addButton(withTitle: L("В браузере", "In browser")) }
            let result = alert.runModal()
            confirmingNavigation = false
            guard generation == dataGeneration, !isResetting, !needsRestart else {
                decisionHandler(.cancel); return
            }
            if result == .alertSecondButtonReturn {
                approvedNavigationHosts.insert(host)
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
                if canOpenBrowser && result == .alertThirdButtonReturn { NSWorkspace.shared.open(url) }
            }
        }
    }
    func webView(_ view: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard !isResetting, !needsRestart, let url = action.request.url,
              ChatGPTNavigationPolicy.decision(url, mainFrame: true, approvedHosts: approvedNavigationHosts) == .allow else { return nil }
        let child = WKWebView(frame: .zero, configuration: configuration)
        child.navigationDelegate = self
        child.uiDelegate = self
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 700), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = action.request.url?.host ?? "ChatGPT"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = child
        popups.append(window)
        window.center()
        window.makeKeyAndOrderFront(nil)
        return child
    }
    func webViewDidClose(_ webView: WKWebView) { webView.window?.close() }
    func webView(_ view: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        guard !isResetting, !needsRestart else { completionHandler(nil); return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        let generation = dataGeneration
        panel.begin { [weak self] result in
            guard let self, self.dataGeneration == generation, !self.isResetting, !self.needsRestart else {
                completionHandler(nil); return
            }
            completionHandler(result == .OK ? panel.urls : nil)
        }
    }
}

struct ChatGPTPage: NSViewRepresentable {
    let session: ChatGPTSession
    let inWindow: Bool
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ container: NSView, context: Context) {
        guard !session.isResetting, !session.needsRestart, session.detached == inWindow else { return }
        let web = session.webView
        if web.superview !== container {
            web.removeFromSuperview()
            web.translatesAutoresizingMaskIntoConstraints = true
            web.autoresizingMask = [.width, .height]
            web.frame = container.bounds
            container.addSubview(web)
        }
        session.start()
    }
}

struct ChatGPTControls: View {
    @ObservedObject var session: ChatGPTSession
    var body: some View {
        HStack(spacing: 12) {
            ChatGPTTextTools(session: session)
            Button(action: session.newChat) { Image(systemName: "square.and.pencil") }.help(L("Новый чат", "New chat"))
            Button(action: session.reload) { Image(systemName: "arrow.clockwise") }.help(L("Обновить", "Reload"))
            Spacer()
            #if DEBUG
            Button(action: session.saveLayoutDiagnostics) { Image(systemName: "ladybug") }
                .help(L("Сохранить диагностику компоновки без текста сообщений", "Save layout diagnostics without message text"))
            #endif
            Button(action: session.openBrowser) { Image(systemName: "safari") }.help(L("Открыть разговор в браузере", "Open conversation in browser"))
            Button(action: session.showWindow) { Image(systemName: "arrow.up.left.and.arrow.down.right") }.help(L("Большое окно и вход в аккаунт", "Full window and sign in")).disabled(session.needsRestart)
        }.buttonStyle(.plain).disabled(session.isResetting)
    }
}

struct ChatGPTIslandView: View {
    @ObservedObject var session = ChatGPTSession.shared
    let screenshot: () -> Void
    let collapse: () -> Void
    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Button(action: screenshot) { Image(systemName: "viewfinder") }.buttonStyle(.plain).help(L("Снимок прикрепляется к ChatGPT и может загрузиться до отправки сообщения", "The screenshot is attached to ChatGPT and may upload before you send the message")).disabled(session.isResetting || session.needsRestart)
                ChatGPTControls(session: session)
            }.font(.system(size: 12)).frame(height: 18)
            if session.isResetting || session.needsRestart {
                VStack(spacing: 8) {
                    Text(session.isResetting ? L("Очистка данных…", "Clearing data…") : (session.resetMessage ?? ""))
                        .font(.caption)
                    Button(L("Открыть ChatGPT", "Open ChatGPT"), action: session.newChat)
                        .disabled(session.isResetting)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if session.detached {
                Button(L("Продолжить в большом окне", "Continue in full window")) { collapse(); session.showWindow() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ChatGPTPage(session: session, inWindow: false).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if let status = session.textStatus {
                Text(status).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(2)
            }
            if let error = session.errorMessage { Text(error).font(.system(size: 10)).foregroundColor(.orange).lineLimit(2) }
            if let url = session.screenshotURL, let status = session.screenshotStatus {
                HStack(spacing: 6) {
                    Text(status).font(.system(size: 10)).lineLimit(2)
                    Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                        Image(systemName: "folder")
                    }.help(L("Показать сохранённый снимок", "Show saved screenshot"))
                    Button { session.dismissScreenshotStatus() } label: {
                        Image(systemName: "xmark")
                    }.help(L("Скрыть подсказку; вложение удаляется в поле GPT", "Hide hint; remove attachments in the GPT composer"))
                }.font(.system(size: 10)).buttonStyle(.plain)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: session.detached) { detached in if detached { collapse() } }
    }
}

private struct ChatGPTWindowView: View {
    @ObservedObject var session: ChatGPTSession
    var body: some View {
        VStack(spacing: 6) {
            ChatGPTControls(session: session).padding(8)
            if let error = session.errorMessage { Text(error).foregroundColor(.orange).font(.caption) }
            if let status = session.textStatus { Text(status).font(.caption).foregroundColor(.secondary) }
            ChatGPTPage(session: session, inWindow: true)
        }.preferredColorScheme(.dark)
    }
}
