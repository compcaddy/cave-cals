import { randomBytes, randomUUID } from 'node:crypto';
import { and, eq, gt, sql } from 'drizzle-orm';
import { verifyAssertion, verifyAttestation } from 'node-app-attest';
import { database } from './db';
import { accounts, devices, challenges } from './schema';
import { APIError, bundleID, required, isDevelopmentUser, DEV_ACCOUNT } from './config';
import { limitPublic } from './rate-limit';
export type Identity = { accountId: string; keyId: string; development: boolean; testAccess?: boolean };
export async function challenge(request: Request, keyId: string, purpose: string) {
  await limitPublic(request);
  const nonce = randomBytes(32).toString('base64url');
  await database().insert(challenges).values({ nonce, keyId, purpose, expiresAt: new Date(Date.now() + 120000) });
  return { nonce };
}
export async function register(keyId: string, nonce: string, attestation: string) {
  return database().transaction(async tx => {
    const [c] = await tx.delete(challenges).where(and(eq(challenges.nonce, nonce), eq(challenges.keyId, keyId), eq(challenges.purpose, 'register'), gt(challenges.expiresAt, new Date()))).returning();
    if (!c) throw new APIError(401, 'invalid_challenge', 'Please retry device registration.');
    let verified;
    try { verified = verifyAttestation({ attestation: Buffer.from(attestation, 'base64'), challenge: nonce, keyId, bundleIdentifier: bundleID(), teamIdentifier: required('APPLE_TEAM_ID'), allowDevelopmentEnvironment: process.env.APPLE_ENVIRONMENT === 'Sandbox' && process.env.VERCEL_ENV !== 'production' }); }
    catch { throw new APIError(401, 'invalid_attestation', 'This device could not be verified.'); }
    const accountId = randomUUID();
    await tx.insert(accounts).values({ id: accountId });
    await tx.insert(devices).values({ keyId, accountId, publicKey: verified.publicKey, signCount: 0 });
    return { accountId };
  });
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
