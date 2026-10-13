// Clans against the isolated clans-dev Neon branch, through the real API routes with local development
// sign-in. Run: NODE_ENV=development npx tsx --test backend-tests/integration/clans.test.ts
import test, { after, before } from 'node:test';
import assert from 'node:assert/strict';
import nextEnv from '@next/env';
import { randomUUID } from 'node:crypto';
import sharp from 'sharp';
import { eq, inArray } from 'drizzle-orm';
import { database, closeDatabase } from '../../backend/src/server/db';
import { clanEntrants, clanPeople, clans, clanSessions, clanIdentities } from '../../backend/src/server/schema';
import { api } from '../../backend/src/server/api';
import { photoResponse } from '../../backend/src/server/clan-api';
import { runClanJobs } from '../../backend/src/server/clan-jobs';
import { addDays, localDay } from '../../backend/src/server/clan-rules';
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';

// SAVE_CLAN_SAMPLES=1 saves real responses for the app's decoding test (Tests/ClanContractTests.swift).
function sample(name: string, body: unknown) {
  if (process.env.SAVE_CLAN_SAMPLES !== '1') return;
  const dir = path.join(process.cwd(), 'Tests', 'Fixtures', 'clans');
  mkdirSync(dir, { recursive: true });
  writeFileSync(path.join(dir, `${name}.json`), JSON.stringify(body, null, 2) + '\n');
}

nextEnv.loadEnvConfig(process.cwd(), true);
const env = process.env as Record<string, string | undefined>;
const run = randomUUID().slice(0, 8);
const people: string[] = [], clanIds: string[] = [];
const zone = 'America/Los_Angeles';

before(() => {
  // Refuse to touch any database other than the clans development branch.
  assert.equal(process.env.NEON_TEST_BRANCH, 'clans-dev', 'Set NEON_TEST_BRANCH=clans-dev in .env.development.local.');
  assert.ok(process.env.DATABASE_URL?.includes('ep-old-dawn-axeue4t9'), 'Refusing to test against a different database.');
  env.NODE_ENV = 'development'; delete env.VERCEL; env.LOCAL_UPLOADS = 'true';
});
after(async () => {
  const db = database();
  if (clanIds.length) await db.delete(clans).where(inArray(clans.id, clanIds));
  if (people.length) await db.delete(clanPeople).where(inArray(clanPeople.id, people));
  await closeDatabase();
});

type Result = { status: number; body: any };
async function call(path: string, body: object, session?: string): Promise<Result> {
  const headers: Record<string, string> = { 'content-type': 'application/json', authorization: `Bearer ${process.env.DEV_API_TOKEN}` };
  if (session) headers['x-clan-session'] = session;
  const response = await api(new Request(`http://localhost:3000/api/v1/${path}`, { method: 'POST', headers, body: JSON.stringify(body) }), path);
  return { status: response.status, body: await response.json() };
}
async function person(name: string) {
  const result = await call('clan/auth/signin', { nonce: 'local', provider: 'dev', devSubject: `${run}-${name}`, name, acceptedTerms: true });
  assert.equal(result.status, 200, JSON.stringify(result.body));
  people.push(result.body.personId);
  await call('clan/days', { timeZone: zone, days: [{ day: localDay(new Date(), zone), logged: false, fullDay: false, percentOfGoal: null, goalOk: true, doneEating: false }] }, result.body.session);
  return result.body as { session: string; personId: string };
}

let ana: { session: string; personId: string }, ben: typeof ana, cal: typeof ana;
let clanId = '', code = '';

test('sign-in needs the clan rules, and makes a person with their first name', async () => {
  const refused = await call('clan/auth/signin', { nonce: 'local', provider: 'dev', devSubject: `${run}-x` });
  assert.equal(refused.status, 400);
  assert.equal(refused.body.error.code, 'terms_required');
  ana = await person('Ana Smith'); ben = await person('Ben'); cal = await person('Cal');
  const again = await call('clan/auth/signin', { nonce: 'local', provider: 'dev', devSubject: `${run}-Ana Smith` });
  assert.equal(again.body.personId, ana.personId);
  assert.equal(again.body.isNew, false);
  const me = (await call('clan/me', {}, ana.session)).body;
  assert.equal(me.displayName, 'Ana');
  sample('me', me);
  assert.equal((await call('clan/me', {}, 'not-a-session')).status, 401);
});

test('names are filtered', async () => {
  assert.equal((await call('clan/me/update', { displayName: 'B!tch' }, ben.session)).body.error.code, 'name_not_allowed');
  assert.equal((await call('clan/create', { name: 'x' }, ana.session)).body.error.code, 'name_too_short');
});

test('clans are made, joined by code, and need Cave Cals+ for a third member', async () => {
  const created = await call('clan/create', { name: 'The Cavemen' }, ana.session);
  assert.equal(created.status, 200);
  clanId = created.body.clanId; clanIds.push(clanId);
  code = (await call('clan/get', { clanId }, ana.session)).body.clan.inviteCode;
  assert.match(code, /^[A-Z2-9]{6}$/);
  const preview = await call('clan/preview', { code: code.toLowerCase() }, ben.session);
  sample('preview', preview.body);
  assert.deepEqual([preview.body.name, preview.body.memberCount, preview.body.alreadyMember], ['The Cavemen', 1, false]);
  assert.equal((await call('clan/join', { code }, ben.session)).status, 200);
  // Without Cave Cals+ on any admin, a third person can't join.
  await database().update(clanSessions).set({ membershipOverride: false, accountId: null }).where(eq(clanSessions.personId, ana.personId));
  const blocked = await call('clan/join', { code }, cal.session);
  assert.equal(blocked.status, 402);
  assert.equal(blocked.body.error.code, 'clan_needs_plus');
  await database().update(clanSessions).set({ membershipOverride: true }).where(eq(clanSessions.personId, ana.personId));
  assert.equal((await call('clan/join', { code, anonymous: true }, cal.session)).status, 200);
  const detail = (await call('clan/get', { clanId }, ben.session)).body;
  assert.deepEqual(detail.members.map((m: any) => m.name), ['Ana', 'Ben', 'Cave person']);
  assert.equal(detail.members[2].photoId, null);
  assert.equal(detail.accountability, null);
  assert.equal((await call('clan/get', { clanId }, 'nope')).status, 401);
});

test('daily reports: locked days and future days are refused', async () => {
  const today = localDay(new Date(), zone);
  const report = (day: string) => ({ day, logged: true, fullDay: true, percentOfGoal: 96, goalOk: true, doneEating: false });
  const saved = await call('clan/days', { timeZone: zone, days: [report(today), report(addDays(today, -3)), report(addDays(today, 2))] }, ana.session);
  assert.deepEqual(saved.body.accepted, [today]);
  assert.equal((await call('clan/days', { timeZone: 'Nowhere/Land', days: [report(today)] }, ana.session)).status, 400);
});

test('accountability shows each day once an admin turns it on', async () => {
  assert.equal((await call('clan/update', { clanId, accountability: 'percent' }, ben.session)).status, 403);
  assert.equal((await call('clan/update', { clanId, accountability: 'percent', rule: { kind: 'withinPercent', percent: 5 } }, ana.session)).status, 200);
  const detail = (await call('clan/get', { clanId }, ben.session)).body;
  const today = localDay(new Date(), zone);
  assert.deepEqual(detail.accountability.cells[ana.personId][today], { state: 'today', logged: true });
  assert.deepEqual(detail.accountability.cells[ben.personId][today], { state: 'today', logged: false });
});

test('one challenge at a time; members join before it starts', async () => {
  const today = localDay(new Date(), zone);
  assert.equal((await call('clan/challenge/create', { clanId, kind: 'streak', settings: {}, savesCount: 1, savesPeriod: 'week', startsOn: today }, ben.session)).status, 403);
  const created = await call('clan/challenge/create', { clanId, kind: 'streak', settings: { streakMode: 'everyone' }, savesCount: 1, savesPeriod: 'week', startsOn: today }, ana.session);
  assert.equal(created.status, 200, JSON.stringify(created.body));
  assert.equal((await call('clan/challenge/create', { clanId, kind: 'loggingDays', settings: {}, startsOn: today, lengthDays: 7 }, ana.session)).body.error.code, 'challenge_running');
  assert.equal((await call('clan/challenge/join', { challengeId: created.body.challengeId }, ben.session)).status, 200);
  const detail = (await call('clan/get', { clanId }, ben.session)).body;
  sample('get', detail);
  const board = detail.challenge;
  assert.equal(board.kind, 'streak');
  assert.equal(board.joined, true);
  assert.equal(board.entrants.length, 2);
  assert.equal(board.inToday, 1);
  const list = (await call('clan/list', {}, ben.session)).body;
  sample('list', list);
  assert.equal(list.clans[0].challenge.kind, 'streak');
  assert.equal(list.clans[0].challenge.madeToday, false);
});

test('nudges go once a day, and blocks stop them', async () => {
  assert.equal((await call('clan/nudge', { clanId, personId: ben.personId, kind: 'nudge', message: 0 }, ana.session)).status, 200);
  assert.equal((await call('clan/nudge', { clanId, personId: ben.personId, kind: 'nudge', message: 1 }, ana.session)).body.error.code, 'already_sent');
  const alerts = (await call('clan/alerts', {}, ben.session)).body;
  sample('alerts', alerts);
  assert.ok(alerts.alerts.some((a: any) => a.kind === 'nudge'));
  assert.equal((await call('clan/block', { personId: ana.personId, blocked: true }, ben.session)).status, 200);
  assert.equal((await call('clan/nudge', { clanId, personId: ben.personId, kind: 'cheer' }, ana.session)).body.error.code, 'blocked');
  const shown = (await call('clan/get', { clanId }, ben.session)).body.members;
  assert.equal(shown[0].name, 'Blocked person');
  await call('clan/block', { personId: ana.personId, blocked: false }, ben.session);
  assert.equal((await call('clan/report', { kind: 'name', personId: ana.personId, clanId, reason: 'test' }, ben.session)).status, 200);
});

test('photos are re-encoded and only clanmates who can see the person get them', async () => {
  const jpeg = await sharp({ create: { width: 900, height: 700, channels: 3, background: '#c86428' } }).jpeg().withMetadata({ exif: { IFD0: { Artist: 'test' } } }).toBuffer();
  const saved = await call('clan/me/photo', { jpeg: jpeg.toString('base64') }, ana.session);
  assert.equal(saved.status, 200);
  const request = (session: string) => new Request(`http://localhost:3000/api/v1/clan-photo/${saved.body.photoId}`, { headers: { 'x-clan-session': session } });
  const response = await photoResponse(request(ben.session), saved.body.photoId);
  const bytes = Buffer.from(await response.arrayBuffer());
  const meta = await sharp(bytes).metadata();
  assert.deepEqual([meta.width, meta.height, meta.exif], [512, 512, undefined]);
  // Someone outside the clan can't fetch it.
  const outsider = await person('Dee');
  await assert.rejects(photoResponse(request(outsider.session), saved.body.photoId), (e: any) => e.status === 404);
  await call('clan/me/photo/remove', {}, ana.session);
});

test('leaving takes someone out of the running challenge; the last admin leaving hands over the clan', async () => {
  assert.equal((await call('clan/leave', { clanId }, ben.session)).status, 200);
  const [entrant] = await database().select().from(clanEntrants).where(eq(clanEntrants.personId, ben.personId));
  assert.equal(entrant.status, 'left');
  await call('clan/leave', { clanId }, ana.session);
  const detail = (await call('clan/get', { clanId }, cal.session)).body;
  assert.equal(detail.me.role, 'owner');
});

test('the clans job runs, and ends a challenge everyone has left', async () => {
  await runClanJobs(new Date());
  const detail = (await call('clan/get', { clanId }, cal.session)).body;
  assert.equal(detail.challenge, null);
  assert.equal(detail.history[0].kind, 'streak');
  sample('get-history', detail);
});

test('deleting a clan account removes the person and everything of theirs', async () => {
  assert.equal((await call('clan/account/delete', {}, cal.session)).status, 200);
  assert.equal((await database().select().from(clanPeople).where(eq(clanPeople.id, cal.personId))).length, 0);
  assert.equal((await database().select().from(clanIdentities).where(eq(clanIdentities.personId, cal.personId))).length, 0);
  // Cal was the last member, so the clan went too.
  assert.equal((await database().select().from(clans).where(eq(clans.id, clanId))).length, 0);
});
