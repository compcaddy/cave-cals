import { and, eq } from 'drizzle-orm';
import { z } from 'zod';
import { APIError, required } from './config';
import { database } from './db';
import { accounts } from './schema';
import { ANDROID_ENVIRONMENT } from './android-integrity';

export const androidProducts = () => (process.env.GOOGLE_PLAY_PRODUCT_IDS || '').split(',').map(s => s.trim()).filter(Boolean);
const expiry = z.string().nullable().optional();
const customer = z.object({ subscriber: z.object({
  entitlements: z.record(z.string(), z.object({ product_identifier: z.string(), expires_date: expiry, grace_period_expires_date: expiry })),
  subscriptions: z.record(z.string(), z.object({ store: z.string(), expires_date: expiry, grace_period_expires_date: expiry, refunded_at: expiry, is_sandbox: z.boolean(), ownership_type: z.string().optional() })),
}) });
const timestamp = (value: string | null | undefined) => value ? Date.parse(value) : NaN;
export function verifiedPlayExpiry(value: unknown, products: string[], allowSandbox: boolean, now = Date.now()): Date | null {
  const parsed = customer.safeParse(value);
  if (!parsed.success) throw new APIError(503, 'purchase_unavailable', 'Purchase verification is temporarily unavailable. Please try again.');
  const { entitlements, subscriptions } = parsed.data.subscriber;
  const entitlement = entitlements.ai;
  if (!entitlement || !products.includes(entitlement.product_identifier)) return null;
  const subscription = subscriptions[entitlement.product_identifier];
  if (!subscription || subscription.store !== 'play_store' || subscription.refunded_at || subscription.ownership_type === 'FAMILY_SHARED' || (subscription.is_sandbox && !allowSandbox)) return null;
  // Both the entitlement and its Play subscription must still be valid. Cancellation alone is not expiration.
  const entitlementEnd = Math.max(timestamp(entitlement.expires_date) || 0, timestamp(entitlement.grace_period_expires_date) || 0);
  const subscriptionEnd = Math.max(timestamp(subscription.expires_date) || 0, timestamp(subscription.grace_period_expires_date) || 0);
  const end = Math.min(entitlementEnd, subscriptionEnd);
  return Number.isFinite(end) && end > now ? new Date(end) : null;
}
export const PLAY_ACTIVE_TTL = 5 * 60_000, PLAY_INACTIVE_TTL = 60_000, PLAY_OUTAGE_GRACE = 60 * 60_000;
export function cachedPlayEntitlement(expiresAt: Date | null, checkedAt: Date | null, now = Date.now()) {
  if (!checkedAt || checkedAt.getTime() > now) return undefined;
  const active = !!expiresAt && expiresAt.getTime() > now;
  if (now - checkedAt.getTime() >= (active ? PLAY_ACTIVE_TTL : PLAY_INACTIVE_TTL)) return undefined;
  return { active, expiresAt: active ? expiresAt!.toISOString() : null, development: false };
}
async function fetchPlayExpiry(accountId: string) {
  const products = androidProducts();
  if (!products.length) throw new APIError(503, 'not_configured', 'Google Play subscriptions are not configured.');
  // This read endpoint supports the app's public SDK key; no project-wide secret is needed.
  const apiKey = required('REVENUECAT_ANDROID_API_KEY');
  let response: Response;
  try {
    response = await fetch(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(`android:${accountId}`)}`, {
      headers: { Authorization: `Bearer ${apiKey}`, Accept: 'application/json' }, cache: 'no-store', signal: AbortSignal.timeout(10_000),
    });
  } catch { throw new APIError(503, 'purchase_unavailable', 'Purchase verification is temporarily unavailable. Please try again.'); }
  if (response.status === 404) return null;
  if (!response.ok) throw new APIError(503, 'purchase_unavailable', 'Purchase verification is temporarily unavailable. Please try again.');
  let value: unknown;
  try { value = await response.json(); } catch { throw new APIError(503, 'purchase_unavailable', 'Purchase verification is temporarily unavailable. Please try again.'); }
  return verifiedPlayExpiry(value, products, process.env.GOOGLE_PLAY_ALLOW_SANDBOX === 'true');
}
export async function androidEntitlement(account: typeof accounts.$inferSelect, force = false) {
  if (account.environment !== ANDROID_ENVIRONMENT) throw new APIError(403, 'wrong_platform', 'Use Google Play to manage this subscription.');
  if (!force) {
    const cached = cachedPlayEntitlement(account.subscriptionExpiresAt, account.subscriptionCheckedAt);
    if (cached) return cached;
  }
  let expiresAt: Date | null;
  try { expiresAt = await fetchPlayExpiry(account.id); }
  catch (error) {
    // Bound outage tolerance: never extend past store expiry or keep a stale entitlement indefinitely.
    const expires = account.subscriptionExpiresAt, checked = account.subscriptionCheckedAt, now = Date.now();
    if (!force && error instanceof APIError && error.code === 'purchase_unavailable' && expires && expires.getTime() > now && checked && checked.getTime() <= now && now - checked.getTime() < PLAY_OUTAGE_GRACE) {
      return { active: true, expiresAt: expires.toISOString(), development: false };
    }
    throw error;
  }
  await database().update(accounts).set({ subscriptionExpiresAt: expiresAt, subscriptionCheckedAt: new Date() })
    .where(and(eq(accounts.id, account.id), eq(accounts.environment, ANDROID_ENVIRONMENT)));
  return { active: !!expiresAt, expiresAt: expiresAt?.toISOString() || null, development: false };
}
