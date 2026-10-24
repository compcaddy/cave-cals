import Link from 'next/link';
import { loadErrors, errorsForAI, errorSource, osName, adminQuery, toPlatform } from '@/server/admin-data';
import { requireAdmin } from '../require-admin';
import { FilterPills, scopeLabel } from '../filters';
import { markFixed, reopen } from '../actions';
import CopyButton from '../copy-button';
export const dynamic = 'force-dynamic';

type Group = Awaited<ReturnType<typeof loadErrors>>[number];

function ErrorCard({ group }: { group: Group }) {
  return <div className="error-card">
    <h3>{errorSource(group)} · {group.area} · <code>{group.code}</code>
      {group.resolvedAt && group.open ? <span className="tag">Back after fix on {group.resolvedAt}</span> : null}</h3>
    <p><b>{group.week}</b> in 7 days · <b>{group.total}</b> in 90 days · {group.people} {group.people === 1 ? 'person' : 'people'} · last {group.last}</p>
    {group.message && group.message !== group.code ? <p>{group.message}</p> : null}
    <p className="note">{group.location || 'Unknown location'}{group.versions.length ? ` · app ${group.versions.join(', ')}` : ''}{group.os.length ? ` · ${group.os.map(osName).join(', ')}` : ''} · first {group.first}</p>
    <details>
      <summary>Details and recent times</summary>
      {group.detail ? <pre>{group.detail}</pre> : null}
      <ul className="note">{group.recent.map(row => <li key={row.at + row.version}>{row.at} · {row.version || 'server'}{row.os ? ` · ${osName(row.os)}` : ''} · {row.location}</li>)}</ul>
    </details>
    <div className="actions">
      <CopyButton text={errorsForAI([group])} label="Copy for AI" />
      <form action={group.open ? markFixed : reopen}>
        <input type="hidden" name="fingerprint" value={group.fingerprint} />
        <button className="admin-button" type="submit">{group.open ? 'Mark fixed' : 'Reopen'}</button>
      </form>
    </div>
  </div>;
}

export default async function ErrorsPage({ searchParams }: { searchParams: Promise<{ env?: string; platform?: string }> }) {
  await requireAdmin();
  const params = await searchParams;
  const all = params.env === 'all';
  const platform = toPlatform(params.platform);
  const groups = await loadErrors(all, platform);
  const open = groups.filter(group => group.open), fixed = groups.filter(group => !group.open);
  const query = adminQuery(all, platform);
  return <>
    <header>
      <div>
        <h1>Errors</h1>
        <p className="note">Last 90 days · {scopeLabel(all, platform)}, plus the server · Pacific time. Matching errors are grouped; Mark fixed hides a group until it happens again.</p>
      </div>
      <nav className="nav">
        <Link className="pill" href={`/admin${query}`}>← Stats</Link>
        <FilterPills path="/admin/errors" all={all} platform={platform} />
      </nav>
    </header>
    <section>
      <h2>Open ({open.length})</h2>
      {open.length ? <div className="actions"><CopyButton primary text={errorsForAI(open)} label={`Copy all ${open.length} for AI`} /></div> : <p className="empty">No open errors.</p>}
      {open.map(group => <ErrorCard key={group.fingerprint} group={group} />)}
    </section>
    {fixed.length ? <section>
      <h2>Marked fixed ({fixed.length})</h2>
      {fixed.map(group => <ErrorCard key={group.fingerprint} group={group} />)}
    </section> : null}
  </>;
}
