import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { and, eq, gt, sql } from 'drizzle-orm';
import { verifyAssertion, verifyAttestation } from 'node-app-attest';
import { database, type DBTransaction } from './db';
import { accounts, devices, challenges } from './schema';
import { APIError, bundleID, required, isDevelopmentUser, DEV_ACCOUNT } from './config';
import { consume, limitPublic, tomorrow } from './rate-limit';
export type Identity = { accountId: string; keyId: string; development: boolean; testAccess?: boolean };
export const OWNER_TEST_KEY = 'owner-test';
export const trialKeyPattern = /^[A-Za-z0-9_-]{43}$/;
export const trialKeyHash = (key: string) => createHash('sha256').update(key).digest('hex');
export async function challenge(request: Request, keyId: string, purpose: string) {
  if (purpose === 'register') await limitPublic(request);
  else {
    // Signing challenges are only for registered devices and are throttled per device, so unregistered
    // callers cannot drain the shared bootstrap budget and lock every user out of signed requests.
    const [device] = await database().select({ keyId: devices.keyId }).from(devices).where(eq(devices.keyId, keyId));
    if (!device) throw new APIError(401, 'unknown_device', 'Please reconnect to verify this device.');
    await consume(`challenge:${keyId}:${new Date().toISOString().slice(0,16)}`, 30, tomorrow());
  }
  const nonce = randomBytes(32).toString('base64url');
  await database().insert(challenges).values({ nonce, keyId, purpose, expiresAt: new Date(Date.now() + 120000) });
  return { nonce };
}
export async function register(keyId: string, nonce: string, attestation: string, trialKey?: string) {
  return database().transaction(async tx => {
    const [c] = await tx.delete(challenges).where(and(eq(challenges.nonce, nonce), eq(challenges.keyId, keyId), eq(challenges.purpose, 'register'), gt(challenges.expiresAt, new Date()))).returning();
    if (!c) throw new APIError(401, 'invalid_challenge', 'Please retry device registration.');
    let verified;
    try { verified = verifyAttestation({ attestation: Buffer.from(attestation, 'base64'), challenge: nonce, keyId, bundleIdentifier: bundleID(), teamIdentifier: required('APPLE_TEAM_ID'), allowDevelopmentEnvironment: process.env.APPLE_ENVIRONMENT === 'Sandbox' && process.env.VERCEL_ENV !== 'production' }); }
    catch { throw new APIError(401, 'invalid_attestation', 'This device could not be verified.'); }
    // Only an attested copy of the app can present its Keychain install key, so a reinstall on the same
    // iPhone resumes the highest earlier usage instead of starting a fresh free allowance.
    const hash = trialKey ? trialKeyHash(trialKey) : null;
    const prior = hash ? await priorUsage(tx, hash) : { scansUsed: 0, regularLogCount: 0 };
    const accountId = randomUUID();
    await tx.insert(accounts).values({ id: accountId, trialKeyHash: hash, ...prior });
    await tx.insert(devices).values({ keyId, accountId, publicKey: verified.publicKey, signCount: 0, trialKeyHash: hash });
    return { accountId };
  });
}
export async function priorUsage(tx: DBTransaction, hash: string) {
  const [prior] = await tx.select({
    scansUsed: sql<number>`coalesce(max(${accounts.scansUsed}), 0)`.mapWith(Number),
    regularLogCount: sql<number>`coalesce(max(${accounts.regularLogCount}), 0)`.mapWith(Number),
  }).from(accounts).where(eq(accounts.trialKeyHash, hash));
  return { scansUsed: prior?.scansUsed ?? 0, regularLogCount: prior?.regularLogCount ?? 0 };
}
// Issues the install key an app keeps in its Keychain (which survives reinstalling the app).
export async function issueTrialKey(identity: Identity): Promise<string> {
  const key = randomBytes(32).toString('base64url');
  const hash = trialKeyHash(key);
  await database().transaction(async tx => {
    await tx.update(accounts).set({ trialKeyHash: hash }).where(eq(accounts.id, identity.accountId));
    await tx.update(devices).set({ trialKeyHash: hash }).where(eq(devices.keyId, identity.keyId));
  });
  return key;
}
export async function authenticate(request: Request, raw: string, nonce: string): Promise<Identity> {
  if (isDevelopmentUser(request)) {
    await database().insert(accounts).values({ id: DEV_ACCOUNT }).onConflictDoNothing();
    return { accountId: DEV_ACCOUNT, keyId: 'local', development: true };
  }
  const keyId = request.headers.get('x-app-key'), assertion = request.headers.get('x-app-assertion');
  if (!keyId || !assertion || keyId.length > 200 || assertion.length > 10000) throw new APIError(401, 'unauthorized', 'Please reconnect to verify this device.');
  return database().transaction(async tx => {
    const [device] = await tx.select().from(devices).where(eq(devices.keyId, keyId)).for('update');
    if (!device) throw new APIError(401, 'unknown_device', 'Please reconnect to verify this device.');
    const [c] = await tx.delete(challenges).where(and(eq(challenges.nonce, nonce), eq(challenges.keyId, keyId), eq(challenges.purpose, 'request'), gt(challenges.expiresAt, new Date()))).returning();
    if (!c) throw new APIError(401, 'invalid_challenge', 'This request has expired. Please try again.');
    const payload = `${request.method}\n${new URL(request.url).pathname}\n${raw}`;
    let verified;
    try { verified = verifyAssertion({ assertion: Buffer.from(assertion, 'base64'), payload, publicKey: device.publicKey, bundleIdentifier: bundleID(), teamIdentifier: required('APPLE_TEAM_ID'), signCount: device.signCount }); }
    catch { throw new APIError(401, 'invalid_assertion', 'This request could not be verified.'); }
    await tx.update(devices).set({ signCount: verified.signCount, lastSeen: sql`now()` }).where(eq(devices.keyId, keyId));
    return { accountId: device.accountId, keyId, development: false };
  });
}
