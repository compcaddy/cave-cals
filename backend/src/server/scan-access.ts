import { and, count, eq, gt, sql } from 'drizzle-orm';
import { z } from 'zod';
import { database, type DBTransaction } from './db';
import { accounts, uploads } from './schema';
import { APIError } from './config';
import type { Identity } from './auth';

export const FREE_SCAN_LIMIT = 10;
export const REGULAR_LOG_LIMIT = 100;
// Longer than the route's 240-second maximum. Abandoned workers release their slot automatically.
export const SCAN_RESERVATION_MS = 5 * 60_000;
export const scanUsageInput = z.object({ regularLogCount: z.number().int().min(0).max(1_000_000).default(0) });

export function scanAllowance(active: boolean, scansUsed: number, regularLogCount: number) {
  const freeScansRemaining = regularLogCount >= REGULAR_LOG_LIMIT ? 0 : Math.max(0, FREE_SCAN_LIMIT - scansUsed);
  return { canScan: active || freeScansRemaining > 0, freeScansRemaining, scansUsed, regularLogCount };
}

export async function scanAccess(identity: Identity, active: boolean, regularLogCount: number, tx?: DBTransaction) {
  const db = tx ?? database();
  // UPDATE acquires the account lock. Every reservation and completion uses this same lock.
  const [account] = await db.update(accounts).set({
    regularLogCount: sql`greatest(${accounts.regularLogCount}, ${Math.min(REGULAR_LOG_LIMIT, regularLogCount)})`,
  }).where(eq(accounts.id, identity.accountId)).returning();
  if (!account) throw new APIError(401, 'unknown_device', 'Please reconnect to verify this device.');
  return scanAllowance(active, account.scansUsed, account.regularLogCount);
}

export async function requireScanAccess(identity: Identity, active: boolean, regularLogCount: number, tx: DBTransaction) {
  const access = await scanAccess(identity, active, regularLogCount, tx);
  if (!access.canScan) throw new APIError(402, 'subscription_required', 'Your free scan access is complete. Upgrade or restore Cave Cals+ to continue photo and voice logging.');
  if (!active) {
    const [pending] = await tx.select({ count: count() }).from(uploads).where(and(
      eq(uploads.accountId, identity.accountId), eq(uploads.state, 'processing'), gt(uploads.scanReservedUntil, new Date()),
    ));
    if (access.scansUsed + pending.count >= FREE_SCAN_LIMIT) {
      throw new APIError(409, 'scan_in_progress', 'Your remaining free scan is still processing. Please try again shortly.');
    }
  }
}
