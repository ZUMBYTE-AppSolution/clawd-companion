'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const {readFileSync} = require('node:fs');
const {awaitingApproval} = require('../BrowserExtension/signals');

// A small accessibility-tree fixture. Selectors are kept separate for headings,
// decision controls and dialog containers so chat text cannot stand in for them.
function element(text = '', attrs = {}) {
  return {
    getAttribute: name => attrs[name] ?? null,
    getClientRects: () => attrs.hidden ? [] : [{}],
    closest: selector => attrs.inChatText && selector.includes('.prose') ? {} : null,
    matches: () => false, textContent:text, innerText:text,
    disabled:!!attrs.disabled, children:[], parentElement:null
  };
}
function page({heading, plainHeading=false, controls=[], attrs={}, inline=false}) {
  const title = element(heading);
  if (plainHeading) title.firstChild = {nodeType:3,nodeValue:heading};
  const root = element('',attrs);
  root.querySelectorAll = selector => {
    if (selector.startsWith('button')) return controls;
    if (selector.startsWith('p,')) return plainHeading ? [title] : [];
    if (selector.startsWith('h1')) return plainHeading ? [] : [title];
    return [];
  };
  for (const button of controls) button.parentElement = root;
  return {querySelectorAll: sel => sel.startsWith('button') ? controls : inline ? [] : [root]};
}
test('visible English and German tool decisions are observable, including inline connector choices', () => {
  assert.ok(awaitingApproval(page({heading:'Claude wants to use Read calendar from Calendar',
    controls:[element('Decline'),element('Allow once (Ctrl ↵)'),element('Always allow')]})));
  assert.ok(awaitingApproval(page({heading:'Claude möchte das Tool Kalenderabfrage von Kalender verwenden',
    controls:[element('',{'aria-label':'Einmal zulassen'}),element('Ablehnen')], inline:true})));
  assert.ok(awaitingApproval(page({heading:'Claude wants to use Create task from Asana', plainHeading:true,
    controls:[element('Deny'),element('Allow once')], inline:true})));
  assert.ok(awaitingApproval(page({heading:'',attrs:{'data-testid':'tool-permission-dialog'},
    controls:[element('Abbrechen'),element('Genehmigen')]})));
});

test('content script holds a remounted card, clears on dismissal or navigation, never posts a false completion', async () => {
  let now = 60000, nextID = 0, observe;
  const document = {state:'idle', pending:false, documentElement:{}, addEventListener() {}};
  const location = {pathname:'/chat/current'};
  const timers = new Map(), posted = [];
  const context = {
    document, location, window:{addEventListener() {}}, Date:class extends Date { static now() { return now; } },
    MutationObserver:class { constructor(callback) { observe=callback; } observe() {} },
    setInterval(){}, setTimeout(fn,delay) { const id = ++nextID; timers.set(id,{fn,when:now+delay}); return id; },
    ClawdWebPush:{create:()=>({setEnabled(){}})},
    ClawdSignals:{chatRoute:p=>p.startsWith('/chat/'), usageRoute:()=>false,
      activity:d=>d.state, awaitingApproval:d=>d.pending},
    chrome:{runtime:{onMessage:{addListener(){}},sendMessage:async message=>{
      if (message.op==='enabled') return {enabled:true};
      posted.push(structuredClone(message));
      return {ok:true};
    }}}
  };
  const settle = () => new Promise(resolve=>setImmediate(resolve));
  async function advance(ms) {
    const end = now + ms;
    await settle();
    for (;;) {
      const due = [...timers].sort((a,b)=>a[1].when-b[1].when)[0];
      if (!due || due[1].when>end) break;
      now=due[1].when; timers.delete(due[0]); due[1].fn(); await settle();
    }
    now=end;
  }
  async function update(fields, ms=190) {
    Object.assign(document,fields); observe(); await advance(ms);
  }
  vm.runInNewContext(readFileSync(require.resolve('../BrowserExtension/observer.js'),'utf8'),context);
  await advance(190);
  await update({state:'working'},1200);
  await update({state:'idle',pending:true});
  await update({pending:false});
  await update({pending:true},800);
  assert.deepEqual(posted.filter(m=>m.op==='approval').map(m=>m.waiting),[false,true]);
  await update({pending:false},1000);
  await update({pending:true});
  location.pathname='/settings/profile';
  await update({});
  assert.deepEqual(posted.filter(m=>m.op==='approval').map(m=>m.waiting),[false,true,false,true,false]);
  assert.ok(posted.filter(m=>m.op==='signal').every(m=>m.finish===false));
});
test('a generic confirmation, account permission, disabled history, or the words in a chat never signal approval', () => {
  for (const heading of ['Use cookies?', 'Claude wants to use your microphone', 'Allow Claude to access your account',
    'Connect GitHub', 'Dein Konto freigeben', 'Confirm deletion', 'Tool configuration']) {
    assert.equal(awaitingApproval(page({heading,controls:[element('Allow once'),element('Decline')]})),false);
  }
  const heading = 'Claude wants to use Create task from Asana';
  for (const controls of [[element('Send'),element('Skip')],[element('Allow once'),element('Deny',{hidden:true})],
    [element('Allow once',{disabled:true}),element('Deny')],[element('Allow once',{'aria-disabled':'true'}),element('Decline')],
    [element('Allow once')]]) {
    assert.equal(awaitingApproval(page({heading,controls})),false);
  }
  for (const attrs of [{hidden:true},{inChatText:true},{'aria-hidden':'true'}]) {
    assert.equal(awaitingApproval(page({heading,attrs,controls:[element('Allow once'),element('Decline')]})),false);
  }
});
