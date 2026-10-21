import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import nextEnv from '@next/env';
import { generateKeyPairSync, randomBytes, randomUUID, sign } from 'node:crypto';
import { eq, inArray, like } from 'drizzle-orm';
import { assertTestDatabase } from './test-database';
import { database, closeDatabase } from '../../backend/src/server/db';
import { accounts, devices, challenges, limits } from '../../backend/src/server/schema';
import { registerAndroid, authenticateAndroid } from '../../backend/src/server/android-auth';
import { requestHash, validateIntegrity } from '../../backend/src/server/android-integrity';
import { authenticate, challenge } from '../../backend/src/server/auth';
import { api } from '../../backend/src/server/api';
nextEnv.loadEnvConfig(process.cwd(), true);
const ids: string[] = [], keys: string[] = [];
let allowed = false;
before(() => { assertTestDatabase(); allowed = true; });
after(async () => {
  if (!allowed) return;
  const db = database();
  if (keys.length) {
    await db.delete(challenges).where(inArray(challenges.keyId, keys));
    await db.delete(devices).where(inArray(devices.keyId, keys));
    for (const key of keys) await db.delete(limits).where(like(limits.bucket, `%${key}%`));
  }
  if (ids.length) await db.delete(accounts).where(inArray(accounts.id, ids));
  await closeDatabase();
});
// Only Google's network boundary is replaced. Signatures, nonce transactions, usage and platform
// isolation use the real database and implementation; no fixture path exists in HTTP production routes.
const checkIntegrity = async (token: string, payload: string) => {
  validateIntegrity(JSON.parse(token), payload, { packageName: 'com.philstarkovich.cavecals', certificates: ['a'.repeat(43)], minimumVersion: 1 });
};
function install(trialKey = randomBytes(32).toString('base64url')) {
  const keyId = `android:${randomUUID()}`; keys.push(keyId);
  const pair = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const publicKey = pair.publicKey.export({ type: 'spki', format: 'der' }).toString('base64');
  function request(path: string, body: object) {
    const raw = JSON.stringify(body), payload = `POST\n/api/v1/${path}\n${raw}`;
    const token = JSON.stringify({ requestDetails: { requestPackageName: 'com.philstarkovich.cavecals', requestHash: requestHash(payload), timestampMillis: String(Date.now()) }, appIntegrity: { appRecognitionVerdict: 'PLAY_RECOGNIZED', packageName: 'com.philstarkovich.cavecals', certificateSha256Digest: ['a'.repeat(43)], versionCode: '1' }, deviceIntegrity: { deviceRecognitionVerdict: ['MEETS_DEVICE_INTEGRITY'] }, accountDetails: { appLicensingVerdict: 'LICENSED' } });
    return { raw, req: new Request(`https://example.com/api/v1/${path}`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-app-key': keyId, 'x-android-signature': sign('sha256', Buffer.from(payload), pair.privateKey).toString('base64url'), 'x-android-integrity': token }, body: raw }) };
  }
  async function register() {
    const nonce = randomBytes(32).toString('base64url');
    await database().insert(challenges).values({ keyId, nonce, purpose: 'register', expiresAt: new Date(Date.now() + 120_000) });
    const input = { keyId, nonce, publicKey, trialKey }, { raw, req } = request('android/device/register', input);
    const reply = await registerAndroid(req, raw, input, checkIntegrity);
    if (!ids.includes(reply.accountId)) ids.push(reply.accountId);
    return { ...reply, req, raw, input };
  }
  return { keyId, request, register, trialKey };
}
test('Play installation registers once, verifies exact request bytes and refuses nonce replay', async () => {
  const device = install(), registration = await device.register();
  await assert.rejects(registerAndroid(registration.req, registration.raw, registration.input, checkIntegrity));
  assert.equal((await device.register()).accountId, registration.accountId);
  const { nonce } = await challenge(new Request('https://example.com'), device.keyId, 'request');
  const { req, raw } = device.request('account/status', { nonce });
  await assert.rejects(authenticateAndroid(req, raw + ' ', nonce, checkIntegrity));
  const identity = await authenticateAndroid(req, raw, nonce, checkIntegrity);
  assert.equal(identity.accountId, registration.accountId);
  await assert.rejects(authenticateAndroid(req, raw, nonce, checkIntegrity));
});
test('concurrent verified requests consume one nonce only once', async () => {
  const device = install(); await device.register();
  const { nonce } = await challenge(new Request('https://example.com'), device.keyId, 'request');
  const { req, raw } = device.request('account/status', { nonce });
  const results = await Promise.allSettled([authenticateAndroid(req, raw, nonce, checkIntegrity), authenticateAndroid(req, raw, nonce, checkIntegrity)]);
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
});
test('reinstall retains usage high-water marks but never merges the diary or account', async () => {
  const first = install(), original = await first.register();
  await database().update(accounts).set({ scansUsed: 8, regularLogCount: 97 }).where(eq(accounts.id, original.accountId));
  const second = install(first.trialKey), replacement = await second.register();
  assert.notEqual(replacement.accountId, original.accountId);
  const [account] = await database().select().from(accounts).where(eq(accounts.id, replacement.accountId));
  assert.deepEqual([account.environment, account.scansUsed, account.regularLogCount], ['GooglePlay', 8, 97]);
});
test('Android key cannot authenticate an account marked as an Apple purchase', async () => {
  const device = install(), registration = await device.register();
  await database().update(accounts).set({ environment: 'Production' }).where(eq(accounts.id, registration.accountId));
  const { nonce } = await challenge(new Request('https://example.com'), device.keyId, 'request');
  const { req, raw } = device.request('account/status', { nonce });
  await assert.rejects(authenticateAndroid(req, raw, nonce, checkIntegrity));
});
test('public API never treats an Android signature or test token as an Apple assertion', async () => {
  const device = install(), { req, raw } = device.request('account/status', { nonce: 'missing' });
  await assert.rejects(authenticate(req, raw, 'missing'));
  assert.equal((await api(req, 'account/status')).status, 401);
});
