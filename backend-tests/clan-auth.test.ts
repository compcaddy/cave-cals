import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash, generateKeyPairSync, randomBytes, sign } from 'node:crypto';
import { googleAudiences, openToken, sealToken, verifyIdentityToken } from '../backend/src/server/clan-auth';
import { cleanClanName, cleanDisplayName, containsBlockedWord } from '../backend/src/server/clan-names';

const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const jwk = { ...publicKey.export({ format: 'jwk' }), kid: 'test-key', alg: 'RS256' };
const keysURL = 'https://keys.example.com/test';
const realFetch = globalThis.fetch;
function token(claims: object, kid = 'test-key') {
  const encode = (value: object) => Buffer.from(JSON.stringify(value)).toString('base64url');
  const unsigned = `${encode({ alg: 'RS256', kid })}.${encode(claims)}`;
  return `${unsigned}.${sign('RSA-SHA256', Buffer.from(unsigned), privateKey).toString('base64url')}`;
}
const nonce = 'a-random-nonce-from-the-app';
const good = { iss: 'https://appleid.apple.com', aud: 'com.philstarkovich.cavecals', sub: 'apple-123', exp: Math.floor(Date.now() / 1000) + 600, nonce: createHash('sha256').update(nonce).digest('hex') };
const options = { keysURL, issuers: ['https://appleid.apple.com'], audiences: ['com.philstarkovich.cavecals'], nonce };

test('Android Google audience is additive and leaves every existing iOS audience accepted', () => {
  const original = { GOOGLE_CLIENT_IDS: process.env.GOOGLE_CLIENT_IDS, GOOGLE_ANDROID_CLIENT_ID: process.env.GOOGLE_ANDROID_CLIENT_ID };
  try {
    process.env.GOOGLE_CLIENT_IDS = 'ios-one, ios-two, ';
    process.env.GOOGLE_ANDROID_CLIENT_ID = 'android-web';
    assert.deepEqual(googleAudiences(), ['ios-one', 'ios-two', 'android-web']);
    process.env.GOOGLE_ANDROID_CLIENT_ID = '';
    assert.deepEqual(googleAudiences(), ['ios-one', 'ios-two']);
    process.env.GOOGLE_ANDROID_CLIENT_ID = ' ios-one ';
    assert.deepEqual(googleAudiences(), ['ios-one', 'ios-two']);
    delete process.env.GOOGLE_CLIENT_IDS;
    delete process.env.GOOGLE_ANDROID_CLIENT_ID;
    assert.deepEqual(googleAudiences(), []);
  } finally {
    for (const [key, value] of Object.entries(original)) {
      if (value === undefined) delete process.env[key]; else process.env[key] = value;
    }
  }
});

test('identity tokens are checked for signature, issuer, audience, expiry, and nonce', async () => {
  globalThis.fetch = (async () => new Response(JSON.stringify({ keys: [jwk] }))) as typeof fetch;
  try {
    assert.equal((await verifyIdentityToken(token(good), options)).sub, 'apple-123');
    const rejects = (t: string, o = options) => assert.rejects(verifyIdentityToken(t, o), (e: any) => e.code === 'invalid_sign_in');
    await rejects(token({ ...good, aud: 'com.someone.else' }));
    await rejects(token({ ...good, iss: 'https://evil.example.com' }));
    await rejects(token({ ...good, exp: Math.floor(Date.now() / 1000) - 3600 }));
    await rejects(token(good), { ...options, nonce: 'a-different-nonce-entirely' });
    await rejects(token(good, 'unknown-key'));
    const [h, b] = token(good).split('.');
    await rejects(`${h}.${b}.${randomBytes(256).toString('base64url')}`);
  } finally { globalThis.fetch = realFetch; }
});

test('stored Apple tokens are sealed and only open with the same key', () => {
  const key = randomBytes(32);
  const sealed = sealToken('refresh-token-value', key)!;
  assert.ok(!sealed.includes('refresh-token-value'));
  assert.equal(openToken(sealed, key), 'refresh-token-value');
  assert.equal(openToken(sealed, randomBytes(32)), null);
  assert.equal(sealToken('x', null), null);
});

test('names are tidied and slurs are refused, without catching ordinary names', () => {
  assert.equal(cleanDisplayName('  Ana   Maria '), 'Ana Maria');
  assert.equal(cleanClanName('The\u200bCavemen'), 'TheCavemen');
  for (const bad of ['b!tch', 'F U C K', 'sh1t heads', 'dick']) assert.ok(containsBlockedWord(bad), bad);
  for (const fine of ['Dickens', 'Cumberland Crew', 'Nazir', 'Hancock', 'Grape Escape', 'Spicy Squad']) assert.ok(!containsBlockedWord(fine), fine);
  assert.throws(() => cleanDisplayName(''), (e: any) => e.code === 'name_too_short');
  assert.throws(() => cleanDisplayName('x'.repeat(31)), (e: any) => e.code === 'name_too_long');
});
