import Link from 'next/link';
import { emailConfigured, emailStats } from '@/server/email';
import { requireAdmin } from '../require-admin';
import { sendTestEmail, sendToSubscribers } from './actions';
export const dynamic = 'force-dynamic';
// Sending to the list runs inside the request, about 10 emails a second.
export const maxDuration = 300;

const n = (value: number) => value.toLocaleString('en-US');
const when = (date: Date | null) => date ? date.toLocaleString('en-US', { timeZone: 'America/Los_Angeles', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }) : '–';

/** Cave Cals news to signed-in people who ticked "Email me Cave Cals news", through Amazon SES. */
export default async function EmailPage({ searchParams }: { searchParams: Promise<{ error?: string; tested?: string; sent?: string; failed?: string; of?: string }> }) {
  await requireAdmin();
  const params = await searchParams;
  const stats = await emailStats();
  const missing = emailConfigured();
  return <>
    <header>
      <div>
        <h1>News email</h1>
        <p className="note">Only to people who signed in and turned on “Email me Cave Cals news.” Every email has an unsubscribe link and your postal address.</p>
      </div>
      <nav className="nav"><Link className="pill" href="/admin">← Stats</Link><a className="pill" href="/admin/email/export">Download list (CSV)</a></nav>
    </header>
    <section>
      <div className="tiles">
        <div className="tile"><b>{n(stats.accounts)}</b><span>Accounts</span></div>
        <div className="tile"><b>{n(stats.withEmail)}</b><span>With an email</span></div>
        <div className="tile"><b>{n(stats.optedIn)}</b><span>Want news</span></div>
      </div>
    </section>
    {missing.length ? <p className="note">Not set up yet. Add these in Vercel: {missing.join(', ')}.</p> : null}
    {params.error ? <p className="note" style={{ color: '#b3261e' }}>{params.error}</p> : null}
    {params.tested ? <p className="note">Test sent.</p> : null}
    {params.sent ? <p className="note">Sent {params.sent} of {params.of}{Number(params.failed) ? ` · ${params.failed} failed` : ''}.</p> : null}
    <section>
      <h2>Write</h2>
      <form className="code-form" style={{ display: 'grid', gap: 12 }}>
        <label>Subject<input type="text" name="subject" required maxLength={200} placeholder="Clans are here" /></label>
        <label>Message (plain text; a blank line starts a new paragraph)<textarea name="body" required rows={12} maxLength={20000} /></label>
        <label>Send a test to<input type="email" name="testTo" placeholder="you@example.com" /></label>
        <button className="admin-button" formAction={sendTestEmail} type="submit">Send test</button>
        <label>Type SEND to email {n(stats.optedIn)} {stats.optedIn === 1 ? 'person' : 'people'}<input type="text" name="confirm" autoComplete="off" /></label>
        <button className="admin-button primary" formAction={sendToSubscribers} type="submit" disabled={missing.length > 0}>Send to everyone who wants news</button>
      </form>
    </section>
    <section>
      <h2>Sent</h2>
      {stats.campaigns.length === 0 ? <p className="note">Nothing yet.</p> : <table>
        <thead><tr><th>When</th><th>Subject</th><th>Sent</th><th>Failed</th><th>Status</th></tr></thead>
        <tbody>{stats.campaigns.map(c => <tr key={c.id}><td>{when(c.createdAt)}</td><td>{c.subject}</td><td>{n(c.sent)} of {n(c.recipients)}</td><td>{n(c.failed)}</td><td>{c.status}</td></tr>)}</tbody>
      </table>}
    </section>
  </>;
}
