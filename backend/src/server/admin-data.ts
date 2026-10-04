import { sql, type SQL } from 'drizzle-orm';
import { database } from './db';

/** Days and weeks on the admin pages follow the owner's time zone; weeks start on Monday. */
export const ADMIN_TIME_ZONE = 'America/Los_Angeles';
const TZ = sql.raw(`'${ADMIN_TIME_ZONE}'`);
const TODAY = sql`(now() at time zone ${TZ})::date`;
const WEEK = sql`date_trunc('week', now() at time zone ${TZ})::date`;
const ITEMS = sql.raw(`d.metric like 'items.%'`);

async function rows<T>(query: SQL): Promise<T[]> {
  return (await database().execute(query)).rows as T[];
}

/** App Store installs only, unless TestFlight and Xcode builds are included. */
function installFilter(all: boolean) { return all ? sql`true` : sql`i.environment = 'appstore'`; }

export type Weekly = { thisWeek: number; lastWeek: number; weekBefore: number };
export type Dashboard = Awaited<ReturnType<typeof loadDashboard>>;

export async function loadDashboard(all: boolean) {
  const env = installFilter(all);
  const [
    headline, newByDay, newByWeek, perDay7, perDay30, itemsByWeek, lifetime, topUsers, buckets,
    paywalls, funnel, choices, finished, methods, scans, cohorts, activation, quiet, ratings, friction,
    missing, errorAreas, traits, versions, countries, ai,
  ] = await Promise.all([
    rows<{ installs: number; existing: number; activeToday: number; active7: number; active30: number; logging7: number }>(sql`
      with active as (
        select d.install_id, max(d.day) as last_day, max(d.day) filter (where ${ITEMS} and d.count > 0) as last_logged
        from usage_daily d join usage_installs i on i.id = d.install_id
        where ${env} and d.day > ${TODAY} - 30 group by d.install_id)
      select
        (select count(*)::int from usage_installs i where ${env}) as "installs",
        (select count(*)::int from usage_installs i where ${env} and i.existing_user) as "existing",
        count(*) filter (where last_day >= ${TODAY})::int as "activeToday",
        count(*) filter (where last_day > ${TODAY} - 7)::int as "active7",
        count(*)::int as "active30",
        count(*) filter (where last_logged > ${TODAY} - 7)::int as "logging7"
      from active`),
    rows<{ day: string; people: number }>(sql`
      select g.day::date::text as "day", count(i.id)::int as "people"
      from generate_series(${TODAY} - 6, ${TODAY}, interval '1 day') as g(day)
      left join usage_installs i on (i.started_at at time zone ${TZ})::date = g.day::date and not i.existing_user and ${env}
      group by g.day order by g.day`),
    rows<Weekly>(sql`
      select
        count(*) filter (where s >= ${WEEK})::int as "thisWeek",
        count(*) filter (where s >= ${WEEK} - 7 and s < ${WEEK})::int as "lastWeek",
        count(*) filter (where s >= ${WEEK} - 14 and s < ${WEEK} - 7)::int as "weekBefore"
      from (select (i.started_at at time zone ${TZ})::date as s from usage_installs i where not i.existing_user and ${env}) x`),
    itemsPerDay(env, 7),
    itemsPerDay(env, 30),
    rows<Weekly & { allTime: number }>(sql`
      select
        coalesce(sum(d.count) filter (where d.day >= ${WEEK}), 0)::int as "thisWeek",
        coalesce(sum(d.count) filter (where d.day >= ${WEEK} - 7 and d.day < ${WEEK}), 0)::int as "lastWeek",
        coalesce(sum(d.count) filter (where d.day >= ${WEEK} - 14 and d.day < ${WEEK} - 7), 0)::int as "weekBefore",
        coalesce(sum(d.count), 0)::int as "allTime"
      from usage_daily d join usage_installs i on i.id = d.install_id where ${ITEMS} and ${env}`),
    rows<{ people: number; loggers: number; average: number | null; median: number | null }>(sql`
      with per_user as (
        select i.id, coalesce(sum(d.count) filter (where ${ITEMS}), 0) as items
        from usage_installs i left join usage_daily d on d.install_id = i.id where ${env} group by i.id)
      select count(*)::int as "people", count(*) filter (where items > 0)::int as "loggers",
        avg(items) filter (where items > 0)::float8 as "average",
        percentile_cont(0.5) within group (order by items) filter (where items > 0)::float8 as "median"
      from per_user`),
    rows<{ id: string; startedAt: string; existing: boolean; items: number; days: number; lastLogged: string | null; version: string; plus: string | null }>(sql`
      select i.id::text as "id", to_char(i.started_at at time zone ${TZ}, 'YYYY-MM-DD') as "startedAt", i.existing_user as "existing",
        coalesce(sum(d.count) filter (where ${ITEMS}), 0)::int as "items",
        count(distinct d.day) filter (where ${ITEMS} and d.count > 0)::int as "days",
        max(d.day) filter (where ${ITEMS} and d.count > 0)::text as "lastLogged",
        i.app_version as "version", i.traits->>'plus' as "plus"
      from usage_installs i left join usage_daily d on d.install_id = i.id
      where ${env} group by i.id order by "items" desc, i.started_at limit 25`),
    rows<{ bucket: string; people: number }>(sql`
      with per_user as (
        select i.id, coalesce(sum(d.count) filter (where ${ITEMS}), 0) as items
        from usage_installs i left join usage_daily d on d.install_id = i.id where ${env} group by i.id)
      select b.bucket as "bucket", count(p.id)::int as "people"
      from (values (1, '0', 0, 0), (2, '1–10', 1, 10), (3, '11–50', 11, 50), (4, '51–200', 51, 200), (5, '201+', 201, 2147483647))
        as b(sort, bucket, low, high)
      left join per_user p on p.items between b.low and b.high
      group by b.sort, b.bucket order by b.sort`),
    rows<{ trigger: string; shown: number; people: number; bought: number; trials: number; restored: number; closed: number; shownAll: number; boughtAll: number }>(sql`
      select coalesce(e.props->>'trigger', 'unknown') as "trigger",
        count(*) filter (where e.name = 'paywall.shown' and e.at > now() - interval '30 days')::int as "shown",
        count(distinct e.install_id) filter (where e.name = 'paywall.shown' and e.at > now() - interval '30 days')::int as "people",
        count(*) filter (where e.name = 'paywall.result' and e.props->>'result' in ('purchased', 'trial') and e.at > now() - interval '30 days')::int as "bought",
        count(*) filter (where e.name = 'paywall.result' and e.props->>'result' = 'trial' and e.at > now() - interval '30 days')::int as "trials",
        count(*) filter (where e.name = 'paywall.result' and e.props->>'result' = 'restored' and e.at > now() - interval '30 days')::int as "restored",
        count(*) filter (where e.name = 'paywall.result' and e.props->>'result' in ('closed', 'unavailable') and e.at > now() - interval '30 days')::int as "closed",
        count(*) filter (where e.name = 'paywall.shown')::int as "shownAll",
        count(*) filter (where e.name = 'paywall.result' and e.props->>'result' in ('purchased', 'trial'))::int as "boughtAll"
      from usage_events e join usage_installs i on i.id = e.install_id
      where e.name in ('paywall.shown', 'paywall.result') and ${env}
      group by 1 order by "shownAll" desc`),
    rows<{ step: string; people: number }>(sql`
      select e.props->>'step' as "step", count(distinct e.install_id)::int as "people"
      from usage_events e join usage_installs i on i.id = e.install_id
      where e.name = 'onboarding.step' and not i.existing_user and i.started_at > now() - interval '30 days' and ${env}
      group by 1`),
    rows<{ choice: string; people: number }>(sql`
      select e.props->>'choice' as "choice", count(distinct e.install_id)::int as "people"
      from usage_events e join usage_installs i on i.id = e.install_id
      where e.name = 'onboarding.choice' and not i.existing_user and i.started_at > now() - interval '30 days' and ${env}
      group by 1`),
    rows<{ started: number; finished: number; plan: number; manual: number; none: number; lose: number; maintain: number; offerShown: number; offerBought: number; logged: number; loggedThreeDays: number }>(sql`
      with cohort as (
        select i.id from usage_installs i
        where not i.existing_user and i.started_at > now() - interval '30 days' and ${env}),
      done as (
        select distinct on (e.install_id) e.install_id, e.props from usage_events e join cohort c on c.id = e.install_id
        where e.name = 'onboarding.finished' order by e.install_id, e.at),
      offer as (
        select e.install_id, bool_or(e.name = 'paywall.shown') as shown,
          bool_or(e.name = 'paywall.result' and e.props->>'result' in ('purchased', 'trial')) as bought
        from usage_events e join cohort c on c.id = e.install_id
        where e.name in ('paywall.shown', 'paywall.result') and e.props->>'trigger' = 'onboarding' group by e.install_id),
      logs as (
        select d.install_id, count(distinct d.day) as days from usage_daily d join cohort c on c.id = d.install_id
        where ${ITEMS} and d.count > 0 group by d.install_id)
      select (select count(*)::int from cohort) as "started",
        (select count(*)::int from done) as "finished",
        (select count(*)::int from done where props->>'goal' = 'plan') as "plan",
        (select count(*)::int from done where props->>'goal' = 'manual') as "manual",
        (select count(*)::int from done where props->>'goal' = 'none') as "none",
        (select count(*)::int from done where props->>'intent' = 'lose') as "lose",
        (select count(*)::int from done where props->>'intent' = 'maintain') as "maintain",
        (select count(*)::int from offer where shown) as "offerShown",
        (select count(*)::int from offer where bought) as "offerBought",
        (select count(*)::int from logs) as "logged",
        (select count(*)::int from logs where days >= 3) as "loggedThreeDays"`),
    rows<{ metric: string; last30: number; allTime: number }>(sql`
      select substr(d.metric, 7) as "metric",
        coalesce(sum(d.count) filter (where d.day > ${TODAY} - 30), 0)::int as "last30", sum(d.count)::int as "allTime"
      from usage_daily d join usage_installs i on i.id = d.install_id
      where ${ITEMS} and ${env} group by 1 order by "allTime" desc`),
    rows<{ metric: string; last30: number; allTime: number; errors30: number }>(sql`
      select s.metric as "metric", s.last30::int as "last30", s.all_time::int as "allTime",
        (select count(*)::int from app_errors a left join usage_installs i on i.id = a.install_id
         where a.source = 'app' and a.area = s.metric and a.at > now() - interval '30 days' and ${env}) as "errors30"
      from (
        select substr(d.metric, 7) as metric, coalesce(sum(d.count) filter (where d.day > ${TODAY} - 30), 0) as last30, sum(d.count) as all_time
        from usage_daily d join usage_installs i on i.id = d.install_id
        where d.metric like 'scans.%' and ${env} group by 1) s
      order by s.all_time desc`),
    rows<{ week: string; people: number; [cell: `w${number}` | `e${number}`]: number }>(sql`
      with cohort as (
        select i.id, i.started_day as d0
        from usage_installs i where not i.existing_user and ${env} and i.started_at > now() - interval '8 weeks'),
      act as (
        select distinct d.install_id, d.day from usage_daily d join cohort c on c.id = d.install_id where ${ITEMS} and d.count > 0)
      select date_trunc('week', c.d0)::date::text as "week", count(distinct c.id)::int as "people",
        ${sql.join([0, 1, 2, 3, 4, 5, 6, 7].map(k => sql`
          count(distinct c.id) filter (where c.d0 + ${7 * k + 6}::int <= ${TODAY})::int as ${sql.raw(`"e${k}"`)},
          count(distinct a.install_id) filter (where a.day - c.d0 between ${7 * k}::int and ${7 * k + 6}::int and c.d0 + ${7 * k + 6}::int <= ${TODAY})::int as ${sql.raw(`"w${k}"`)}`), sql`,`)}
      from cohort c left join act a on a.install_id = c.id
      group by 1 order by 1 desc`),
    rows<{ people: number; dayZero: number; threeDays: number }>(sql`
      with cohort as (
        select i.id, i.started_day as d0 from usage_installs i
        where not i.existing_user and ${env} and i.started_at > now() - interval '37 days' and i.started_day <= ${TODAY} - 7),
      first_week as (
        select c.id, count(distinct d.day) filter (where d.day = c.d0) as day_zero, count(distinct d.day) as days
        from cohort c join usage_daily d on d.install_id = c.id
        where ${ITEMS} and d.count > 0 and d.day between c.d0 and c.d0 + 6 group by c.id)
      select (select count(*)::int from cohort) as "people",
        count(*) filter (where day_zero > 0)::int as "dayZero", count(*) filter (where days >= 3)::int as "threeDays"
      from first_week`),
    rows<{ id: string; lastDay: string; items: number; existing: boolean; finishedSetup: boolean; lastStep: string | null; lastEvent: string | null; lastProps: Record<string, unknown> | null; lastError: string | null }>(sql`
      with quiet as (
        select i.id, i.existing_user, max(d.day) as last_day,
          coalesce(sum(d.count) filter (where ${ITEMS}), 0)::int as items
        from usage_installs i join usage_daily d on d.install_id = i.id where ${env}
        group by i.id having max(d.day) between ${TODAY} - 60 and ${TODAY} - 7)
      select q.id::text as "id", q.last_day::text as "lastDay", q.items as "items", q.existing_user as "existing",
        exists (select 1 from usage_events e where e.install_id = q.id and e.name = 'onboarding.finished') as "finishedSetup",
        (select e.props->>'step' from usage_events e where e.install_id = q.id and e.name = 'onboarding.step' order by e.at desc limit 1) as "lastStep",
        le.name as "lastEvent", le.props as "lastProps",
        (select a.area || ' · ' || a.code from app_errors a where a.install_id = q.id and a.at >= q.last_day - 1 order by a.at desc limit 1) as "lastError"
      from quiet q
      left join lateral (select e.name, e.props from usage_events e where e.install_id = q.id order by e.at desc limit 1) le on true`),
    rows<{ answer: string; last30: number; allTime: number }>(sql`
      select e.props->>'answer' as "answer", count(*) filter (where e.at > now() - interval '30 days')::int as "last30", count(*)::int as "allTime"
      from usage_events e join usage_installs i on i.id = e.install_id where e.name = 'rating' and ${env} group by 1`),
    rows<{ metric: string; last30: number }>(sql`
      select d.metric as "metric", sum(d.count)::int as "last30"
      from usage_daily d join usage_installs i on i.id = d.install_id
      where d.day > ${TODAY} - 30 and ${env}
        and (d.metric in ('searches', 'searchesAbandoned', 'edits', 'deletes', 'undos', 'feedbackTaps', 'doneEating', 'progressViews', 'weighIns', 'reminderTaps', 'opens') or ${ITEMS})
      group by 1`),
    rows<{ query: string; times: number; people: number; last: string }>(sql`
      select lower(trim(e.props->>'query')) as "query", count(*)::int as "times", count(distinct e.install_id)::int as "people",
        to_char(max(e.at) at time zone ${TZ}, 'Mon DD') as "last"
      from usage_events e join usage_installs i on i.id = e.install_id
      where e.name = 'search.missing' and e.at > now() - interval '30 days' and ${env}
      group by 1 order by "times" desc, max(e.at) desc limit 40`),
    rows<{ area: string; week: number; month: number; people: number }>(sql`
      select case when a.source = 'server' then 'server · ' || a.area else a.area end as "area", count(*) filter (where a.at > now() - interval '7 days')::int as "week", count(*)::int as "month",
        count(distinct a.install_id)::int as "people"
      from app_errors a left join usage_installs i on i.id = a.install_id
      where a.at > now() - interval '30 days' and (a.install_id is null or ${env})
      group by 1 order by "month" desc`),
    rows<Record<string, number>>(sql`
      select count(*)::int as "people",
        ${sql.join(['goal', 'tracksWeight', 'tracksMacros', 'plus', 'healthCalories', 'healthWeights', 'reminders', 'widget', 'iCloud', 'quickStart', 'doneEatingButton'].map(trait =>
          sql`count(*) filter (where i.traits->>${trait} = 'true')::int as ${sql.raw(`"${trait}"`)}`), sql`, `)},
        count(*) filter (where i.traits->>'intent' = 'lose')::int as "lose",
        count(*) filter (where i.traits->>'intent' = 'maintain')::int as "maintain"
      from usage_installs i where ${env} and i.last_seen_at > now() - interval '30 days'`),
    rows<{ version: string; device: string; people: number }>(sql`
      select i.app_version || ' (' || coalesce(i.traits->>'build', '?') || ')' as "version", i.device as "device", count(*)::int as "people"
      from usage_installs i where ${env} and i.last_seen_at > now() - interval '30 days'
      group by 1, 2 order by "people" desc limit 12`),
    rows<{ country: string; people: number }>(sql`
      select coalesce(i.country, '??') as "country", count(*)::int as "people"
      from usage_installs i where ${env} group by 1 order by 2 desc limit 12`),
    rows<{ accounts: number; scanned: number; usedAll: number; subscribers: number; scans: number }>(sql`
      select count(*)::int as "accounts", count(*) filter (where scans_used > 0)::int as "scanned",
        count(*) filter (where scans_used >= 10)::int as "usedAll",
        count(*) filter (where subscription_expires_at > now())::int as "subscribers",
        coalesce(sum(scans_used), 0)::int as "scans"
      from ai_accounts where id not in ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000002')`),
  ]);
  return {
    headline: headline[0], newByDay, newByWeek: newByWeek[0], perDay7: perDay7[0], perDay30: perDay30[0],
    itemsByWeek: itemsByWeek[0], lifetime: lifetime[0], topUsers, buckets, paywalls, funnel, choices,
    finished: finished[0], methods, scans, cohorts, activation: activation[0], quiet: quietReasons(quiet),
    ratings, friction: Object.fromEntries(friction.map(row => [row.metric, row.last30])) as Record<string, number>,
    missing, errorAreas, traits: traits[0], versions, countries, ai: ai[0],
  };
}

/** Average items per day for people on the days they logged, plus the same for people averaging more than five. */
function itemsPerDay(env: SQL, days: number) {
  return rows<{ people: number; personDays: number; average: number | null; activePeople: number; activeAverage: number | null; daysPerWeek: number | null }>(sql`
    with per_day as (
      select d.install_id, d.day, sum(d.count) as items
      from usage_daily d join usage_installs i on i.id = d.install_id
      where ${ITEMS} and d.day > ${TODAY} - ${days}::int and ${env}
      group by d.install_id, d.day having sum(d.count) > 0),
    per_user as (select install_id, sum(items) as items, count(*) as days from per_day group by install_id)
    select count(*)::int as "people", coalesce(sum(days), 0)::int as "personDays",
      (sum(items)::float8 / nullif(sum(days), 0)) as "average",
      count(*) filter (where items::float8 / days > 5)::int as "activePeople",
      (sum(items) filter (where items::float8 / days > 5))::float8 / nullif(sum(days) filter (where items::float8 / days > 5), 0) as "activeAverage",
      (avg(days)::float8 * 7 / ${days}::int) as "daysPerWeek"
    from per_user`);
}

const stepNames: Record<string, string> = {
  welcome: 'the welcome', aboutYou: 'Tell About You', measurements: 'Measurements', usualWeek: 'Usual Week',
  setGoal: 'Set Goal', tracking: 'Tracking', target: 'Your target',
};

/** Sorts people who went quiet (no activity for 7–60 days) by the most telling thing that happened last. */
function quietReasons(people: { items: number; existing: boolean; finishedSetup: boolean; lastStep: string | null; lastEvent: string | null; lastProps: Record<string, unknown> | null; lastError: string | null }[]) {
  const counts = new Map<string, number>();
  for (const person of people) {
    let reason: string;
    if (!person.existing && !person.finishedSetup && person.lastStep) reason = `Left setup at ${stepNames[person.lastStep] ?? person.lastStep}`;
    else if (person.items <= 0) reason = 'Never logged food';
    else if (person.lastEvent === 'paywall.result' && person.lastProps?.result !== 'purchased' && person.lastProps?.result !== 'trial')
      reason = `Closed the paywall last (${person.lastProps?.trigger ?? 'unknown'})`;
    else if (person.lastError) reason = `Hit an error last: ${person.lastError}`;
    else if (person.lastEvent === 'rating' && person.lastProps?.answer === 'no') reason = 'Said “Not really” to Cave Cals good?';
    else if (person.items <= 5) reason = 'Logged 1–5 foods, then stopped';
    else if (person.items <= 50) reason = 'Logged 6–50 foods, then stopped';
    else reason = 'Logged 50+ foods, then stopped';
    counts.set(reason, (counts.get(reason) ?? 0) + 1);
  }
  return { people: people.length, reasons: [...counts].map(([reason, count]) => ({ reason, count })).sort((a, b) => b.count - a.count) };
}

export type ErrorGroup = {
  fingerprint: string; source: string; area: string; code: string; message: string; location: string; detail: string;
  total: number; week: number; people: number; first: string; last: string; versions: string[]; os: string[];
  resolvedAt: string | null; sinceFix: number;
};

export async function loadErrors(all: boolean) {
  const env = installFilter(all);
  const [groups, recent] = await Promise.all([
    rows<ErrorGroup>(sql`
      select a.fingerprint as "fingerprint", max(a.source) as "source", max(a.area) as "area", max(a.code) as "code",
        (array_agg(a.message order by a.at desc))[1] as "message", (array_agg(a.location order by a.at desc))[1] as "location",
        (array_agg(a.detail order by a.at desc))[1] as "detail",
        count(*)::int as "total", count(*) filter (where a.at > now() - interval '7 days')::int as "week",
        count(distinct a.install_id)::int as "people",
        to_char(min(a.at) at time zone ${TZ}, 'Mon DD, HH12:MI AM') as "first", to_char(max(a.at) at time zone ${TZ}, 'Mon DD, HH12:MI AM') as "last",
        array_remove(array_agg(distinct nullif(a.app_version, '')), null) as "versions",
        array_remove(array_agg(distinct nullif(a.os_version, '')), null) as "os",
        to_char(r.resolved_at at time zone ${TZ}, 'Mon DD') as "resolvedAt",
        count(*) filter (where r.resolved_at is not null and a.at > r.resolved_at)::int as "sinceFix"
      from app_errors a
      left join error_resolutions r on r.fingerprint = a.fingerprint
      left join usage_installs i on i.id = a.install_id
      where a.at > now() - interval '90 days' and (a.install_id is null or ${env})
      group by a.fingerprint, r.resolved_at
      order by max(a.at) desc limit 300`),
    rows<{ fingerprint: string; at: string; version: string; os: string; location: string; message: string }>(sql`
      select fingerprint as "fingerprint", to_char(at at time zone ${TZ}, 'Mon DD, HH12:MI AM') as "at",
        app_version as "version", os_version as "os", location as "location", message as "message"
      from (
        select a.*, row_number() over (partition by a.fingerprint order by a.at desc) as n
        from app_errors a left join usage_installs i on i.id = a.install_id
        where a.at > now() - interval '90 days' and (a.install_id is null or ${env})) ranked
      where n <= 5 order by at desc`),
  ]);
  const occurrences = new Map<string, typeof recent>();
  for (const row of recent) occurrences.set(row.fingerprint, [...(occurrences.get(row.fingerprint) ?? []), row]);
  return groups.map(group => ({ ...group, open: !group.resolvedAt || group.sinceFix > 0, recent: occurrences.get(group.fingerprint) ?? [] }));
}

/** Plain text an AI coding assistant can work from: one section per open error group. */
export function errorsForAI(groups: (ErrorGroup & { recent: { at: string; version: string; os: string }[] })[]) {
  const header = [
    '# Cave Cals error report',
    '',
    'Each section is one group of matching errors from the last 90 days.',
    'App errors come from the iOS app in this repository: `location` is the Swift file and line that reported it.',
    'Server errors come from the Next.js backend in `backend/src`: `location` is the API path and `detail` holds stack frames (messages are not stored).',
    'Please find the cause of each and fix it where possible.',
  ].join('\n');
  const sections = groups.map(group => [
    `## ${group.source === 'server' ? 'Server' : 'App'} · ${group.area} · ${group.code}`,
    `- Message: ${group.message || '(none)'}`,
    `- Where: ${group.location || '(unknown)'}`,
    `- Count: ${group.total} total, ${group.week} in the last 7 days, ${group.people} ${group.people === 1 ? 'person' : 'people'}`,
    `- First seen: ${group.first}; last seen: ${group.last} (Pacific)`,
    group.versions.length ? `- App versions: ${group.versions.join(', ')}` : '',
    group.os.length ? `- iOS versions: ${group.os.join(', ')}` : '',
    group.resolvedAt ? `- Marked fixed ${group.resolvedAt}; happened ${group.sinceFix} time(s) since` : '',
    group.detail ? `- Detail:\n\n\`\`\`\n${group.detail}\n\`\`\`` : '',
  ].filter(Boolean).join('\n'));
  return [header, ...sections].join('\n\n');
}
