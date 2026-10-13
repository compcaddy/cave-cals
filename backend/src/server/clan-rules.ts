// Clan scoring (Documentation/Clans.md). Pure functions only, so every rule is unit-tested: what counts as a
// made day, when a day locks, accountability cells, and how each challenge type scores and ends.
import { z } from 'zod';

export type Day = string; // YYYY-MM-DD, the person's own calendar day
export type DayReport = { logged: boolean; fullDay: boolean; percentOfGoal: number | null; goalOk: boolean; doneEating: boolean };

// What "on target" means. Only percentages: the server never knows calories or goals.
export const clanRuleSchema = z.object({
  kind: z.enum(['atOrUnder', 'withinPercent', 'upToPercentOver']),
  percent: z.number().int().min(1).max(50).default(5),
});
export type ClanRule = z.infer<typeof clanRuleSchema>;
export const DEFAULT_RULE: ClanRule = { kind: 'atOrUnder', percent: 5 };

export const CHALLENGE_KINDS = ['loggingDays', 'onTargetDays', 'teamTotal', 'survivor', 'streak', 'weightLoss'] as const;
export type ChallengeKind = typeof CHALLENGE_KINDS[number];
export const SAVES_PERIODS = ['week', 'month', 'challenge'] as const;
export type SavesPeriod = typeof SAVES_PERIODS[number];
export const challengeSettingsSchema = z.object({
  // Which days count: a full logged day (or any food, when the admin allows it), or an on-target day.
  basis: z.enum(['logging', 'onTarget']).default('logging'),
  anyFood: z.boolean().default(false),
  rule: clanRuleSchema.optional(),
  streakMode: z.enum(['everyone', 'percent']).default('everyone'),
  streakPercent: z.number().int().min(10).max(100).default(80),
  teamTarget: z.number().int().min(1).max(10000).default(100),
}).default({ basis: 'logging', anyFood: false, streakMode: 'everyone', streakPercent: 80, teamTarget: 100 });
export type ChallengeSettings = z.infer<typeof challengeSettingsSchema>;

// MARK: Days and time zones

export function validTimeZone(zone: string): boolean {
  try { new Intl.DateTimeFormat('en-US', { timeZone: zone }); return zone.length <= 64; } catch { return false; }
}
function parts(now: Date, timeZone: string) {
  const values = Object.fromEntries(new Intl.DateTimeFormat('en-CA', {
    timeZone, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).formatToParts(now).map(p => [p.type, p.value]));
  return { day: `${values.year}-${values.month}-${values.day}`, hour: Number(values.hour), minute: Number(values.minute) };
}
export const localDay = (now: Date, timeZone: string): Day => parts(now, timeZone).day;
export const localHour = (now: Date, timeZone: string): number => parts(now, timeZone).hour;
export function addDays(day: Day, count: number): Day {
  const date = new Date(`${day}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + count);
  return date.toISOString().slice(0, 10);
}
export function daysBetween(from: Day, to: Day): number {
  return Math.round((Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / 86_400_000);
}
export const LOCK_HOUR = 9;
// A day locks at 9 AM the next morning, the person's time. Backfills after that don't count.
export function isLocked(day: Day, timeZone: string, now: Date): boolean {
  const { day: today, hour } = parts(now, timeZone);
  const next = addDays(day, 1);
  return today > next || (today === next && hour >= LOCK_HOUR);
}
// The latest locked day for someone in this zone.
export function lastLockedDay(timeZone: string, now: Date): Day {
  const { day: today, hour } = parts(now, timeZone);
  return addDays(today, hour >= LOCK_HOUR ? -1 : -2);
}

// MARK: Made days

export function inRange(percent: number, rule: ClanRule): boolean {
  switch (rule.kind) {
    case 'atOrUnder': return percent <= 100;
    case 'withinPercent': return percent >= 100 - rule.percent && percent <= 100 + rule.percent;
    case 'upToPercentOver': return percent <= 100 + rule.percent;
  }
}
// On target means a full day inside the range, with a goal of at least the healthy minimum.
export function onTarget(report: DayReport | undefined, rule: ClanRule): boolean {
  return !!report && report.fullDay && report.goalOk && report.percentOfGoal !== null && inRange(report.percentOfGoal, rule);
}
export function madeDay(report: DayReport | undefined, settings: ChallengeSettings, rule: ClanRule): boolean {
  if (!report) return false;
  if (settings.basis === 'onTarget') return onTarget(report, settings.rule ?? rule);
  return settings.anyFood ? report.logged : report.fullDay;
}

// MARK: Accountability

export type Accountability = 'off' | 'logged' | 'percent';
export type Cell = {
  state: 'today' | 'none' | 'partial' | 'full'; // today = not locked yet
  logged: boolean;
  // ± mode only, once the day locks or after Done eating: calories as a % of goal, and whether it's in range.
  percent?: number; inRange?: boolean;
};
export function accountabilityCell(report: DayReport | undefined, locked: boolean, mode: Accountability, rule: ClanRule): Cell | null {
  if (mode === 'off') return null;
  const logged = !!report?.logged;
  const cell: Cell = { state: !locked ? 'today' : !logged ? 'none' : report!.fullDay ? 'full' : 'partial', logged };
  if (mode === 'percent' && report && report.percentOfGoal !== null && (locked || report.doneEating)) {
    cell.percent = report.percentOfGoal;
    cell.inRange = report.fullDay && report.goalOk && inRange(report.percentOfGoal, rule);
  }
  return cell;
}

// MARK: Challenges

export type Mark = 'made' | 'saved' | 'missed';
export type EntrantInput = { personId: string; timeZone: string; leftOn?: Day | null; weight?: WeightReport | null };
export type WeightReport = { startReady: boolean; changePct: number | null; finalPct: number | null; endReady: boolean };
export type ChallengeInput = {
  kind: ChallengeKind; settings: ChallengeSettings; rule: ClanRule;
  savesCount: number; savesPeriod: SavesPeriod;
  startsOn: Day; endsOn: Day | null;
  entrants: EntrantInput[];
  reports: Map<string, Map<Day, DayReport>>;
  now: Date;
};
export type EntrantResult = {
  personId: string; status: 'in' | 'out' | 'left'; points: number; livesLeft: number | null;
  outOn: Day | null; marks: Record<Day, Mark>; rank: number | null;
  creditedLossPct?: number | null; // weight challenges
};
export type ChallengeResult = {
  // Days every entrant has locked; the clan-wide outcome is decided through this day.
  completeThrough: Day | null;
  ended: boolean; endedOn: Day | null;
  entrants: EntrantResult[];
  streak?: { length: number; brokeOn: Day | null };
  team?: { total: number; target: number; reached: boolean };
  winners: string[];
};

const usesSaves = (kind: ChallengeKind) => kind === 'streak' || kind === 'survivor';
function periodIndex(dayIndex: number, period: SavesPeriod) {
  return period === 'week' ? Math.floor(dayIndex / 7) : period === 'month' ? Math.floor(dayIndex / 30) : 0;
}
// Ranks by score, highest first; ties share a rank (1, 1, 3).
export function ranks<T>(items: T[], score: (item: T) => number): Map<T, number> {
  const sorted = [...items].sort((a, b) => score(b) - score(a));
  const result = new Map<T, number>();
  sorted.forEach((item, index) => {
    const previous = sorted[index - 1];
    result.set(item, previous !== undefined && score(previous) === score(item) ? result.get(previous)! : index + 1);
  });
  return result;
}
// Weight credit stops at 1% of body weight per week, so crash diets and water cuts don't win.
export const WEIGHT_CREDIT_PER_WEEK = 1;
export function creditedLoss(changePct: number, weeks: number): number {
  const loss = -changePct;
  return Math.round(Math.min(loss, WEIGHT_CREDIT_PER_WEEK * weeks) * 10) / 10;
}

export function evaluateChallenge(input: ChallengeInput): ChallengeResult {
  const { kind, settings, rule, startsOn, endsOn, now } = input;
  const lastDay = (entrant: EntrantInput) => {
    let day = lastLockedDay(entrant.timeZone, now);
    if (endsOn && day > endsOn) day = endsOn;
    if (entrant.leftOn && day >= entrant.leftOn) day = addDays(entrant.leftOn, -1);
    return day;
  };
  const results = input.entrants.map((entrant): EntrantResult => {
    const reports = input.reports.get(entrant.personId) ?? new Map<Day, DayReport>();
    const marks: Record<Day, Mark> = {};
    const used = new Map<number, number>();
    let points = 0, outOn: Day | null = null;
    const through = lastDay(entrant);
    if (kind !== 'weightLoss') for (let day = startsOn; day <= through; day = addDays(day, 1)) {
      if (madeDay(reports.get(day), settings, rule)) { marks[day] = 'made'; points += 1; continue; }
      const period = periodIndex(daysBetween(startsOn, day), input.savesPeriod);
      if (usesSaves(kind) && (used.get(period) ?? 0) < input.savesCount) { marks[day] = 'saved'; used.set(period, (used.get(period) ?? 0) + 1); continue; }
      marks[day] = 'missed';
      if (kind === 'survivor') { outOn = day; break; }
    }
    const currentPeriod = periodIndex(Math.max(0, daysBetween(startsOn, lastLockedDay(entrant.timeZone, now)) + 1), input.savesPeriod);
    const livesLeft = usesSaves(kind) ? Math.max(0, input.savesCount - (used.get(currentPeriod) ?? 0)) : null;
    const left = !!entrant.leftOn && entrant.leftOn <= localDay(now, entrant.timeZone);
    return { personId: entrant.personId, status: left ? 'left' : outOn ? 'out' : 'in', points, livesLeft: outOn ? 0 : livesLeft, outOn, marks, rank: null };
  });
  // The clan-wide outcome waits until every entrant's day has locked (people who left don't hold it up).
  const staying = input.entrants.filter(e => !e.leftOn);
  const completeThrough = input.entrants.length
    ? (staying.length ? staying : input.entrants).map(lastDay).reduce((a, b) => (a < b ? a : b)) : null;
  const result: ChallengeResult = { completeThrough: completeThrough && completeThrough >= startsOn ? completeThrough : null, ended: false, endedOn: null, entrants: results, winners: [] };
  const present = (entrant: EntrantInput, day: Day) => !entrant.leftOn || entrant.leftOn > day;
  const finishedByDate = !!endsOn && !!result.completeThrough && result.completeThrough >= endsOn;

  if (kind === 'loggingDays' || kind === 'onTargetDays') {
    const active = results.filter(r => r.status !== 'left');
    const ranked = ranks(active, r => r.points);
    for (const r of active) r.rank = ranked.get(r) ?? null;
    if (finishedByDate) { result.ended = true; result.endedOn = endsOn; }
    if (result.ended && active.length) { const best = Math.max(...active.map(r => r.points)); result.winners = active.filter(r => r.points === best && best > 0).map(r => r.personId); }
  }
  if (kind === 'teamTotal') {
    // Every made day counts toward the target, in order, until it's reached.
    const total = results.reduce((sum, r) => sum + r.points, 0);
    result.team = { total, target: settings.teamTarget, reached: false };
    if (result.completeThrough) {
      let running = 0;
      for (let day = startsOn; day <= result.completeThrough; day = addDays(day, 1)) {
        for (const r of results) if (r.marks[day] === 'made') running += 1;
        if (running >= settings.teamTarget) { result.team.reached = true; result.ended = true; result.endedOn = day; break; }
      }
    }
    if (!result.ended && finishedByDate) { result.ended = true; result.endedOn = endsOn; }
    if (result.ended && result.team.reached) result.winners = results.filter(r => r.status !== 'left').map(r => r.personId);
  }
  if (kind === 'survivor' && result.completeThrough) {
    const alive = (day: Day) => input.entrants.filter((e, i) => present(e, day) && (!results[i].outOn || results[i].outOn! > day));
    for (let day = startsOn; day <= result.completeThrough; day = addDays(day, 1)) {
      const standing = alive(day);
      if (!endsOn && input.entrants.length > 1 && standing.length <= 1) {
        result.ended = true; result.endedOn = day;
        // Everyone left went out the same day: they share the win.
        result.winners = standing.length ? standing.map(e => e.personId)
          : results.filter((r, i) => r.outOn === day && present(input.entrants[i], day)).map(r => r.personId);
        break;
      }
    }
    if (!result.ended && finishedByDate) { result.ended = true; result.endedOn = endsOn; result.winners = alive(endsOn!).map(e => e.personId); }
  }
  if (kind === 'streak') {
    let length = 0, brokeOn: Day | null = null;
    if (result.completeThrough) for (let day = startsOn; day <= result.completeThrough; day = addDays(day, 1)) {
      const here = input.entrants.map((e, i) => ({ e, r: results[i] })).filter(({ e }) => present(e, day));
      const kept = here.filter(({ r }) => r.marks[day] === 'made' || r.marks[day] === 'saved').length;
      const passes = here.length > 0 && (settings.streakMode === 'everyone' ? kept === here.length : kept * 100 >= settings.streakPercent * here.length);
      if (!passes) { brokeOn = day; break; }
      length += 1;
    }
    result.streak = { length, brokeOn };
    if (brokeOn) { result.ended = true; result.endedOn = brokeOn; }
  }
  // Everyone who entered has left: nothing is left to play for.
  if (input.entrants.length && !staying.length && !result.ended) {
    result.ended = true;
    result.endedOn = input.entrants.map(e => e.leftOn!).reduce((a, b) => (a > b ? a : b));
  }
  if (kind === 'weightLoss') {
    const weeks = endsOn ? (daysBetween(startsOn, endsOn) + 1) / 7 : 0;
    const elapsed = Math.max(0, Math.min(weeks, (daysBetween(startsOn, localDay(now, 'UTC')) + 1) / 7));
    for (const [i, r] of results.entries()) {
      const w = input.entrants[i].weight;
      const final = finishedByDate;
      const change = final ? w?.finalPct : w?.changePct;
      const ranked = !!w?.startReady && change !== null && change !== undefined && (!final || w.endReady);
      r.creditedLossPct = ranked ? creditedLoss(change!, final ? weeks : Math.max(elapsed, 1 / 7)) : null;
    }
    const active = results.filter(r => r.status !== 'left' && r.creditedLossPct !== null && r.creditedLossPct !== undefined);
    const ranked = ranks(active, r => r.creditedLossPct!);
    for (const r of active) r.rank = ranked.get(r) ?? null;
    if (finishedByDate) {
      result.ended = true; result.endedOn = endsOn;
      if (active.length) { const best = Math.max(...active.map(r => r.creditedLossPct!)); if (best > 0) result.winners = active.filter(r => r.creditedLossPct === best).map(r => r.personId); }
    }
  }
  return result;
}

// MARK: Codes and names

// Six letters and digits without look-alikes (no 0/O, 1/I/L).
export const INVITE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
export function inviteCode(random: (max: number) => number): string {
  return Array.from({ length: 6 }, () => INVITE_ALPHABET[random(INVITE_ALPHABET.length)]).join('');
}
export function normalizeInviteCode(text: string): string {
  return text.normalize('NFKC').toUpperCase().replace(/[^A-Z0-9]/g, '');
}
