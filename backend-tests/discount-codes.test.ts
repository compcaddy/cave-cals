import test from 'node:test';
import assert from 'node:assert/strict';
import { statsInput } from '../backend/src/server/stats';
import {
  appStoreLink, campaignToken, CODE_PATTERN, dealLine, discountCheckInput, isBot, linkCode, normalizeCode, prettyCode, RESERVED_CODES,
} from '../backend/src/server/discount-codes';

test('typed codes ignore capitals, spaces, and punctuation', () => {
  assert.equal(normalizeCode('sarah'), 'SARAH');
  assert.equal(normalizeCode(' Sarah-30 '), 'SARAH30');
  assert.equal(normalizeCode('ｓａｒａｈ'), 'SARAH');
  assert.ok(CODE_PATTERN.test('SARAH30'));
  assert.ok(!CODE_PATTERN.test('S'));
  assert.ok(!CODE_PATTERN.test('A'.repeat(31)));
});

test('page addresses are codes in any capitalization, and nothing else', () => {
  assert.equal(linkCode('Sarah'), 'SARAH');
  assert.equal(linkCode('sarah'), 'SARAH');
  assert.equal(linkCode('SARAH'), 'SARAH');
  assert.equal(linkCode('favicon.ico'), null);
  assert.equal(linkCode('sarah-j'), null);
  assert.equal(linkCode('x'), null);
});

test('the site’s own pages can’t be codes', () => {
  for (const page of ['admin', 'privacy', 'terms', 'test', 'api']) assert.ok(RESERVED_CODES.has(normalizeCode(page)), page);
});

test('campaign tokens default to the code in lower case and stay link-safe', () => {
  assert.equal(campaignToken('', 'SARAH'), 'sarah');
  assert.equal(campaignToken(undefined, 'SARAH'), 'sarah');
  assert.equal(campaignToken(' Sarah 2026/10 ', 'SARAH'), 'sarah202610');
  assert.equal(campaignToken('sarah_2026-10', 'SARAH'), 'sarah_2026-10');
  assert.equal(campaignToken('x'.repeat(60), 'SARAH').length, 40);
});

test('the App Store link carries the campaign token only with a provider token', () => {
  const saved = { provider: process.env.APP_STORE_PROVIDER_TOKEN, url: process.env.APP_STORE_URL };
  try {
    delete process.env.APP_STORE_URL;
    delete process.env.APP_STORE_PROVIDER_TOKEN;
    assert.equal(appStoreLink('sarah'), 'https://apps.apple.com/us/app/cave-cals-ai-calorie-tracker/id6809208501');
    process.env.APP_STORE_PROVIDER_TOKEN = 'not-a-number';
    assert.ok(!appStoreLink('sarah').includes('ct='));
    process.env.APP_STORE_PROVIDER_TOKEN = '123456';
    assert.equal(appStoreLink('sarah'), 'https://apps.apple.com/app/apple-store/id6809208501?pt=123456&ct=sarah&mt=8');
    assert.ok(!appStoreLink(null).includes('ct='));
  } finally {
    if (saved.provider === undefined) delete process.env.APP_STORE_PROVIDER_TOKEN; else process.env.APP_STORE_PROVIDER_TOKEN = saved.provider;
    if (saved.url === undefined) delete process.env.APP_STORE_URL; else process.env.APP_STORE_URL = saved.url;
  }
});

test('link previews and crawlers aren’t counted as visits; in-app browsers are', () => {
  for (const agent of [
    null, 'facebookexternalhit/1.1 Facebot Twitterbot/1.0', 'Mozilla/5.0 (compatible; Googlebot/2.1)', 'Slackbot-LinkExpanding 1.0',
    'TelegramBot (like TwitterBot)', 'WhatsApp/2.23.20.0', 'Mozilla/5.0 (compatible; Bytespider; spider-feedback@bytedance.com)', 'curl/8.4.0',
  ]) assert.ok(isBot(agent), String(agent));
  for (const agent of [
    'Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1',
    'Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Instagram 400.0.0.0.0',
    'Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 musical_ly_40.0.0 BytedanceWebview/d8a21c6',
  ]) assert.ok(!isBot(agent), agent);
});

test('links read the way the creator spells their name', () => {
  assert.equal(prettyCode('SARAH', 'Sarah'), 'Sarah');
  assert.equal(prettyCode('SARAHJ', 'Sarah J'), 'SarahJ');
  assert.equal(prettyCode('ZOG30', 'Zog the trainer'), 'Zog30');
});

test('code checks are small and the deal reads plainly', () => {
  assert.deepEqual(discountCheckInput.parse({ code: 'sarah', count: false }), { code: 'sarah', count: false });
  assert.throws(() => discountCheckInput.parse({ code: '' }));
  assert.throws(() => discountCheckInput.parse({ code: 'x'.repeat(61) }));
  assert.equal(dealLine('discount'), 'Half price on Cave Cals+');
  assert.equal(dealLine('somethingElse'), 'A Cave Cals+ deal');
});

test('the app’s new usage events fit the existing stats contract', () => {
  const report = {
    install: '9f1f6a1e-4a8e-4d9e-8f3e-1f2a3b4c5d6e', batch: '0d1e2f3a-4b5c-4d6e-8f70-8192a3b4c5d6',
    app: { version: '1.0.5', build: '1', os: '26.0', device: 'iPhone', environment: 'appstore' },
    startedAt: '2026-10-06T15:00:00Z', startedDay: '2026-10-06', existingUser: false, traits: {}, days: [], errors: [],
    events: [
      { id: '5b0d1c3e-1111-4222-8333-944455566677', name: 'onboarding.source', at: '2026-10-06T16:00:00Z', props: { source: 'other', other: 'gym flyer' } },
      { id: '5b0d1c3e-1111-4222-8333-944455566678', name: 'discount.code', at: '2026-10-06T16:00:01Z', props: { result: 'applied', code: 'SARAH', from: 'setup' } },
      { id: '5b0d1c3e-1111-4222-8333-944455566679', name: 'paywall.result', at: '2026-10-06T16:01:00Z', props: { trigger: 'onboarding', result: 'purchased', product: 'x', code: 'SARAH' } },
    ],
  };
  assert.equal(statsInput.parse(report).events.length, 3);
});
