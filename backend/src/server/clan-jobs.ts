// The clans job (every 15 minutes, `/api/cron/clans`): starts challenges, saves each evaluation, finishes
// challenges, and sends their alerts plus the 7 PM "fire going out" reminder. Each run only does what's due,
// so a late or repeated run is harmless.
import { and, eq, inArray, isNull, ne, or } from 'drizzle-orm';
import { database } from './db';
import { clanChallenges, clanEntrants, clanMembers, clanPeople, clans } from './schema';
import { challengeState, CHALLENGE_NAMES, reportsFor, ruleOf, type ChallengeRow, type ClanRow } from './clan-board';
import { challengeSettingsSchema, localDay, localHour, madeDay, type ChallengeKind, type ChallengeResult } from './clan-rules';
import { sendAlerts } from './clan-push';

export const STREAK_MILESTONES = [7, 14, 30, 50, 100, 200, 365];
type Stored = { streakLength?: number; milestones?: number[]; recordSent?: boolean; [key: string]: unknown };

async function names(clanId: string, personIds: string[]) {
  if (!personIds.length) return [];
  const rows = await database().select({ personId: clanMembers.personId, anonymous: clanMembers.anonymous, name: clanPeople.displayName })
    .from(clanMembers).innerJoin(clanPeople, eq(clanPeople.id, clanMembers.personId))
    .where(and(eq(clanMembers.clanId, clanId), inArray(clanMembers.personId, personIds), isNull(clanMembers.leftAt)));
  return personIds.map(id => { const r = rows.find(x => x.personId === id); return !r || r.anonymous ? 'A Cave person' : r.name || 'A clanmate'; });
}
export function winnerLine(winners: string[]): string {
  if (!winners.length) return 'Challenge over.';
  if (winners.length === 1) return `${winners[0]} won!`;
  if (winners.length === 2) return `${winners[0]} and ${winners[1]} won!`;
  return `${winners.length} cavemen tied for the win!`;
}

// Saves each entrant's cached score, and alerts anyone who just used a save or went out.
async function saveEntrants(challenge: ChallengeRow, clan: ClanRow, result: ChallengeResult, previous: (typeof clanEntrants.$inferSelect)[]) {
  const db = database();
  const lives = challenge.kind === 'survivor' ? 'lives' : 'saves';
  const period = challenge.savesPeriod === 'week' ? ' this week' : challenge.savesPeriod === 'month' ? ' this month' : '';
  for (const r of result.entrants) {
    const before = previous.find(p => p.personId === r.personId);
    if (!before) continue;
    const status = before.status === 'left' ? 'left' : r.status;
    await db.update(clanEntrants).set({ status, points: r.points, livesLeft: r.livesLeft, rank: r.rank, outOn: r.outOn })
      .where(and(eq(clanEntrants.challengeId, challenge.id), eq(clanEntrants.personId, r.personId)));
    const target = [{ personId: r.personId, clanId: clan.id }];
    if (before.status === 'in' && status === 'out') {
      await sendAlerts(target, 'out', { challengeId: challenge.id }, { title: clan.name, body: `You’re out of ${CHALLENGE_NAMES[challenge.kind as ChallengeKind]}. Cheer on the rest!` });
    } else if (status === 'in' && before.livesLeft !== null && r.livesLeft !== null && r.livesLeft < before.livesLeft) {
      const left = r.livesLeft === 0 ? `No ${lives} left${period}.` : `${r.livesLeft} left${period}.`;
      await sendAlerts(target, 'lifeLost', { challengeId: challenge.id, livesLeft: r.livesLeft }, { title: clan.name, body: `You used ${challenge.kind === 'survivor' ? 'a life' : 'a save'}. ${left}` });
    }
  }
}

export async function finishChallenge(challenge: ChallengeRow, clan: ClanRow, now: Date, manual = false) {
  const db = database();
  if (challenge.status === 'ended' || challenge.status === 'canceled') return;
  const state = await challengeState(challenge, clan, now);
  const entrantIds = state.entrants.filter(e => e.status !== 'left').map(e => ({ personId: e.personId, clanId: clan.id }));
  const name = CHALLENGE_NAMES[challenge.kind as ChallengeKind];
  if (manual && localDay(now, 'Pacific/Kiritimati') < challenge.startsOn) {
    await db.update(clanChallenges).set({ status: 'canceled', endedAt: now }).where(eq(clanChallenges.id, challenge.id));
    await sendAlerts(entrantIds, 'challengeEnded', { challengeId: challenge.id, canceled: true }, { title: clan.name, body: `${name} was canceled.` });
    return;
  }
  const { result } = state;
  await saveEntrants(challenge, clan, result, state.entrants);
  const winnerNames = await names(clan.id, result.winners);
  let body: string, record = false;
  if (challenge.kind === 'streak') {
    const length = result.streak?.length ?? 0;
    record = length > clan.bestStreak;
    if (record) await db.update(clans).set({ bestStreak: length }).where(eq(clans.id, clan.id));
    body = `Streak over at ${length} ${length === 1 ? 'day' : 'days'}.${record && length > 1 ? ' New clan record!' : ''}`;
  } else if (challenge.kind === 'teamTotal' && result.team) {
    body = result.team.reached ? `Clan goal reached! ${result.team.target} days.` : `Clan goal ended at ${result.team.total} of ${result.team.target} days.`;
  } else body = `${name} is over. ${winnerLine(winnerNames)}`;
  const final = {
    endedOn: result.endedOn ?? localDay(now, 'UTC'), manual, winners: result.winners, winnerNames, streak: result.streak ?? null, team: result.team ?? null, record,
    standings: result.entrants.map(e => ({ personId: e.personId, rank: e.rank, points: e.points, status: e.status, creditedLossPct: e.creditedLossPct ?? null })),
  };
  await db.update(clanChallenges).set({ status: 'ended', endedAt: now, evaluatedAt: now, result: final }).where(eq(clanChallenges.id, challenge.id));
  await sendAlerts(entrantIds, 'challengeEnded', { challengeId: challenge.id }, { title: clan.name, body });
}

async function evaluateRunning(now: Date) {
  const db = database();
  const running = await db.select({ challenge: clanChallenges, clan: clans }).from(clanChallenges)
    .innerJoin(clans, eq(clans.id, clanChallenges.clanId))
    .where(or(eq(clanChallenges.status, 'upcoming'), eq(clanChallenges.status, 'active')));
  for (const { challenge, clan } of running) {
    try {
      const [creator] = challenge.createdBy ? await db.select({ zone: clanPeople.timeZone }).from(clanPeople).where(eq(clanPeople.id, challenge.createdBy)) : [];
      if (challenge.status === 'upcoming') {
        if (localDay(now, creator?.zone ?? 'UTC') < challenge.startsOn) continue;
        await db.update(clanChallenges).set({ status: 'active' }).where(eq(clanChallenges.id, challenge.id));
        const entrants = await db.select({ personId: clanEntrants.personId }).from(clanEntrants).where(and(eq(clanEntrants.challengeId, challenge.id), ne(clanEntrants.status, 'left')));
        await sendAlerts(entrants.map(e => ({ personId: e.personId, clanId: clan.id })), 'challengeStarted', { challengeId: challenge.id, phase: 'started' },
          { title: clan.name, body: `${CHALLENGE_NAMES[challenge.kind as ChallengeKind]} starts today. Good luck!` });
        challenge.status = 'active';
      }
      const state = await challengeState(challenge, clan, now);
      if (state.result.ended) { await finishChallenge(challenge, clan, now); continue; }
      await saveEntrants(challenge, clan, state.result, state.entrants);
      const stored = (challenge.result ?? {}) as Stored;
      const next: Stored = { ...stored, team: state.result.team ?? null };
      if (state.result.streak) {
        const length = state.result.streak.length, before = stored.streakLength ?? 0;
        const targets = state.entrants.filter(e => e.status !== 'left').map(e => ({ personId: e.personId, clanId: clan.id }));
        const crossed = STREAK_MILESTONES.filter(m => before < m && length >= m && !(stored.milestones ?? []).includes(m));
        if (crossed.length) {
          const m = crossed[crossed.length - 1];
          await sendAlerts(targets, 'streakMilestone', { challengeId: challenge.id, days: m }, { title: clan.name, body: `Fire lit ${m} days! Keep it burning.` });
          next.milestones = [...(stored.milestones ?? []), ...crossed];
        }
        if (clan.bestStreak > 0 && length > clan.bestStreak && !stored.recordSent) {
          await sendAlerts(targets, 'streakRecord', { challengeId: challenge.id, days: length }, { title: clan.name, body: `New clan record: ${length} days!` });
          next.recordSent = true;
        }
        next.streakLength = length;
      }
      await db.update(clanChallenges).set({ result: next, evaluatedAt: now }).where(eq(clanChallenges.id, challenge.id));
    } catch (error) {
      console.error('Clan challenge evaluation failed', error instanceof Error ? error.name : 'UnknownError');
    }
  }
}

// 7 PM, once a day: people in a streak or Survivor whose day doesn't count yet.
export const EVENING_HOURS = [19, 20, 21, 22];
async function eveningAlerts(now: Date) {
  const db = database();
  const rows = await db.select({ challenge: clanChallenges, clan: clans, person: clanPeople }).from(clanEntrants)
    .innerJoin(clanChallenges, eq(clanChallenges.id, clanEntrants.challengeId))
    .innerJoin(clans, eq(clans.id, clanChallenges.clanId))
    .innerJoin(clanPeople, eq(clanPeople.id, clanEntrants.personId))
    .where(and(eq(clanChallenges.status, 'active'), inArray(clanChallenges.kind, ['streak', 'survivor']), eq(clanEntrants.status, 'in')));
  const done = new Set<string>();
  for (const { challenge, clan, person } of rows) {
    if (done.has(person.id) || !EVENING_HOURS.includes(localHour(now, person.timeZone))) continue;
    const today = localDay(now, person.timeZone);
    if (person.eveningAlertOn === today || today < challenge.startsOn) continue;
    const report = (await reportsFor([person.id], today, today)).get(person.id)?.get(today);
    const settings = challengeSettingsSchema.parse(challenge.settings ?? {});
    if (madeDay(report, settings, ruleOf(clan.rule))) continue;
    done.add(person.id);
    await db.update(clanPeople).set({ eveningAlertOn: today }).where(eq(clanPeople.id, person.id));
    const stake = challenge.kind === 'survivor' ? 'to stay in Survivor' : `to keep ${clan.name}’s streak alive`;
    await sendAlerts([{ personId: person.id, clanId: clan.id }], 'evening', { challengeId: challenge.id },
      { title: report?.logged ? 'Fire low!' : 'Fire going out!', body: report?.logged ? `Finish logging today ${stake}.` : `Nothing logged today. Log ${stake}.` });
  }
}

export async function runClanJobs(now = new Date()) {
  await evaluateRunning(now);
  await eveningAlerts(now);
}
