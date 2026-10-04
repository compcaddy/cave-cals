'use server';
import { eq, sql } from 'drizzle-orm';
import { refresh } from 'next/cache';
import { z } from 'zod';
import { database } from '@/server/db';
import { errorResolutions } from '@/server/schema';
import { requireAdmin } from './require-admin';
const fingerprint = z.string().regex(/^[0-9a-f]{16}$/);
/** Hides an error group until it happens again. */
export async function markFixed(form: FormData) {
  await requireAdmin();
  const value = fingerprint.parse(form.get('fingerprint'));
  await database().insert(errorResolutions).values({ fingerprint: value })
    .onConflictDoUpdate({ target: errorResolutions.fingerprint, set: { resolvedAt: sql`now()` } });
  refresh();
}
export async function reopen(form: FormData) {
  await requireAdmin();
  await database().delete(errorResolutions).where(eq(errorResolutions.fingerprint, fingerprint.parse(form.get('fingerprint'))));
  refresh();
}
