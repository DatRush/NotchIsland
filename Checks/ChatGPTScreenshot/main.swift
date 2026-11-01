import AppKit
import WebKit

// Local fixtures only. No account, network requests, or real uploads.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let config = WKWebViewConfiguration()
config.websiteDataStore = .nonPersistent()
let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 404, height: 237), configuration: config)
let window = NSWindow(contentRect: web.frame, styleMask: [.titled], backing: .buffered, defer: false)
window.title = "NotchIsland compact layout checks"
window.contentView = web
window.orderFront(nil) // requestAnimationFrame must run for input/mutation checks.
final class Loader: NSObject, WKNavigationDelegate {
    var loaded = false
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded = true }
}
let loader = Loader()
web.navigationDelegate = loader
func wait(_ description: String, _ predicate: () -> Bool) {
    let deadline = Date().addingTimeInterval(15)
    while !predicate() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    guard predicate() else { fatalError("Timed out: \(description)") }
}
@discardableResult func js(_ source: String) -> Any? {
    var done = false
    var result: Any?
    web.evaluateJavaScript(source) { value, error in
        if let error = error { fatalError("JavaScript failed: \(error)") }
        result = value; done = true
    }
    wait("JavaScript") { done }
    return result
}
func expect(_ description: String, _ expression: String) {
    guard js(expression) as? Bool == true else { fatalError("FAIL: \(description)") }
    print("PASS: \(description)")
}

let html = """
<html><body><form><div contenteditable="true" id="prompt-textarea">Question stays here</div><button type="submit">Send</button><div id="attachments"></div></form>
<script>
window.sent=0;window.received=[];
document.querySelector('form').addEventListener('submit',e=>{e.preventDefault();window.sent++});
window.handler=e=>{e.preventDefault(); const file=e.clipboardData.files[0]; window.received.push({name:file.name,type:file.type,size:file.size}); const item=document.createElement('button');item.type='button';item.textContent=file.name;item.onclick=()=>item.remove();document.querySelector('#attachments').append(item)};
document.querySelector('[contenteditable]').addEventListener('paste',window.handler);
</script></body></html>
"""
func load(_ url: String = "https://chatgpt.com/c/fixture") {
    loader.loaded=false
    web.loadHTMLString(html,baseURL:URL(string:url))
    wait("load") { loader.loaded }
}
func attach() -> String {
    var done=false;var output=""
    web.callAsyncJavaScript(ChatGPTScreenshot.script,
        arguments:["png":Data([137,80,78,71,13,10,26,10]).base64EncodedString(),"name":"Снимок 'test'.png"],
        in:nil,in:.page) { result in
        switch result {case .success(let value):output=value as? String ?? "";case .failure(let error):fatalError("\(error)")}
        done=true
    }
    wait("attach") { done }
    return output
}
load()
guard attach()=="handled" else {fatalError("Paste not handled")}
expect("PNG file delivered once with intact metadata", "received.length===1 && received[0].type==='image/png' && received[0].size===8 && received[0].name===\"Снимок 'test'.png\"")
expect("Question preserved and no submit", "document.querySelector('[contenteditable]').textContent==='Question stays here' && sent===0")
js("document.querySelector('#attachments button').click()")
expect("Site can remove attachment", "document.querySelector('#attachments').children.length===0")
js("document.querySelector('[contenteditable]').removeEventListener('paste',window.handler)")
guard attach()=="unconfirmed" else {fatalError("Unhandled paste reported success")}
js("document.querySelector('form').insertAdjacentHTML('beforeend','<div contenteditable=true></div>');document.querySelector('#prompt-textarea').removeAttribute('id')")
guard attach()=="unavailable" else {fatalError("Ambiguous editor accepted")}
// A handled paste can still fail asynchronously on the service. Only explicit retry is allowed.
load()
js("window.attempts=0;window.failUpload=true;document.querySelector('[contenteditable]').removeEventListener('paste',window.handler);document.querySelector('[contenteditable]').addEventListener('paste',e=>{e.preventDefault();attempts++;if(failUpload){setTimeout(()=>{document.querySelector('#attachments').innerHTML='<div role=alert>Upload failed</div>'},20)}else{document.querySelector('#attachments').innerHTML='';window.handler(e)}})")
guard attach()=="handled" else {fatalError("Failure fixture did not accept paste")}
wait("asynchronous upload failure") { js("document.querySelector('[role=alert]')!==null") as? Bool == true }
expect("Handled paste does not imply successful upload or automatic retry", "attempts===1 && received.length===0 && sent===0")
expect("Failed upload preserves draft", "document.querySelector('[contenteditable]').textContent==='Question stays here'")
js("window.failUpload=false")
guard attach()=="handled" else {fatalError("Explicit retry was not handled")}
expect("Explicit retry delivers exactly one attachment", "attempts===2 && received.length===1 && document.querySelector('#attachments').children.length===1 && !document.querySelector('[role=alert]')")
expect("Retry preserves draft without submitting", "document.querySelector('[contenteditable]').textContent==='Question stays here' && sent===0")
load("https://chatgpt.com/auth/login")
guard attach()=="unavailable" else {fatalError("Auth route accepted")}
load("https://example.org/")
guard attach()=="unavailable" else {fatalError("Foreign origin accepted")}
print("All screenshot bridge checks passed (file, draft, no submit, removal, unhandled, ambiguity, auth, origin)")
window.orderOut(nil)
