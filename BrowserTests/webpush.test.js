const test = require('node:test');
const assert = require('node:assert/strict');
const {webcrypto} = require('node:crypto');
const {create} = require('../BrowserExtension/webpush.js');

function fixture() {
  const sent = [];
  let tick;
  let reads = 0;
  let result = {ok: true};
  const registration = {scope: 'https://claude.ai/', entries: [], getNotifications() { reads++; return this.entries; }};
  const page = {
    location: {origin: 'https://claude.ai'},
    Notification: {permission: 'granted'},
    navigator: {serviceWorker: {getRegistration: async () => registration}},
    crypto: webcrypto,
    setInterval(fn) { tick = fn; return 42; },
    clearInterval(id) { assert.equal(id, 42); tick = null; }
  };
  const watcher = create({send: async payload => { sent.push(payload); return result; }}, page);
  // A deterministic tick awaits WebCrypto's digest and the resulting asynchronous delivery.
  return {page, registration, watcher, sent, reads: () => reads, tick: () => tick?.(), result(value) { result = value; }};
}

test('ignores existing entries, reports newly visible notifications once and sends bounded text only', async () => {
  const f = fixture();
  const old = {title: 'Old', tag: 'old', timestamp: 11};
  f.registration.entries.push(old);
  await f.watcher.setEnabled(true);
  assert.deepEqual(f.sent, []);
  f.registration.entries.push({title:'T'.repeat(64) + '🐈', body:'B'.repeat(240), tag:'sensitive-reference',
    timestamp:12, data:{secret:true}, actions:[{action:'foo'}]});
  await f.tick();
  await f.tick();
  assert.equal(f.sent.length, 1);
  const [entry] = f.sent;
  assert.equal(entry.op, 'notification');
  assert.equal(entry.title, 'T'.repeat(64));
  assert.equal(entry.body, 'B'.repeat(220));
  assert.match(entry.eventKey, /^sw:[a-f0-9]{64}$/);
  assert.deepEqual(Object.keys(entry).sort(), ['body','eventKey','op','title']);
  assert.ok(!JSON.stringify(entry).includes('sensitive-reference'));
});

test('does not read notifications until already granted on matching page and registration', async () => {
  const f = fixture();
  f.page.Notification.permission = 'default';
  await f.watcher.setEnabled(true);
  assert.equal(f.reads(), 0);
  f.page.Notification.permission = 'granted';
  f.page.location.origin = 'https://other.example';
  await f.tick();
  assert.equal(f.reads(), 0);
  f.page.location.origin = 'https://claude.ai';
  f.registration.scope = 'https://other.example/';
  await f.tick();
  assert.equal(f.reads(), 0);
  f.page.navigator.serviceWorker.getRegistration = () => { throw new Error('unavailable'); };
  await f.tick();
  f.page.navigator = {};
  await f.tick();
  assert.deepEqual(f.sent, []);
});

test('two tabs derive the same key, retries offline and drops in-flight work on unpair', async () => {
  const a = fixture(), b = fixture();
  await Promise.all([a.watcher.setEnabled(true), b.watcher.setEnabled(true)]);
  const message = {title:'Claude', body:'Aufgabe abgeschlossen', tag:'chat-123', timestamp:42};
  a.registration.entries = [message];
  b.registration.entries = [message];
  a.result({ok:false});
  await Promise.all([a.tick(), b.tick()]);
  assert.equal(a.sent[0].eventKey, b.sent[0].eventKey);
  a.result({ok:true});
  await a.tick();
  await a.tick();
  assert.equal(a.sent.length, 2);
  let release;
  b.page.navigator.serviceWorker.getRegistration = () => new Promise(resolve => { release = resolve; });
  const inFlight = b.tick();
  b.watcher.setEnabled(false);
  b.registration.entries.push({...message, timestamp:43});
  release(b.registration);
  await inFlight;
  assert.equal(b.sent.length, 1);
});

test('the next pairing establishes a new baseline', async () => {
  const f = fixture();
  await f.watcher.setEnabled(true);
  f.watcher.setEnabled(false);
  f.registration.entries = [{title:'Bereits vorhanden', timestamp:1}];
  await f.watcher.setEnabled(true);
  await f.tick();
  assert.deepEqual(f.sent, []);
});
