import Foundation

enum ChatGPTTextBridge {
    // Scripts execute only following a user action. Arguments never become JavaScript source.
    static let guardPage = #"""
    if (location.origin !== 'https://chatgpt.com' ||
        !(location.pathname === '/' || location.pathname.startsWith('/c/') || location.pathname.startsWith('/uc/'))) return {status:'unavailable'};
    const visible = e => e.getClientRects().length > 0 && getComputedStyle(e).visibility !== 'hidden';
    const stops = [...document.querySelectorAll('[data-testid="stop-button"],button[aria-label="Stop generating"],button[aria-label="Остановить генерацию"]')];
    if (stops.some(visible)) return {status:'busy'};
    """#
    static let copy = guardPage + #"""
    const candidates = [...document.querySelectorAll('[data-message-author-role="assistant"]')].filter(visible)
      .map(node => ({node, bodies:[...node.querySelectorAll('.markdown,.prose')].filter(e => !e.parentElement.closest('.markdown,.prose'))}));
    // Observed signed-in layout: an accessibility-only speaker heading followed by
    // exactly one content branch. The toolbar is outside this parent container.
    const region = document.querySelector('[role="region"][aria-label="Conversation"]');
    for (const heading of (region?.querySelectorAll('h4') || [])) {
      if (!['ChatGPT said:', 'ChatGPT сказал:'].includes(heading.textContent.trim())) continue;
      const rect = heading.getBoundingClientRect(), style = getComputedStyle(heading);
      if (!visible(heading) || rect.width > 2 || rect.height > 2 || style.position !== 'absolute' || style.overflow !== 'hidden') continue;
      const parent = heading.parentElement;
      if (parent.closest('[data-message-author-role]')) continue;
      const candidate = {node:parent, bodies:[]};
      candidates.push(candidate);
      const children = [...parent.children];
      if (children.length !== 2 || children[0] !== heading || children[1].tagName !== 'DIV') continue;
      const body = children[1];
      // Refuse ambiguous branches instead of copying controls or another turn.
      const codeEditor = '[aria-label="Edit code"]';
      const safe = !body.querySelector('form,textarea,[data-message-author-role]')
        && ![...body.querySelectorAll('[contenteditable="true"],[role="textbox"]')].some(e => !e.matches(codeEditor))
        && (!body.querySelector('button,[role="button"]') || !!body.querySelector('pre,code,table,' + codeEditor));
      candidate.bodies = safe ? [body] : [];
    }
    candidates.sort((a,b) => a.node === b.node ? 0 : a.node.compareDocumentPosition(b.node) & Node.DOCUMENT_POSITION_FOLLOWING ? -1 : 1);
    if (selectionOnly) {
        const selection = window.getSelection();
        if (!selection || selection.isCollapsed || !selection.rangeCount) return {status:'empty'};
        const range = selection.getRangeAt(0);
        const parent = range.commonAncestorContainer.nodeType === Node.ELEMENT_NODE
            ? range.commonAncestorContainer : range.commonAncestorContainer.parentElement;
        // Only recognized assistant content can authorize an editable code block.
        const body = candidates.flatMap(c => c.bodies).find(e => e.contains(parent));
        if (!body || parent.closest('form,textarea,button,[role="button"]')) return {status:'unavailable'};
        const forbidden = [...document.querySelectorAll('form,textarea,button,[role="button"],[contenteditable="true"],[role="textbox"]')]
            .filter(e => !(e.matches('[aria-label="Edit code"]') && body.contains(e)
                && !e.closest('form,textarea')));
        if (forbidden.some(e => range.intersectsNode(e))) return {status:'unavailable'};
        return {status:'copied', text:selection.toString()};
    }
    const last = candidates.at(-1);
    if (!last || !last.bodies.length) return {status:'unavailable'};
    const bodies = last.bodies;
    // Serialize structure instead of flattening editor lines or HTML table cells.
    const render = node => {
      if (node.nodeType === Node.TEXT_NODE) return node.textContent;
      if (node.nodeType !== Node.ELEMENT_NODE) return '';
      const tag = node.tagName;
      if (node.matches('button,[role="button"],script,style,svg,[aria-hidden="true"]') || getComputedStyle(node).display === 'none') return '';
      if (tag === 'PRE' || node.matches('[aria-label="Edit code"]')) {
        const raw = node.innerText.replace(/\n$/, '');
        const fence = '`'.repeat(Math.max(3, ...[...raw.matchAll(/`+/g)].map(m => m[0].length + 1)));
        return '\n\n' + fence + '\n' + raw + '\n' + fence + '\n\n';
      }
      if (tag === 'TABLE') {
        const rows = [...node.rows].map(row => [...row.cells].map(cell => cell.innerText.trim().replace(/\|/g, '\\|').replace(/\n/g, '<br>')));
        if (!rows.length) return '';
        const width = Math.max(...rows.map(row => row.length));
        const line = row => '| ' + Array.from({length:width}, (_,i) => row[i] || '').join(' | ') + ' |';
        return '\n\n' + [line(rows[0]), line(Array(width).fill('---')), ...rows.slice(1).map(line)].join('\n') + '\n\n';
      }
      if (tag === 'OL' || tag === 'UL') {
        const items = [...node.children].filter(e => e.tagName === 'LI');
        const reversed = tag === 'OL' && node.hasAttribute('reversed');
        let number = node.hasAttribute('start') ? node.start : reversed ? items.length : 1;
        const lines = items.map(item => {
          if (tag === 'OL' && item.hasAttribute('value')) number = item.value;
          const marker = tag === 'OL' ? `${number}. ` : '- ';
          number += reversed ? -1 : 1;
          const text = [...item.childNodes].map(render).join('').trim();
          return marker + text.replace(/\n/g, '\n' + ' '.repeat(marker.length));
        });
        return '\n' + lines.join('\n') + '\n';
      }
      if (tag === 'BR') return '\n';
      const content = [...node.childNodes].map(render).join('');
      if (/^H[1-6]$/.test(tag)) return '\n\n' + '#'.repeat(Number(tag[1])) + ' ' + content.trim() + '\n\n';
      if (['P','DIV','SECTION','UL','OL','BLOCKQUOTE'].includes(tag)) return '\n' + content.trim() + '\n';
      return content;
    };
    const text = bodies.map(render).join('\n\n').trim();
    return text ? {status:'copied', text} : {status:'empty'};
    """#
}
