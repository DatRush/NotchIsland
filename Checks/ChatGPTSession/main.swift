import AppKit
import WebKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let session = ChatGPTSession()
let page = session.webView // Does not start navigation or read/export website data.
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
    print("PASS: \(message)")
}
for (code, fragment) in [
    (NSURLErrorNotConnectedToInternet, "Соединение"),
    (NSURLErrorNetworkConnectionLost, "Соединение"),
    (NSURLErrorTimedOut, "вовремя"),
    (NSURLErrorCannotFindHost, "подключиться"),
    (NSURLErrorCannotConnectToHost, "подключиться"),
    (NSURLErrorDNSLookupFailed, "подключиться"),
    (NSURLErrorSecureConnectionFailed, "защищённое"),
    (NSURLErrorServerCertificateUntrusted, "защищённое")
] {
    session.webView(page, didFailProvisionalNavigation:nil, withError:NSError(domain:NSURLErrorDomain,code:code))
    check(session.errorMessage?.contains(fragment) == true, "navigation error \(code)")
}
let previous = session.errorMessage
session.webView(page, didFailProvisionalNavigation:nil, withError:NSError(domain:NSURLErrorDomain,code:NSURLErrorCancelled))
check(session.errorMessage == previous, "cancelled navigation does not replace status")
check(ChatGPTNavigationError.message(for:NSError(domain:"custom",code:NSURLErrorCancelled)) != nil, "foreign-domain error is not mistaken for cancellation")
session.webView(page, didStartProvisionalNavigation:nil)
check(session.errorMessage == nil, "new navigation clears old load error")
session.webView(page, didFail:nil, withError:NSError(domain:NSURLErrorDomain,code:NSURLErrorTimedOut))
check(session.errorMessage != nil, "committed navigation error is shown")
session.webView(page, didFinish:nil)
check(session.errorMessage == nil, "successful load clears error")
let config = WKWebViewConfiguration()
config.websiteDataStore = .nonPersistent()
let popup = WKWebView(frame:.zero,configuration:config)
session.webView(popup, didFailProvisionalNavigation:nil, withError:NSError(domain:NSURLErrorDomain,code:NSURLErrorNotConnectedToInternet))
check(session.errorMessage?.contains("окна входа") == true, "popup failure is identified separately")
session.textStatus = "Pending"
session.screenshotStatus = "Pending"
session.webViewWebContentProcessDidTerminate(page)
check(session.textStatus == nil && session.screenshotStatus == nil, "process termination clears pending operation state")
check(session.errorMessage?.contains("остановлена") == true, "process termination explains recovery")
check(page.configuration.websiteDataStore.isPersistent, "main view uses persistent WebKit store")
check(session.webView === page, "same page retained across access")
// Retry before a chat is ready must retain the selected file without starting an upload.
let selectedScreenshot = URL(fileURLWithPath: "/private/tmp/notch-session-fixture.png")
session.attachScreenshot(selectedScreenshot)
check(session.screenshotURL == selectedScreenshot && !session.attachingScreenshot, "unavailable chat retains screenshot for retry")
check(session.screenshotStatus?.contains("снимок") == true, "unavailable chat explains manual retry")
session.attachScreenshot(selectedScreenshot)
check(session.screenshotURL == selectedScreenshot && !session.attachingScreenshot, "repeated unavailable attempt stays retryable")
session.webView(page, didStartProvisionalNavigation:nil)
check(session.screenshotURL == selectedScreenshot && !session.attachingScreenshot, "navigation retains screenshot retry source")
session.webView(page, didFailProvisionalNavigation:nil, withError:NSError(domain:NSURLErrorDomain,code:NSURLErrorNotConnectedToInternet))
check(session.screenshotURL == selectedScreenshot && session.screenshotStatus?.contains("снимок") == true, "offline failure preserves manual retry")
session.webView(page, didFinish:nil)
check(session.screenshotURL == selectedScreenshot && !session.attachingScreenshot, "recovery does not automatically upload")
session.webViewWebContentProcessDidTerminate(page)
check(session.screenshotURL == selectedScreenshot && !session.attachingScreenshot, "process termination retains screenshot retry source")
session.dismissScreenshotStatus()
check(session.screenshotURL == nil && session.screenshotStatus == nil, "dismiss clears retry prompt")
print("All session checks passed; no website loaded, login state or system clipboard modified")

// Reset only isolated stores. Never clear the default/user website store.
func waitForResetCheck(_ predicate: () -> Bool) {
    let deadline = Date().addingTimeInterval(15)
    while !predicate() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    check(predicate(), "asynchronous isolated store operation completed")
}
let isolated = WKWebsiteDataStore.nonPersistent()
let untouched = WKWebsiteDataStore.nonPersistent()
let cookie = HTTPCookie(properties: [.domain: "privacy.invalid", .path: "/", .name: "fixture", .value: "synthetic", .secure: "TRUE"])!
var seeded = 0
isolated.httpCookieStore.setCookie(cookie) { seeded += 1 }
untouched.httpCookieStore.setCookie(cookie) { seeded += 1 }
waitForResetCheck { seeded == 2 }
let resetSession = ChatGPTSession(websiteDataStore: isolated)
let oldPage = resetSession.webView
final class ResetFixtureLoader: NSObject, WKNavigationDelegate {
    var ready = false
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready = true }
}
let fixtureLoader = ResetFixtureLoader()
oldPage.navigationDelegate = fixtureLoader
oldPage.loadHTMLString("<html><body><script>localStorage.setItem('privacy-fixture', 'synthetic')</script></body></html>", baseURL: URL(string: "https://privacy.invalid/"))
waitForResetCheck { fixtureLoader.ready }
var seededValue: String?
oldPage.evaluateJavaScript("localStorage.getItem('privacy-fixture')") { value, _ in seededValue = value as? String }
waitForResetCheck { seededValue == "synthetic" }
oldPage.navigationDelegate = resetSession
resetSession.screenshotURL = URL(fileURLWithPath: "/private/tmp/notch-reset-synthetic.png")
resetSession.textStatus = "synthetic"
var resetDone = false
resetSession.clearWebsiteData { resetDone = true }
check(resetSession.isResetting && resetSession.needsRestart, "reset blocks automatic page start")
resetSession.start()
resetSession.newChat()
resetSession.attachScreenshot(URL(fileURLWithPath: "/private/tmp/must-not-read.png"))
check(resetSession.screenshotURL == nil && resetSession.textStatus == nil, "reset clears pending content and rejects attachments")
waitForResetCheck { resetDone }
var clearedCookies: [HTTPCookie]?
var otherCookies: [HTTPCookie]?
isolated.httpCookieStore.getAllCookies { clearedCookies = $0 }
untouched.httpCookieStore.getAllCookies { otherCookies = $0 }
waitForResetCheck { clearedCookies != nil && otherCookies != nil }
check(clearedCookies!.isEmpty, "reset removes isolated cookies")
check(otherCookies!.contains { $0.name == "fixture" }, "reset preserves other website stores")
check(!resetSession.isResetting && resetSession.needsRestart && resetSession.resetMessage != nil, "reset completes with explicit restart required")
resetSession.start()
resetSession.reload()
check(resetSession.webView !== oldPage && resetSession.webView.url == nil, "reset replaces page and does not navigate automatically")
check(oldPage.navigationDelegate == nil && oldPage.uiDelegate == nil, "old page callbacks detached")
let clearedPage = resetSession.webView
fixtureLoader.ready = false
clearedPage.navigationDelegate = fixtureLoader
clearedPage.loadHTMLString("<html><body>local fixture</body></html>", baseURL: URL(string: "https://privacy.invalid/"))
waitForResetCheck { fixtureLoader.ready }
var storageChecked = false
clearedPage.evaluateJavaScript("localStorage.getItem('privacy-fixture') === null") { value, error in
    check(error == nil && value as? Bool == true, "reset removes localStorage contents")
    storageChecked = true
}
waitForResetCheck { storageChecked }
clearedPage.navigationDelegate = resetSession
var secondResetDone = false
resetSession.clearWebsiteData { secondResetDone = true }
waitForResetCheck { secondResetDone }
check(resetSession.needsRestart, "repeated empty-store reset remains stopped")
print("PASS: isolated reset, cookie deletion, scope, pending actions, page replacement and explicit restart")

// Pure document-policy tests: no real site, browser launch or account is used.
func navigation(_ value: String, main: Bool = true, hosts: Set<String> = []) -> ChatGPTNavigationPolicy.Decision {
    ChatGPTNavigationPolicy.decision(URL(string: value)!, mainFrame: main, approvedHosts: hosts)
}
for host in ["chatgpt.com", "auth.openai.com", "auth0.openai.com"] {
    check(navigation("https://" + host) == .allow, "built-in document host " + host)
}
for value in ["http://chatgpt.com", "file:///tmp/example", "javascript:alert(1)", "about:config", "https://user:pass@chatgpt.com", "https://chatgpt.com:444"] {
    check(navigation(value) == .cancel, "unsafe navigation rejected " + value)
}
for host in ["chatgpt.com.attacker.invalid", "accounts.google.com", "appleid.apple.com", "login.microsoftonline.com", "company.invalid"] {
    check(navigation("https://" + host) == .confirm(host), "unapproved host needs consent " + host)
    check(navigation("https://" + host, hosts: [host]) == .allow, "explicit consent permits exact host " + host)
}
check(navigation("https://child.company.invalid", hosts: ["company.invalid"]) == .confirm("child.company.invalid"), "consent does not cover subdomains")
check(navigation("https://challenge.invalid", main: false) == .allow, "HTTPS subframe remains available")
check(navigation("http://challenge.invalid", main: false) == .cancel, "insecure subframe blocked")
check(navigation("about:blank") == .allow, "blank popup bootstrap allowed")
