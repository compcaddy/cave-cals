import { AppStoreServerAPIClient, Environment, SignedDataVerifier, Status, type JWSTransactionDecodedPayload } from '@apple/app-store-server-library';
import { and, eq, ne } from 'drizzle-orm';
import roots from './certs/roots.json';
import { APIError, bundleID, required } from './config';
import { database } from './db';
import { accounts, devices } from './schema';
import type { Identity } from './auth';
export function products() { return (process.env.APPLE_PRODUCT_IDS || '').split(',').map(s => s.trim()).filter(Boolean); }
export function appleEnvironments(): Environment[] {
  const env = process.env.APPLE_ENVIRONMENT || 'Production';
  if (env !== 'Production' && env !== 'Sandbox') throw new APIError(503, 'not_configured', 'Invalid Apple environment.');
  if (env === 'Sandbox' && process.env.VERCEL_ENV === 'production') throw new APIError(503, 'not_configured', 'Production must verify production purchases first.');
  return env === 'Sandbox' ? [Environment.SANDBOX] :
    [Environment.PRODUCTION, ...(process.env.APPLE_ALLOW_SANDBOX === 'true' ? [Environment.SANDBOX] : [])];
}
export function verifier(env = appleEnvironments()[0]) {
  if (!appleEnvironments().includes(env)) throw new APIError(401, 'invalid_purchase', 'Unsupported purchase environment.');
  const appId = env === Environment.PRODUCTION ? Number(required('APPLE_APP_ID')) : undefined;
  if (appId !== undefined && (!Number.isSafeInteger(appId) || appId <= 0)) throw new APIError(503, 'not_configured', 'Invalid Apple App ID.');
  return new SignedDataVerifier(roots.map(s => Buffer.from(s, 'base64')), true, env, bundleID(), appId);
}
function client(env: Environment) { return new AppStoreServerAPIClient(required('APPLE_PRIVATE_KEY').replace(/\\n/g, '\n'), required('APPLE_KEY_ID'), required('APPLE_ISSUER_ID'), bundleID(), env); }
// Try independently verified Apple environments, never an unverified JWT claim.
export async function decodePurchase(signed: string) {
  for (const env of appleEnvironments()) {
    try { return { transaction: await verifier(env).verifyAndDecodeTransaction(signed), environment: env }; }
    catch (error) { if (error instanceof APIError) throw error; }
  }
  throw new APIError(401, 'invalid_purchase', 'Apple could not verify this purchase.');
}
export async function verifyNotification(signed: string) {
  for (const env of appleEnvironments()) {
    try { return await verifier(env).verifyAndDecodeNotification(signed); }
    catch (error) { if (error instanceof APIError) throw error; }
  }
  throw new APIError(401, 'invalid_notification', 'Apple could not verify this notification.');
}
export function allowedTransaction(t: JWSTransactionDecodedPayload): boolean {
  return !!t.originalTransactionId && !!t.productId && products().includes(t.productId) &&
    t.bundleId === bundleID() && t.type === 'Auto-Renewable Subscription' && !t.revocationDate && t.inAppOwnershipType !== 'FAMILY_SHARED';
}
export async function activePurchase(originalId: string, env: Environment) {
  if (!products().length) throw new APIError(503, 'not_configured', 'Subscriptions have not been configured yet.');
  const v = verifier(env);
  let status;
  try { status = await client(env).getAllSubscriptionStatuses(originalId); }
  catch { throw new APIError(503, 'purchase_unavailable', 'Apple purchase verification is temporarily unavailable. Please try again.'); }
  for (const group of status.data || []) for (const item of group.lastTransactions || []) {
    if (!item.signedTransactionInfo || item.originalTransactionId !== originalId) continue;
    const t = await v.verifyAndDecodeTransaction(item.signedTransactionInfo);
    if (!allowedTransaction(t) || t.originalTransactionId !== originalId) continue;
    let expires = t.expiresDate || 0;
    if (item.status === Status.BILLING_GRACE_PERIOD && item.signedRenewalInfo) {
      const renewal = await v.verifyAndDecodeRenewalInfo(item.signedRenewalInfo);
      expires = renewal.gracePeriodExpiresDate || 0;
    } else if (item.status !== Status.ACTIVE) continue;
    if (expires > Date.now()) return { transaction: t, expiresAt: new Date(expires).toISOString() };
  }
  return null;
}
export async function entitlement(identity: Identity) {
  if (identity.testAccess !== undefined) return { active: identity.testAccess, expiresAt: null, development: false, testing: true };
  if (identity.development) return { active: true, expiresAt: null, development: true };
  const [account] = await database().select().from(accounts).where(eq(accounts.id, identity.accountId));
  if (!account?.originalTransactionId || !appleEnvironments().includes(account.environment as Environment)) return { active: false, expiresAt: null, development: false };
  const current = await activePurchase(account.originalTransactionId, account.environment as Environment);
  return { active: !!current, expiresAt: current?.expiresAt || null, development: false };
}
export async function requirePaid(identity: Identity) {
  if (!(await entitlement(identity)).active) throw new APIError(402, 'subscription_required', 'Upgrade or restore a subscription to use photo and voice logging.');
}
export async function verifyPurchase(identity: Identity, signedTransaction: string) {
  if (identity.development) throw new APIError(400, 'development_mode', 'Use a physical device to test Apple purchases.');
  const verified = await decodePurchase(signedTransaction);
  const decoded = verified.transaction;
  if (!allowedTransaction(decoded)) throw new APIError(402, 'invalid_purchase', 'This purchase does not include AI access.');
  const current = await activePurchase(decoded.originalTransactionId!, verified.environment);
  if (!current) throw new APIError(402, 'subscription_required', 'This subscription is no longer active.');
  const token = current.transaction.appAccountToken?.toLowerCase();
  const result = await database().transaction(async tx => {
    // The signed appAccountToken links the original purchase to an anonymous server identity.
    const [existing] = await tx.select().from(accounts).where(eq(accounts.originalTransactionId, decoded.originalTransactionId!)).for('update');
    if (!token || !/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(token)) throw new APIError(403, 'purchase_owner', 'This purchase has no account association. Please contact support.');
    const [tokenAccount] = await tx.select().from(accounts).where(eq(accounts.id, token)).for('update');
    const ownerId = existing?.id || tokenAccount?.id;
    if (!ownerId || (tokenAccount?.originalTransactionId && tokenAccount.originalTransactionId !== decoded.originalTransactionId && !existing)) throw new APIError(403, 'purchase_owner', 'This purchase could not be linked. Please contact support.');
    if (token !== ownerId.toLowerCase()) throw new APIError(403, 'purchase_owner', 'This purchase could not be linked. Please contact support.');
    await tx.select().from(accounts).where(eq(accounts.id, ownerId)).for('update');
    const others = await tx.select({ key: devices.keyId }).from(devices).where(and(eq(devices.accountId, ownerId), ne(devices.keyId, identity.keyId)));
    if (others.length >= 5) throw new APIError(403, 'device_limit', 'This subscription has reached its device limit. Contact support to reset old devices.');
    await tx.update(accounts).set({ originalTransactionId: decoded.originalTransactionId, environment: verified.environment }).where(eq(accounts.id, ownerId));
    await tx.update(devices).set({ accountId: ownerId }).where(eq(devices.keyId, identity.keyId));
    return { accountId: ownerId, active: true, expiresAt: current.expiresAt };
  });
  return result;
}
