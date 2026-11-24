'use strict';
process.env.TZ = 'Europe/Berlin';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {usage, usageRoute, chatRoute, activity, resetTime} = require('../BrowserExtension/signals');
const now = new Date('2026-11-24T09:00:00Z');
const parse = data => usage(data, now);
test('English page separates total weekly capacity from model and credit cards', () => {
  assert.deepEqual(parse('Current session\nResets in 2 hr 15 min\n35% used\nWeekly limits\nAll models\nResets Fri 3:00 PM\n72% used\nFable only\nResets Sun 8:00 AM\n95% used\nUsage credits\n100%'), [
    {kind: 'session', remainingPercent: 65, resetLabel: 'Resets in 2 hr 15 min', resetAt: '2026-11-24T11:15:00Z', resetApproximate: true},
    {kind: 'weekly', remainingPercent: 28, resetLabel: 'Resets Fri 3:00 PM', resetAt: '2026-11-27T14:00:00Z'}
  ]);
});
test('German cards support already remaining percentages, bare consumed percentages and absolute reset times', () => {
  assert.deepEqual(parse('Aktuelle Sitzung\n85 % verbleibend\nWird in 1 Std. 20 Min. zurückgesetzt\nWöchentliche Limits\nAlle Modelle\n17 %\nZurücksetzung am Fr. um 09:30 Uhr'), [
    {kind: 'session', remainingPercent: 85, resetLabel: 'Wird in 1 Std. 20 Min. zurückgesetzt', resetAt: '2026-11-24T10:20:00Z', resetApproximate: true},
    {kind: 'weekly', remainingPercent: 83, resetLabel: 'Zurücksetzung am Fr. um 09:30 Uhr', resetAt: '2026-11-27T08:30:00Z'}
  ]);
});
test('preserve unknown reset labels without guessing a date', () => {
  assert.deepEqual(parse('Weekly limits\nAll models\n90% used\nResets Dec 2 at noon EST'), [
    {kind: 'weekly', remainingPercent: 10, resetLabel: 'Resets Dec 2 at noon EST'}
  ]);
  assert.equal(resetTime('Resets in 2 h 12 fortnights', now, 'session'), null);
  assert.equal(resetTime('Resets 10:00 PM', now, 'weekly'), null);
});
test('missing, ambiguous, invalid and model-specific values are never guessed', () => {
  for (const raw of ['Current session\nNo data', 'Current session\n101% used', 'Weekly limits\nOpus only\n86% used', 'Weekly limits\n17% used\n26% used', 'Fable only\n9% used', 'Your message 11% used'])
    assert.deepEqual(parse(raw), []);
  assert.deepEqual(parse('Current session\n100% used\nExtra usage\n24% used'), [{kind:'session', remainingPercent:0}]);
  assert.deepEqual(parse('Current session\n0% used'), [{kind:'session', remainingPercent:100}]);
});
test('route scoping', () => {
  for (const path of ['/settings/usage','/de/settings/usage/']) assert.ok(usageRoute(path));
  for (const path of ['/chat/secret','/settings','/settings/usage/evil']) assert.equal(usageRoute(path), false);
  assert.ok(chatRoute('/chat/abc'));
  assert.ok(chatRoute('/new'));
  assert.equal(chatRoute('/settings/usage'), false);
});
function element(attributes, visible = true) {
  return {getClientRects: () => visible ? [{}] : [], getAttribute: name => attributes[name] || null};
}
test('activity requires a visible stop control and uses only explicit activity labels', () => {
  const doc = (buttons, statuses) => ({querySelectorAll: selector => selector.includes('button') ? buttons : statuses});
  const stop = element({'aria-label': 'Stop response'});
  assert.equal(activity(doc([element({'aria-label': 'Copy'})], [])), 'idle');
  assert.equal(activity(doc([element({'data-testid':'stop-button'}, false)], [])), 'idle');
  assert.equal(activity(doc([stop], [])), 'working');
  assert.equal(activity(doc([stop], [element({'aria-label':'Searching the web…'})])), 'searching');
  assert.equal(activity(doc([stop], [element({'aria-label':'Claude denkt nach …'})])), 'thinking');
  assert.equal(activity(doc([stop], [element({'aria-label':'Thinking yesterday'})])), 'working');
});
