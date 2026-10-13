import Link from 'next/link';
import { desc, eq, isNull } from 'drizzle-orm';
import { alias } from 'drizzle-orm/pg-core';
import { database } from '@/server/db';
import { clanPeople, clanReports, clans } from '@/server/schema';
import { requireAdmin } from '../require-admin';
import { clearName, dismissReport, removePerson, removePhoto, resetClanName } from './actions';
export const dynamic = 'force-dynamic';

const kindNames: Record<string, string> = { name: 'Name', photo: 'Photo', clanName: 'Clan name' };
const when = (date: Date) => date.toLocaleString('en-US', { timeZone: 'America/Los_Angeles', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });

/** Reported names and photos in clans. Apple expects action within 24 hours (guideline 1.2). */
export default async function ReportsPage({ searchParams }: { searchParams: Promise<{ done?: string }> }) {
  await requireAdmin();
  const done = (await searchParams).done === '1';
  const target = alias(clanPeople, 'target');
  const open = await database().select({ report: clanReports, targetName: target.displayName, targetPhoto: target.photoId, clanName: clans.name })
    .from(clanReports).leftJoin(target, eq(target.id, clanReports.targetPersonId)).leftJoin(clans, eq(clans.id, clanReports.targetClanId))
    .where(isNull(clanReports.resolvedAt)).orderBy(desc(clanReports.createdAt)).limit(200);
  const recent = await database().select().from(clanReports).orderBy(desc(clanReports.resolvedAt)).limit(20);
  return <>
    <header>
      <div>
        <h1>Clan reports</h1>
        <p className="note">Names and photos people reported. Act within 24 hours. Pacific times.</p>
      </div>
      <nav className="nav"><Link className="pill" href="/admin">← Stats</Link></nav>
    </header>
    {done ? <p className="note">Done.</p> : null}
    <section>
      <h2>Open · {open.length}</h2>
      {open.length === 0 ? <p className="note">Nothing to review.</p> : <table>
        <thead><tr><th>Reported</th><th>What</th><th>Now</th><th>Clan</th><th>Reason</th><th></th></tr></thead>
        <tbody>{open.map(({ report, targetName, targetPhoto, clanName }) => <tr key={report.id}>
          <td>{when(report.createdAt)}</td>
          <td>{kindNames[report.kind] ?? report.kind}: {report.kind === 'photo'
            ? (report.snapshot ? <img src={`/admin/reports/photo/${report.snapshot}`} width="64" height="64" alt="Reported photo" /> : '–')
            : <b>{report.snapshot}</b>}</td>
          <td>{report.kind === 'clanName' ? clanName ?? 'Deleted' : report.kind === 'photo' ? (targetPhoto === report.snapshot ? 'Still showing' : 'Changed') : targetName ?? 'Deleted'}</td>
          <td>{clanName ?? '–'}</td>
          <td>{report.reason || '–'}</td>
          <td className="actions">
            <form action={dismissReport}><input type="hidden" name="id" value={report.id} /><button className="admin-button" type="submit">Dismiss</button></form>
            {report.kind === 'name' ? <form action={clearName}><input type="hidden" name="id" value={report.id} /><button className="admin-button" type="submit">Clear name</button></form> : null}
            {report.kind === 'photo' ? <form action={removePhoto}><input type="hidden" name="id" value={report.id} /><button className="admin-button" type="submit">Remove photo</button></form> : null}
            {report.kind === 'clanName' ? <form action={resetClanName}><input type="hidden" name="id" value={report.id} /><button className="admin-button" type="submit">Rename clan</button></form> : null}
            {report.targetPersonId ? <form action={removePerson}><input type="hidden" name="id" value={report.id} /><button className="admin-button" type="submit">Remove account</button></form> : null}
          </td>
        </tr>)}</tbody>
      </table>}
    </section>
    <section>
      <h2>Recently handled</h2>
      <table><tbody>{recent.filter(r => r.resolvedAt).map(r => <tr key={r.id}><td>{when(r.resolvedAt!)}</td><td>{kindNames[r.kind] ?? r.kind}</td><td>{r.kind === 'photo' ? 'Photo' : r.snapshot}</td><td>{r.resolution}</td></tr>)}</tbody></table>
    </section>
  </>;
}
