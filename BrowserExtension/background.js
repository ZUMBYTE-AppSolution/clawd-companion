const webExt = globalThis.browser || globalThis.chrome;
const endpoint = 'http://127.0.0.1:49217/v1/events';
const activeStates = new Set(['working', 'thinking', 'searching', 'planning', 'reading', 'executing', 'drawing']);
// Content scripts do not need the local pairing token.
if (webExt.storage.local.setAccessLevel) void webExt.storage.local.setAccessLevel({accessLevel: 'TRUSTED_CONTEXTS'}).catch(() => {});
const sessions = webExt.storage.session || webExt.storage.local;
const nativeTransport = webExt.runtime.getURL('').startsWith('safari-web-extension://');

let queue = Promise.resolve();
function ordered(action) {
  const run = queue.then(action);
  queue = run.catch(() => {});
  return run;
}
async function post(token, event) {
  if (!token) return {ok: false, reason: 'unpaired'};
  if (nativeTransport) {
    try {
      return await webExt.runtime.sendNativeMessage('de.zumbyte.clawdcompanion', {token, event});
    } catch { return {ok: false, reason: 'offline'}; }
  }
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 2000);
  try {
    const response = await fetch(endpoint, {
      method: 'POST', headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token},
      redirect: 'error', cache: 'no-store', credentials: 'omit', referrerPolicy: 'no-referrer',
      body: JSON.stringify(event), signal: controller.signal
    });
    return response.ok ? {ok: true} : {ok: false, reason: [401, 403].includes(response.status) ? 'token' : 'rejected'};
  } catch { return {ok: false, reason: 'offline'}; }
  finally { clearTimeout(timer); }
}
async function syncTabs(enabled) {
  for (const tab of await webExt.tabs.query({url: 'https://claude.ai/*'})) {
    if (Number.isInteger(tab.id)) webExt.tabs.sendMessage(tab.id, {op: 'sample', enabled}).catch(() => {});
  }
}
async function settings(message) {
  if (message.op === 'forget') {
    await clearApprovals();
    await webExt.storage.local.remove('token');
    await sessions.remove(['tabs', 'reported', 'recentNotices']);
    await syncTabs(false);
    return {ok: true};
  }
  const {token} = await webExt.storage.local.get('token');
  if (message.op === 'status') {
    if (!token) return {ok: false, reason: 'unpaired'};
    const {tabs = {}} = await sessions.get('tabs');
    return post(token, {type: 'activity', state: dominant(tabs)?.state ?? 'connected'});
  }
  if (message.op === 'pair') {
    const code = String(message.code || '').trim();
    if (!/^[A-Za-z0-9_+/=.-]{8,256}$/.test(code)) return {ok: false, reason: 'token'};
    const result = await post(code, {type: 'activity', state: 'connected'});
    if (result.ok) {
      await clearApprovals();
      await webExt.storage.local.set({token: code});
      await sessions.remove(['tabs', 'reported', 'recentNotices']);
      await syncTabs(true);
    }
    return result;
  }
  return {ok: false};
}
const approvalLease = 125000;
async function clearApprovals() {
  const {approvalPublished} = await sessions.get('approvalPublished');
  const {token, approvalSource} = await webExt.storage.local.get(['token', 'approvalSource']);
  if (approvalPublished && token && approvalSource) await post(token, {type:'approval', sourceID:approvalSource, waiting:false});
  await sessions.remove(['approvalTabs', 'approvalPublished']);
}
async function reportApproval(id, waiting) {
  const {token, approvalSource} = await webExt.storage.local.get(['token', 'approvalSource']);
  if (!token) return {ok:false, reason:'unpaired'};
  const {approvalTabs = {}, approvalPublished = false} = await sessions.get(['approvalTabs', 'approvalPublished']);
  const now = Date.now();
  let changed = false;
  for (const [tab, seen] of Object.entries(approvalTabs)) {
    if (seen < now - approvalLease || (tab === String(id) && !waiting)) { delete approvalTabs[tab]; changed = true; }
  }
  if (waiting) { approvalTabs[id] = now; changed = true; }
  const any = Object.keys(approvalTabs).length > 0;
  if (changed) await sessions.set({approvalTabs});
  // A heartbeat from an idle tab cannot renew a suspended tab's native lease.
  if (!waiting && any === approvalPublished) return {ok:true};
  let sourceID = approvalSource;
  if (!sourceID) {
    if (!any) return {ok:true};
    sourceID = crypto.randomUUID().toLowerCase();
    await webExt.storage.local.set({approvalSource:sourceID});
  }
  // An interrupted HTTP response may already have reached the Mac. Keep the
  // clearing obligation through worker restarts and harmless retries.
  if (any && !approvalPublished) await sessions.set({approvalPublished:true});
  const result = await post(token, {type:'approval', sourceID, waiting:any});
  if (result.ok && !any) await sessions.remove(['approvalTabs','approvalPublished']);
  return result;
}
function dominant(tabs) {
  return Object.values(tabs).filter(tab => tab.time > Date.now() - 120000)
    .sort((a, b) => b.time - a.time)[0];
}
async function reportTab(id, state, finish) {
  const {token} = await webExt.storage.local.get('token');
  if (!token) return {ok: false, reason: 'unpaired'};
  const {tabs = {}, reported} = await sessions.get(['tabs', 'reported']);
  const previous = tabs[id];
  for (const key of Object.keys(tabs)) if (tabs[key].time < Date.now() - 120000) delete tabs[key];
  if (activeStates.has(state)) tabs[id] = {state, time: Date.now()};
  else delete tabs[id];
  const selected = activeStates.has(state) ? tabs[id] : dominant(tabs);
  let aggregate = selected?.state || (previous ? (finish ? 'done' : 'idle') : 'connected');
  // Recover a completion after a failed post, until another working turn starts.
  if (!selected && !previous && reported?.pending) aggregate = reported.pending;
  if (!selected && !previous && aggregate === 'connected' && reported?.sent > Date.now() - 18000) {
    await sessions.set({tabs});
    return {ok: true};
  }
  const result = await post(token, {type: 'activity', state: aggregate});
  await sessions.set({
    tabs, reported: result.ok ? {sent: Date.now()} : {pending: ['done', 'idle'].includes(aggregate) ? aggregate : null}
  });
  return result;
}
function usagePayload(message) {
  const instant = value => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(value) && Number.isFinite(Date.parse(value));
  if (!Array.isArray(message.windows) || message.windows.length < 1 || message.windows.length > 2 || !instant(message.observedAt)) return null;
  const kinds = new Set();
  const windows = [];
  for (const input of message.windows) {
    if (!input || !['session','weekly'].includes(input.kind) || kinds.has(input.kind)
      || !Number.isInteger(input.remainingPercent) || input.remainingPercent < 0 || input.remainingPercent > 100) return null;
    kinds.add(input.kind);
    const win = {kind: input.kind, remainingPercent: input.remainingPercent};
    if (instant(input.resetAt)) {
      win.resetAt = input.resetAt;
      if (input.resetApproximate === true) win.resetApproximate = true;
    }
    if (typeof input.resetLabel === 'string' && input.resetLabel.length <= 100 && !/[\r\n]/.test(input.resetLabel)) win.resetLabel = input.resetLabel;
    windows.push(win);
  }
  return {type: 'usage', observedAt: message.observedAt, windows};
}
function noticePayload(message) {
  const push = message.op === 'notification';
  const shorten = (value, max) => typeof value === 'string'
    ? [...value.replace(/[\u0000-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]/g, ' ').replace(/\s+/g, ' ').trim()].slice(0, max).join('') : '';
  let title = shorten(message.title, 65);
  let body = shorten(push ? message.body : message.message, 220);
  if (push && title && !body) {
    body = title;
    title = 'Claude.ai';
  }
  const kind = push ? 'info' : message.kind;
  if (!title || !body || !['info', 'success', 'warning', 'error', 'attention'].includes(kind)) return null;
  return {type: 'notice', title, message: body, kind};
}
async function fingerprint(text) {
  const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return Array.from(new Uint8Array(bytes), n => n.toString(16).padStart(2, '0')).join('');
}
async function reportNotice(notice, eventKey) {
  const {token} = await webExt.storage.local.get('token');
  if (!token) return {ok: false, reason: 'unpaired'};
  const {recentNotices = []} = await sessions.get('recentNotices');
  const now = Date.now();
  const notes = recentNotices.filter(entry => now - entry.time < 86400000).slice(-127);
  const content = await fingerprint(JSON.stringify([notice.title, notice.message]));
  const id = typeof eventKey === 'string' && eventKey.length <= 1024 && eventKey
    ? await fingerprint(eventKey) : null;
  if (id && notes.some(item => item.id === id)) return {ok: true};
  const duplicate = notes.find(item => item.content === content && now - item.time < 12000);
  if (duplicate) {
    if (id && !duplicate.id) {
      duplicate.id = id;
      await sessions.set({recentNotices: notes});
    }
    return {ok: true};
  }
  if (notes.filter(item => now - item.time < 15000).length >= 4) return {ok: true};
  const result = await post(token, notice);
  if (result.ok) await sessions.set({recentNotices: [...notes, {id, content, time: now}]});
  return result;
}
webExt.runtime.onMessage.addListener((message, sender, reply) => {
  if ((sender.id && webExt.runtime.id && sender.id !== webExt.runtime.id) || !message || typeof message !== 'object') return;
  let action;
  if (sender.url === webExt.runtime.getURL('popup.html')) action = () => settings(message);
  else if (Number.isInteger(sender.tab?.id) && sender.frameId === 0 && sender.url?.startsWith('https://claude.ai/')) {
    if (message.type === 'notice' || message.op === 'notification') {
      const notice = noticePayload(message);
      if (notice) action = () => reportNotice(notice, message.op === 'notification' ? message.eventKey : null);
    }
    if (message.op === 'enabled') action = async () => ({ok: true, enabled: Boolean((await webExt.storage.local.get('token')).token)});
    if (message.op === 'signal' && (message.state === 'idle' || activeStates.has(message.state)))
      action = () => reportTab(sender.tab.id, message.state, message.finish === true);
    if (message.op === 'approval' && typeof message.waiting === 'boolean') {
      const chat = /^\/(?:[a-z]{2,3}(?:-[a-z]{2,8}){0,2}\/)?(?:chat\/[^/]+|new|project\/[^/]+)\/?$/i.test(new URL(sender.url).pathname);
      if (chat || !message.waiting) action = () => reportApproval(sender.tab.id, message.waiting);
    }
    if (message.op === 'usage' && /^\/(?:[a-z]{2,3}(?:-[a-z]{2,8}){0,2}\/)?settings\/usage\/?$/i.test(new URL(sender.url).pathname)) {
      const payload = usagePayload(message);
      if (payload) action = async () => post((await webExt.storage.local.get('token')).token, payload);
    }
  }
  if (!action) { reply({ok: false}); return; }
  ordered(action).then(reply, () => reply({ok: false, reason: 'offline'}));
  return true;
});
function detach(id) {
  ordered(async () => {
    await reportApproval(id, false);
    const {tabs = {}} = await sessions.get('tabs');
    if (tabs[id]) await reportTab(id, 'idle', false);
  }).catch(() => {});
}
webExt.tabs.onRemoved.addListener(detach);
webExt.tabs.onUpdated.addListener((id, change) => { if (change.status === 'loading') detach(id); });
