import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, sign } from 'node:crypto';
import { androidHeaders, androidPublicKey, requestHash, validateIntegrity, verifyAndroidSignature } from '../backend/src/server/android-integrity';
import { cachedPlayEntitlement, verifiedPlayExpiry, PLAY_ACTIVE_TTL, PLAY_INACTIVE_TTL } from '../backend/src/server/android-purchases';
import { deadFirebaseToken, firebaseMessage, pushRegistration } from '../backend/src/server/android-push';
const now = Date.parse('2026-10-17T12:00:00Z');
const payload = 'POST\n/api/v1/account/status\n{"nonce":"one-use"}';
const policy = { packageName: 'com.philstarkovich.cavecals', certificates: ['a'.repeat(43)], minimumVersion: 1 };
function verdict() { return {
  requestDetails: { requestPackageName: policy.packageName, requestHash: requestHash(payload), timestampMillis: String(now) },
  appIntegrity: { appRecognitionVerdict: 'PLAY_RECOGNIZED', packageName: policy.packageName, certificateSha256Digest: policy.certificates, versionCode: '1' },
  deviceIntegrity: { deviceRecognitionVerdict: ['MEETS_DEVICE_INTEGRITY'] }, accountDetails: { appLicensingVerdict: 'LICENSED' },
}; }
test('Play verdict binds the precise request, package, certificate, license, device and version', () => {
  validateIntegrity(verdict(), payload, policy, now);
  const mutations = [
    (v: ReturnType<typeof verdict>) => { v.requestDetails.requestHash = requestHash(payload + ' '); },
    (v: ReturnType<typeof verdict>) => { v.requestDetails.requestPackageName += '.dev'; },
    (v: ReturnType<typeof verdict>) => { v.appIntegrity.packageName += '.dev'; },
    (v: ReturnType<typeof verdict>) => { v.appIntegrity.certificateSha256Digest = ['b'.repeat(43)]; },
    (v: ReturnType<typeof verdict>) => { v.appIntegrity.appRecognitionVerdict = 'UNRECOGNIZED_VERSION'; },
    (v: ReturnType<typeof verdict>) => { v.deviceIntegrity.deviceRecognitionVerdict = ['MEETS_BASIC_INTEGRITY']; },
    (v: ReturnType<typeof verdict>) => { v.accountDetails.appLicensingVerdict = 'UNLICENSED'; },
    (v: ReturnType<typeof verdict>) => { v.appIntegrity.versionCode = '0'; },
    (v: ReturnType<typeof verdict>) => { v.requestDetails.timestampMillis = String(now - 120_001); },
    (v: ReturnType<typeof verdict>) => { v.requestDetails.timestampMillis = String(now + 30_001); },
  ];
  for (const mutate of mutations) { const v = verdict(); mutate(v); assert.throws(() => validateIntegrity(v, payload, policy, now)); }
  assert.throws(() => validateIntegrity({}, payload, policy, now));
});
test('a device signature cannot be replayed over different bytes or a different device key', () => {
  const pair = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const publicKey = androidPublicKey(pair.publicKey.export({ format: 'der', type: 'spki' }).toString('base64'));
  const signature = sign('sha256', Buffer.from(payload), pair.privateKey).toString('base64url');
  verifyAndroidSignature(publicKey, signature, payload);
  assert.throws(() => verifyAndroidSignature(publicKey, signature, payload + ' '));
  const other = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  assert.throws(() => verifyAndroidSignature(other.publicKey.export({ format: 'pem', type: 'spki' }).toString(), signature, payload));
  const wrongCurve = generateKeyPairSync('ec', { namedCurve: 'secp384r1' });
  assert.throws(() => androidPublicKey(wrongCurve.publicKey.export({ format: 'der', type: 'spki' }).toString('base64')));
  assert.throws(() => androidPublicKey('not a key'));
});
test('Android cannot mix Apple and Play authentication headers', () => {
  const headers = { 'x-app-key': 'android:00000000-0000-4000-8000-000000000001', 'x-android-signature': 'a'.repeat(96), 'x-android-integrity': 'token' };
  assert.equal(androidHeaders(new Request('https://example.com', { headers })).keyId, headers['x-app-key']);
  assert.throws(() => androidHeaders(new Request('https://example.com', { headers: { ...headers, 'x-app-assertion': 'apple' } })));
  assert.throws(() => androidHeaders(new Request('https://example.com', { headers: { ...headers, 'x-app-key': 'apple-key' } })));
});
const product = 'cavecals_plus_monthly:monthly';
function customer() { return { subscriber: {
  entitlements: { ai: { product_identifier: product, expires_date: new Date(now + 86_400_000).toISOString(), grace_period_expires_date: null as string | null } },
  subscriptions: { [product]: { store: 'play_store', expires_date: new Date(now + 86_400_000).toISOString(), grace_period_expires_date: null as string | null, refunded_at: null as string | null, is_sandbox: false, ownership_type: 'PURCHASED' } },
} }; }
test('only an active allowlisted Play subscription grants Android access', () => {
  assert.equal(verifiedPlayExpiry(customer(), [product], false, now)?.getTime(), now + 86_400_000);
  assert.equal(verifiedPlayExpiry(customer(), ['different'], false, now), null);
  for (const store of ['app_store', 'promotional', 'stripe']) {
    const c = customer(); c.subscriber.subscriptions[product].store = store;
    assert.equal(verifiedPlayExpiry(c, [product], false, now), null);
  }
  const refunded = customer(); refunded.subscriber.subscriptions[product].refunded_at = new Date(now - 1).toISOString();
  assert.equal(verifiedPlayExpiry(refunded, [product], false, now), null);
  const sandbox = customer(); sandbox.subscriber.subscriptions[product].is_sandbox = true;
  assert.equal(verifiedPlayExpiry(sandbox, [product], false, now), null);
  assert.ok(verifiedPlayExpiry(sandbox, [product], true, now));
  const shared = customer(); shared.subscriber.subscriptions[product].ownership_type = 'FAMILY_SHARED';
  assert.equal(verifiedPlayExpiry(shared, [product], false, now), null);
  assert.throws(() => verifiedPlayExpiry({ subscriber: {} }, [product], false, now));
});
test('Play expiry requires matching subscription and entitlement, including grace periods', () => {
  const c = customer(); c.subscriber.subscriptions[product].expires_date = new Date(now - 1).toISOString();
  assert.equal(verifiedPlayExpiry(c, [product], false, now), null);
  c.subscriber.subscriptions[product].grace_period_expires_date = new Date(now + 60_000).toISOString();
  assert.equal(verifiedPlayExpiry(c, [product], false, now)?.getTime(), now + 60_000);
  c.subscriber.entitlements.ai.expires_date = new Date(now - 1).toISOString();
  assert.equal(verifiedPlayExpiry(c, [product], false, now), null);
  c.subscriber.entitlements.ai.grace_period_expires_date = new Date(now + 30_000).toISOString();
  assert.equal(verifiedPlayExpiry(c, [product], false, now)?.getTime(), now + 30_000);
});
test('Play cached access is brief and never extends beyond the store expiry', () => {
  assert.equal(cachedPlayEntitlement(new Date(now + 1000), new Date(now - 1), now)?.active, true);
  assert.equal(cachedPlayEntitlement(new Date(now - 1), new Date(now - 1), now)?.active, false);
  assert.equal(cachedPlayEntitlement(new Date(now + 1000), new Date(now - PLAY_ACTIVE_TTL), now), undefined);
  assert.equal(cachedPlayEntitlement(null, new Date(now - PLAY_INACTIVE_TTL), now), undefined);
  assert.equal(cachedPlayEntitlement(new Date(now + 1000), new Date(now + 1), now), undefined);
});
test('push registration keeps APNs and Firebase formats separate', () => {
  assert.ok(pushRegistration.safeParse({ environment: 'production', token: 'a'.repeat(64) }).success);
  assert.ok(pushRegistration.safeParse({ environment: 'android', token: 'fcm_token:12345678901234567890' }).success);
  assert.equal(pushRegistration.safeParse({ environment: 'production', token: 'fcm_token:12345678901234567890' }).success, false);
  assert.equal(pushRegistration.safeParse({ environment: 'android', token: 'malicious\nheader' }).success, false);
});
test('Firebase preserves notification routing and removes only explicitly unregistered tokens', () => {
  const message = firebaseMessage({ token: 'fixture', title: 'Clan', body: 'Cheer', clanId: 'clan', kind: 'cheer' });
  assert.deepEqual(message.message.data, { title: 'Clan', body: 'Cheer', clanId: 'clan', kind: 'cheer' });
  assert.equal(deadFirebaseToken({ error: { code: 400, details: [{ errorCode: 'INVALID_ARGUMENT' }] } }), false);
  assert.equal(deadFirebaseToken({ error: { details: [{ '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError', errorCode: 'UNREGISTERED' }] } }), true);
});

test('license and certification failures explain recovery without relaxing integrity checks', () => {
  const unlicensed = verdict();
  unlicensed.accountDetails.appLicensingVerdict = 'UNLICENSED';
  assert.throws(() => validateIntegrity(unlicensed, payload, policy, now), (error: unknown) => {
    assert.ok(error instanceof Error && 'code' in error);
    assert.equal(error.code, 'play_install_required');
    assert.match(error.message, /Google Play/);
    return true;
  });
  const uncertified = verdict();
  uncertified.deviceIntegrity.deviceRecognitionVerdict = ['MEETS_BASIC_INTEGRITY'];
  assert.throws(() => validateIntegrity(uncertified, payload, policy, now), (error: unknown) => {
    assert.ok(error instanceof Error && 'code' in error);
    assert.equal(error.code, 'unsupported_device');
    assert.match(error.message, /Manual logging still works/);
    assert.match(error.message, /subscription/);
    return true;
  });
});
