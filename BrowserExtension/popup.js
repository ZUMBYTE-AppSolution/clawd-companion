const webExt = globalThis.browser || globalThis.chrome;
const $ = id => document.getElementById(id);
const {language, direction, strings} = ClawdPopupLocale.select([
  webExt.i18n?.getUILanguage?.(), ...(navigator.languages || []), navigator.language
]);
document.documentElement.lang = language;
document.documentElement.dir = direction;
document.title = strings.title;
for (const element of document.querySelectorAll('[data-message]')) {
  element.textContent = strings[element.dataset.message];
}
async function request(message) {
  try { return await webExt.runtime.sendMessage(message); }
  catch { return {ok: false, reason: 'offline'}; }
}
function render(result) {
  const reason = ['token', 'offline', 'rejected', 'unpaired'].includes(result?.reason) ? result.reason : 'offline';
  $('status').textContent = result?.ok ? strings.connected : strings[reason];
  $('pair').hidden = !!result?.ok;
  $('connected').hidden = !result?.ok;
  webExt.storage.local.get('token').then(({token}) => { $('forget').hidden = !token; });
}
$('pair').addEventListener('submit', async event => {
  event.preventDefault();
  const button = $('pair').querySelector('button');
  button.disabled = true;
  const result = await request({op: 'pair', code: $('code').value});
  if (result?.ok) $('code').value = '';
  render(result);
  button.disabled = false;
});
$('forget').addEventListener('click', async () => {
  await request({op: 'forget'});
  $('code').value = '';
  render({ok: false, reason: 'unpaired'});
});
$('usage').addEventListener('click', () => webExt.tabs.create({url: 'https://claude.ai/settings/usage'}));
request({op: 'status'}).then(render);
