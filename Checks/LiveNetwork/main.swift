import AppKit
import WebKit

// The production delegate uses WebKit's default response policy. Observe the main
// response in this standalone probe, preserving WebKit's MIME capability check.
extension ChatGPTSession {
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if response.isForMainFrame, let http = response.response as? HTTPURLResponse {
            print("Main response:", http.url?.host ?? "none", "HTTP", http.statusCode)
        }
        decisionHandler(response.canShowMIMEType ? .allow : .cancel)
    }
}

// Explicit live audit. The probe loads the public page without signing in.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let store = WKWebsiteDataStore.nonPersistent()
let session = ChatGPTSession(websiteDataStore: store)
let view = session.webView
view.configuration.userContentController.addUserScript(WKUserScript(
    source: "performance.setResourceTimingBufferSize(4000)",
    injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .defaultClient))
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
                      styleMask: [.borderless], backing: .buffered, defer: false)
window.contentView = view
func spin(_ seconds: TimeInterval) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

session.start()
let deadline = Date().addingTimeInterval(30)
while view.isLoading && Date() < deadline { spin(0.1) }
spin(5)
print("Document host:", view.url?.host ?? "none", "loading:", view.isLoading,
      "navigation error:", session.errorMessage != nil)
var sampled = false
view.evaluateJavaScript("""
(() => {
  const hosts = performance.getEntriesByType('resource').flatMap(entry => {
    try { const u = new URL(entry.name); return u.protocol === 'https:' ? [u.hostname] : []; }
    catch { return []; }
  });
  const nav = performance.getEntriesByType('navigation')[0];
  return { hosts: [...new Set(hosts)].sort(), count: hosts.length, status: nav?.responseStatus || 0 };
})()
""", in: nil, in: .defaultClient) { result in
    if case .success(let value) = result, let sample = value as? [String: Any] {
        print("Document HTTP status (0 if unavailable):", sample["status"] ?? 0)
        print("HTTPS resource timing entries:", sample["count"] ?? 0)
        print("Resource hosts:", (sample["hosts"] as? [String] ?? []).joined(separator: ", "))
    } else { print("Resource sample unavailable") }
    sampled = true
}
let sampleDeadline = Date().addingTimeInterval(5)
while !sampled && Date() < sampleDeadline { spin(0.05) }
if !sampled { print("Resource sample timed out") }
view.stopLoading()

// Public fixture: first public YouTube video, independent of local playback.
var finished = false
let request = RemoteArtworkRequest.start(URL(string: "https://i.ytimg.com/vi/jNQXAC9IVRw/hqdefault.jpg")!) { data in
    print("i.ytimg.com validated artwork bytes:", data?.count ?? 0)
    finished = true
}
let artworkDeadline = Date().addingTimeInterval(25)
while !finished && Date() < artworkDeadline { spin(0.05) }
if !finished { print("Artwork timed out"); request?.cancel() }
