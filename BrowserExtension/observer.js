(() => {
  const webExt = globalThis.browser || globalThis.chrome;
  const signals = globalThis.ClawdSignals;
  const HEARTBEAT = 20000;
  const send = message => webExt.runtime.sendMessage(message).catch(() => ({ok: false}));
  const webPush = globalThis.ClawdWebPush.create({send});
  let enabled = false;
  let path = location.pathname;
  let state = 'idle';
  let cancelled = false;
  let lastActivity = 0;
  let lastUsage = null;
  let usageSent = false;
  let previousWorkingAt = 0;
  let approval = null;
  let approvalSentAt = 0;
  let missingSince = null;
  let timer = 0;
  let running = false;
  let rerun = false;

  async function sample() {
    if (!enabled) return;
    if (running) { rerun = true; return; }
    running = true;
    try {
      const now = Date.now();
      const routeChanged = path !== location.pathname;
      // A new chat gets a permanent URL after submit. It remains the same turn.
      const sameNewTurn = /\/new\/?$/.test(path) && /\/chat\/[^/]+\/?$/.test(location.pathname);
      path = location.pathname;
      if (routeChanged) { lastUsage = null; usageSent = false; }
      const chat = signals.chatRoute(path) && !document.prerendering;
      const active = chat ? signals.activity(document) : 'idle';
      let waiting = chat && signals.awaitingApproval(document);
      const previouslyWaiting = approval === true;
      if (previouslyWaiting && !waiting && !routeChanged) {
        // Keep a brief React remount of the same decision card from folding the sign.
        if (missingSince === null) { missingSince = now; setTimeout(schedule, 500); }
        waiting = now - missingSince < 450;
      } else { missingSince = null; }
      if (approval !== waiting || now - approvalSentAt >= HEARTBEAT || routeChanged) {
        const delivered = await send({op:'approval', waiting});
        if (delivered?.ok) { approval = waiting; approvalSentAt = now; }
      }
      if (active !== 'idle') previousWorkingAt = now;
      // A brief re-render can temporarily dismount the stop control.
      if (active === 'idle' && state !== 'idle' && !routeChanged && now - previousWorkingAt < 900) {
        setTimeout(schedule, 950);
      } else if (active !== state || routeChanged || now - lastActivity >= HEARTBEAT) {
        const wasBusy = state !== 'idle';
        const finish = wasBusy && active === 'idle' && !waiting && !previouslyWaiting && !cancelled && (!routeChanged || sameNewTurn);
        const delivered = await send({op: 'signal', state: active, finish});
        if (delivered?.ok) {
          state = active;
          lastActivity = now;
          if (active === 'idle') cancelled = false;
        }
      }

      if (signals.usageRoute(path) && !document.prerendering) {
        const main = document.querySelector('main, [role="main"]') || document.body;
        if (!main) return;
        const observed = new Date();
        const windows = signals.usage(main.innerText || '', observed);
        if (!windows.length) return;
        // A fixed relative label must retain its first observation time across retries.
        const key = JSON.stringify(windows.map(({kind, remainingPercent, resetLabel}) => [kind, remainingPercent, resetLabel]));
        if (!lastUsage || lastUsage.key !== key) {
          lastUsage = {key, windows, observedAt: signals.isoSeconds(observed)};
          usageSent = false;
        }
        if (!usageSent) {
          const result = await send({op: 'usage', windows: lastUsage.windows, observedAt: lastUsage.observedAt});
          usageSent = !!result?.ok;
        }
      }
    } finally {
      running = false;
      if (rerun) { rerun = false; schedule(); }
    }
  }

  function schedule() {
    if (!enabled || timer) return;
    timer = setTimeout(() => { timer = 0; void sample(); }, 180);
  }
  const observer = new MutationObserver(schedule);
  observer.observe(document.documentElement, {
    childList: true, subtree: true, characterData: true, attributes: true,
    attributeFilter: ['aria-label', 'aria-labelledby', 'aria-hidden', 'aria-disabled', 'disabled', 'open', 'inert',
      'role', 'title', 'data-testid', 'data-is-streaming', 'hidden', 'style', 'class']
  });
  document.addEventListener('click', event => {
    const button = event.target instanceof Element ? event.target.closest('button') : null;
    if (button && signals.isStopButton(button)) cancelled = true;
  }, true);
  document.addEventListener('visibilitychange', schedule);
  window.addEventListener('pageshow', schedule);
  window.addEventListener('popstate', schedule);
  webExt.runtime.onMessage.addListener(message => {
    if (message.op === 'sample') {
      enabled = message.enabled === true;
      webPush.setEnabled(enabled);
      lastActivity = 0;
      state = 'idle';
      cancelled = false;
      usageSent = false;
      approval = null;
      approvalSentAt = 0;
      missingSince = null;
      if (!enabled) lastUsage = null;
      schedule();
    }
  });
  setInterval(schedule, HEARTBEAT);
  send({op: 'enabled'}).then(answer => {
    enabled = answer?.enabled === true;
    webPush.setEnabled(enabled);
    schedule();
  });
})();
