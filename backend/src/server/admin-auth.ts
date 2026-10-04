import { createHash } from 'node:crypto';
import { and, eq, gt, sql } from 'drizzle-orm';
import { safeEqual } from './config';
import { database } from './db';
import { limits } from './schema';
/** Wrong passwords from one IP before it's locked out of the admin pages for an hour. */
export const ADMIN_MAX_FAILURES = 10;
/** The admin pages need ADMIN_PASSWORD in the deployment's environment; without it they're a 404. Any length (the owner's choice); the lockout limits guessing. */
export function adminConfigured() { return !!process.env.ADMIN_PASSWORD; }
/** HTTP Basic authentication: any user name, the configured password. */
export function adminAuthorized(header: string | null): boolean {
  const password = process.env.ADMIN_PASSWORD;
  if (!password || !header?.startsWith('Basic ')) return false;
  const decoded = Buffer.from(header.slice(6), 'base64').toString('utf8');
  const separator = decoded.indexOf(':');
  return separator >= 0 && safeEqual(decoded.slice(separator + 1), password);
}
function failureBucket(request: Request) {
  // Vercel supplies this header; local callers share one bucket.
  const ip = process.env.VERCEL ? request.headers.get('x-vercel-forwarded-for') || 'unknown' : 'local';
  return `admin-fail:${createHash('sha256').update(`admin:${ip}`).digest('hex').slice(0, 32)}`;
}
/** True while this IP is locked out, even with the right password. */
export async function adminLocked(request: Request) {
  const [row] = await database().select({ count: limits.count }).from(limits)
    .where(and(eq(limits.bucket, failureBucket(request)), gt(limits.expiresAt, new Date())));
  return (row?.count ?? 0) >= ADMIN_MAX_FAILURES;
}
/** Counts a wrong password. Failures within an hour add up; the tenth locks the IP out for an hour from then. */
export async function recordAdminFailure(request: Request) {
  const expired = sql`${limits.expiresAt} <= now()`;
  await database().insert(limits).values({ bucket: failureBucket(request), count: 1, expiresAt: new Date(Date.now() + 3_600_000) })
    .onConflictDoUpdate({
      target: limits.bucket,
      set: {
        count: sql`case when ${expired} then 1 else ${limits.count} + 1 end`,
        expiresAt: sql`case when ${expired} or ${limits.count} + 1 >= ${ADMIN_MAX_FAILURES} then now() + interval '1 hour' else ${limits.expiresAt} end`,
      },
    });
}
