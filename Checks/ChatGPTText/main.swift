import AppKit
import WebKit

// Local fixtures only. No account, network requests, or real uploads.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let config = WKWebViewConfiguration()
config.websiteDataStore = .nonPersistent()
let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 404, height: 237), configuration: config)
let window = NSWindow(contentRect: web.frame, styleMask: [.titled], backing: .buffered, defer: false)
window.title = "NotchIsland response copying checks"
window.contentView = web
window.makeKeyAndOrderFront(nil) // requestAnimationFrame must run for input/mutation checks.
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


let html = #"""
<!doctype html><html><body>
<section role="region" aria-label="Conversation">
<div data-message-author-role="user"><div class="markdown">Question</div></div>
<div data-message-author-role="assistant"><div class="markdown">Earlier answer</div></div>
<div data-message-author-role="assistant" id="answer"><div class="markdown" id="body"><p>Latest answer</p><pre>let x = 1;</pre><ul><li>First</li><li>Second</li></ul></div><button>Copy toolbar</button></div>
</section>
<form><div id="attachment">keep.png</div><div id="prompt-textarea" contenteditable="true"></div><button type="submit">Send</button></form>
<script>window.sent=0;window.inputs=0;document.querySelector('form').onsubmit=e=>{e.preventDefault();sent++};document.querySelector('form').oninput=()=>inputs++;</script>
</body></html>
"""#
func load(_ url: String = "https://chatgpt.com/c/test") {
    loader.loaded=false
    web.loadHTMLString(html,baseURL: URL(string:url))
    wait("load") {loader.loaded}
}
func call(_ script: String, _ arguments: [String: Any]) -> [String: Any] {
    var done=false; var output: [String:Any] = [:]
    web.callAsyncJavaScript(script, arguments:arguments, in:nil, in:.page) { result in
        switch result {case .success(let value): output=value as? [String:Any] ?? [:]
        case .failure(let error):fatalError("\(error)")}
        done=true
    }
    wait("bridge") {done}
    return output
}
func copy(_ selection: Bool = false) -> [String:Any] {
    call(ChatGPTTextBridge.copy,["selectionOnly":selection])
}
func status(_ actual: String?, _ expected: String) {
    guard actual == expected else { FileHandle.standardError.write(Data((String(describing: js("JSON.stringify(document.querySelector('#prompt-textarea')?.innerText)")) + "\n").utf8)); fatalError("Expected \(expected), got \(actual ?? "nil")")}
    print("PASS: \(expected)")
}
load()
let copied = copy()
status(copied["status"] as? String,"copied")
guard let answer = copied["text"] as? String, answer.contains("Latest answer"), answer.contains("let x = 1;"), answer.contains("Second"), !answer.contains("Earlier"), !answer.contains("toolbar") else {fatalError("Wrong response copied")}
let board = NSPasteboard(name:NSPasteboard.Name("NotchIsland.CopyCheck.\(UUID().uuidString)"))
board.clearContents()
guard board.setString(answer,forType:.string), board.string(forType:.string)==answer else {fatalError("Clipboard round trip failed")}
board.releaseGlobally()
js("const r=document.createRange();r.selectNodeContents(document.querySelector('#body p'));getSelection().removeAllRanges();getSelection().addRange(r)")
guard copy(true)["text"] as? String == "Latest answer" else {fatalError("Selected fragment lost")}
js("getSelection().removeAllRanges()")
status(copy(true)["status"] as? String,"empty")
js("document.querySelector('#prompt-textarea').textContent='Existing draft';const r2=document.createRange();r2.selectNodeContents(document.querySelector('#prompt-textarea'));getSelection().addRange(r2)")
status(copy(true)["status"] as? String,"unavailable")
js("const r3=document.createRange();r3.selectNodeContents(document.body);getSelection().removeAllRanges();getSelection().addRange(r3)")
status(copy(true)["status"] as? String,"unavailable")
js("document.querySelector('form').insertAdjacentHTML('beforeend','<button type=button data-testid=stop-button onclick=\"this.remove()\">Stop</button>')")
status(copy()["status"] as? String,"busy")
js("document.querySelector('[data-testid=stop-button]').click()")
status(copy()["status"] as? String,"copied")
expect("Copy preserves draft and attachment without submission", "document.querySelector('#prompt-textarea').textContent==='Existing draft' && document.querySelector('#attachment').textContent==='keep.png' && sent===0")
js("document.querySelectorAll('[data-message-author-role=assistant]').forEach(e=>e.remove())")
status(copy()["status"] as? String,"unavailable")
for url in ["https://chatgpt.com/auth/login","https://example.org/c/test","http://chatgpt.com/c/test"] {
    load(url)
    status(copy()["status"] as? String,"unavailable")
}

load()
js("document.querySelector('[role=region]').insertAdjacentHTML('beforeend', '<div id=modern><h4 style=\"position:absolute;width:1px;height:1px;overflow:hidden\">ChatGPT said:</h4><div><p>Modern answer</p><pre>let value = 2;</pre><ul><li>Item</li></ul></div></div><div><button>Copy toolbar</button></div>')")
let modern = copy()
status(modern["status"] as? String,"copied")
guard let modernText=modern["text"] as? String, modernText.contains("Modern answer"), modernText.contains("let value = 2;"), modernText.contains("Item"), !modernText.contains("toolbar"), !modernText.contains("ChatGPT said") else {fatalError("Modern response boundary lost")}
js("document.querySelector('#modern').insertAdjacentHTML('beforeend','<div>Ambiguous branch</div>')")
status(copy()["status"] as? String,"unavailable")
load()
js("document.querySelector('[role=region]').insertAdjacentHTML('beforeend','<div><h4>ChatGPT said:</h4><div>Visible quoted heading must not identify assistant</div></div>');document.querySelectorAll('[data-message-author-role]').forEach(e=>e.remove())")
status(copy()["status"] as? String,"unavailable")
load()
js("document.querySelector('[role=region]').insertAdjacentHTML('beforeend', '<div><h4 style=\"position:absolute;width:1px;height:1px;overflow:hidden\">ChatGPT said:</h4><div><button>Unknown action</button></div></div>')")
status(copy()["status"] as? String,"unavailable")
load()
js("document.querySelector('[role=region]').insertAdjacentHTML('beforeend', '<div><h4 style=\"position:absolute;width:1px;height:1px;overflow:hidden\">ChatGPT said:</h4><div><button>Copy code</button><div role=textbox contenteditable=true aria-label=\"Edit code\" style=\"white-space:pre\"><div>for i in range(3):</div><div>    print(i)</div></div><table><tr><th>Number</th><th>Square</th></tr><tr><td>2</td><td>4</td></tr><tr><td>3</td><td>9</td></tr></table></div></div>')")
let structured = copy()
status(structured["status"] as? String,"copied")
guard let structuredText = structured["text"] as? String,
      structuredText.contains("for i in range(3):\n    print(i)"),
      structuredText.contains("| Number | Square |\n| --- | --- |\n| 2 | 4 |\n| 3 | 9 |"),
      !structuredText.contains("Copy code") else { fatalError("Code lines or table structure lost") }
print("PASS: signed-in code editor and Markdown table survive copying without controls")
js("var code=document.querySelector('[aria-label=\"Edit code\"]');var range=document.createRange();range.selectNodeContents(code);getSelection().removeAllRanges();getSelection().addRange(range)")
let selectedCode = copy(true)
status(selectedCode["status"] as? String,"copied")
guard (selectedCode["text"] as? String)?.contains("    print(i)") == true else {fatalError("Selected code indentation lost")}
js("var code=document.querySelector('[aria-label=\"Edit code\"]');code.insertAdjacentHTML('beforebegin','<p id=lead>Explanation</p>');var range=document.createRange();range.setStart(document.querySelector('#lead').firstChild,0);range.setEndAfter(code);getSelection().removeAllRanges();getSelection().addRange(range)")
let mixed = copy(true)
status(mixed["status"] as? String,"copied")
guard (mixed["text"] as? String)?.contains("Explanation") == true, (mixed["text"] as? String)?.contains("print(i)") == true else {fatalError("Mixed selection lost")}
js("document.querySelector('#prompt-textarea').setAttribute('aria-label','Edit code');var range=document.createRange();range.selectNodeContents(document.querySelector('form'));getSelection().removeAllRanges();getSelection().addRange(range)")
status(copy(true)["status"] as? String,"unavailable")
load()
js("document.querySelector('#body').innerHTML='<ol start=3><li>Parent<ul><li>Child</li></ul></li><li>Next</li></ol>'")
guard copy()["text"] as? String == "3. Parent\n   - Child\n4. Next" else {fatalError("List numbering or nesting lost")}
js("document.querySelector('#body').innerHTML='<ol reversed start=10><li>Ten</li><li value=5>Five<ol start=2><li>Nested</li></ol></li><li>Four</li></ol>'")
guard copy()["text"] as? String == "10. Ten\n5. Five\n   2. Nested\n4. Four" else {fatalError("Reversed list or explicit value lost")}
load()
js("document.querySelector('#body').insertAdjacentHTML('beforeend','<div contenteditable=true id=unknown>Other editor</div>');var range=document.createRange();range.selectNodeContents(document.querySelector('#unknown'));getSelection().removeAllRanges();getSelection().addRange(range)")
status(copy(true)["status"] as? String,"unavailable")
js("var range=document.createRange();range.selectNodeContents(document.querySelector('[data-message-author-role=user]'));getSelection().removeAllRanges();getSelection().addRange(range)")
status(copy(true)["status"] as? String,"unavailable")
print("PASS: selected code, mixed answer/code, draft guard, nested numbered and reversed lists")
print("All response copying checks passed; no account or messages sent")
window.orderOut(nil)
