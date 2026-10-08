import Link from 'next/link';
import { loadDashboard, ADMIN_TIME_ZONE, type Weekly } from '@/server/admin-data';
import { requireAdmin } from './require-admin';
export const dynamic = 'force-dynamic';

const methodNames: Record<string, string> = {
  quickAdd: 'Quick Add', searchHistory: 'Search · past foods', searchBuiltIn: 'Search · built-in foods', searchOnline: 'Search · online',
  manual: 'Manual (typed calories)', meal: 'Saved meals', barcode: 'Barcode Scan', mealScan: 'Meal Scan', voice: 'Voice Log',
  siri: 'Siri', copy: 'Duplicate / copy', other: 'Other',
};
const scanNames: Record<string, string> = { mealScan: 'Meal Scan', voice: 'Voice Log', barcode: 'Barcode Scan', recipe: 'Recipe import (link)', recipePhoto: 'Recipe import (photo)', recipeText: 'Recipe import (pasted text)', siri: 'Siri Log Food', voiceTyped: 'Voice Log (typed instead)' };
const triggerNames: Record<string, string> = {
  onboarding: 'Offer after setup', mealScanOpen: 'Meal Scan opened, no scans left', mealScanAnalyze: 'Meal Scan at Analyze',
  voiceOpen: 'Voice Log opened, no scans left', voiceAnalyze: 'Voice Log at Analyze',
  newMealPhotoOpen: 'New Meal · Snap opened', newMealPhotoAnalyze: 'New Meal · Snap at Analyze',
  newMealVoiceOpen: 'New Meal · Say opened', newMealVoiceAnalyze: 'New Meal · Say at Analyze',
  recipeImportOpen: 'Import a recipe opened', recipeImport: 'Import a recipe at Import',
  progressPhotos: 'Progress Photos, second photo of a day',
  settings: 'Cave Cals+ card in Settings', aboutYou: 'Cave Cals+ card in About You', siri: 'Siri, out of scans (spoken, no screen)',
};
const steps: [string, string][] = [
  ['welcome', 'Welcome'], ['aboutYou', 'Tell About You'], ['measurements', 'Measurements'], ['usualWeek', 'Usual Week'],
  ['setGoal', 'Set Goal'], ['tracking', 'Tracking'], ['target', 'Your target'],
];
const traitNames: [string, string][] = [
  ['goal', 'Has a calorie goal'], ['tracksWeight', 'Tracks weight'], ['tracksMacros', 'Tracks macros'], ['plus', 'Cave Cals+ member'],
  ['healthCalories', 'Shares food with Apple Health'], ['healthWeights', 'Shares weigh-ins with Apple Health'],
  ['reminders', 'Log reminders on'], ['widget', 'Has a widget'], ['iCloud', 'iCloud sync on'],
  ['quickStart', 'Quick Start on'], ['doneEatingButton', '“Done eating” button on'],
];

const n = (value: number | null | undefined, digits = 0) =>
  value == null || !Number.isFinite(value) ? '–' : value.toLocaleString('en-US', { maximumFractionDigits: digits, minimumFractionDigits: digits });
const pct = (part: number, whole: number) => (whole > 0 ? `${Math.round((part / whole) * 100)}%` : '–');

function Tile({ value, label, children }: { value: React.ReactNode; label: string; children?: React.ReactNode }) {
  return <div className="tile"><b>{value}</b><span>{label}</span>{children}</div>;
}
function Change({ now, before }: { now: number; before: number }) {
  if (!before) return null;
  const change = Math.round(((now - before) / before) * 100);
  return <span className={change >= 0 ? 'up' : 'down'}>{change >= 0 ? '▲' : '▼'} {Math.abs(change)}% vs prior</span>;
}
function WeekTiles({ weeks, noun }: { weeks: Weekly; noun: string }) {
  return <div className="tiles">
    <Tile value={n(weeks.thisWeek)} label={`${noun} this week (so far)`} />
    <Tile value={n(weeks.lastWeek)} label={`${noun} last week`}><Change now={weeks.lastWeek} before={weeks.weekBefore} /></Tile>
    <Tile value={n(weeks.weekBefore)} label={`${noun} the week before`} />
  </div>;
}
function Bars({ rows, format = (value: number) => n(value) }: { rows: { label: string; value: number; note?: string }[]; format?: (value: number) => string }) {
  const max = Math.max(1, ...rows.map(row => row.value));
  if (!rows.length) return <p className="empty">Nothing yet.</p>;
  return <div className="bars">{rows.map(row =>
    <div className="bar" key={row.label}>
      <span className="label" title={row.label}>{row.label}</span>
      <span className="track"><span className="fill" style={{ width: `${(row.value / max) * 100}%`, display: 'block' }} /></span>
      <span className="value">{format(row.value)}{row.note ? ` · ${row.note}` : ''}</span>
    </div>)}</div>;
}
const weekday = (day: string) => new Date(`${day}T12:00:00Z`).toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric', timeZone: 'UTC' });

export default async function StatsPage({ searchParams }: { searchParams: Promise<{ env?: string }> }) {
  await requireAdmin();
  const all = (await searchParams).env === 'all';
  const d = await loadDashboard(all);
  const query = all ? '?env=all' : '';
  const itemsAll = d.methods.reduce((sum, row) => sum + row.allTime, 0);
  const items30 = d.methods.reduce((sum, row) => sum + row.last30, 0);
  const search30 = d.methods.filter(row => row.metric.startsWith('search')).reduce((sum, row) => sum + row.last30, 0);
  const stepCounts = Object.fromEntries(d.funnel.map(row => [row.step, row.people]));
  const choices = Object.fromEntries(d.choices.map(row => [row.choice, row.people]));
  const started = d.finished.started;
  const friction = d.friction;
  const items30Friction = Object.entries(friction).filter(([metric]) => metric.startsWith('items.')).reduce((sum, [, value]) => sum + value, 0);
  const updated = new Date().toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', timeZone: ADMIN_TIME_ZONE });
  const errors7 = d.errorAreas.reduce((sum, row) => sum + row.week, 0);

  return <>
    <header>
      <div>
        <h1>Cave Cals stats</h1>
        <p className="note">{all ? 'All builds, including TestFlight and Xcode' : 'App Store installs only'} · Pacific time · weeks start Monday · updated {updated}</p>
      </div>
      <nav className="nav">
        <Link className={`pill${all ? '' : ' on'}`} href="/admin">App Store</Link>
        <Link className={`pill${all ? ' on' : ''}`} href="/admin?env=all">All builds</Link>
        <Link className="pill" href={`/admin/errors${query}`}>Errors · {n(errors7)} this week</Link>
        <Link className="pill" href={`/admin/codes${query}`}>Discount codes</Link>
      </nav>
    </header>

    <section>
      <h2>Overview</h2>
      <div className="tiles">
        <Tile value={n(d.headline.activeToday)} label="Active today" />
        <Tile value={n(d.headline.active7)} label="Active, last 7 days" />
        <Tile value={n(d.headline.active30)} label="Active, last 30 days" />
        <Tile value={n(d.headline.logging7)} label="Logged food, last 7 days" />
        <Tile value={n(d.headline.installs)} label={`Reporting iPhones (${n(d.headline.existing)} had the app before stats)`} />
      </div>
      <p className="note">Active means opened the app or logged food that day. Stats start with version 1.0.5; people who had the app before then are counted from their earliest diary entry, not as new users.</p>
    </section>

    <div className="grid">
      <section>
        <h2>1 · New users</h2>
        <Bars rows={d.newByDay.map(row => ({ label: weekday(row.day), value: row.people }))} />
        <h3>By week</h3>
        <WeekTiles weeks={d.newByWeek} noun="New users" />
      </section>

      <section>
        <h2>2 · Items per day</h2>
        <div className="tiles">
          <Tile value={n(d.perDay7.average, 1)} label={`Per person, on days they logged (7 days · ${n(d.perDay7.people)} people)`} />
          <Tile value={n(d.perDay30.average, 1)} label={`Same, last 30 days (${n(d.perDay30.people)} people)`} />
          <Tile value={n(d.perDay30.activeAverage, 1)} label={`Active loggers: ${n(d.perDay30.activePeople)} people averaging more than 5 a day (30 days)`} />
          <Tile value={n(d.perDay30.daysPerWeek, 1)} label="Logging days per week, people who logged (30 days)" />
        </div>
      </section>
    </div>

    <section>
      <h2>3 · Items added</h2>
      <WeekTiles weeks={d.itemsByWeek} noun="Items" />
      <div className="tiles" style={{ marginTop: 10 }}>
        <Tile value={n(d.itemsByWeek.allTime)} label="Items, all time (includes history from before stats)" />
        <Tile value={n(d.lifetime.average, 0)} label={`Average per person who logged (${n(d.lifetime.loggers)} of ${n(d.lifetime.people)})`} />
        <Tile value={n(d.lifetime.median, 0)} label="Median per person who logged" />
      </div>
      <div className="grid">
        <div>
          <h3>People by lifetime items</h3>
          <Bars rows={d.buckets.map(row => ({ label: `${row.bucket} items`, value: row.people }))} />
        </div>
        <div>
          <h3>Top 25 by lifetime items</h3>
          <div className="scroll"><table>
            <thead><tr><th>iPhone</th><th>Started</th><th>Items</th><th>Days</th><th>Last logged</th><th>Version</th></tr></thead>
            <tbody>{d.topUsers.map(user => <tr key={user.id}>
              <td><code>{user.id.slice(0, 8)}</code>{user.plus === 'true' ? <span className="tag">+</span> : null}</td>
              <td>{user.startedAt}{user.existing ? '*' : ''}</td><td>{n(user.items)}</td><td>{n(user.days)}</td>
              <td>{user.lastLogged ?? '–'}</td><td>{user.version}</td>
            </tr>)}</tbody>
          </table></div>
          <p className="note">* Had the app before stats. + Cave Cals+ member.</p>
        </div>
      </div>
    </section>

    <section>
      <h2>4a · Paywall views</h2>
      <div className="scroll"><table>
        <thead><tr><th>What showed it (last 30 days)</th><th>Views</th><th>People</th><th>Bought</th><th>Trials</th><th>Restored</th><th>Closed</th><th>Converted</th><th>All-time views</th><th>All-time bought</th></tr></thead>
        <tbody>{d.paywalls.map(row => <tr key={row.trigger}>
          <td>{triggerNames[row.trigger] ?? row.trigger}</td><td>{n(row.shown)}</td><td>{n(row.people)}</td><td>{n(row.bought)}</td><td>{n(row.trials)}</td>
          <td>{n(row.restored)}</td><td>{n(row.closed)}</td><td>{pct(row.bought, row.shown)}</td><td>{n(row.shownAll)}</td><td>{n(row.boughtAll)}</td>
        </tr>)}</tbody>
      </table></div>
      {!d.paywalls.length && <p className="empty">No paywall views yet.</p>}
      <p className="note">Bought includes free trials started. Revenue and renewals stay in RevenueCat.</p>
    </section>

    <section>
      <h2>4b · Setup funnel (new users, last 30 days)</h2>
      <div className="grid">
        <div>
          <Bars rows={[
            { label: 'New users', value: started, note: '100%' },
            ...steps.map(([step, label]) => ({ label, value: stepCounts[step] ?? 0, note: pct(stepCounts[step] ?? 0, started) })),
            { label: 'Finished setup', value: d.finished.finished, note: pct(d.finished.finished, started) },
            { label: 'Saw the offer', value: d.finished.offerShown, note: pct(d.finished.offerShown, started) },
            { label: 'Bought from the offer', value: d.finished.offerBought, note: pct(d.finished.offerBought, started) },
            { label: 'Logged food', value: d.finished.logged, note: pct(d.finished.logged, started) },
            { label: 'Logged on 3+ days', value: d.finished.loggedThreeDays, note: pct(d.finished.loggedThreeDays, started) },
          ]} />
          <p className="note">Percentages are of all new users from the last 30 days. “Just start tracking” skips from Welcome to Tracking.</p>
        </div>
        <div>
          <h3>Welcome choice</h3>
          <Bars rows={[
            { label: 'Build Plan', value: choices.buildPlan ?? 0 },
            { label: 'Just start tracking', value: choices.justStart ?? 0 },
            { label: '…then skipped the plan', value: choices.skipConfirmed ?? 0 },
            { label: '…then built a plan', value: choices.skipDeclined ?? 0 },
          ]} />
          <h3>How setup finished</h3>
          <Bars rows={[
            { label: 'Calculated plan', value: d.finished.plan }, { label: 'Own target', value: d.finished.manual },
            { label: 'No goal', value: d.finished.none }, { label: 'Goal: lose', value: d.finished.lose }, { label: 'Goal: maintain', value: d.finished.maintain },
          ]} />
        </div>
      </div>
    </section>

    <section>
      <h2>5 · Logging methods</h2>
      <div className="grid">
        <div>
          <h3>Scans</h3>
          <div className="scroll"><table>
            <thead><tr><th>Kind</th><th>30 days</th><th>All time</th><th>Errors (30 days)</th><th>Error rate</th></tr></thead>
            <tbody>{d.scans.map(row => <tr key={row.metric}>
              <td>{scanNames[row.metric] ?? row.metric}</td><td>{n(row.last30)}</td><td>{n(row.allTime)}</td><td>{n(row.errors30)}</td>
              <td>{pct(row.errors30, row.last30 + row.errors30)}</td>
            </tr>)}</tbody>
          </table></div>
          {!d.scans.length && <p className="empty">No scans yet.</p>}
          <p className="note">A scan is one capture that returned a result; one scan can log several items.</p>
        </div>
        <div>
          <h3>Share of items logged, last 30 days ({n(items30)} items · search {pct(search30, items30)})</h3>
          <Bars rows={d.methods.filter(row => row.last30 > 0).sort((a, b) => b.last30 - a.last30)
            .map(row => ({ label: methodNames[row.metric] ?? row.metric, value: row.last30, note: pct(row.last30, items30) }))} />
          <h3>All time ({n(itemsAll)} items)</h3>
          <Bars rows={d.methods.map(row => ({ label: methodNames[row.metric] ?? row.metric, value: row.allTime, note: pct(row.allTime, itemsAll) }))} />
        </div>
      </div>
    </section>

    <div className="grid">
      <section>
        <h2>Retention by start week</h2>
        <div className="scroll"><table>
          <thead><tr><th>Started week of</th><th>People</th>{[0, 1, 2, 3, 4, 5, 6, 7].map(k => <th key={k}>Wk {k}</th>)}</tr></thead>
          <tbody>{d.cohorts.map(row => <tr key={row.week}>
            <td>{weekday(row.week)}</td><td>{n(row.people)}</td>
            {[0, 1, 2, 3, 4, 5, 6, 7].map(k => <td key={k}>{row[`e${k}`] ? pct(row[`w${k}`], row[`e${k}`]) : ''}</td>)}
          </tr>)}</tbody>
        </table></div>
        {!d.cohorts.length && <p className="empty">No new users yet.</p>}
        <p className="note">Share of each week’s new users who logged food in their week 0, 1, 2… (week 0 is their first 7 days). Blank until that week has passed.</p>
      </section>

      <section>
        <h2>First week</h2>
        <div className="tiles">
          <Tile value={pct(d.activation.dayZero, d.activation.people)} label={`Logged food on day one (${n(d.activation.people)} new users, 7–37 days ago)`} />
          <Tile value={pct(d.activation.threeDays, d.activation.people)} label="Logged on 3+ of their first 7 days" />
        </div>
        <h3>Went quiet ({n(d.quiet.people)} people inactive 7–60 days)</h3>
        <Bars rows={d.quiet.reasons.map(row => ({ label: row.reason, value: row.count, note: pct(row.count, d.quiet.people) }))} />
        <p className="note">The most telling last thing that happened before each person stopped opening the app.</p>
      </section>
    </div>

    <div className="grid">
      <section>
        <h2>How it’s going</h2>
        <div className="tiles">
          {['yes', 'no'].map(answer => {
            const row = d.ratings.find(r => r.answer === answer);
            return <Tile key={answer} value={n(row?.allTime ?? 0)} label={`${answer === 'yes' ? '“Yes! Me like”' : '“Not really”'} (${n(row?.last30 ?? 0)} in 30 days)`} />;
          })}
          <Tile value={n(friction.feedbackTaps ?? 0)} label="Send Feedback taps (30 days)" />
        </div>
        <h3>Last 30 days</h3>
        <div className="tiles">
          <Tile value={pct(friction.searchesAbandoned ?? 0, friction.searches ?? 0)} label={`Searches left without adding (${n(friction.searches ?? 0)} searches)`} />
          <Tile value={n(((friction.edits ?? 0) / Math.max(1, items30Friction)) * 100, 1)} label="Edits per 100 items" />
          <Tile value={n(((friction.deletes ?? 0) / Math.max(1, items30Friction)) * 100, 1)} label="Deletes per 100 items" />
          <Tile value={n(((friction.undos ?? 0) / Math.max(1, items30Friction)) * 100, 1)} label="Undos per 100 items" />
          <Tile value={n(friction.doneEating ?? 0)} label="Done eating taps" />
          <Tile value={n(friction.progressViews ?? 0)} label="Progress views" />
          <Tile value={n(friction.weighIns ?? 0)} label="Weigh-ins saved" />
          <Tile value={n(friction.progressPhotos ?? 0)} label="Progress photos saved" />
          <Tile value={n(friction.photoCompares ?? 0)} label="Photo comparisons opened" />
          <Tile value={n(friction.reminderTaps ?? 0)} label="Reminder notifications tapped" />
          <Tile value={n(friction.mealMoves ?? 0)} label="Foods moved to another meal" />
        </div>
      </section>

      <section>
        <h2>Searches that found nothing (30 days)</h2>
        <div className="scroll"><table>
          <thead><tr><th>Search</th><th>Times</th><th>People</th><th>Last</th></tr></thead>
          <tbody>{d.missing.map(row => <tr key={row.query}><td className="wrap">{row.query}</td><td>{n(row.times)}</td><td>{n(row.people)}</td><td>{row.last}</td></tr>)}</tbody>
        </table></div>
        {!d.missing.length && <p className="empty">None yet.</p>}
        <p className="note">Nothing in past foods, saved meals, built-in foods, or online results.</p>
      </section>
    </div>

    <div className="grid">
      <section>
        <h2>Errors (30 days)</h2>
        <div className="scroll"><table>
          <thead><tr><th>Area</th><th>7 days</th><th>30 days</th><th>People</th></tr></thead>
          <tbody>{d.errorAreas.map(row => <tr key={row.area}><td>{row.area}</td><td>{n(row.week)}</td><td>{n(row.month)}</td><td>{n(row.people)}</td></tr>)}</tbody>
        </table></div>
        {!d.errorAreas.length && <p className="empty">No errors.</p>}
        <p><Link href={`/admin/errors${query}`}>Review errors and copy them for AI →</Link></p>
      </section>

      <section>
        <h2>Setup and features</h2>
        <p className="note">{n(d.traits.people)} iPhones seen in the last 30 days.</p>
        <Bars rows={[
          ...traitNames.map(([trait, label]) => ({ label, value: d.traits[trait] ?? 0, note: pct(d.traits[trait] ?? 0, d.traits.people) })),
          { label: 'Plan: lose', value: d.traits.lose ?? 0, note: pct(d.traits.lose ?? 0, d.traits.people) },
          { label: 'Plan: maintain', value: d.traits.maintain ?? 0, note: pct(d.traits.maintain ?? 0, d.traits.people) },
          { label: 'Meal types, set by time of day', value: d.traits.mealTypesTime ?? 0, note: pct(d.traits.mealTypesTime ?? 0, d.traits.people) },
          { label: 'Meal types, asks each time', value: d.traits.mealTypesAsk ?? 0, note: pct(d.traits.mealTypesAsk ?? 0, d.traits.people) },
        ]} />
      </section>
    </div>

    <div className="grid">
      <section>
        <h2>Versions and devices (30 days)</h2>
        <Bars rows={d.versions.map(row => ({ label: `${row.version} · ${row.device}`, value: row.people }))} />
        <h3>Countries (all time)</h3>
        <Bars rows={d.countries.map(row => ({ label: row.country === '??' ? 'Unknown' : row.country, value: row.people }))} />
      </section>

      <section>
        <h2>AI scans and Cave Cals+</h2>
        <div className="tiles">
          <Tile value={n(d.ai.accounts)} label="AI accounts (iPhones that reached the backend)" />
          <Tile value={n(d.ai.scanned)} label="Used at least one scan" />
          <Tile value={n(d.ai.usedAll)} label="Used all 10 free scans" />
          <Tile value={n(d.ai.scans)} label="Scans, all time" />
          <Tile value={n(d.ai.subscribers)} label="Active Cave Cals+ subscriptions" />
        </div>
        <p className="note">From the AI account tables, which predate stats and include every build.</p>
      </section>
    </div>
  </>;
}
