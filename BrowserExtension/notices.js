/* Runs in the extension's isolated world. Observe only page-owned notification surfaces. */
(() => {
  'use strict';
  const candidates = [
    '[role="alert"]', '[data-sonner-toast]', '.Toastify__toast', '[data-radix-toast-root]',
    '[data-slot="toast"]', '[data-testid="toast"]', '[data-testid="toast-notification"]',
    '[data-testid="notification-toast"]', '[data-testid="notification-banner"]',
    '[data-testid="system-notification"]', '[data-testid="toast-viewport"] [role="status"]',
    '[aria-label*="Notification" i] li[role="status"]', '[aria-label*="Benachrichtigung" i] li[role="status"]',
    'li[role="status"][data-state][data-swipe-direction]'
  ].join(',');
  const privateSurface = [
    'form', 'input', 'textarea', '[contenteditable]:not([contenteditable="false"])', '[role="textbox"]',
    '[role="log"]', '[data-message-author-role]', '[data-message-id]', '[data-message-index]',
    '[data-user-message-bubble]', '[data-testid="chat-input"]', '[data-testid*="user-message"]',
    '[data-testid*="assistant-message"]', '[data-testid="user-human-turn"]', '[data-testid="ai-turn"]',
    '[data-testid="assistant-turn"]', '[data-testid="conversation-turn"]', '[data-testid="chat-messages"]',
    '[data-testid="message-content"]', '[data-testid="chat-message"]', '[data-artifact-id]',
    '.font-claude-response', '.standard-markdown', '.prose', '.tiptap', '.ProseMirror', 'pre', 'code'
  ].join(',');
  const ignored = [
    privateSurface, 'script', 'style', 'template', 'svg', 'iframe', 'canvas', 'button', '[role="button"]',
    '[hidden]', '[aria-hidden="true"]', '[inert]', '.sr-only', '.visually-hidden', '[data-close-button]'
  ].join(',');
  const heading = '[data-title],[data-toast-title],[data-slot="toast-title"],[data-testid="toast-title"],h1,h2,h3,h4,[role="heading"]';
  const description = '[data-description],[data-toast-description],[data-slot="toast-description"],[data-testid="toast-description"]';
  const blockedRoutes = /(?:^|\/)(?:login|signup|verify|oauth|sso|auth|reset-password)(?:\/|$)/i;

  function clean(text, limit) {
    const normalized = text.replace(/[\u0000-\u001f\u007f-\u009f]/gu, ' ')
      .replace(/[\u200e\u200f\u202a-\u202e\u2066-\u2069]/gu, '').replace(/\s+/gu, ' ').trim();
    if (normalized.length <= limit) return normalized;
    const glyphs = typeof Intl.Segmenter === 'function'
      ? [...new Intl.Segmenter(undefined, {granularity:'grapheme'}).segment(normalized)].map(x => x.segment)
      : Array.from(normalized);
    let result = '';
    for (const glyph of glyphs) {
      if (result.length + glyph.length >= limit) break;
      result += glyph;
    }
    return result.trimEnd() + '…';
  }

  function payload(title, body, type = '') {
    let message = clean(body, 220);
    let label = clean(title, 65);
    if (!message) { message = clean(title, 220); label = ''; }
    if (!message || /^(?:(?:link |text )?copied(?: to clipboard)?|(?:link |text |in die zwischenablage )?kopiert)[.! ]*$/i.test(message)) return null;
    if (!label || label === message) label = 'Claude.ai';
    const words = label + ' ' + message;
    const kinds = ['info','success','warning','error','attention'];
    let kind = kinds.includes(type) ? type : 'info';
    if (!kinds.includes(type)) {
      if (/\b(?:error|failed|fehler|fehlgeschlagen|couldn.t|wasn.t sent|nicht gesendet)\b/i.test(words)) kind = 'error';
      else if (/\b(?:warnung|warning|limit|kontingent|limit reached|nutzungslimit)\b/i.test(words)) kind = 'warning';
      else if (/\b(?:approval|permission|bestätigung|freigabe|berechtigung)\b/i.test(words)) kind = 'attention';
      else if (/\b(?:success(?:ful(?:ly)?)?|completed|finished|gespeichert|erfolgreich|abgeschlossen)\b/i.test(words)) kind = 'success';
    }
    return {type:'notice', title:label, message, kind};
  }

  function visible(root) {
    if (!root.isConnected || root.closest('[hidden],[inert],[aria-hidden="true"],[data-state="closed"],.sr-only,.visually-hidden')) return false;
    const view = root.ownerDocument.defaultView;
    const rect = root.getBoundingClientRect();
    if (rect.width <= 2 || rect.height <= 2 || rect.bottom <= 0 || rect.right <= 0 ||
        rect.left >= view.innerWidth || rect.top >= view.innerHeight) return false;
    if (typeof root.checkVisibility === 'function')
      return root.checkVisibility({checkVisibilityCSS:true, checkOpacity:true});
    for (let el = root; el; el = el.parentElement) {
      const css = view.getComputedStyle(el);
      if (css.visibility === 'hidden' || css.display === 'none' || css.opacity === '0') return false;
    }
    return true;
  }

  function textFrom(root, skip = null) {
    if (!root) return '';
    const view = root.ownerDocument.defaultView;
    let result = '', visited = 0;
    function collect(node) {
      if (visited++ > 220 || result.length > 640 || node === skip) return;
      if (node.nodeType === 3) { result += node.nodeValue; return; }
      if (node.nodeType !== 1 || node.matches(ignored)) return;
      const css = view.getComputedStyle(node);
      if (css.display === 'none' || css.visibility === 'hidden' || css.opacity === '0') return;
      const block = !css.display.startsWith('inline') && css.display !== 'contents';
      if (block || node.tagName === 'BR') result += ' ';
      for (const child of node.childNodes) collect(child);
      if (block) result += ' ';
    }
    collect(root);
    return result;
  }

  function readNotice(root) {
    if (root.closest(privateSurface) || root.querySelector(privateSurface) || !visible(root)) return null;
    const title = root.querySelector(heading);
    const body = root.querySelector(description);
    const hint = root.getAttribute('data-type') || root.getAttribute('data-variant') || '';
    return payload(textFrom(title), body ? textFrom(body) : textFrom(root, title), hint);
  }

  function watch(doc, send) {
    let enabled = false, timer = 0, transitionTimer = 0, seen = new WeakMap();
    const pending = new Set(), recent = new Map();

    function flush() {
      timer = 0;
      if (!enabled || blockedRoutes.test(doc.location.pathname)) { pending.clear(); return; }
      const delayed = [];
      const now = Date.now();
      for (const [key, stamp] of recent) if (now - stamp >= 12000) recent.delete(key);
      for (const node of pending) {
        if (!node.isConnected || !node.matches(candidates)) continue;
        const info = readNotice(node);
        if (!info) {
          seen.delete(node);
          if (!visible(node)) delayed.push(node);
          continue;
        }
        const key = JSON.stringify(info);
        if (seen.get(node) === key) continue;
        seen.set(node, key);
        if (recent.has(key)) continue;
        recent.set(key, now);
        if (recent.size > 32) recent.delete(recent.keys().next().value);
        send(info);
      }
      pending.clear();
      // CSS transitions may have started with opacity zero. Retry once, even if the
      // animation itself produces no more DOM mutations.
      if (delayed.length && !transitionTimer) {
        transitionTimer = setTimeout(() => {
          for (const node of delayed) if (node.isConnected && visible(node)) pending.add(node);
          if (pending.size && !timer) timer = setTimeout(flush, 0);
          transitionTimer = 0;
        }, 350);
      }
    }

    function remember(el) {
      let outer = el;
      while (outer.parentElement?.closest(candidates)) outer = outer.parentElement.closest(candidates);
      pending.add(outer);
    }

    function queue(node, descendants) {
      const el = node.nodeType === 1 ? node : node.parentElement;
      if (!el || el.closest(privateSurface)) return;
      const enclosing = el.closest(candidates);
      if (enclosing) remember(enclosing);
      if (descendants && !enclosing && el.nodeType === 1) {
        for (const child of el.querySelectorAll(candidates)) if (!child.closest(privateSurface)) remember(child);
      }
    }

    const observer = new MutationObserver(records => {
      if (!enabled || blockedRoutes.test(doc.location.pathname)) return;
      for (const change of records) {
        if (change.type === 'childList') {
          queue(change.target, false);
          for (const node of change.addedNodes) queue(node, true);
        } else {
          queue(change.target, change.type === 'attributes');
        }
      }
      if (pending.size && !timer) timer = setTimeout(flush, 100);
    });

    return function setEnabled(value) {
      if (enabled === value) return;
      enabled = value;
      if (enabled) {
        // Treat already displayed notices as history when pairing or loading the page.
        if (!blockedRoutes.test(doc.location.pathname)) {
          for (const root of doc.querySelectorAll(candidates)) {
            const info = readNotice(root);
            if (info) seen.set(root, JSON.stringify(info));
          }
        }
        observer.observe(doc.documentElement, {subtree:true, childList:true, characterData:true, attributes:true,
          attributeFilter:['role','data-state','aria-hidden','hidden','style','class','data-type']});
      } else {
        observer.disconnect();
        clearTimeout(timer); clearTimeout(transitionTimer);
        timer = transitionTimer = 0;
        pending.clear(); recent.clear(); seen = new WeakMap();
      }
    };
  }

  if (typeof module !== 'undefined' && module.exports) module.exports = {payload, readNotice, watch};
  const runtime = (globalThis.browser || globalThis.chrome)?.runtime;
  if (!runtime || typeof document === 'undefined') return;
  const setEnabled = watch(document, notice => { runtime.sendMessage(notice).catch(() => {}); });
  let changes = 0;
  function apply(answer) { setEnabled(answer?.enabled === true && answer.noticesEnabled !== false); }
  runtime.onMessage.addListener(message => {
    if (message?.op === 'sample') { changes++; apply(message); }
  });
  runtime.sendMessage({op:'enabled'}).then(result => { if (!changes) apply(result); }).catch(() => {});
})();
