import Link from 'next/link';
import { loadErrors, errorsForAI } from '@/server/admin-data';
import { requireAdmin } from '../require-admin';
import { markFixed, reopen } from '../actions';
import CopyButton from '../copy-button';
export const dynamic = 'force-dynamic';

type Group = Awaited<ReturnType<typeof loadErrors>>[number];

function ErrorCard({ group }: { group: Group }) {
  return <div className="error-card">
    <h3>{group.source === 'server' ? 'Server' : 'App'} · {group.area} · <code>{group.code}</code>
      {group.resolvedAt && group.open ? <span className="tag">Back after fix on {group.resolvedAt}</span> : null}</h3>
    <p><b>{group.week}</b> in 7 days · <b>{group.total}</b> in 90 days · {group.people} {group.people === 1 ? 'person' : 'people'} · last {group.last}</p>
    {group.message && group.message !== group.code ? <p>{group.message}</p> : null}
    <p className="note">{group.location || 'Unknown location'}{group.versions.length ? ` · app ${group.versions.join(', ')}` : ''}{group.os.length ? ` · iOS ${group.os.join(', ')}` : ''} · first {group.first}</p>
    <details>
      <summary>Details and recent times</summary>
      {group.detail ? <pre>{group.detail}</pre> : null}
      <ul className="note">{group.recent.map(row => <li key={row.at + row.version}>{row.at} · {row.version || 'server'}{row.os ? ` · iOS ${row.os}` : ''} · {row.location}</li>)}</ul>
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

export default async function ErrorsPage({ searchParams }: { searchParams: Promise<{ env?: string }> }) {
  await requireAdmin();
  const all = (await searchParams).env === 'all';
  const groups = await loadErrors(all);
  const open = groups.filter(group => group.open), fixed = groups.filter(group => !group.open);
  const query = all ? '?env=all' : '';
  return <>
    <header>
      <div>
        <h1>Errors</h1>
        <p className="note">Last 90 days · {all ? 'all builds' : 'App Store installs and the server'} · Pacific time. Matching errors are grouped; Mark fixed hides a group until it happens again.</p>
      </div>
      <nav className="nav">
        <Link className="pill" href={`/admin${query}`}>← Stats</Link>
        <Link className={`pill${all ? '' : ' on'}`} href="/admin/errors">App Store</Link>
        <Link className={`pill${all ? ' on' : ''}`} href="/admin/errors?env=all">All builds</Link>
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
