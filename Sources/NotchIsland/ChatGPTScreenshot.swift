import Foundation

/// Delivers only the user-selected screenshot through the page's paste handler.
/// No private endpoints, credentials, message submission, or editor replacement.
enum ChatGPTScreenshot {
    static let script = #"""
    if (location.origin !== 'https://chatgpt.com' ||
        !(location.pathname === '/' || location.pathname.startsWith('/c/') || location.pathname.startsWith('/uc/'))) return 'unavailable';
    const visible = e => e.getClientRects().length > 0 && getComputedStyle(e).visibility !== 'hidden';
    const named = [...document.querySelectorAll('#prompt-textarea,#mobile-composer-prompt')].filter(visible);
    const candidates = [...document.querySelectorAll('form [contenteditable="true"],form textarea')].filter(visible);
    const editor = named.length === 1 ? named[0] : candidates.length === 1 ? candidates[0] : null;
    if (!editor || !editor.closest('form')) return 'unavailable';
    const bytes = Uint8Array.from(atob(png), c => c.charCodeAt(0));
    const file = new File([bytes], name, {type:'image/png'});
    const transfer = new DataTransfer();
    transfer.items.add(file);
    // Do not retry automatically: the page might have started an asynchronous upload.
    editor.focus({preventScroll:true});
    const event = new ClipboardEvent('paste', {clipboardData:transfer, bubbles:true, cancelable:true});
    editor.dispatchEvent(event);
    return event.defaultPrevented ? 'handled' : 'unconfirmed';
    """#
}
