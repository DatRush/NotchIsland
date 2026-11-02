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
<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
<style>body{margin:0} li{display:list-item} form{background:#ddd} #uploaded{padding:6px} #upload-error{padding:4px}</style>
</head><body><main><section role="region" aria-label="Conversation"><div class="layout"><article><div data-message-author-role="assistant"><div class="markdown">
<ol id="steps" start="3"><li id="first">First step<ul id="nested"><li>Nested point</li></ul></li><li>Second step</li></ol>
<ul id="bullets"><li>Bullet</li></ul><pre><code>example</code></pre><table><tbody><tr><td>Cell</td></tr></tbody></table>
</div></div></article></div></section>
<form><div id="uploaded"><span>sample.pdf</span><button type="button" id="remove" onclick="this.parentElement.remove()">Remove</button></div>
<div role="alert" id="upload-error">Upload failed</div><div>
<button type="button" id="attach" ATTACH_ATTRIBUTES>+</button><div id="prompt-textarea" contenteditable="true"><p>Hello</p></div>
<button type="submit" data-testid="send-button">Send</button></div></form></main>
<script>
window.visible = id => { const e=document.getElementById(id); if(!e) return false; const r=e.getBoundingClientRect(); return r.width>0 && r.height>0 && getComputedStyle(e).visibility!=='hidden'; };
window.formHeight = () => document.querySelector('form').getBoundingClientRect().height;
window.reserved = () => parseFloat(document.documentElement.style.getPropertyValue('--ni-composer-height'));
window.formContains = id => {const r=document.getElementById(id).getBoundingClientRect(), f=document.querySelector('form').getBoundingClientRect();return r.top>=f.top && r.bottom<=f.bottom;};
</script></body></html>
"""
func load(_ attributes: String, width: CGFloat = 404) {
    loader.loaded = false
    window.setContentSize(NSSize(width: width, height: width > 500 ? 700 : 237))
    web.loadHTMLString(html.replacingOccurrences(of: "ATTACH_ATTRIBUTES", with: attributes), baseURL: URL(string:"https://chatgpt.com/"))
    wait("page load") { loader.loaded }
    js(ChatGPTCompact.script)
}
for (name, attributes) in [
    ("English", "aria-label='Add files and more' aria-haspopup='menu'"),
    ("Russian", "aria-label='Добавить файлы и другое' aria-haspopup='menu'"),
    ("Expanded attachment", "aria-label='Add files and more' aria-expanded='true'"),
    ("Russian expanded attachment", "aria-label='Добавить файлы и другое' aria-expanded='false'"),
    ("Unknown label", "aria-label='添付' data-testid='composer-plus-btn'"),
    ("Unknown structure", "aria-label='Unrecognised control'")
] {
    load(attributes)
    expect("\(name): attachment, remove button and error visible", "['uploaded','remove','upload-error'].every(visible)")
    expect("\(name): ordered and nested list structure preserved", "[...document.querySelectorAll('li')].every(e=>getComputedStyle(e).display==='list-item') && getComputedStyle(document.querySelector('#steps')).listStyleType==='decimal' && getComputedStyle(document.querySelector('#bullets')).listStyleType==='disc' && getComputedStyle(document.querySelector('#nested')).paddingLeft!=='0px'")
    expect("\(name): message content is not flattened", "!document.querySelector('[data-message-author-role] [data-ni-flow]')")
    expect("\(name): transcript reserves actual composer height", "Math.abs(reserved()-formHeight()-4)<1 && document.querySelector('section').getBoundingClientRect().bottom <= document.querySelector('form').getBoundingClientRect().top")
    js("document.querySelector('#upload-error').style.display='none';")
    wait("error hide reserves current height") { js("Math.abs(reserved()-formHeight()-4)<1") as? Bool == true }
    js("document.querySelector('#upload-error').style.display='block';")
    wait("error reveal reserves current height") { js("Math.abs(reserved()-formHeight()-4)<1") as? Bool == true }
    expect("\(name): revealed error remains visible", "visible('upload-error')")
    // Extras are scrollable when the half-height bound is reached, never hidden.
    expect("\(name): extras have real grid rows", "document.querySelector('#uploaded').getBoundingClientRect().top >= document.querySelector('#prompt-textarea').getBoundingClientRect().bottom")
    js("document.querySelector('#remove').click(); document.querySelector('#upload-error').remove();")
    wait("attachment removal refresh") { js("!document.querySelector('#uploaded') && Math.abs(reserved()-formHeight()-4)<1") as? Bool == true }
    expect("\(name): editor survives removal", "visible('prompt-textarea')")
    if name != "Unknown structure" {
        expect("\(name): compact attachment menu hidden without empty row", "!visible('attach') && formHeight()<=42")
    }
    js("document.querySelector('#prompt-textarea').innerHTML='<p>one</p><p>two</p><p>three</p><p>four</p>'; document.querySelector('#prompt-textarea').dispatchEvent(new Event('input',{bubbles:true}));")
    wait("growing editor") { js("document.querySelector('#prompt-textarea').getBoundingClientRect().height >= 60") as? Bool == true }
    expect("\(name): growing composer does not overlap transcript", "Math.abs(reserved()-formHeight()-4)<1")
}
load("aria-label='Добавить файлы и другое' aria-haspopup='menu'", width: 900)
expect("Wide view keeps site layout and controls", "getComputedStyle(document.querySelector('form')).position==='static' && ['uploaded','remove','upload-error','attach'].every(visible)")
expect("Wide lists retain markers", "getComputedStyle(document.querySelector('#first')).display==='list-item'")
load("data-testid='composer-plus-btn'")
js("document.querySelector('#uploaded').remove();document.querySelector('#upload-error').remove();const toolbar=document.createElement('div');toolbar.append(document.querySelector('#attach'));document.querySelector('form').append(toolbar);document.querySelector('#prompt-textarea').insertAdjacentHTML('beforebegin','<button id=\"model-menu\" aria-haspopup=\"menu\">Model</button>');")
wait("separate toolbar collapses") { js("!visible('attach') && !visible('model-menu') && formHeight()<=42") as? Bool == true }
expect("Separate plus and model menus leave one compact input row", "formHeight()<=42 && document.querySelector('#prompt-textarea').getBoundingClientRect().width>340")
// Sending can move the composer inside Conversation; unrelated submit controls may appear.
load("aria-haspopup='menu'")
js("document.querySelector('section').append(document.querySelector('form')); document.querySelector('section form').insertAdjacentHTML('beforeend','<div id=\"nested-marker\" style=\"display:none\"></div>'); document.body.insertAdjacentHTML('beforeend','<form id=\"unrelated\"><button type=\"submit\">Unrelated</button></form>'); document.querySelector('[data-testid=send-button]').remove();")
wait("nested composer adaptation") { js("document.querySelector('#nested-marker').hasAttribute('data-ni-extra') && !document.querySelector('[data-ni-composer]')?.closest('[data-ni-transcript]') && document.documentElement.hasAttribute('data-ni-ready')") as? Bool == true }
expect("Nested composer does not disable compact mode", "!document.querySelector('section').hasAttribute('data-ni-transcript') && document.querySelector('section [data-ni-transcript]')!==null && document.querySelector('section form').hasAttribute('data-ni-composer')")
expect("Nested message and attachment branches remain visible", "document.querySelector('article').getBoundingClientRect().height>0 && visible('uploaded') && visible('upload-error')")
expect("Unrelated submit cannot become composer", "!document.querySelector('#unrelated').hasAttribute('data-ni-composer') && getComputedStyle(document.querySelector('section form')).position==='fixed'")
expect("Nested editor is actually clickable outside transcript", "(() => { const e=document.querySelector('#prompt-textarea'),r=e.getBoundingClientRect(),hit=document.elementFromPoint(r.x+r.width/2,r.y+r.height/2);return hit===e || e.contains(hit); })()")

// Actual report: one visible form editor without either legacy ID, a Conversation region,
// and no legacy turn/message markers or send button while the editor is empty.
load("aria-haspopup='menu'")
js("document.querySelector('#prompt-textarea').removeAttribute('id'); document.querySelector('[data-testid=send-button]').remove(); document.querySelector('[data-message-author-role]').removeAttribute('data-message-author-role'); document.querySelector('form').insertAdjacentHTML('beforeend','<textarea style=\"display:none\"></textarea>');")
wait("unnamed editor adaptation") { js("document.querySelector('form textarea').hasAttribute('data-ni-extra') && document.querySelector('form [contenteditable]').closest('[data-ni-composer]') !== null && document.documentElement.hasAttribute('data-ni-ready')") as? Bool == true }
expect("Unnamed signed-in editor remains compact", "getComputedStyle(document.querySelector('form [contenteditable]')).gridColumnStart==='1' && getComputedStyle(document.querySelector('form')).position==='fixed'")
expect("Conversation without message markers remains visible", "document.querySelector('[data-ni-transcript]').getBoundingClientRect().height>80 && document.querySelector('article').getBoundingClientRect().height>0")
// Signed-in-style landing page: a composer exists but no conversation region yet.
loader.loaded = false
window.setContentSize(NSSize(width:404, height:237))
let landing = """
<html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head><body><main>
<header id="site-header">Chat / Work</header><div id="suggestions">Suggested prompt</div>
<form><div><button type="button" data-testid="composer-plus-btn" aria-haspopup="menu">+</button><div id="prompt-textarea" contenteditable="true"><p><br></p></div><button type="button" aria-label="Start voice mode">Voice</button></div></form>
</main></body></html>
"""
web.loadHTMLString(landing, baseURL:URL(string:"https://chatgpt.com/"))
wait("landing page load") { loader.loaded }
js(ChatGPTCompact.script)
expect("Empty home activates compact composer without a transcript", "document.documentElement.hasAttribute('data-ni-ready') && getComputedStyle(document.querySelector('form')).position==='fixed'")
expect("Empty home hides site header and suggestions", "document.querySelector('#site-header').getClientRects().length===0 && document.querySelector('#suggestions').getClientRects().length===0")
expect("Empty home retains one-line input", "document.querySelector('form').getBoundingClientRect().height<=42 && document.querySelector('#prompt-textarea').getBoundingClientRect().width>200")
js("document.querySelector('main').insertAdjacentHTML('afterbegin','<section role=\"region\" aria-label=\"Conversation\"><article data-message-author-role=\"assistant\"><p>First answer</p></article></section>'); document.querySelector('form').insertAdjacentHTML('beforeend','<button type=\"submit\" data-testid=\"send-button\">Send</button>');")
wait("first transcript becomes compact") { js("document.querySelector('[data-ni-transcript]')!==null") as? Bool == true }
expect("First conversation and send appear without reloading", "document.querySelector('section').getBoundingClientRect().height>0 && document.querySelector('[data-ni-send]').getBoundingClientRect().width>0")
loader.loaded = false
web.loadHTMLString(landing, baseURL:URL(string:"https://chatgpt.com/auth/login"))
wait("auth page load") { loader.loaded }
js(ChatGPTCompact.script)
expect("Authentication page stays native", "!document.documentElement.hasAttribute('data-ni-ready') && getComputedStyle(document.querySelector('form')).position==='static'")
js("document.querySelector('#prompt-textarea').textContent='PRIVATE_MESSAGE_MARKER'; document.querySelector('#prompt-textarea').setAttribute('data-private','PRIVATE_ATTRIBUTE_MARKER');")
guard let diagnostic = js(ChatGPTLayoutDiagnostics.script) as? String,
      let data = diagnostic.data(using:.utf8),
      let report = try? JSONSerialization.jsonObject(with:data) as? [String:Any],
      report["viewport"] != nil,
      !diagnostic.contains("PRIVATE_MESSAGE_MARKER"), !diagnostic.contains("PRIVATE_ATTRIBUTE_MARKER"),
      !diagnostic.contains("https://") else { fatalError("Unsafe or missing layout diagnostic") }
print("PASS: layout diagnostic contains geometry without fixture text, arbitrary attributes or URL")

// The site can retain a hidden submit while showing a separate stop button.
load("aria-haspopup='menu'")
js("window.stopped=0;document.querySelector('[data-testid=send-button]').style.display='none';document.querySelector('form').insertAdjacentHTML('beforeend','<button type=button id=stop data-testid=stop-button onclick=\"stopped++\">Stop</button>')")
wait("stop promoted over hidden send") { js("document.querySelector('#stop').hasAttribute('data-ni-send')") as? Bool == true }
expect("Stop remains hit-testable beside editor with hidden send", "(()=>{const e=document.querySelector('#stop'),r=e.getBoundingClientRect(),hit=document.elementFromPoint(r.x+r.width/2,r.y+r.height/2);return r.bottom<=innerHeight && (hit===e||e.contains(hit));})()")
js("(()=>{const r=document.querySelector('#stop').getBoundingClientRect();document.elementFromPoint(r.x+r.width/2,r.y+r.height/2).click()})()")
expect("Hit at stop reaches original site handler", "stopped===1")
// Attribute-only state transitions must update layout without waiting for token text.
js("document.querySelector('#stop').style.display='none';document.querySelector('[data-testid=send-button]').style.display=''")
wait("send restored after stop hides") { js("document.querySelector('[data-testid=send-button]').hasAttribute('data-ni-send') && !document.querySelector('#stop').hasAttribute('data-ni-send')") as? Bool == true }
expect("Send returns to primary slot after attribute-only transition", "document.querySelector('[data-testid=send-button]').hasAttribute('data-ni-send')")
js("document.querySelector('#stop').style.display='';document.querySelector('[data-testid=send-button]').disabled=true")
wait("visible stop outranks disabled submit") { js("document.querySelector('#stop').hasAttribute('data-ni-send')") as? Bool == true }
expect("Stop outranks visible disabled submit", "document.querySelector('#stop').hasAttribute('data-ni-send')")
// Modern signed-in content uses div-based code lines without markdown/article.
load("aria-haspopup='menu'")
js("document.querySelector('section').innerHTML='<div><div><h4 style=\"position:absolute;width:1px;height:1px;overflow:hidden\">ChatGPT said:</h4><div id=answer-body><div><div role=textbox id=code style=\"white-space:pre\"><div id=line1>for i in range(3):</div><div id=line2>    print(i)</div></div></div><table><tbody><tr><td id=cell style=\"padding:24px\">2</td><td>4</td></tr></tbody></table></div></div></div>'")
wait("modern body preserved") { js("document.querySelector('#line1') && !document.querySelector('#line1').hasAttribute('data-ni-flow')") as? Bool == true }
expect("Modern code lines retain block layout", "getComputedStyle(document.querySelector('#line1')).display==='block' && document.querySelector('#line2').getBoundingClientRect().top>document.querySelector('#line1').getBoundingClientRect().top")
expect("Modern code text retains newline and indent", "document.querySelector('#code').innerText.includes('range(3):\\n    print(i)')")
expect("Table cells use compact padding", "getComputedStyle(document.querySelector('#cell')).paddingTop==='5px'")
// Live diagnostic v4: display:contents extra, nested padding, relative popup and absolute span.
load("data-testid='composer-plus-btn'")
js(##"document.querySelector('#uploaded').remove();document.querySelector('#upload-error').remove();document.querySelector('form').insertAdjacentHTML('afterbegin',`<div id=preview-extra style='display:contents'><div style='padding:8px 8px 6px'><div style='display:flex;padding:4px'><div id=preview aria-haspopup=dialog style='position:relative;display:flex;width:122px;height:122px'><span style='position:absolute;inset:0;overflow:hidden'><img id=preview-image style='display:block;width:100%;height:100%' src='data:image/svg+xml,%3Csvg xmlns="http://www.w3.org/2000/svg" width="122" height="122"/%3E'></span><button type=button id=preview-remove style='position:absolute;right:-2px;top:-2px' onclick='this.closest("#preview-extra").remove()'>×</button></div></div></div></div>`)"##)
wait("live preview adapted") { js("document.querySelector('#preview-image').getBoundingClientRect().height===48") as? Bool == true }
expect("Absolute-span image stays visible at 48 pixels", "visible('preview-image') && document.querySelector('#preview-image').getBoundingClientRect().width===48")
expect("Preview has a full grid row and fits with editor", "getComputedStyle(document.querySelector('#preview-extra')).display==='block' && formContains('preview-image') && formContains('prompt-textarea') && formHeight()<=110")
expect("Remove control is hit-testable", "(()=>{const e=document.querySelector('#preview-remove'),r=e.getBoundingClientRect(),h=document.elementFromPoint(r.x+r.width/2,r.y+r.height/2);return h===e||e.contains(h);})()")
window.setContentSize(NSSize(width:900,height:700))
wait("wide preview unchanged") { js("document.querySelector('#preview-image').getBoundingClientRect().height===122") as? Bool == true }
expect("Wide preview retains original site size", "getComputedStyle(document.querySelector('#preview-extra')).display==='contents'")
window.setContentSize(NSSize(width:404,height:237))
wait("preview compact again") { js("document.querySelector('#preview-image').getBoundingClientRect().height===48") as? Bool == true }
js("(()=>{const r=document.querySelector('#preview-remove').getBoundingClientRect();document.elementFromPoint(r.x+r.width/2,r.y+r.height/2).click()})()")
wait("preview removed") { js("!document.querySelector('#preview-extra') && formHeight()<=42") as? Bool == true }
expect("Removal preserves draft and editor", "document.querySelector('#prompt-textarea').textContent.trim()==='Hello' && visible('prompt-textarea')")
load("aria-label='Add files and more'")
js(#"history.replaceState(null,'','/c/fixture');document.querySelector('section').removeAttribute('aria-label');document.querySelector('article').setAttribute('data-testid','conversation-turn-3');document.querySelector('#uploaded').remove();document.querySelector('#upload-error').remove();document.querySelector('main').insertAdjacentHTML('afterbegin','<header id=share>Share</header>');document.querySelector('form button[type=submit]').setAttribute('data-testid','stop-button');document.querySelector('form').insertAdjacentHTML('beforeend','<button id=medium aria-haspopup=menu>Medium</button>')"#)
wait("streaming turns without named region") { js("document.querySelector('[data-ni-transcript]')?.contains(document.querySelector('article')) && !visible('share') && !visible('medium') && formHeight()<=42") as? Bool == true }
expect("Streaming layout keeps stop and editor clear of the transcript", "visible('prompt-textarea') && document.querySelector('[data-ni-send]').getBoundingClientRect().height>0 && document.querySelector('[data-ni-transcript]').getBoundingClientRect().bottom<=document.querySelector('form').getBoundingClientRect().top")
load("aria-label='Add files and more'")
js(#"history.replaceState(null,'','/c/live');const region=document.querySelector('section');region.innerHTML='<div id="turns"><div><h4 aria-label="You said:"></h4><p>Question</p></div><div><h4 aria-label="ChatGPT said:"></h4><p id="math">Equation</p></div></div><div style="height:0"></div>';region.append(document.querySelector('form'));document.querySelector('#uploaded').remove();document.querySelector('#upload-error').remove();document.querySelector('main').insertAdjacentHTML('afterbegin','<header id=live-share>Share</header>');document.querySelector('form').insertAdjacentHTML('beforeend','<button id=medium aria-haspopup=menu>Medium</button>')"#)
wait("actual three-branch conversation") { js("document.querySelector('[data-ni-transcript]')?.contains(document.querySelector('#math')) && !visible('live-share') && !visible('medium') && formHeight()<=42") as? Bool == true }
window.close()
print("All compact ChatGPT checks passed")
