// Loading clans for display: members as each viewer may see them, the accountability week, and challenge
// boards evaluated live from the daily reports (the cron job saves the same results and sends alerts).
import { and, desc, eq, gte, inArray, isNull, lte, or } from 'drizzle-orm';
import { database } from './db';
import { clanBlocks, clanChallenges, clanDays, clanEntrants, clanMembers, clanPeople, clans } from './schema';
import {
  accountabilityCell, addDays, challengeSettingsSchema, clanRuleSchema, DEFAULT_RULE, evaluateChallenge, isLocked, localDay, madeDay,
  daysBetween, type Accountability, type ChallengeKind, type ChallengeResult, type ClanRule, type Day, type DayReport, type SavesPeriod, type WeightReport,
} from './clan-rules';

export type ClanRow = typeof clans.$inferSelect;
export type MemberRow = typeof clanMembers.$inferSelect;
export type PersonRow = typeof clanPeople.$inferSelect;
export type ChallengeRow = typeof clanChallenges.$inferSelect;
export const CHALLENGE_NAMES: Record<ChallengeKind, string> = {
  loggingDays: 'Logging days', onTargetDays: 'On-target days', teamTotal: 'Clan goal', survivor: 'Survivor', streak: 'Streak', weightLoss: 'Weight loss',
};
export const ruleOf = (value: unknown): ClanRule => clanRuleSchema.safeParse(value).data ?? DEFAULT_RULE;

export type ShownMember = { personId: string; name: string; photoId: string | null; anonymous: boolean; blocked: boolean; role: string; isMe: boolean; joinedAt: string };
// Cave people show as "Cave person" (numbered when there are several) with no photo, to everyone.
// People the viewer blocked keep their place but not their name or photo.
export function shownMembers(viewerId: string, members: MemberRow[], people: Map<string, PersonRow>, blocked: Set<string>): ShownMember[] {
  const anonymousCount = members.filter(m => m.anonymous).length;
  return members.map(m => {
    const person = people.get(m.personId), isMe = m.personId === viewerId;
    const hidden = !isMe && blocked.has(m.personId);
    const name = m.anonymous ? (anonymousCount > 1 ? `Cave person ${m.anonNumber ?? ''}`.trim() : 'Cave person')
      : hidden ? 'Blocked person' : person?.displayName || 'Caveman';
    return {
      personId: m.personId, name: isMe && m.anonymous ? `${name} (you)` : name,
      photoId: m.anonymous || hidden ? null : person?.photoId ?? null, anonymous: m.anonymous, blocked: hidden,
      role: m.role, isMe, joinedAt: m.joinedAt.toISOString(),
    };
  });
}

export async function activeMembers(clanId: string) {
  return database().select().from(clanMembers).where(and(eq(clanMembers.clanId, clanId), isNull(clanMembers.leftAt))).orderBy(clanMembers.joinedAt);
}
export async function peopleById(ids: string[]) {
  if (!ids.length) return new Map<string, PersonRow>();
  const rows = await database().select().from(clanPeople).where(inArray(clanPeople.id, ids));
  return new Map(rows.map(p => [p.id, p]));
}
export async function blockedBy(viewerId: string) {
  const rows = await database().select({ id: clanBlocks.blockedId }).from(clanBlocks).where(eq(clanBlocks.blockerId, viewerId));
  return new Set(rows.map(r => r.id));
}
export async function reportsFor(personIds: string[], from: Day, to: Day) {
  const map = new Map<string, Map<Day, DayReport>>();
  if (!personIds.length) return map;
  const rows = await database().select().from(clanDays)
    .where(and(inArray(clanDays.personId, personIds), gte(clanDays.day, from), lte(clanDays.day, to)));
  for (const row of rows) {
    if (!map.has(row.personId)) map.set(row.personId, new Map());
    map.get(row.personId)!.set(row.day, { logged: row.logged, fullDay: row.fullDay, percentOfGoal: row.percentOfGoal, goalOk: row.goalOk, doneEating: row.doneEating });
  }
  return map;
}

// MARK: Accountability week

export function accountabilityWeek(clan: ClanRow, members: MemberRow[], people: Map<string, PersonRow>, reports: Map<string, Map<Day, DayReport>>, days: Day[], now: Date) {
  const mode = clan.accountability as Accountability;
  if (mode === 'off') return null;
  const cells: Record<string, Record<Day, ReturnType<typeof accountabilityCell>>> = {};
  const weekly: Record<string, { logged: number; full: number; averagePercent: number | null }> = {};
  for (const m of members) {
    const zone = people.get(m.personId)?.timeZone ?? 'UTC', today = localDay(now, zone);
    const rule = clan.ruleChoice === 'member' && m.rule ? ruleOf(m.rule) : ruleOf(clan.rule);
    const mine = reports.get(m.personId) ?? new Map<Day, DayReport>();
    cells[m.personId] = {};
    const percents: number[] = [];
    let logged = 0, full = 0;
    for (const day of days) {
      if (day > today) continue;
      const locked = isLocked(day, zone, now), report = mine.get(day);
      cells[m.personId][day] = accountabilityCell(report, locked, mode, rule);
      if (locked && report?.logged) logged += 1;
      if (locked && report?.fullDay) full += 1;
      if (locked && report?.fullDay && report.percentOfGoal !== null) percents.push(report.percentOfGoal);
    }
    weekly[m.personId] = {
      logged, full,
      averagePercent: mode === 'percent' && percents.length ? Math.round(percents.reduce((a, b) => a + b, 0) / percents.length) : null,
    };
  }
  return { mode, rule: ruleOf(clan.rule), ruleChoice: clan.ruleChoice, days, cells, weekly };
}

// MARK: Challenges

export async function challengeState(challenge: ChallengeRow, clan: ClanRow, now: Date) {
  const entrants = await database().select().from(clanEntrants).where(eq(clanEntrants.challengeId, challenge.id));
  const people = await peopleById(entrants.map(e => e.personId));
  // Tomorrow in UTC covers every time zone's today.
  const horizon = addDays(localDay(now, 'UTC'), 1);
  const until = challenge.endsOn && challenge.endsOn < horizon ? challenge.endsOn : horizon;
  const reports = await reportsFor(entrants.map(e => e.personId), challenge.startsOn, until);
  const settings = challengeSettingsSchema.parse(challenge.settings ?? {});
  const result = evaluateChallenge({
    kind: challenge.kind as ChallengeKind, settings, rule: ruleOf(clan.rule),
    savesCount: challenge.savesCount, savesPeriod: challenge.savesPeriod as SavesPeriod,
    startsOn: challenge.startsOn, endsOn: challenge.endsOn,
    entrants: entrants.map(e => ({ personId: e.personId, timeZone: people.get(e.personId)?.timeZone ?? 'UTC', leftOn: e.leftOn, weight: (e.weight as WeightReport | null) ?? null })),
    reports, now,
  });
  return { entrants, people, reports, settings, result };
}
export async function currentChallenge(clanId: string) {
  const [row] = await database().select().from(clanChallenges)
    .where(and(eq(clanChallenges.clanId, clanId), or(eq(clanChallenges.status, 'upcoming'), eq(clanChallenges.status, 'active'))))
    .orderBy(desc(clanChallenges.createdAt)).limit(1);
  return row ?? null;
}

type Board = Awaited<ReturnType<typeof challengeState>>;
// The board a viewer sees: entrants in rank order, today's progress, and the type's own numbers.
export function boardJSON(challenge: ChallengeRow, clan: ClanRow, state: Board, viewerId: string, shown: Map<string, ShownMember>, now: Date) {
  const { result, reports, settings } = state;
  const viewerZone = state.people.get(viewerId)?.timeZone ?? 'UTC';
  const today = localDay(now, viewerZone);
  const dayNumber = Math.max(0, daysBetween(challenge.startsOn, today) + 1);
  const totalDays = challenge.endsOn ? daysBetween(challenge.startsOn, challenge.endsOn) + 1 : null;
  const recent = Array.from({ length: 7 }, (_, i) => addDays(today, i - 6)).filter(d => d >= challenge.startsOn);
  const entrants = result.entrants.map(r => {
    const zone = state.people.get(r.personId)?.timeZone ?? 'UTC';
    const theirToday = localDay(now, zone);
    return {
      ...(shown.get(r.personId) ?? { personId: r.personId, name: 'Former member', photoId: null, anonymous: false, blocked: false, role: 'member', isMe: r.personId === viewerId, joinedAt: '' }),
      status: r.status, points: r.points, livesLeft: r.livesLeft, rank: r.rank, outOn: r.outOn,
      creditedLossPct: r.creditedLossPct ?? null,
      // Today isn't scored until it locks; this is just whether it counts so far.
      madeToday: madeDay(reports.get(r.personId)?.get(theirToday), settings, ruleOf(clan.rule)),
      recent: Object.fromEntries(recent.map(d => [d, r.marks[d] ?? null])),
    };
  }).sort((a, b) => (a.rank ?? 999) - (b.rank ?? 999) || b.points - a.points);
  const statusNow = result.ended ? 'ended' : today < challenge.startsOn ? 'upcoming' : challenge.status === 'upcoming' ? 'active' : challenge.status;
  // An admin can end a challenge early: its saved result has the winners then.
  const stored = challenge.status === 'ended' ? (challenge.result as { winners?: string[]; endedOn?: string } | null) : null;
  return {
    id: challenge.id, kind: challenge.kind, name: CHALLENGE_NAMES[challenge.kind as ChallengeKind] ?? challenge.kind,
    settings, savesCount: challenge.savesCount, savesPeriod: challenge.savesPeriod,
    startsOn: challenge.startsOn, endsOn: challenge.endsOn, status: statusNow, dayNumber, totalDays,
    joined: result.entrants.some(e => e.personId === viewerId),
    canJoin: today <= challenge.startsOn && !result.entrants.some(e => e.personId === viewerId) && !result.ended,
    entrants, winners: stored?.winners ?? result.winners, endedOn: stored?.endedOn ?? result.endedOn,
    streak: result.streak ? { ...result.streak, record: clan.bestStreak } : null,
    team: result.team ?? null,
    inToday: entrants.filter(e => e.status === 'in' && e.madeToday).length,
    inCount: entrants.filter(e => e.status === 'in').length,
  };
}
export type BoardJSON = ReturnType<typeof boardJSON>;
export type EvaluatedChallenge = { challenge: ChallengeRow; result: ChallengeResult };
