'use server';
import { and, eq, isNull, or } from 'drizzle-orm';
import { redirect } from 'next/navigation';
import { database } from '@/server/db';
import { clanPeople, clanReports, clans } from '@/server/schema';
import { deletePhoto } from '@/server/clan-photos';
import { deleteClanPerson } from '@/server/clan-api';
import { requireAdmin } from '../require-admin';

async function report(form: FormData) {
  await requireAdmin();
  const [row] = await database().select().from(clanReports).where(eq(clanReports.id, String(form.get('id') ?? '')));
  if (!row) redirect('/admin/reports');
  return row;
}
// Closes this report and any other open ones about the same thing.
async function resolve(row: typeof clanReports.$inferSelect, resolution: string) {
  const same = row.kind === 'clanName' ? eq(clanReports.targetClanId, row.targetClanId!) : eq(clanReports.targetPersonId, row.targetPersonId!);
  await database().update(clanReports).set({ resolvedAt: new Date(), resolution })
    .where(and(isNull(clanReports.resolvedAt), or(eq(clanReports.id, row.id), and(eq(clanReports.kind, row.kind), same))));
  redirect('/admin/reports?done=1');
}

export async function dismissReport(form: FormData) { await resolve(await report(form), 'dismissed'); }

/** The person is asked for a new name next time they open clans. */
export async function clearName(form: FormData) {
  const row = await report(form);
  if (row.targetPersonId) await database().update(clanPeople).set({ displayName: '' }).where(eq(clanPeople.id, row.targetPersonId));
  await resolve(row, 'name cleared');
}
export async function removePhoto(form: FormData) {
  const row = await report(form);
  if (row.targetPersonId) {
    const [person] = await database().select({ photoId: clanPeople.photoId }).from(clanPeople).where(eq(clanPeople.id, row.targetPersonId));
    await database().update(clanPeople).set({ photoId: null }).where(eq(clanPeople.id, row.targetPersonId));
    await deletePhoto(person?.photoId);
  }
  await resolve(row, 'photo removed');
}
export async function resetClanName(form: FormData) {
  const row = await report(form);
  if (row.targetClanId) await database().update(clans).set({ name: 'Unnamed clan' }).where(eq(clans.id, row.targetClanId));
  await resolve(row, 'clan renamed');
}
/** For serious or repeated abuse: deletes their clan account (their diary stays on their phone). */
export async function removePerson(form: FormData) {
  const row = await report(form);
  if (row.targetPersonId) await deleteClanPerson(row.targetPersonId);
  await resolve(row, 'account removed');
}
