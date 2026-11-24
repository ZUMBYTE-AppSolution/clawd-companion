const {test} = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const vm = require('node:vm');
const {webcrypto} = require('node:crypto');

function area() {
  const data = {};
  return {
    get: async keys => Object.fromEntries([keys].flat().filter(k => k in data).map(k => [k,data[k]])),
    set: async values => Object.assign(data,values),
    remove: async keys => keys.forEach(k => delete data[k]),
    setAccessLevel: async () => {}
  };
}
function harness(safari = false) {
  let listen;
  let removed, updated, offline = false, clock = Date.now();
  const sent = [];
  const id = 'abcdefghijklmnopabcdefghijklmnop';
  const base = (safari ? 'safari-web-extension://' : 'chrome-extension://') + id + '/';
  const popup = {url: base + 'popup.html',id};
  const chat = n => ({url:'https://claude.ai/chat/abc',frameId:0,tab:{id:n},id});
  const webExt = {
    runtime: {
      id, getURL: path => base + path, onMessage:{addListener:f => { listen=f; }},
      sendNativeMessage: async (app, {token,event}) => {
        assert.ok(safari);
        assert.equal(app, 'de.zumbyte.clawdcompanion');
        assert.equal(token, 'test-test-test');
        if (offline) throw Error('offline');
        sent.push(structuredClone(event));
        return {ok:true};
      }
    },
    tabs: {query:async()=>[],onRemoved:{addListener:fn=>{removed=fn;}},onUpdated:{addListener:fn=>{updated=fn;}}},
    storage: {local:area(), session:safari ? null : area()}
  };
  async function fetch(url, options) {
    assert.equal(safari,false);
    assert.equal(url,'http://127.0.0.1:49217/v1/events');
    assert.equal(options.headers.Authorization,'Bearer test-test-test');
    if (offline) throw Error('offline');
    sent.push(JSON.parse(options.body));
    return {ok:true,status:200};
  }
  const globals = {browser:safari?webExt:undefined,chrome:safari?undefined:webExt,fetch,crypto:webcrypto,TextEncoder,URL,AbortController,
    Date:class extends Date { static now() { return clock; } },setTimeout,clearTimeout};
  vm.runInNewContext(readFileSync(require.resolve('../BrowserExtension/background.js'),'utf8'),globals);
  const send = (message,sender) => new Promise(resolve => {
    if (!listen(message,sender,r=>resolve(r))) resolve(undefined);
  });
  return {chat,popup,sent,send,remove:id=>removed(id),navigate:id=>updated(id,{status:'loading'}),
    offline:value=>{offline=value;}, advance:ms=>{clock+=ms;}};
}
for (const safari of [false,true]) {
  test((safari?'Safari':'Chromium')+' aggregates separate permission waits, renews, clears on last dismiss/navigation/close', async () => {
    const {chat,popup,sent,send,navigate,remove} = harness(safari);
    const request = (id, waiting) => send({op:'approval',waiting,toolName:'never store'},chat(id));
    assert.equal((await request(1,true)).ok,false);
    await send({op:'pair',code:'test-test-test'},popup);
    await request(1,true);
    await request(2,true);
    await request(1,false);
    await request(2,true);
    await request(2,false);
    await request(3,true);
    navigate(3);
    await request(4,true);
    remove(4);
    await send({op:'enabled'},chat(1)); // drain the worker queue
    const approvals = sent.filter(e => e.type === 'approval');
    assert.deepEqual(approvals.map(e=>e.waiting),[true,true,true,false,true,false,true,false]);
    assert.match(approvals[0].sourceID,/^[a-f\d]{8}-[a-f\d]{4}-4[a-f\d]{3}-[89ab][a-f\d]{3}-[a-f\d]{12}$/);
    assert.equal(new Set(approvals.map(e=>e.sourceID)).size,1);
    assert.deepEqual(Object.keys(approvals[0]).sort(),['sourceID','type','waiting']);
  });
}
test('permissions drop stale tabs, retry a failed clear, and cannot start on settings or in an iframe',async () => {
  const {chat,popup,sent,send,offline,advance} = harness();
  await send({op:'pair',code:'test-test-test'},popup);
  for (const sender of [{...chat(1),frameId:1},{...chat(1),url:'https://claude.ai/settings/usage'}])
    assert.equal((await send({op:'approval',waiting:true}, sender)).ok,false);
  await send({op:'approval',waiting:true},chat(1));
  advance(130000);
  offline(true);
  assert.equal((await send({op:'approval',waiting:false},chat(2))).ok,false);
  offline(false);
  assert.equal((await send({op:'approval',waiting:false},chat(2))).ok,true);
  assert.deepEqual(sent.filter(e=>e.type==='approval').map(e=>e.waiting),[true,false]);
  await send({op:'approval',waiting:true},chat(3));
  await send({op:'forget'},popup);
  assert.equal(sent.at(-1).waiting,false);
});
for (const safari of [false,true]) {
  test((safari?'Safari native relay':'Chromium relay')+' authenticates, excludes unpaired messages and only finishes after all busy tabs stop', async () => {
    const {chat,popup,sent,send}=harness(safari);
    assert.equal((await send({op:'signal', state:'working'},chat(1))).ok,false);
    assert.equal((await send({op:'pair', code:'test-test-test'},popup)).ok,true);
    await send({op:'signal', state:'working'},chat(1));
    await send({op:'signal', state:'thinking'},chat(2));
    await send({op:'signal', state:'idle', finish:true},chat(1));
    await send({op:'signal', state:'idle', finish:true},chat(2));
    assert.deepEqual(sent.map(e=>e.state),['connected','working','thinking','thinking','done']);
  });
}
test('notices require the top Claude frame and are coalesced across tabs',async () => {
  const {chat,popup,send,sent} = harness();
  await send({op:'pair', code:'test-test-test'},popup);
  const note = {type:'notice',title:'Claude.ai',message:'Limit erreicht',kind:'warning'};
  for (const frame of [{...chat(2),frameId:1},{...chat(2),url:'https://claude.ai.example/'}])
    assert.equal((await send(note,frame))?.ok,false);
  await send(note,chat(1));
  await send(note,chat(2));
  await send({op:'notification',title:'Claude.ai',body:'Limit erreicht',eventKey:'same'},chat(2));
  await send({op:'notification', title:'Update bereit', body:'', eventKey:'title-only'},chat(2));
  assert.deepEqual(sent.filter(e=>e.type==='notice'), [
    note, {type:'notice',title:'Claude.ai',message:'Update bereit',kind:'info'}
  ]);
});
test('quota snapshots are accepted only from the usage page and retain no extra fields', async () => {
  const {chat,popup,send,sent}=harness();
  await send({op:'pair', code:'test-test-test'},popup);
  const message = {op:'usage',observedAt:'2026-11-24T12:00:00Z',windows:[{kind:'weekly',remainingPercent:80,unexpected:'private'}]};
  assert.equal((await send(message,chat(1)))?.ok,false);
  await send(message,{...chat(1),url:'https://claude.ai/settings/usage'});
  assert.deepEqual(sent.at(-1),{type:'usage',observedAt:message.observedAt,windows:[{kind:'weekly',remainingPercent:80}]});
});
test('relays explicit prop actions and approximate resets from an international usage route',async () => {
  const {chat,popup,sent,send} = harness();
  await send({op:'pair',code:'test-test-test'},popup);
  for (const state of ['planning','searching','reading','executing','drawing']) {
    assert.equal((await send({op:'signal',state},chat(1))).ok,true);
    assert.equal(sent.at(-1).state,state);
  }
  await send({op:'usage',observedAt:'2026-11-24T12:00:00Z',windows:[
    {kind:'session',remainingPercent:25,resetAt:'2026-11-24T14:00:00Z',resetApproximate:true,resetLabel:'将在 2 小时后重置'}
  ]},{...chat(1),url:'https://claude.ai/zh-Hans/settings/usage'});
  assert.equal(sent.at(-1).windows[0].resetApproximate,true);
});
