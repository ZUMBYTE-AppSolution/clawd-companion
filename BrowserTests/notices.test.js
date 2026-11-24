'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {payload, readNotice, watch} = require('../BrowserExtension/notices');

test('keeps source wording, handles untitled notifications and classifies explicit severity', () => {
  assert.deepEqual(payload('Nutzungslimit', ' Dein Kontingent ist fast aufgebraucht. ', 'warning'),
    {type:'notice',title:'Nutzungslimit',message:'Dein Kontingent ist fast aufgebraucht.',kind:'warning'});
  assert.deepEqual(payload('Your previous message wasn’t sent', '', 'error'),
    {type:'notice',title:'Claude.ai',message:'Your previous message wasn’t sent',kind:'error'});
  assert.equal(payload('', 'Freigabe erforderlich.').kind, 'attention');
  assert.equal(payload('', 'Datei erfolgreich gespeichert.').kind, 'success');
  assert.equal(payload('Copied', '', 'success'), null);
  assert.equal(payload('', 'In die Zwischenablage kopiert.'), null);
  assert.equal(payload(' ', ' '), null);
});

test('bounded, single-line plain text preserves accents and emoji', () => {
  const notice = payload('A'.repeat(90), 'Ü 👩‍💻\u202e\n' + 'x'.repeat(250));
  assert.ok(notice.title.length <= 65 && notice.message.length <= 220);
  assert.ok(notice.message.startsWith('Ü 👩‍💻 '));
  assert.ok(!notice.message.includes('\u202e'));
  assert.ok(notice.message.endsWith('…'));
});

// Minimal DOM fixtures exercise observer gating and privacy before text traversal.
function fixture({text = '', hidden = false, blocked = false, status = true, children = []} = {}) {
  const view = {innerWidth:800,innerHeight:600,getComputedStyle:() => ({display:'block',visibility:'visible',opacity:'1'})};
  const root = {
    ownerDocument:{defaultView:view}, tagName:'DIV', nodeType:1, isConnected:true, parentElement:null,
    childNodes:[{nodeType:3,nodeValue:text}, ...children],
    getBoundingClientRect:() => hidden ? {width:0,height:0} : {width:270,height:44,left:20,top:6,right:290,bottom:50},
    checkVisibility:() => !hidden,
    matches:s => s.includes('[role="alert"]') ? status : false,
    querySelector:() => null, querySelectorAll:() => [], getAttribute:() => null,
    closest(s) {
      if (s.includes('[role="alert"]')) return status ? this : null;
      if (s.includes('[data-message-author-role]')) return blocked ? this : null;
      return null;
    }
  };
  return root;
}

test('avoids reading chat or form contents and omits controls from actual alerts', () => {
  for (const root of [fixture({blocked:true}), fixture({hidden:true})]) {
    Object.defineProperty(root, 'childNodes', {get:() => assert.fail('sensitive or hidden text was read')});
    assert.equal(readNotice(root), null);
  }
  const control = fixture({text:'Close', status:false});
  control.matches = s => s.includes('button');
  assert.equal(readNotice(fixture({text:'Verbindung wiederhergestellt.', children:[control]})).message, 'Verbindung wiederhergestellt.');
});

test('observes newly surfaced and changed notices only while paired, with de-duplication', async () => {
  let callback, observing = false;
  global.MutationObserver = class {
    constructor(cb) { callback = cb; }
    observe() { observing = true; }
    disconnect() { observing = false; }
  };
  const existing = fixture({text:'Old alert'}), page = fixture({status:false});
  const doc = {location:{pathname:'/chat/fixture'},documentElement:page,querySelectorAll:() => [existing]};
  const notices = [], enable = watch(doc, n => notices.push(n.message));
  assert.equal(observing,false);
  enable(true); assert.equal(observing,true);
  const notify = root => callback([{type:'childList', target:page, addedNodes:[root]}]);
  const fresh = fixture({text:'Ein neuer Hinweis.'});
  notify(existing); notify(fresh); notify(fixture({text:'Ein neuer Hinweis.'})); notify(fixture({text:'Secret.',blocked:true}));
  await new Promise(r => setTimeout(r,135));
  assert.deepEqual(notices,['Ein neuer Hinweis.']);
  fresh.childNodes[0].nodeValue = 'Der Hinweis wurde aktualisiert.'; notify(fresh);
  await new Promise(r => setTimeout(r,135));
  assert.equal(notices.at(-1),'Der Hinweis wurde aktualisiert.');
  doc.location.pathname = '/oauth/verify'; notify(fixture({text:'Sensitive code'}));
  enable(false); assert.equal(observing,false); notify(fixture({text:'Disconnected'}));
  await new Promise(r => setTimeout(r,135));
  assert.equal(notices.length,2);
  delete global.MutationObserver;
});
