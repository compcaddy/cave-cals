'use server';
import { eq, sql } from 'drizzle-orm';
import { redirect } from 'next/navigation';
import { database } from '@/server/db';
import { discountCodes } from '@/server/schema';
import { CODE_PATTERN, RESERVED_CODES, campaignToken, normalizeCode } from '@/server/discount-codes';
import { requireAdmin } from '../require-admin';

const OFFERING = /^[A-Za-z0-9_.-]{1,64}$/;
const back = (query: string): never => redirect(`/admin/codes?${query}`);
const fail = (message: string): never => back(`error=${encodeURIComponent(message)}`);

/** Adds a code, or updates one when `editing` is set. A code can't be renamed; add a new one instead. */
export async function saveCode(form: FormData) {
  await requireAdmin();
  const text = (key: string) => String(form.get(key) ?? '').trim();
  const code = normalizeCode(text('code'));
  const name = text('name').slice(0, 60);
  const offering = text('offering') || 'discount';
  if (!CODE_PATTERN.test(code)) fail('A code is 2 to 30 letters or digits.');
  if (RESERVED_CODES.has(code)) fail(`CaveCals.com/${code} is one of the site’s own pages. Pick another code.`);
  if (!name) fail('Add the name people know them by.');
  if (!OFFERING.test(offering)) fail('The offering is a RevenueCat offering identifier, like discount.');
  const values = { name, campaign: campaignToken(text('campaign'), code), offering, active: form.get('active') === 'on' };
  if (form.get('editing') === '1') {
    await database().update(discountCodes).set({ ...values, updatedAt: sql`now()` }).where(eq(discountCodes.code, code));
  } else {
    const added = await database().insert(discountCodes).values({ code, ...values }).onConflictDoNothing()
      .returning({ code: discountCodes.code });
    if (!added.length) fail(`${code} already exists. Edit it below instead.`);
  }
  back(`saved=${code}`);
}

/** Pausing keeps a code's page and history; the page sends visitors to the home page and the app refuses it. */
export async function setCodeActive(form: FormData) {
  await requireAdmin();
  const code = normalizeCode(String(form.get('code') ?? ''));
  await database().update(discountCodes).set({ active: form.get('active') === '1', updatedAt: sql`now()` })
    .where(eq(discountCodes.code, code));
  back(`saved=${code}`);
}
