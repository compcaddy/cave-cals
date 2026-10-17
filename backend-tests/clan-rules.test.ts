import test from 'node:test';
import assert from 'node:assert/strict';
import {
  accountabilityCell, addDays, challengeSettingsSchema, creditedLoss, DEFAULT_RULE, evaluateChallenge, inRange, INVITE_ALPHABET,
  inviteCode, isLocked, lastLockedDay, madeDay, normalizeInviteCode, onTarget, ranks, validTimeZone,
  type ChallengeInput, type DayReport,
} from '../backend/src/server/clan-rules';

const full = (percentOfGoal = 95): DayReport => ({ logged: true, fullDay: true, percentOfGoal, goalOk: true, doneEating: false });
const partial: DayReport = { logged: true, fullDay: false, percentOfGoal: 40, goalOk: true, doneEating: false };
const LA = 'America/Los_Angeles';
// 9 AM Pacific (PDT, UTC−7) on the given day.
const nineAM = (day: string, minutes = 0) => new Date(Date.parse(`${day}T16:00:00Z`) + minutes * 60_000);
function challenge(partial: Partial<ChallengeInput> & { days: Record<string, Record<string, DayReport>> }): ChallengeInput {
  const reports = new Map(Object.entries(partial.days).map(([person, days]) => [person, new Map(Object.entries(days))]));
  return {
    kind: 'loggingDays', settings: challengeSettingsSchema.parse({}), rule: DEFAULT_RULE, savesCount: 0, savesPeriod: 'challenge',
    startsOn: '2026-10-01', endsOn: '2026-10-03', now: nineAM('2026-10-04', 5),
    entrants: Object.keys(partial.days).map(personId => ({ personId, timeZone: LA })),
    reports, ...partial,
  };
}

test('a day locks at 9 AM the next morning, in each person’s own time zone', () => {
  assert.ok(!isLocked('2026-10-13', LA, nineAM('2026-10-14', -1)));
  assert.ok(isLocked('2026-10-13', LA, nineAM('2026-10-14')));
  assert.ok(!isLocked('2026-10-14', LA, nineAM('2026-10-14')));
  // 9 AM in India (UTC+5:30) is 03:30 UTC.
  assert.ok(!isLocked('2026-10-13', 'Asia/Kolkata', new Date('2026-10-14T03:29:00Z')));
  assert.ok(isLocked('2026-10-13', 'Asia/Kolkata', new Date('2026-10-14T03:30:00Z')));
  assert.equal(lastLockedDay(LA, nineAM('2026-10-14', -1)), '2026-10-12');
  assert.equal(lastLockedDay(LA, nineAM('2026-10-14')), '2026-10-13');
  assert.equal(addDays('2026-12-31', 1), '2027-01-01');
  assert.ok(validTimeZone(LA));
  assert.ok(!validTimeZone('Mars/Olympus'));
});

test('on target needs a full day, a healthy goal, and the clan’s range', () => {
  assert.ok(inRange(100, { kind: 'atOrUnder', percent: 5 }));
  assert.ok(!inRange(101, { kind: 'atOrUnder', percent: 5 }));
  assert.ok(inRange(95, { kind: 'withinPercent', percent: 5 }) && inRange(105, { kind: 'withinPercent', percent: 5 }));
  assert.ok(!inRange(94, { kind: 'withinPercent', percent: 5 }) && !inRange(106, { kind: 'withinPercent', percent: 5 }));
  assert.ok(inRange(105, { kind: 'upToPercentOver', percent: 5 }) && !inRange(106, { kind: 'upToPercentOver', percent: 5 }));
  assert.ok(onTarget(full(90), DEFAULT_RULE));
  // A low, incomplete day never counts as on target.
  assert.ok(!onTarget({ ...full(40), fullDay: false }, DEFAULT_RULE));
  assert.ok(!onTarget({ ...full(90), goalOk: false }, DEFAULT_RULE));
  assert.ok(!onTarget({ ...full(90), percentOfGoal: null }, DEFAULT_RULE));
  assert.ok(!onTarget(undefined, DEFAULT_RULE));
});

test('logging days need a full day unless the admin allows any food', () => {
  const settings = challengeSettingsSchema.parse({});
  assert.ok(madeDay(full(), settings, DEFAULT_RULE));
  assert.ok(!madeDay(partial, settings, DEFAULT_RULE));
  assert.ok(madeDay(partial, { ...settings, anyFood: true }, DEFAULT_RULE));
  assert.ok(!madeDay(full(120), { ...settings, basis: 'onTarget' }, DEFAULT_RULE));
  assert.ok(madeDay(full(120), { ...settings, basis: 'onTarget', rule: { kind: 'withinPercent', percent: 25 } }, DEFAULT_RULE));
});

test('accountability shows today as logged-or-not, and ± only once a day is done', () => {
  assert.equal(accountabilityCell(full(), true, 'off', DEFAULT_RULE), null);
  assert.deepEqual(accountabilityCell(full(), false, 'percent', DEFAULT_RULE), { state: 'today', logged: true });
  assert.deepEqual(accountabilityCell({ ...full(97), doneEating: true }, false, 'percent', DEFAULT_RULE), { state: 'today', logged: true, percent: 97, inRange: true });
  assert.deepEqual(accountabilityCell(partial, true, 'logged', DEFAULT_RULE), { state: 'partial', logged: true });
  assert.deepEqual(accountabilityCell(undefined, true, 'logged', DEFAULT_RULE), { state: 'none', logged: false });
  assert.deepEqual(accountabilityCell(full(112), true, 'percent', DEFAULT_RULE), { state: 'full', logged: true, percent: 112, inRange: false });
});

test('ties share a rank', () => {
  const r = ranks([{ s: 5 }, { s: 7 }, { s: 5 }, { s: 1 }], x => x.s);
  assert.deepEqual([...r.values()].sort(), [1, 2, 2, 4]);
});

test('logging-days challenges score full days and end once the last day locks everywhere', () => {
  const input = challenge({ days: {
    ana: { '2026-10-01': full(), '2026-10-02': full(), '2026-10-03': full() },
    ben: { '2026-10-01': full(), '2026-10-02': partial, '2026-10-03': full() },
    cal: { '2026-10-01': full(), '2026-10-02': full(), '2026-10-03': full() },
  } });
  const result = evaluateChallenge(input);
  assert.deepEqual(result.entrants.map(e => [e.personId, e.points, e.rank]), [['ana', 3, 1], ['ben', 2, 3], ['cal', 3, 1]]);
  assert.ok(result.ended);
  assert.deepEqual(result.winners, ['ana', 'cal']);
  // Before 9 AM on the 4th, the 3rd is still open, so nothing has ended.
  assert.ok(!evaluateChallenge({ ...input, now: nineAM('2026-10-04', -1) }).ended);
});

test('streaks keep going on saves and break on the first day the clan misses', () => {
  const days = {
    ana: { '2026-10-01': full(), '2026-10-02': full(), '2026-10-03': full(), '2026-10-04': full() },
    ben: { '2026-10-01': full(), '2026-10-02': partial, '2026-10-03': full() },
  };
  const result = evaluateChallenge(challenge({ kind: 'streak', endsOn: null, savesCount: 1, now: nineAM('2026-10-06', 5), days }));
  assert.equal(result.entrants[1].marks['2026-10-02'], 'saved');
  assert.deepEqual(result.streak, { length: 3, brokeOn: '2026-10-04' });
  assert.ok(result.ended);
  // With 50%, Ana alone keeps it going.
  const half = evaluateChallenge(challenge({ kind: 'streak', endsOn: null, now: nineAM('2026-10-06', 5), days,
    settings: challengeSettingsSchema.parse({ streakMode: 'percent', streakPercent: 50 }) }));
  assert.deepEqual(half.streak, { length: 4, brokeOn: '2026-10-05' });
});

test('someone leaving never breaks the streak or holds it up', () => {
  const input = challenge({ kind: 'streak', endsOn: null, now: nineAM('2026-10-04', 5), days: {
    ana: { '2026-10-01': full(), '2026-10-02': full(), '2026-10-03': full() },
    ben: { '2026-10-01': full() },
  } });
  input.entrants[1].leftOn = '2026-10-02';
  const result = evaluateChallenge(input);
  assert.deepEqual(result.streak, { length: 3, brokeOn: null });
  assert.equal(result.completeThrough, '2026-10-03');
  assert.equal(result.entrants[1].status, 'left');
});

test('a challenge everyone has left is over', () => {
  const input = challenge({ kind: 'streak', endsOn: null, days: { ana: { '2026-10-01': full() }, ben: {} } });
  input.entrants[0].leftOn = '2026-10-02'; input.entrants[1].leftOn = '2026-10-01';
  const result = evaluateChallenge(input);
  assert.ok(result.ended);
  assert.equal(result.endedOn, '2026-10-02');
});

test('Survivor: a miss without a life is out; the last one standing wins', () => {
  const days = {
    ana: { '2026-10-01': full(), '2026-10-02': full(), '2026-10-03': full() },
    ben: { '2026-10-01': full(), '2026-10-02': partial },
  };
  const result = evaluateChallenge(challenge({ kind: 'survivor', endsOn: null, now: nineAM('2026-10-04', 5), days }));
  assert.deepEqual(result.entrants.map(e => [e.status, e.outOn]), [['in', null], ['out', '2026-10-02']]);
  assert.ok(result.ended);
  assert.equal(result.endedOn, '2026-10-02');
  assert.deepEqual(result.winners, ['ana']);
  // Both out the same day share the win.
  const both = evaluateChallenge(challenge({ kind: 'survivor', endsOn: null, now: nineAM('2026-10-04', 5), days: {
    ana: { '2026-10-01': full() }, ben: { '2026-10-01': full() },
  } }));
  assert.deepEqual(both.winners, ['ana', 'ben']);
  assert.equal(both.endedOn, '2026-10-02');
});

test('Survivor with an end date: the last one standing wins at once; otherwise everyone left at the end wins', () => {
  const early = evaluateChallenge(challenge({ kind: 'survivor', endsOn: '2026-10-14', now: nineAM('2026-10-04', 5), days: {
    ana: { '2026-10-01': full(), '2026-10-02': full(), '2026-10-03': full() },
    ben: { '2026-10-01': full(), '2026-10-02': partial },
  } }));
  assert.ok(early.ended);
  assert.equal(early.endedOn, '2026-10-02', 'ends the day only one is left, not on the end date');
  assert.deepEqual(early.winners, ['ana']);
  const days: Record<string, DayReport> = {};
  for (let i = 0; i < 7; i++) days[addDays('2026-10-01', i)] = full();
  const atEnd = evaluateChallenge(challenge({ kind: 'survivor', endsOn: '2026-10-07', now: nineAM('2026-10-09'), days: { ana: days, ben: days } }));
  assert.ok(atEnd.ended);
  assert.equal(atEnd.endedOn, '2026-10-07');
  assert.deepEqual(atEnd.winners, ['ana', 'ben']);
});

test('Survivor lives refill each week when saves are weekly', () => {
  const days: Record<string, DayReport> = {};
  for (let i = 0; i < 9; i++) days[addDays('2026-10-01', i)] = full();
  delete days['2026-10-01']; delete days['2026-10-08']; delete days['2026-10-09'];
  const result = evaluateChallenge(challenge({ kind: 'survivor', endsOn: '2026-10-28', savesCount: 1, savesPeriod: 'week', now: nineAM('2026-10-11'), days: { ana: days, ben: {} } }));
  const ana = result.entrants[0];
  assert.equal(ana.marks['2026-10-01'], 'saved');
  assert.equal(ana.marks['2026-10-08'], 'saved');
  assert.equal(ana.marks['2026-10-09'], 'missed');
  assert.equal(ana.outOn, '2026-10-09');
});

test('team totals end the day the clan reaches the target', () => {
  const result = evaluateChallenge(challenge({ kind: 'teamTotal', endsOn: '2026-10-10', now: nineAM('2026-10-04', 5),
    settings: challengeSettingsSchema.parse({ teamTarget: 4 }), days: {
      ana: { '2026-10-01': full(), '2026-10-02': full(), '2026-10-03': full() },
      ben: { '2026-10-02': full() },
    } }));
  assert.deepEqual(result.team, { total: 4, target: 4, reached: true });
  assert.equal(result.endedOn, '2026-10-03');
  assert.deepEqual(result.winners, ['ana', 'ben']);
});

test('weight loss credit stops at 1% a week, and needs start and final weigh-ins', () => {
  assert.equal(creditedLoss(-3.4, 2), 2);
  assert.equal(creditedLoss(-1.24, 2), 1.2);
  assert.equal(creditedLoss(0.8, 2), -0.8);
  const result = evaluateChallenge(challenge({ kind: 'weightLoss', endsOn: '2026-10-14', now: nineAM('2026-10-15', 5), days: { ana: {}, ben: {}, cal: {} } }));
  assert.ok(result.ended);
  const input = challenge({ kind: 'weightLoss', endsOn: '2026-10-14', now: nineAM('2026-10-15', 5), days: { ana: {}, ben: {}, cal: {} } });
  input.entrants[0].weight = { startReady: true, changePct: -3, finalPct: -3.2, endReady: true };
  input.entrants[1].weight = { startReady: true, changePct: -1.5, finalPct: -1.5, endReady: true };
  input.entrants[2].weight = { startReady: false, changePct: -4, finalPct: -4, endReady: true };
  const done = evaluateChallenge(input);
  assert.deepEqual(done.entrants.map(e => [e.creditedLossPct, e.rank]), [[2, 1], [1.5, 2], [null, null]]);
  assert.deepEqual(done.winners, ['ana']);
});

test('invite codes avoid look-alike characters and ignore capitals and spaces', () => {
  for (const ch of '0O1IL') assert.ok(!INVITE_ALPHABET.includes(ch));
  let n = 0;
  assert.equal(inviteCode(() => n++ % INVITE_ALPHABET.length), 'ABCDEF');
  assert.equal(normalizeInviteCode(' x7k-2qm '), 'X7K2QM');
});
