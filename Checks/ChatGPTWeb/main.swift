import AppKit
import WebKit

// Isolated feasibility probe: ordinary website navigation, no private API or DOM bridge.
final class Probe: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate {
    private var window: NSWindow!
    private var web: WKWebView!
    private let address = NSTextField(labelWithString: "chatgpt.com")
    private var popups: [NSWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "NotchIsland — проверка ChatGPT"
        window.isReleasedWhenClosed = false
        let controls = NSStackView()
        controls.orientation = .horizontal
        controls.spacing = 8
        for (title, action) in [("Новый чат", #selector(home)), ("Обновить", #selector(reload)),
                                ("Размер", #selector(resize)), ("В браузере", #selector(openBrowser)),
                                ("Сброс входа", #selector(resetSession))] {
            controls.addArrangedSubview(NSButton(title: title, target: self, action: action))
        }
        controls.distribution = .fillProportionally
        address.font = .systemFont(ofSize: 11)
        address.lineBreakMode = .byTruncatingMiddle
        let root = NSView()
        window.contentView = root
        for view in [controls, address, web!] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            controls.topAnchor.constraint(equalTo: root.topAnchor, constant: 6),
            controls.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 6),
            controls.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -6),
            address.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 4),
            address.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            address.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            web.topAnchor.constraint(equalTo: address.bottomAnchor, constant: 4),
            web.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        home()
    }

    @objc private func home() { web.load(URLRequest(url: URL(string: "https://chatgpt.com/")!)) }
    @objc private func reload() { web.reload() }
    @objc private func resize() {
        // Includes test controls; the usable page is smaller than 405 × 240.
        let small = window.contentView!.bounds.width > 500
        window.setContentSize(small ? NSSize(width: 405, height: 240) : NSSize(width: 900, height: 700))
    }
    @objc private func openBrowser() {
        guard let url = web.url, url.scheme == "https", url.host == "chatgpt.com" else { return }
        NSWorkspace.shared.open(url)
    }
    @objc private func resetSession() {
        let alert = NSAlert()
        alert.messageText = "Удалить вход в тестовом окне?"
        alert.informativeText = "Будут удалены данные сайтов этого прототипа. Вход в обычном браузере сохранится."
        alert.addButton(withTitle: "Удалить")
        alert.addButton(withTitle: "Отмена")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        web.stopLoading()
        popups.forEach { $0.close() }
        popups.removeAll()
        web.loadHTMLString("", baseURL: nil)
        web.configuration.websiteDataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { [weak self] in
            self?.home()
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === web { address.stringValue = webView.url?.host ?? "" }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { address.stringValue = "Не удалось загрузить: \(error.localizedDescription)" }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        decisionHandler(["https", "about"].contains(url.scheme ?? "") ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let child = WKWebView(frame: .zero, configuration: configuration)
        child.uiDelegate = self
        child.navigationDelegate = self
        let popup = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 700), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        popup.title = "ChatGPT — дополнительное окно"
        popup.isReleasedWhenClosed = false
        popup.contentView = child
        popups.append(popup)
        popup.center()
        popup.makeKeyAndOrderFront(nil)
        return child
    }
    func webViewDidClose(_ webView: WKWebView) {
        popups.first { $0.contentView === webView }?.close()
        popups.removeAll { $0.contentView === webView }
    }
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.begin { result in completionHandler(result == .OK ? panel.urls : nil) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = Probe()
app.delegate = delegate
app.run()
