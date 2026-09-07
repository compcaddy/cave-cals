import { sql } from 'drizzle-orm';
import { createHash } from 'node:crypto';
import { database, type DBTransaction } from './db';
import { APIError } from './config';
import { limits } from './schema';
export async function consume(bucket: string, cap: number, expiresAt: Date, tx: DBTransaction | ReturnType<typeof database> = database()) {
  const result = await tx.insert(limits).values({ bucket, count: 1, expiresAt }).onConflictDoUpdate({
    target: limits.bucket, set: { count: sql`${limits.count} + 1` }, setWhere: sql`${limits.count} < ${cap}`,
  }).returning({ count: limits.count });
  if (!result.length) throw new APIError(429, 'usage_limit', 'The usage limit has been reached. Please try again later.');
}
export function utcDay(now = new Date()) { return now.toISOString().slice(0, 10); }
export function tomorrow() { const d = new Date(); d.setUTCHours(24, 0, 0, 0); return d; }
export async function limitPublic(request: Request) {
  // Vercel supplies this header. Local callers share a bucket rather than trusting arbitrary forwarded headers.
  const ip = process.env.VERCEL ? request.headers.get('x-vercel-forwarded-for') || 'unknown' : 'local';
  const hash = createHash('sha256').update(`${utcDay()}:${ip}`).digest('hex');
  await consume(`bootstrap:${hash}:${new Date().toISOString().slice(0,13)}`, 120, tomorrow());
  await consume(`bootstrap-global:${utcDay()}`, 10000, tomorrow());
}
