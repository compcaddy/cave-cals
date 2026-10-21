import { createHash, randomUUID } from 'node:crypto';
import { and, eq, gt, sql } from 'drizzle-orm';
import { z } from 'zod';
import { APIError } from './config';
import { database } from './db';
import { accounts, devices, challenges } from './schema';
import { priorUsage, trialKeyPattern, type Identity } from './auth';
import { consume, tomorrow } from './rate-limit';
import { ANDROID_ENVIRONMENT, androidHeaders, androidKeyPattern, androidPayload, androidPublicKey, verifyAndroidSignature, verifyIntegrityToken } from './android-integrity';

export const androidRegistration = z.object({ keyId: z.string().regex(androidKeyPattern), nonce: z.string().min(1).max(200), publicKey: z.string().min(1).max(512), trialKey: z.string().regex(trialKeyPattern) });
export async function registerAndroid(request: Request, raw: string, input: z.infer<typeof androidRegistration>, checkIntegrity = verifyIntegrityToken) {
  const headers = androidHeaders(request);
  if (headers.keyId !== input.keyId) throw new APIError(401, 'invalid_integrity', 'Please retry device registration.');
  const publicKey = androidPublicKey(input.publicKey), payload = androidPayload(request, raw);
  verifyAndroidSignature(publicKey, headers.signature, payload);
  // Reject missing challenges before making a paid verification request; consume atomically after verification.
  const [pending] = await database().select().from(challenges).where(and(eq(challenges.nonce, input.nonce), eq(challenges.keyId, input.keyId), eq(challenges.purpose, 'register'), gt(challenges.expiresAt, new Date())));
  if (!pending) throw new APIError(401, 'invalid_challenge', 'Please retry device registration.');
  await checkIntegrity(headers.token, payload);
  return database().transaction(async tx => {
    const [used] = await tx.delete(challenges).where(and(eq(challenges.nonce, input.nonce), eq(challenges.keyId, input.keyId), eq(challenges.purpose, 'register'), gt(challenges.expiresAt, new Date()))).returning();
    if (!used) throw new APIError(401, 'invalid_challenge', 'Please retry device registration.');
    const [existing] = await tx.select().from(devices).where(eq(devices.keyId, input.keyId));
    if (existing) {
      if (existing.publicKey !== publicKey) throw new APIError(401, 'invalid_integrity', 'Please retry device registration.');
      return { accountId: existing.accountId };
    }
    // Platform namespacing prevents any iOS/Android install-key collision or account migration.
    const hash = createHash('sha256').update(`android:${input.trialKey}`).digest('hex');
    await tx.execute(sql`select pg_advisory_xact_lock(hashtextextended(${hash}, 0))`);
    const prior = await priorUsage(tx, hash), accountId = randomUUID();
    await tx.insert(accounts).values({ id: accountId, environment: ANDROID_ENVIRONMENT, trialKeyHash: hash, ...prior });
    await tx.insert(devices).values({ keyId: input.keyId, accountId, publicKey, trialKeyHash: hash });
    return { accountId };
  });
}
export async function authenticateAndroid(request: Request, raw: string, nonce: string, checkIntegrity = verifyIntegrityToken): Promise<Identity> {
  const { keyId, signature, token } = androidHeaders(request), payload = androidPayload(request, raw);
  const [device] = await database().select().from(devices).where(eq(devices.keyId, keyId));
  if (!device) throw new APIError(401, 'unknown_device', 'Please reconnect to verify this device.');
  verifyAndroidSignature(device.publicKey, signature, payload);
  const [pending] = await database().select().from(challenges).where(and(eq(challenges.nonce, nonce), eq(challenges.keyId, keyId), eq(challenges.purpose, 'request'), gt(challenges.expiresAt, new Date())));
  if (!pending) throw new APIError(401, 'invalid_challenge', 'This request has expired. Please try again.');
  await consume(`android-verify:${keyId}:${new Date().toISOString().slice(0,16)}`, 30, tomorrow());
  await checkIntegrity(token, payload);
  return database().transaction(async tx => {
    const [current] = await tx.select().from(devices).where(eq(devices.keyId, keyId)).for('update');
    const [account] = current ? await tx.select().from(accounts).where(eq(accounts.id, current.accountId)) : [];
    if (!current || current.publicKey !== device.publicKey || account?.environment !== ANDROID_ENVIRONMENT) throw new APIError(401, 'unknown_device', 'Please reconnect to verify this device.');
    const [used] = await tx.delete(challenges).where(and(eq(challenges.nonce, nonce), eq(challenges.keyId, keyId), eq(challenges.purpose, 'request'), gt(challenges.expiresAt, new Date()))).returning();
    if (!used) throw new APIError(401, 'invalid_challenge', 'This request has expired. Please try again.');
    await tx.update(devices).set({ lastSeen: sql`now()` }).where(eq(devices.keyId, keyId));
    return { accountId: current.accountId, keyId, development: false };
  });
}
