import Foundation

/// Structural diagnostics only: no text, HTML, URLs, attribute values, or storage.
enum ChatGPTLayoutDiagnostics {
    static let script = #"""
    (() => {
      const selectors = {
        editor: '#mobile-composer-prompt, #prompt-textarea',
        editable: '[contenteditable="true"],textarea', form: 'form',
        region: '[role="region"][aria-label="Conversation"]',
        section: 'section[aria-label^="Conversation "]',
        turn: '[data-testid^="conversation-turn-"]',
        message: '[data-message-author-role]',
        send: 'button[data-testid="send-button"],button[type="submit"]',
        image: 'img', popup: '[aria-haspopup]', extra: '[data-ni-extra]', inputPath: '[data-ni-input-path]', heading: 'h4', body: '.markdown,.prose', button: 'button', article: 'article'
      };
      const describe = e => {
        const r = e.getBoundingClientRect(), s = getComputedStyle(e);
        return {
          tag: e.tagName, rect: [r.x,r.y,r.width,r.height].map(Math.round),
          client: [e.clientWidth,e.clientHeight], scroll: [e.scrollWidth,e.scrollHeight,e.scrollTop],
          display:s.display, position:s.position, overflow:[s.overflowX,s.overflowY],
          height:s.height, minHeight:s.minHeight, maxHeight:s.maxHeight,
          padding:s.padding, margin:s.margin, masked:s.maskImage!=='none',
          hidden:e.hasAttribute('data-ni-hide'), compactPath:e.hasAttribute('data-ni-path'),
          matches:Object.keys(selectors).filter(k=>e.matches(selectors[k]))
        };
      };
      const chain = e => {
        const result=[];
        for(let n=e;n && result.length<16;n=n.parentElement) {
          result.push({...describe(n), children:[...n.children].slice(0,16).map(describe)});
        }
        return result;
      };
      const region = document.querySelector(selectors.region);
      const answerHeadings = [...(region?.querySelectorAll('h4') || [])].filter(e => ['ChatGPT said:', 'ChatGPT сказал:'].includes(e.textContent.trim()));
      const structure = (e, depth = 0) => ({tag:e.tagName, matches:Object.keys(selectors).filter(k=>e.matches(selectors[k])),
        children:depth<5?[...e.children].slice(0,12).map(c=>structure(c,depth+1)):[]});
      return JSON.stringify({
        answerStructures:answerHeadings.slice(-2).map(e=>structure(e.parentElement)),
        answerChains:answerHeadings.slice(-2).map(chain),
        attachmentImages:[...document.querySelectorAll('form img,[data-ni-composer] img')].slice(0,4).map(chain),
        version:4, capturedAt:new Date().toISOString(),
        regionContainsForm:!!document.querySelector(selectors.region)?.contains(document.querySelector('form')),
        regions:[...document.querySelectorAll(selectors.region)].slice(0,2).map(chain),
        viewport:[innerWidth,innerHeight],
        chatGPT:location.hostname==='chatgpt.com',
        route:location.pathname==='/'?'home':location.pathname.startsWith('/c/')?'conversation':location.pathname.startsWith('/uc/')?'guest':'other',
        installed:!!window.__notchCompactInstalled,
        ready:document.documentElement.hasAttribute('data-ni-ready'),
        counts:Object.fromEntries(Object.entries(selectors).map(([k,s])=>[k,document.querySelectorAll(s).length])),
        editors:[...document.querySelectorAll(selectors.editable)].slice(0,3).map(chain),
        messages:[...document.querySelectorAll(selectors.message)].slice(0,2).map(chain),
        turns:[...document.querySelectorAll(selectors.turn)].slice(0,2).map(chain)
      },null,2);
    })();
    """#
}
