const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const resource = name => path.join(__dirname, '../BrowserExtension', name);
const localeScript = fs.readFileSync(resource('popup-locale.js'), 'utf8');
const popupScript = fs.readFileSync(resource('popup.js'), 'utf8');
const markup = fs.readFileSync(resource('popup.html'), 'utf8');
const staticKeys = Array.from(markup.matchAll(/data-message="(\w+)"/g), match => match[1]);
const states = ['checking', 'connected', 'token', 'offline', 'rejected', 'unpaired'];
const supported = [
  ['de-CH','de','de','Mit dem Mac verbinden'], ['en-GB','en','en','Connect to Mac'],
  ['zh-Hans-SG','zh-Hans','zh_CN','连接到 Mac'], ['hi-IN','hi','hi','Mac से कनेक्ट करें'],
  ['es-419','es','es','Conectar al Mac'], ['ar-EG','ar','ar','الاتصال بجهاز Mac'],
  ['fr-CA','fr','fr','Connecter au Mac'], ['bn-BD','bn','bn','Mac-এ সংযোগ করুন'],
  ['pt-BR','pt','pt_BR','Conectar ao Mac'], ['pt_PT','pt-PT','pt_PT','Conectar ao Mac'],
  ['id-ID','id','id','Hubungkan ke Mac'], ['ur-PK','ur','ur','Mac سے جڑیں']
];

function settings() {
  const context = vm.createContext({Intl});
  vm.runInContext(localeScript, context);
  return context.ClawdPopupLocale;
}

test('all popup languages resolve, cover each visible message and match browser metadata', () => {
  const i18n = settings();
  for (const [tag, key, catalog, button] of supported) {
    const {language, direction, strings} = i18n.select([tag]);
    assert.equal(language, key);
    assert.equal(direction, key === 'ur' || key === 'ar' ? 'rtl' : 'ltr');
    assert.equal(strings.connect, button);
    for (const message of [...staticKeys,...states]) assert.ok(strings[message]?.trim(), tag+' '+message);
    const manifestStrings = JSON.parse(fs.readFileSync(resource('_locales/'+catalog+'/messages.json')));
    assert.equal(strings.title, manifestStrings.title.message);
    assert.ok(manifestStrings.extensionName.message.includes('Claw’d'));
    assert.ok(manifestStrings.description.message.trim());
  }
  assert.equal(i18n.select([' ??? ', 'uk', 'de-DE']).language, 'de');
  assert.equal(i18n.select(['ja-JP']).language, 'en');
  assert.equal(i18n.select(['en-US','de-DE']).language, 'en');
  for (const name of ['manifest.json','../SafariExtension/manifest.json']) {
    const manifest = JSON.parse(fs.readFileSync(resource(name)));
    assert.equal(manifest.version, '1.1.0');
    assert.equal(manifest.default_locale, 'en');
    assert.equal(manifest.name, '__MSG_extensionName__');
    assert.equal(manifest.action.default_title, '__MSG_title__');
  }
});

test('popup displays the browser UI language, keeps codes LTR and localizes pairing responses', async () => {
  const elements = new Map();
  class Element {
    constructor(key) { this.dataset = {message:key}; this.listeners = {}; this.value = ''; }
    addEventListener(type, fn) { this.listeners[type] = fn; }
    querySelector() { return submit; }
  }
  const get = id => {
    if (!elements.has(id)) elements.set(id,new Element(id));
    return elements.get(id);
  };
  const submit = new Element('connect');
  const nodes = staticKeys.map(key => key === 'checking' ? get('status') : new Element(key));
  const document = {documentElement:{}, getElementById:get, querySelectorAll:() => nodes};
  const web = {i18n:{getUILanguage:()=>'ur-PK'}, storage:{local:{get:async()=>({token:''})}},
    tabs:{create(){}}, runtime:{sendMessage:async request => request.op === 'status'
      ? {ok:false,reason:'unpaired'} : {ok:false,reason:'token'}}};
  const context = vm.createContext({browser:web,document,navigator:{languages:['en-US']},Intl});
  vm.runInContext(localeScript,context);
  vm.runInContext(popupScript,context);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(document.documentElement.dir,'rtl');
  assert.equal(document.documentElement.lang,'ur');
  assert.match(markup,/<input[^>]+dir="ltr"/);
  assert.equal(get('status').textContent, context.ClawdPopupLocale.select(['ur']).strings.unpaired);
  await get('pair').listeners.submit({preventDefault(){}});
  assert.equal(get('status').textContent, context.ClawdPopupLocale.select(['ur']).strings.token);
  assert.ok(nodes.every(el => el.textContent));
});
