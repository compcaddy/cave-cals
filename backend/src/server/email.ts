// News emails to people who signed in and ticked "Email me Cave Cals news", sent through Amazon SES (SMTP).
// Every email carries a one-click unsubscribe link and the sender's postal address (CAN-SPAM).
import { createHmac, randomUUID, timingSafeEqual } from 'node:crypto';
import { and, desc, eq, isNotNull, sql } from 'drizzle-orm';
import nodemailer from 'nodemailer';
import { database } from './db';
import { clanPeople, emailCampaigns } from './schema';
import { APIError, required } from './config';

export const SITE_URL = 'https://cavecals.com';

// MARK: Unsubscribe links

function unsubscribeKey(): Buffer {
  const key = process.env.CLAN_TOKEN_KEY ? Buffer.from(process.env.CLAN_TOKEN_KEY, 'base64') : null;
  if (!key || key.length !== 32) throw new APIError(503, 'not_configured', 'The service is not configured (CLAN_TOKEN_KEY).');
  return key;
}
export function unsubscribeToken(personId: string, key = unsubscribeKey()): string {
  return createHmac('sha256', key).update(`unsubscribe:${personId}`).digest('base64url').slice(0, 32);
}
export function validUnsubscribe(personId: string, token: string, key = unsubscribeKey()): boolean {
  const expected = Buffer.from(unsubscribeToken(personId, key)), given = Buffer.from(token);
  return expected.length === given.length && timingSafeEqual(expected, given);
}
export function unsubscribeURL(personId: string, key = unsubscribeKey()): string {
  return `${SITE_URL}/unsubscribe?p=${personId}&t=${unsubscribeToken(personId, key)}`;
}
/** One-click unsubscribe (also used by mail apps through List-Unsubscribe-Post). */
export async function unsubscribe(personId: string, token: string): Promise<boolean> {
  if (!/^[0-9a-f-]{36}$/.test(personId) || !validUnsubscribe(personId, token)) return false;
  await database().update(clanPeople).set({ newsOptIn: false, newsOptOutAt: new Date() })
    .where(and(eq(clanPeople.id, personId), eq(clanPeople.newsOptIn, true)));
  return true;
}

// MARK: Composing

const escapeHTML = (text: string) => text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
/** The owner writes plain text; blank lines make paragraphs and links become clickable in the HTML part. */
export function compose(body: string, unsubscribeLink: string, postalAddress: string) {
  const footer = `You’re getting this because you asked for Cave Cals news.\nUnsubscribe: ${unsubscribeLink}\n\nClaim727 LLC · ${postalAddress}`;
  const text = `${body.trim()}\n\n--\n${footer}\n`;
  const paragraphs = body.trim().split(/\n{2,}/).map(p => `<p style="margin:0 0 16px">${escapeHTML(p).replace(/\n/g, '<br>')
    .replace(/(https?:\/\/[^\s<]+)/g, '<a href="$1" style="color:#c4531b">$1</a>')}</p>`).join('');
  const html = `<!doctype html><html><body style="margin:0;background:#f5ecdc"><div style="max-width:560px;margin:0 auto;padding:28px 22px;font:17px/1.55 -apple-system,Helvetica,Arial,sans-serif;color:#2b2118">`
    + `<p style="margin:0 0 20px;font-weight:700;color:#c4531b">Cave Cals</p>${paragraphs}`
    + `<hr style="border:none;border-top:1px solid #e2d6c3;margin:28px 0 14px"><p style="margin:0;font-size:13px;color:#7a6a58">You’re getting this because you asked for Cave Cals news. `
    + `<a href="${escapeHTML(unsubscribeLink)}" style="color:#7a6a58">Unsubscribe</a>.<br>Claim727 LLC · ${escapeHTML(postalAddress)}</p></div></body></html>`;
  return { text, html };
}

// MARK: Sending

function transport() {
  return nodemailer.createTransport({
    host: required('SES_SMTP_HOST'), port: Number(process.env.SES_SMTP_PORT || 587), secure: Number(process.env.SES_SMTP_PORT || 587) === 465,
    auth: { user: required('SES_SMTP_USER'), pass: required('SES_SMTP_PASS') },
  });
}
export function emailConfigured() {
  return ['SES_SMTP_HOST', 'SES_SMTP_USER', 'SES_SMTP_PASS', 'EMAIL_FROM', 'EMAIL_POSTAL_ADDRESS', 'CLAN_TOKEN_KEY'].filter(name => !process.env[name]);
}
type Recipient = { personId: string; email: string };
async function sendOne(mailer: ReturnType<typeof transport>, to: Recipient, subject: string, body: string) {
  const link = unsubscribeURL(to.personId);
  const { text, html } = compose(body, link, required('EMAIL_POSTAL_ADDRESS'));
  await mailer.sendMail({
    from: required('EMAIL_FROM'), to: to.email, subject, text, html,
    // Mail apps show their own Unsubscribe button and post here directly.
    headers: { 'List-Unsubscribe': `<${SITE_URL}/api/unsubscribe?p=${to.personId}&t=${unsubscribeToken(to.personId)}>`, 'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click' },
  });
}
export async function subscribers(): Promise<Recipient[]> {
  const rows = await database().select({ personId: clanPeople.id, email: clanPeople.email }).from(clanPeople)
    .where(and(eq(clanPeople.newsOptIn, true), isNotNull(clanPeople.email)));
  return rows.filter((r): r is Recipient => !!r.email);
}
/** A test to one address, with a sample unsubscribe link that does nothing. */
export async function sendTest(to: string, subject: string, body: string) {
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(to)) throw new APIError(400, 'invalid_email', 'Enter a valid email address.');
  await sendOne(transport(), { personId: '00000000-0000-4000-8000-000000000000', email: to }, `[Test] ${subject}`, body);
}
/** Sends to everyone opted in, about 10 a second (well under SES's default rate), recording progress. */
export async function sendCampaign(subject: string, body: string, deadline = Date.now() + 270_000) {
  const missing = emailConfigured();
  if (missing.length) throw new APIError(503, 'not_configured', `Email isn't set up yet (${missing.join(', ')}).`);
  const recipients = await subscribers();
  const id = randomUUID(), db = database(), mailer = transport();
  await db.insert(emailCampaigns).values({ id, subject, body, recipients: recipients.length });
  let sent = 0, failed = 0;
  for (const recipient of recipients) {
    if (Date.now() > deadline) break;
    try { await sendOne(mailer, recipient, subject, body); sent += 1; } catch { failed += 1; }
    if ((sent + failed) % 10 === 0) await db.update(emailCampaigns).set({ sent, failed }).where(eq(emailCampaigns.id, id));
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  const finished = sent + failed === recipients.length;
  await db.update(emailCampaigns).set({ sent, failed, status: finished ? 'sent' : 'failed', finishedAt: new Date() }).where(eq(emailCampaigns.id, id));
  mailer.close();
  return { id, recipients: recipients.length, sent, failed, finished };
}
export async function emailStats() {
  const db = database();
  const [counts] = await db.select({
    accounts: sql<number>`count(*)`.mapWith(Number),
    withEmail: sql<number>`count(${clanPeople.email})`.mapWith(Number),
    optedIn: sql<number>`count(*) filter (where ${clanPeople.newsOptIn} and ${clanPeople.email} is not null)`.mapWith(Number),
  }).from(clanPeople);
  const campaigns = await db.select().from(emailCampaigns).orderBy(desc(emailCampaigns.createdAt)).limit(20);
  return { ...counts, campaigns };
}
