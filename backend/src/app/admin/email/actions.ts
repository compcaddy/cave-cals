'use server';
import { redirect } from 'next/navigation';
import { sendCampaign, sendTest } from '@/server/email';
import { requireAdmin } from '../require-admin';

const back = (query: string): never => redirect(`/admin/email?${query}`);
function fields(form: FormData) {
  const subject = String(form.get('subject') ?? '').trim().slice(0, 200), body = String(form.get('body') ?? '').trim().slice(0, 20000);
  if (!subject || !body) back(`error=${encodeURIComponent('Add a subject and a message.')}`);
  return { subject, body };
}
export async function sendTestEmail(form: FormData) {
  await requireAdmin();
  const { subject, body } = fields(form);
  try { await sendTest(String(form.get('testTo') ?? '').trim(), subject, body); }
  catch (error) { back(`error=${encodeURIComponent(error instanceof Error ? error.message : 'The test didn’t send.')}`); }
  back(`tested=1`);
}
/** Sends to everyone opted in. The owner types SEND to confirm. */
export async function sendToSubscribers(form: FormData) {
  await requireAdmin();
  const { subject, body } = fields(form);
  if (String(form.get('confirm') ?? '').trim() !== 'SEND') back(`error=${encodeURIComponent('Type SEND to confirm.')}`);
  let result;
  try { result = await sendCampaign(subject, body); }
  catch (error) { back(`error=${encodeURIComponent(error instanceof Error ? error.message : 'Sending failed.')}`); }
  back(`sent=${result!.sent}&failed=${result!.failed}&of=${result!.recipients}`);
}
