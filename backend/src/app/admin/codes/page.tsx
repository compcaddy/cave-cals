import Link from 'next/link';
import { loadCodesPage, prettyCode, SITE, type CodeStats } from '@/server/discount-codes';
import { requireAdmin } from '../require-admin';
import CopyButton from '../copy-button';
import { saveCode, setCodeActive } from './actions';
export const dynamic = 'force-dynamic';

const sourceNames: Record<string, string> = {
  trainer: 'Trainer or coach', social: 'Social media', friend: 'Friend or family', appStore: 'App Store',
  google: 'Google search', ai: 'AI (ChatGPT, Claude…)', other: 'Other', skipped: 'Skipped the question',
};
const n = (value: number) => value.toLocaleString('en-US');
const pct = (part: number, whole: number) => (whole > 0 ? `${Math.round((part / whole) * 100)}%` : '–');

function Counts({ week, month, all }: { week: number; month: number; all: number }) {
  return <>{n(week)} · {n(month)} · <b>{n(all)}</b></>;
}

function CodeForm({ row }: { row?: CodeStats }) {
  return <form action={saveCode} className="code-form">
    {row ? <><input type="hidden" name="editing" value="1" /><input type="hidden" name="code" value={row.code} /></> : null}
    <label>Name<input type="text" name="name" required maxLength={60} defaultValue={row?.name} placeholder="Sarah" /></label>
    {row ? null : <label>Code<input type="text" name="code" required maxLength={30} placeholder="SARAH" autoCapitalize="characters" autoComplete="off" /></label>}
    <label>Campaign token (ct)<input type="text" name="campaign" maxLength={40} defaultValue={row?.campaign} placeholder="Same as the code" autoComplete="off" /></label>
    <label>RevenueCat offering<input type="text" name="offering" maxLength={64} defaultValue={row?.offering ?? 'discount'} autoComplete="off" /></label>
    <label className="check"><input type="checkbox" name="active" defaultChecked={row?.active ?? true} /> Active</label>
    <button className="admin-button primary" type="submit">{row ? 'Save' : 'Add code'}</button>
  </form>;
}

export default async function CodesPage({ searchParams }: { searchParams: Promise<{ env?: string; error?: string; saved?: string }> }) {
  await requireAdmin();
  const params = await searchParams;
  const all = params.env === 'all';
  const { codes, sources, others } = await loadCodesPage(all);
  const query = all ? '?env=all' : '';
  const asked30 = sources.reduce((sum, row) => sum + row.last30, 0);
  const askedAll = sources.reduce((sum, row) => sum + row.allTime, 0);
  const total = (key: keyof CodeStats) => codes.reduce((sum, row) => sum + Number(row[key]), 0);

  return <>
    <header>
      <div>
        <h1>Discount codes</h1>
        <p className="note">Pages at {SITE}/&lt;name&gt; in any capitalization · Pacific days · counts shown as 7 days · 30 days · <b>all time</b>.</p>
      </div>
      <nav className="nav">
        <Link className="pill" href={`/admin${query}`}>← Stats</Link>
        <Link className={`pill${all ? '' : ' on'}`} href="/admin/codes">App Store</Link>
        <Link className={`pill${all ? ' on' : ''}`} href="/admin/codes?env=all">All builds</Link>
      </nav>
    </header>
    {params.error ? <p className="form-error" role="alert">{params.error}</p> : null}
    {params.saved ? <p className="note">Saved {params.saved}.</p> : null}

    <section>
      <h2>Add a code</h2>
      <CodeForm />
      <p className="note">Letters and digits only; capitals don’t matter (Sarah, sarah, and SARAH are the same code). The campaign token is what App Store Connect reports the code’s App Store visits under. Every code uses the <code>discount</code> offering unless you set another RevenueCat offering.</p>
    </section>

    <section>
      <h2>Codes</h2>
      {codes.length ? <div className="scroll"><table>
        <thead><tr>
          <th>Code</th><th>Page visits</th><th>App Store taps</th><th>Applied</th><th>iPhones applied</th><th>Bought with code</th><th />
        </tr></thead>
        <tbody>{codes.map(row => {
          const link = `${SITE}/${prettyCode(row.code, row.name)}`;
          return <tr key={row.code}>
            <td className="wrap">
              <b>{row.code}</b>{row.active ? null : <span className="tag">Paused</span>}<br />
              <span className="note">{row.name} · <a href={`https://${link}`}>{link}</a> · ct <code>{row.campaign}</code>{row.offering !== 'discount' ? <> · offering <code>{row.offering}</code></> : null}</span>
              <details><summary>Edit</summary><CodeForm row={row} /></details>
            </td>
            <td><Counts week={row.visits7} month={row.visits30} all={row.visitsAll} /></td>
            <td><Counts week={row.taps7} month={row.taps30} all={row.tapsAll} /></td>
            <td><Counts week={row.applies7} month={row.applies30} all={row.appliesAll} /></td>
            <td>{n(row.appliedInApp)}</td>
            <td>{n(row.purchases)}</td>
            <td><div className="actions">
              <CopyButton text={`https://${link}`} label="Copy link" />
              <form action={setCodeActive}>
                <input type="hidden" name="code" value={row.code} />
                <input type="hidden" name="active" value={row.active ? '0' : '1'} />
                <button className="admin-button" type="submit">{row.active ? 'Pause' : 'Resume'}</button>
              </form>
            </div></td>
          </tr>;
        })}</tbody>
        <tfoot><tr>
          <td>Total</td>
          <td><Counts week={total('visits7')} month={total('visits30')} all={total('visitsAll')} /></td>
          <td><Counts week={total('taps7')} month={total('taps30')} all={total('tapsAll')} /></td>
          <td><Counts week={total('applies7')} month={total('applies30')} all={total('appliesAll')} /></td>
          <td>{n(total('appliedInApp'))}</td>
          <td>{n(total('purchases'))}</td>
          <td />
        </tr></tfoot>
      </table></div> : <p className="empty">No codes yet. Add one above.</p>}
      <p className="note"><b>Page visits</b> and <b>App Store taps</b> come from the code’s page (link previews and crawlers aren’t counted). <b>Applied</b> counts every successful Apply in the app, from any build. <b>iPhones applied</b> and <b>Bought with code</b> (Cave Cals+ purchases or trials started while the code was applied) come from anonymous usage stats, so people who turned stats off are missing.</p>
      <p className="note">Apple’s numbers for each campaign token (product page views, first-time downloads, sales) are in App Store Connect → Analytics → Acquisition → Campaigns. Apple only counts people who share analytics with developers and hides small numbers.</p>
    </section>

    <section>
      <h2>Where did you find Cave Cals?</h2>
      {sources.length ? <div className="scroll"><table>
        <thead><tr><th>Answer</th><th>30 days</th><th>Share</th><th>All time</th><th>Share</th></tr></thead>
        <tbody>{sources.map(row => <tr key={row.source}>
          <td>{sourceNames[row.source] ?? row.source}</td>
          <td>{n(row.last30)}</td><td>{pct(row.last30, asked30)}</td>
          <td>{n(row.allTime)}</td><td>{pct(row.allTime, askedAll)}</td>
        </tr>)}</tbody>
      </table></div> : <p className="empty">Nobody has seen the question yet.</p>}
      <p className="note">Asked once, after setup and before the Cave Cals+ offer. Shares include people who skipped.</p>
      {others.length ? <>
        <h3>Other answers (latest {others.length})</h3>
        <ul className="other-answers">{others.map((row, index) => <li key={index}><span className="note">{row.day}</span> {row.text}</li>)}</ul>
      </> : null}
    </section>
  </>;
}
