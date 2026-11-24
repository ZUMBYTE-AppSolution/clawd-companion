// Observe persistent notifications of the current website registration, when the browser exposes them.
(() => {
  const origin = 'https://claude.ai';
  function text(value, max) {
    if (typeof value !== 'string') return '';
    const clean = value.slice(0, 2048).replace(/[\u0000-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]/gu, ' ')
      .replace(/\s+/gu, ' ').trim().slice(0, max);
    // Both the transport and the size limits count UTF-16 units.
    return clean.replace(/[\ud800-\udbff]$/u, '').trimEnd();
  }

  function create({send}, page = globalThis) {
    let current;
    let timer;

    async function record(notification, scope) {
      const title = text(notification.title, 65);
      const body = text(notification.body, 220);
      if (!title && !body) return null;
      // Tags can contain conversation IDs. Only the digest leaves this script.
      const identity = [scope, text(notification.tag, 256), Number.isFinite(notification.timestamp) ? notification.timestamp : null, title, body];
      const hash = await page.crypto.subtle.digest('SHA-256', new TextEncoder().encode(JSON.stringify(identity)));
      const eventKey = 'sw:' + Array.from(new Uint8Array(hash), byte => byte.toString(16).padStart(2, '0')).join('');
      return {op: 'notification', eventKey, title: title || 'Claude.ai', body};
    }

    async function sample() {
      const session = current;
      if (!session || session.reading) return;
      session.reading = true;
      try {
        const eligible = () => current === session && page.location.origin === origin && page.Notification?.permission === 'granted';
        if (!eligible()) { session.scope = null; session.seen.clear(); return; }
        const registration = await page.navigator.serviceWorker?.getRegistration();
        if (!eligible()) return;
        if (!registration || new URL(registration.scope).origin !== origin || typeof registration.getNotifications !== 'function') {
          session.scope = null;
          session.seen.clear();
          return;
        }
        const notifications = await registration.getNotifications();
        if (!eligible()) return;
        // When the browser presents a backlog, resume from a new baseline instead of replaying history.
        if (!Array.isArray(notifications) || notifications.length > 64) {
          session.scope = null;
          session.seen.clear();
          return;
        }
        const records = (await Promise.all(notifications.map(item => record(item, registration.scope)))).filter(Boolean);
        if (!eligible()) return;
        if (registration.scope !== session.scope) {
          session.scope = registration.scope;
          session.seen = new Set(records.map(item => item.eventKey));
          return;
        }
        const active = new Set(records.map(item => item.eventKey));
        for (const key of session.seen) if (!active.has(key)) session.seen.delete(key);
        for (const entry of records) {
          if (!eligible()) return;
          if (!session.seen.has(entry.eventKey) && (await send(entry))?.ok) session.seen.add(entry.eventKey);
        }
      } catch {
        // Restricted isolated worlds and browsers without access to site registrations simply skip this channel.
      } finally {
        session.reading = false;
      }
    }

    function setEnabled(enabled) {
      if (enabled === Boolean(current)) return;
      if (current) page.clearInterval(timer);
      current = enabled ? {scope: null, seen: new Set(), reading: false} : null;
      if (current) {
        timer = page.setInterval(sample, 5000);
        return sample();
      }
    }
    return {setEnabled};
  }

  globalThis.ClawdWebPush = {create};
  if (typeof module !== 'undefined' && module.exports) module.exports = {create};
})();
