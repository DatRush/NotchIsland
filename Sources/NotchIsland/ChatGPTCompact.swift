import Foundation

/// Presentation-only adaptation. Never exports messages or accesses cookies or app internals;
/// never replaces editor nodes or submits a form. Wide windows retain the site UI.
enum ChatGPTCompact {
    static let script = #"""
    (() => {
      if (location.hostname !== 'chatgpt.com' || window.__notchCompactInstalled) return;
      window.__notchCompactInstalled = true;
      const style = document.createElement('style');
      style.id = 'notch-compact-style';
      style.textContent = `
        @media (max-width: 500px) {
          html[data-ni-ready] { background:#000 !important; color-scheme:dark; overflow:hidden !important; }
          html[data-ni-ready] body { margin:0 !important; background:#000 !important; overflow:hidden !important; }
          [data-ni-path], [data-ni-input-path] { display:contents !important; transform:none !important; filter:none !important; contain:none !important; }
          html[data-ni-ready] [data-ni-hide] { display:none !important; }
          [data-ni-transcript] {
            display:block !important; position:fixed !important; inset:0 0 var(--ni-composer-height, 42px) 0 !important;
            width:100% !important; height:auto !important; min-height:0 !important;
            transform:none !important; filter:none !important; contain:none !important;
            max-height:none !important; overflow:auto !important; padding:4px 7px !important;
            margin:0 !important; box-sizing:border-box !important; background:#000 !important;
            color:#eee !important; font:14px/1.5 -apple-system,BlinkMacSystemFont,sans-serif !important;
          }
          [data-ni-transcript] * { font-size:14px !important; line-height:1.5 !important; max-width:100% !important; }
          [data-ni-transcript] [data-ni-flow] { display:contents !important; transform:none !important; contain:none !important; }
          [data-ni-transcript] button { margin-block:4px !important; }
          html[data-ni-ready] [data-ni-transcript] :is([aria-label="Response actions"],[role="menu"]) { display:none !important; }
          [data-ni-transcript] :is(p,ul,ol,pre) { margin-block:5px !important; }
          [data-ni-transcript] :is(article,[data-message-author-role]) { padding-block:5px !important; min-height:0 !important; }
          [data-ni-transcript] pre { overflow-x:auto !important; }
          [data-ni-transcript] table { border-collapse:collapse !important; width:100% !important; margin:8px 0 !important; }
          [data-ni-transcript] :is(th,td) { padding:5px 8px !important; height:auto !important; text-align:left !important; border-bottom:1px solid #333 !important; }
          [data-ni-transcript] :is(th,td) :is(div,p) { padding:0 !important; margin:0 !important; min-height:0 !important; }
          [data-ni-transcript] :is(h1,h2,h3) { margin:10px 0 6px !important; font-weight:600 !important; }
          [data-ni-transcript] :is(pre,code,[role="textbox"]) { font-family:ui-monospace,SFMono-Regular,Menlo,monospace !important; }

          /* Site scroll fades and bubble decoration are oversized in the island. */
          [data-ni-path], [data-ni-input-path], [data-ni-transcript], [data-ni-transcript] :is(div,section,article,span) {
            mask-image:none !important; -webkit-mask-image:none !important;
            background-image:none !important; box-shadow:none !important;
          }
          [data-ni-path]::before, [data-ni-path]::after,
          [data-ni-input-path]::before, [data-ni-input-path]::after,
          [data-ni-transcript]::before, [data-ni-transcript]::after,
          [data-ni-transcript] [data-ni-flow]::before, [data-ni-transcript] [data-ni-flow]::after { display:none !important; }
          html[data-ni-ready] [data-ni-transcript] [data-message-author-role="user"] {
            display:block !important; width:auto !important; min-height:0 !important;
            margin:6px 0 !important; padding:2px 0 2px 9px !important;
            border:0 !important; border-left:2px solid #484848 !important;
            border-radius:0 !important; background:transparent !important; color:#c8c8c8 !important;
          }
          [data-ni-transcript] [data-message-author-role="user"] :is(div,span,p) {
            background:transparent !important; border-radius:0 !important;
            padding:0 !important; margin:0 !important; min-height:0 !important;
          }

          [data-ni-composer] {
            display:grid !important; grid-template-columns:minmax(0,1fr) 28px !important; align-items:center !important; gap:6px !important; position:fixed !important; inset:auto 0 0 0 !important;
            width:100% !important; height:auto !important; min-height:38px !important;
            max-height:50vh !important; margin:0 !important; padding:5px 7px !important;
            border:1px solid #333 !important; border-radius:12px !important;
            box-sizing:border-box !important; background:#191919 !important; color:#eee !important;
            overflow-y:auto !important; z-index:20 !important;
          }
          [data-ni-composer] :is(textarea,[contenteditable=true]) {
            grid-column:1 !important; grid-row:1 !important; width:100% !important; min-width:0 !important; box-sizing:border-box !important;
            font:14px/1.5 -apple-system,BlinkMacSystemFont,sans-serif !important;
            min-height:24px !important; max-height:67px !important; height:var(--ni-editor-height, 24px) !important; overflow-y:auto !important; resize:none !important;
            padding:2px !important; margin:0 !important; color:#eee !important; background:transparent !important;
          }
          [data-ni-composer] :is(textarea,[contenteditable=true]) p { margin:0 !important; }
          [data-ni-composer] button { min-width:24px !important; min-height:24px !important; height:26px !important; padding:3px !important; }
          [data-ni-extra] { grid-column:1 / -1 !important; min-width:0 !important; }
          /* The live attachment is a relative popup with an absolute span, not an img-sized div. */
          [data-ni-extra]:has(div[aria-haspopup] > span > img) { display:block !important; }
          [data-ni-extra] > div:has(> div > div[aria-haspopup] > span > img) { padding:0 !important; }
          [data-ni-extra] div[aria-haspopup]:has(> span > img) {
            width:48px !important; height:48px !important; min-width:48px !important; min-height:48px !important;
            max-width:48px !important; max-height:48px !important; flex:0 0 48px !important;
          }
          [data-ni-extra] div[aria-haspopup] > span:has(> img) {
            inset:0 !important; width:100% !important; height:100% !important; min-height:0 !important;
          }
          [data-ni-extra] div[aria-haspopup] > span > img { width:100% !important; height:100% !important; object-fit:cover !important; }
          [data-ni-send] { grid-column:2 !important; grid-row:1 !important; }
          [data-ni-attach] { display:none !important; }
          [data-ni-composer] svg { width:16px !important; height:16px !important; }
          [data-ni-composer] button[aria-label*="dictation" i],
          [data-ni-composer] button[aria-label*="voice" i] { display:none !important; }
        }
      `;
      document.head.appendChild(style);
      let scheduled = false;
      let scrollTarget = null;
      let composerTarget = null;
      const composerResize = new ResizeObserver(() => queue());
      let followLatest = true;
      const refresh = () => {
        scheduled = false;
        const visible = element => element.getClientRects().length > 0
          && getComputedStyle(element).visibility !== 'hidden';
        const namedEditors = [...document.querySelectorAll('#mobile-composer-prompt, #prompt-textarea')].filter(visible);
        // Signed-in builds can omit both legacy IDs. Only accept an unambiguous form editor.
        const formEditors = [...document.querySelectorAll('form [contenteditable="true"],form textarea')].filter(visible);
        const editor = namedEditors.length === 1 ? namedEditors[0]
          : formEditors.length === 1 ? formEditors[0] : null;
        let composer = editor?.closest('form');
        const sendSelector = 'button[type="submit"],button[data-testid="send-button"],button[data-testid="stop-button"],button[aria-label="Send message"],button[aria-label="Отправить сообщение"],button[aria-label="Stop generating"],button[aria-label="Остановить генерацию"]';
        const activeControl = root => {
          const buttons = [...root.querySelectorAll(sendSelector)].filter(visible);
          return buttons.find(button => button.matches('[data-testid="stop-button"],[aria-label="Stop generating"],[aria-label="Остановить генерацию"]'))
            || buttons.find(button => !button.disabled) || buttons[0];
        };
        let transcript = document.querySelector('[role="region"][aria-label="Conversation"]')
          || document.querySelector('section[aria-label^="Conversation "]')
          || document.querySelector('[data-testid="conversation-turn-0"]')?.parentElement;
        // A submit button elsewhere on the page must not expand the composer to the whole app.
        if (composer && !activeControl(composer)) {
          const siblingHost = composer.parentElement;
          if (siblingHost && siblingHost !== document.body && siblingHost !== transcript
              && !siblingHost.contains(transcript) && activeControl(siblingHost)) composer = siblingHost;
        }
        // The signed-in Conversation region includes both messages and the composer.
        // Use its separate message branch, never an overflowing ancestor of the fixed editor.
        if (transcript && composer && transcript.contains(composer)) {
          let shared = transcript;
          while (shared && shared !== composer) {
            const branches = [...shared.children].filter(e => !e.matches('script,style') && getComputedStyle(e).display !== 'none');
            const composerBranch = branches.find(e => e === composer || e.contains(composer));
            if (!composerBranch) break;
            const siblings = branches.filter(e => e !== composerBranch);
            if (siblings.length === 1) { transcript = siblings[0]; break; }
            if (siblings.length > 1) {
              const messageBranches = siblings.filter(e => e.matches('article,[data-message-author-role]') || e.querySelector('article,[data-message-author-role]'));
              if (messageBranches.length === 1) transcript = messageBranches[0];
              break;
            }
            shared = composerBranch;
          }
        }
        // Unknown pages and authentication retain their normal presentation.
        const validRoute = location.pathname === '/' || location.pathname.startsWith('/c/') || location.pathname.startsWith('/uc/');
        document.querySelectorAll('[data-ni-path],[data-ni-hide],[data-ni-composer],[data-ni-transcript],[data-ni-input-path],[data-ni-send],[data-ni-attach],[data-ni-flow],[data-ni-extra]').forEach(e => {
          for (const a of ['data-ni-path','data-ni-hide','data-ni-composer','data-ni-transcript','data-ni-input-path','data-ni-send','data-ni-attach','data-ni-flow','data-ni-extra']) e.removeAttribute(a);
        });
        document.documentElement.removeAttribute('data-ni-ready');
        // The signed-in landing page can have a composer before any transcript exists.
        // Only allow that empty state on the home route; unknown conversation pages stay native.
        const emptyHome = location.pathname === '/' && !document.querySelector('[data-message-author-role],[data-testid^="conversation-turn-"]');
        if (!validRoute || !composer || (!transcript && !emptyHome)
            || (transcript && (composer.contains(transcript) || transcript.contains(composer)))) return;
        const paths = new Set();
        for (const target of [composer, transcript].filter(Boolean)) {
          for (let node = target.parentElement; node && node !== document.body && node !== document.documentElement; node = node.parentElement) paths.add(node);
        }
        for (const node of paths) {
          if (node === transcript) continue;
          node.setAttribute('data-ni-path','');
          // In some signed-in layouts the composer lives inside Conversation.
          // Keep its sibling message branches rather than treating them as site chrome.
          if (transcript?.contains(node)) continue;
          for (const child of node.children) {
            if (paths.has(child) || child === composer || child === transcript || child.matches('script,style')) continue;
            // Preserve dialogs, consent, menus and alerts; never hide a required choice.
            if (child.matches('dialog,[role="dialog"],[role="alert"],[role="menu"]') || child.querySelector('dialog,[role="dialog"],[role="alert"],[role="menu"]')) continue;
            child.setAttribute('data-ni-hide','');
          }
        }
        const send = activeControl(composer);
        // Compact mode uses the island screenshot action, not the site's attachment menu.
        // Include hidden controls in the path walk so their toolbar wrappers leave no empty row.
        const attachmentButtons = [...composer.querySelectorAll('[data-testid="composer-plus-btn"],button[aria-haspopup="menu"],button[aria-label="Add files and more"],[role="button"][aria-label="Add files and more"],button[aria-label="Добавить файлы и другое"],[role="button"][aria-label="Добавить файлы и другое"]')]
          .filter(button => button !== send);
        const controls = [editor, send, ...attachmentButtons].filter(Boolean);
        const inputPaths = new Set();
        for (const control of controls) {
          for (let node = control.parentElement; node && node !== composer; node = node.parentElement) inputPaths.add(node);
        }
        for (const node of [composer, ...inputPaths]) {
          if (node !== composer) node.setAttribute('data-ni-input-path','');
          for (const child of node.children) {
            if (inputPaths.has(child) || controls.includes(child) || child.matches('input[type="file"],style,script')) continue;
            if (child.matches('[role="menu"],[role="dialog"],dialog') || child.querySelector('[role="menu"],[role="dialog"],dialog')) continue;
            // Keep attachments, remove/retry buttons, upload errors and unknown controls.
            // Preserve their subtree and site listeners; give each branch its own grid row.
            child.setAttribute('data-ni-extra','');
          }
        }
        send?.setAttribute('data-ni-send','');
        attachmentButtons.forEach(button => button.setAttribute('data-ni-attach',''));
        // Signed-in responses may have no article/markdown markers. Their hidden
        // speaker heading identifies a content sibling whose internal layout must
        // remain intact (including div-based code-editor lines).
        const responseBodies = [...(transcript?.querySelectorAll('h4') || [])]
          .filter(h => ['ChatGPT said:', 'ChatGPT сказал:'].includes(h.textContent.trim())
            && getComputedStyle(h).position === 'absolute'
            && getComputedStyle(h).overflow === 'hidden'
            && h.getBoundingClientRect().width <= 2 && h.getBoundingClientRect().height <= 2)
          .map(h => h.nextElementSibling).filter(Boolean);
        for (const node of (transcript?.querySelectorAll('div,section') || [])) {
          // Flatten only layout wrappers, never message content or semantic lists/tables.
          if (composer.contains(node) || responseBodies.some(body => body === node || body.contains(node))) continue;
          // Preserve action rows instead of turning each button into a separate block.
          if (node.querySelector('button') && !node.querySelector('p,pre,ol,ul,table,article,[data-message-author-role]')) continue;
          if (node.closest('[data-message-author-role],.markdown,article,ol,ul,li,pre,table,blockquote')) continue;
          if (getComputedStyle(node).display !== 'none') node.setAttribute('data-ni-flow','');
        }
        if (composerTarget !== composer) {
          composerResize.disconnect();
          composerTarget = composer;
          composerResize.observe(composer);
        }
        composer.setAttribute('data-ni-composer','');
        transcript?.setAttribute('data-ni-transcript','');
        document.documentElement.setAttribute('data-ni-ready','');
        // Hide only site footer copy, never matching text inside a message or dialog.
        for (const node of (transcript?.querySelectorAll('div,p,span') || [])) {
          if (node.children.length || node.closest('[data-message-author-role],article,[data-testid^="conversation-turn-"],[role="dialog"],[role="alert"]')) continue;
          if (/^(ChatGPT is AI and can make mistakes\.|ChatGPT can make mistakes\.|ChatGPT может допускать ошибки)/.test(node.textContent.trim())) node.setAttribute('data-ni-hide', '');
        }
        if (innerWidth <= 500) {
          document.documentElement.style.setProperty('--ni-editor-height', '24px');
          const height = Math.min(67, Math.max(24, editor.scrollHeight));
          document.documentElement.style.setProperty('--ni-editor-height', `${height}px`);
          document.documentElement.style.setProperty('--ni-composer-height', `${composer.getBoundingClientRect().height + 4}px`);
        }
        if (transcript && scrollTarget !== transcript) {
          scrollTarget = transcript;
          followLatest = true;
          let userScrollUntil = 0;
          const beginUserScroll = () => { userScrollUntil = performance.now() + 1200; };
          for (const event of ['wheel','touchstart','pointerdown','keydown']) transcript.addEventListener(event, beginUserScroll, {passive:true});
          transcript.addEventListener('scroll', () => {
            if (performance.now() > userScrollUntil) return;
            followLatest = transcript.scrollHeight - transcript.scrollTop - transcript.clientHeight < 24;
          }, {passive:true});
        }
        if (transcript && innerWidth <= 500 && followLatest) transcript.scrollTop = transcript.scrollHeight;
      };
      const queue = () => { if (!scheduled) { scheduled = true; requestAnimationFrame(refresh); } };
      new MutationObserver(queue).observe(document.body, {childList:true, characterData:true, subtree:true, attributes:true, attributeFilter:["class","style","hidden","disabled","aria-hidden","aria-label","data-testid","type"]});
      window.addEventListener('popstate', queue);
      window.addEventListener('resize', queue);
      document.addEventListener('input', queue, true);
      refresh();
    })();
    """#
}
