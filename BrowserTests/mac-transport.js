// JavaScriptCore supplies the JS runtime; these stand-ins implement browser transport and storage.
const extensionID = 'abcdefghijklmnopabcdefghijklmnop';
let receiveFromTab;
const ignore = {addListener() {}};
function storageArea() {
  let items = {};
  return {
    async setAccessLevel() {},
    async get(keys) {
      return Object.fromEntries([].concat(keys).map(k => [k, items[k]]));
    },
    async set(updates) { Object.assign(items, updates); },
    async remove(keys) { for (const key of [].concat(keys)) delete items[key]; },
    async clear() { items = {}; }
  };
}
globalThis.chrome = {
  runtime: {
    id: extensionID,
    getURL: p => 'chrome-extension://' + extensionID + '/' + p,
    onMessage: {addListener(fn) { receiveFromTab = fn; }}
  },
  tabs: {onRemoved: ignore, onUpdated: ignore, query: async () => []},
  storage: {local: storageArea(), session: storageArea()}
};
globalThis.URL = class {
  constructor(url) { this.pathname = url.replace(/^https?:\/\/[^/]+/, ''); }
};
globalThis.AbortController = class { abort() {} };
globalThis.setTimeout = () => 1;
globalThis.clearTimeout = () => {};
globalThis.TextEncoder = class {
  encode(value) {
    return Uint8Array.from(unescape(encodeURIComponent(value)), c => c.charCodeAt(0));
  }
};
globalThis.crypto = {randomUUID: () => '815cc349-15fe-4916-a60a-818f5d163745', subtle: {async digest(algorithm, bytes) {
  if (algorithm !== 'SHA-256') throw new Error('Unexpected digest');
  return Uint8Array.from(nativeSHA256(Array.from(bytes))).buffer;
}}};
globalThis.fetch = async (url, init) => {
  const status = nativeRequest(url, init.method, init.headers['Content-Type'], init.headers.Authorization, init.body);
  return {ok: status === 200, status};
};
async function exerciseWorker(pairingCode) {
  function send(message, sender) {
    return new Promise((resolve, reject) => {
      receiveFromTab(message, Object.assign({id: extensionID}, sender), reply => {
        if (reply && reply.ok) resolve();
        else reject(new Error('Worker declined ' + message.op + ': ' + JSON.stringify(reply)));
      });
    });
  }
  const chat = {tab: {id: 2}, frameId: 0, url: 'https://claude.ai/chat/example'};
  const settingsPage = {tab: {id: 3}, frameId: 0, url: 'https://claude.ai/settings/usage'};
  await send({op: 'pair', code: pairingCode}, {url: chrome.runtime.getURL('popup.html')});
  await send({op: 'signal', state: 'thinking'}, chat);
  await send({op: 'signal', state: 'working'}, chat);
  await send({op: 'signal', state: 'idle', finish: true}, chat);
  const now = new Date();
  const visibleUsage = 'Current session\n25% used\nResets in 2 hours\nWeekly limits\nAll models\n40% used\nResets in 4 days';
  await send({op: 'usage', observedAt: ClawdSignals.isoSeconds(now), windows: ClawdSignals.usage(visibleUsage, now)}, settingsPage);
  const notice = {type: 'notice', kind: 'error', title: 'Claude.ai', message: 'Bitte erneut versuchen.'};
  await send(notice, chat);
  await send(notice, chat);
  await send({op:'approval', waiting:true}, chat);
  await send({op:'approval', waiting:false}, chat);
}
