// Clan routes (`/api/v1/clan/...`), signed in with a clan session token (`x-clan-session`). Sign-in itself goes
// through the App Attest–verified routes in api.ts. See Documentation/Clans.md.
import { randomInt, randomUUID } from 'node:crypto';
import { and, desc, eq, gte, inArray, isNull, max, or, sql } from 'drizzle-orm';
import { z } from 'zod';
import { database } from './db';
import {
  clanAlerts, clanBlocks, clanChallenges, clanDays, clanEntrants, clanIdentities, clanJoinRequests, clanMembers, clanNudges, clanPeople,
  clanPushTokens, clanReports, clans, clanSessions,
} from './schema';
import { APIError } from './config';
import { consume, tomorrow } from './rate-limit';
import { entitlement } from './apple';
import { clanSession, revokeAppleToken } from './clan-auth';
import { cleanClanName, cleanDisplayName } from './clan-names';
import { deletePhoto, readPhoto, storePhoto } from './clan-photos';
import { ALERT_SWITCH, sendAlerts, type AlertKind } from './clan-push';
import { finishChallenge } from './clan-jobs';
import {
  activeMembers, accountabilityWeek, blockedBy, boardJSON, challengeState, CHALLENGE_NAMES, currentChallenge, peopleById, reportsFor,
  ruleOf, shownMembers, type ClanRow, type MemberRow,
} from './clan-board';
import {
  addDays, CHALLENGE_KINDS, challengeSettingsSchema, clanRuleSchema, daysBetween, inviteCode, isLocked, localDay, normalizeInviteCode,
  SAVES_PERIODS, validTimeZone, type ChallengeKind,
} from './clan-rules';

// Never shown anywhere; a full clan just says so.
export const MAX_MEMBERS = 50;
export const MAX_PHOTO_BODY = 2_200_000;
const uuid = z.string().uuid();
const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);
export const NUDGES = ['Fire need food! Log today.', 'Cave waiting on you.', 'No log yet. Ugh!'];
export const CHEERS = ['Strong caveman!', 'Fire burn bright!', 'Me proud of you!'];

// MARK: Helpers

async function membership(clanId: string, personId: string) {
  const [member] = await database().select().from(clanMembers)
    .where(and(eq(clanMembers.clanId, clanId), eq(clanMembers.personId, personId), isNull(clanMembers.leftAt)));
  if (!member) throw new APIError(404, 'not_in_clan', 'You’re not in this clan.');
  return member;
}
async function clanRow(clanId: string) {
  const [clan] = await database().select().from(clans).where(eq(clans.id, clanId));
  if (!clan) throw new APIError(404, 'clan_not_found', 'This clan no longer exists.');
  return clan;
}
const isAdmin = (member: MemberRow) => member.role === 'owner' || member.role === 'admin';
function requireAdmin(member: MemberRow) {
  if (!isAdmin(member)) throw new APIError(403, 'admin_only', 'Only clan admins can do that.');
}
async function me(personId: string) {
  const [person] = await database().select().from(clanPeople).where(eq(clanPeople.id, personId));
  if (!person) throw new APIError(401, 'signed_out', 'Sign in to use clans.');
  return person;
}
// Clans of three or more need an admin with Cave Cals+ (Apple-verified, through any iPhone they signed in on).
export async function clanHasPlus(clanId: string): Promise<boolean> {
  const admins = (await activeMembers(clanId)).filter(isAdmin).map(m => m.personId);
  if (!admins.length) return false;
  const sessions = await database().selectDistinct({ accountId: clanSessions.accountId, override: clanSessions.membershipOverride })
    .from(clanSessions).where(inArray(clanSessions.personId, admins));
  if (sessions.some(s => s.override === true)) return true;
  const accounts = [...new Set(sessions.map(s => s.accountId).filter((id): id is string => !!id))].slice(0, 6);
  for (const accountId of accounts) {
    try { if ((await entitlement({ accountId, keyId: '', development: false })).active) return true; } catch { /* next account */ }
  }
  return false;
}
async function requirePlusForGroup(clanId: string, memberCount: number) {
  if (memberCount >= 2 && !(await clanHasPlus(clanId))) {
    throw new APIError(402, 'clan_needs_plus', 'Clans of three or more need an admin with Cave Cals+.');
  }
}
async function newInviteCode(): Promise<string> {
  for (let attempt = 0; attempt < 8; attempt++) {
    const code = inviteCode(randomInt);
    const [taken] = await database().select({ id: clans.id }).from(clans).where(eq(clans.inviteCode, code));
    if (!taken) return code;
  }
  throw new APIError(503, 'try_again', 'Please try again.');
}
// How a person appears in alerts sent from a clan.
async function alertName(clanId: string, personId: string) {
  const [row] = await database().select({ anonymous: clanMembers.anonymous, name: clanPeople.displayName }).from(clanMembers)
    .innerJoin(clanPeople, eq(clanPeople.id, clanMembers.personId))
    .where(and(eq(clanMembers.clanId, clanId), eq(clanMembers.personId, personId), isNull(clanMembers.leftAt)));
  return !row || row.anonymous ? 'A Cave person' : row.name || 'A clanmate';
}
// Leaving (or being removed) ends someone's part in running challenges from today, and keeps an admin.
async function leaveClan(clan: ClanRow, member: MemberRow, removedBy: string | null) {
  const db = database();
  const person = await me(member.personId);
  const today = localDay(new Date(), person.timeZone);
  await db.update(clanMembers).set({ leftAt: new Date(), removedBy }).where(eq(clanMembers.id, member.id));
  const running = await db.select({ id: clanChallenges.id }).from(clanChallenges)
    .where(and(eq(clanChallenges.clanId, clan.id), or(eq(clanChallenges.status, 'upcoming'), eq(clanChallenges.status, 'active'))));
  if (running.length) {
    await db.update(clanEntrants).set({ status: 'left', leftOn: today })
      .where(and(inArray(clanEntrants.challengeId, running.map(c => c.id)), eq(clanEntrants.personId, member.personId)));
  }
  const rest = await activeMembers(clan.id);
  if (!rest.length) { await db.delete(clans).where(eq(clans.id, clan.id)); return; }
  if (!rest.some(isAdmin)) {
    // The longest-standing member takes over.
    await db.update(clanMembers).set({ role: member.role === 'owner' ? 'owner' : 'admin' }).where(eq(clanMembers.id, rest[0].id));
  } else if (member.role === 'owner' && !rest.some(m => m.role === 'owner')) {
    const next = rest.find(isAdmin)!;
    await db.update(clanMembers).set({ role: 'owner' }).where(eq(clanMembers.id, next.id));
  }
}
function adultByBirth(year: number | null, month: number | null, now = new Date()) {
  if (!year || !month) return null;
  // Counted from the end of the birth month, so nobody under 18 slips through.
  const months = (now.getUTCFullYear() - year) * 12 + (now.getUTCMonth() + 1 - month);
  return months >= 18 * 12 + 1;
}

// MARK: Inputs

const meUpdate = z.object({
  displayName: z.string().max(200).optional(),
  newsOptIn: z.boolean().optional(),
  birthYear: z.number().int().min(1900).max(new Date().getUTCFullYear()).optional(),
  birthMonth: z.number().int().min(1).max(12).optional(),
  alertPrefs: z.record(z.enum([...new Set(Object.values(ALERT_SWITCH))] as [string, ...string[]]), z.boolean()).optional(),
});
const dayReport = z.object({
  day, logged: z.boolean(), fullDay: z.boolean(), percentOfGoal: z.number().int().min(0).max(1000).nullable(),
  goalOk: z.boolean(), doneEating: z.boolean().default(false),
});
const challengeCreate = z.object({
  clanId: uuid, kind: z.enum(CHALLENGE_KINDS), settings: challengeSettingsSchema,
  savesCount: z.number().int().min(0).max(10).default(0), savesPeriod: z.enum(SAVES_PERIODS).default('challenge'),
  startsOn: day,
  // Logging days, on-target days, and clan goals (teamTotal): 3–90 days. Survivor: optional (none = last one standing).
  // Weight loss: 2–12 weeks. Streaks have no end.
  lengthDays: z.number().int().min(3).max(90).optional(),
  weeks: z.number().int().min(2).max(12).optional(),
});

// MARK: Routes

export async function clanAPI(request: Request, path: string, body: unknown): Promise<unknown> {
  const session = await clanSession(request);
  const personId = session.personId;
  const minute = new Date().toISOString().slice(0, 16);
  await consume(`clan:${personId}:${minute}`, 60, tomorrow());
  const db = database();
  const now = new Date();

  switch (path) {
    case 'clan/me': {
      const person = await me(personId);
      return profile(person);
    }
    case 'clan/me/update': {
      const update = meUpdate.parse(body);
      const set: Partial<typeof clanPeople.$inferInsert> = {};
      if (update.displayName !== undefined) set.displayName = cleanDisplayName(update.displayName);
      if (update.birthYear !== undefined) set.birthYear = update.birthYear;
      if (update.birthMonth !== undefined) set.birthMonth = update.birthMonth;
      if (update.newsOptIn !== undefined) {
        set.newsOptIn = update.newsOptIn;
        if (update.newsOptIn) set.newsOptInAt = new Date(); else set.newsOptOutAt = new Date();
      }
      if (update.alertPrefs) set.alertPrefs = { ...((await me(personId)).alertPrefs as object), ...update.alertPrefs };
      if (Object.keys(set).length) await db.update(clanPeople).set(set).where(eq(clanPeople.id, personId));
      return profile(await me(personId));
    }
    case 'clan/me/photo': {
      const { jpeg } = z.object({ jpeg: z.string().min(1).max(MAX_PHOTO_BODY) }).parse(body);
      await consume(`clan-photo:${personId}:${now.toISOString().slice(0, 10)}`, 20, tomorrow());
      const photoId = await storePhoto(Buffer.from(jpeg, 'base64'));
      const old = (await me(personId)).photoId;
      await db.update(clanPeople).set({ photoId }).where(eq(clanPeople.id, personId));
      await deletePhoto(old);
      return { photoId };
    }
    case 'clan/me/photo/remove': {
      const old = (await me(personId)).photoId;
      await db.update(clanPeople).set({ photoId: null }).where(eq(clanPeople.id, personId));
      await deletePhoto(old);
      return { photoId: null };
    }
    case 'clan/push/register': {
      const { token, environment } = z.object({ token: z.string().regex(/^[a-f0-9]{64,200}$/), environment: z.enum(['sandbox', 'production']) }).parse(body);
      await db.insert(clanPushTokens).values({ token, personId, environment }).onConflictDoUpdate({
        target: clanPushTokens.token, set: { personId, environment, updatedAt: sql`now()` },
      });
      return { registered: true };
    }
    case 'clan/list': return listClans(personId, now);
    case 'clan/create': {
      const { name } = z.object({ name: z.string().max(200) }).parse(body);
      await consume(`clan-create:${personId}:${now.toISOString().slice(0, 10)}`, 10, tomorrow());
      const id = randomUUID();
      await db.transaction(async tx => {
        // Accountability starts on (yes/no); admins can change it. Joining needs an admin's OK unless they open it up.
        await tx.insert(clans).values({ id, name: cleanClanName(name), inviteCode: await newInviteCode(), createdBy: personId, accountability: 'logged' });
        await tx.insert(clanMembers).values({ id: randomUUID(), clanId: id, personId, role: 'owner' });
      });
      return { clanId: id };
    }
    case 'clan/preview': {
      const { code } = z.object({ code: z.string().max(40) }).parse(body);
      await consume(`clan-code:${personId}:${now.toISOString().slice(0, 13)}`, 30, tomorrow());
      const [clan] = await db.select().from(clans).where(eq(clans.inviteCode, normalizeInviteCode(code)));
      if (!clan) throw new APIError(404, 'code_not_found', 'That code doesn’t match a clan. Check it and try again.');
      const members = await activeMembers(clan.id);
      const [request] = await db.select().from(clanJoinRequests).where(and(eq(clanJoinRequests.clanId, clan.id), eq(clanJoinRequests.personId, personId)));
      return {
        clanId: clan.id, name: clan.name, memberCount: members.length, alreadyMember: members.some(m => m.personId === personId),
        full: members.length >= MAX_MEMBERS, needsApproval: clan.joinMode !== 'open', pending: !!request,
      };
    }
    case 'clan/join': {
      const { code, anonymous } = z.object({ code: z.string().max(40), anonymous: z.boolean().default(false) }).parse(body);
      await consume(`clan-code:${personId}:${now.toISOString().slice(0, 13)}`, 30, tomorrow());
      const [clan] = await db.select().from(clans).where(eq(clans.inviteCode, normalizeInviteCode(code)));
      if (!clan) throw new APIError(404, 'code_not_found', 'That code doesn’t match a clan. Check it and try again.');
      const members = await activeMembers(clan.id);
      if (members.some(m => m.personId === personId)) return { clanId: clan.id };
      if (members.length >= MAX_MEMBERS) throw new APIError(409, 'clan_full', 'This clan is full.');
      if (clan.joinMode !== 'open') {
        // A code alone isn't enough: an admin lets them in (and sees who's asking, even if they'll hide in the clan).
        const inserted = await db.insert(clanJoinRequests).values({ clanId: clan.id, personId, anonymous })
          .onConflictDoUpdate({ target: [clanJoinRequests.clanId, clanJoinRequests.personId], set: { anonymous } }).returning({ createdAt: clanJoinRequests.createdAt });
        const person = await me(personId);
        if (inserted.length && Date.now() - inserted[0].createdAt.getTime() < 5_000) {
          await sendAlerts(members.filter(isAdmin).map(m => ({ personId: m.personId, clanId: clan.id })), 'joinRequest', { personId },
            { title: clan.name, body: `${person.displayName || 'Someone'} wants to join. Tap to let them in.` });
        }
        return { clanId: clan.id, pending: true };
      }
      await requirePlusForGroup(clan.id, members.length);
      await addMember(clan, members, personId, anonymous);
      return { clanId: clan.id };
    }
    case 'clan/get': {
      const { clanId, weekStart } = z.object({ clanId: uuid, weekStart: day.optional() }).parse(body);
      const member = await membership(clanId, personId);
      // Opening a clan clears its badge.
      await db.update(clanAlerts).set({ readAt: now }).where(and(eq(clanAlerts.personId, personId), eq(clanAlerts.clanId, clanId), isNull(clanAlerts.readAt)));
      return clanDetail(await clanRow(clanId), member, personId, weekStart, now);
    }
    case 'clan/update': {
      const update = z.object({
        clanId: uuid, name: z.string().max(200).optional(), accountability: z.enum(['off', 'logged', 'percent']).optional(),
        rule: clanRuleSchema.optional(), ruleChoice: z.enum(['clan', 'member']).optional(), joinMode: z.enum(['approval', 'open']).optional(),
      }).parse(body);
      const member = await membership(update.clanId, personId); requireAdmin(member);
      const clan = await clanRow(update.clanId);
      const set: Partial<typeof clans.$inferInsert> = {};
      if (update.name !== undefined) set.name = cleanClanName(update.name);
      if (update.accountability) set.accountability = update.accountability;
      if (update.rule) set.rule = update.rule;
      if (update.ruleChoice) set.ruleChoice = update.ruleChoice;
      if (update.joinMode) set.joinMode = update.joinMode;
      if (Object.keys(set).length) await db.update(clans).set(set).where(eq(clans.id, clan.id));
      if (clan.accountability === 'off' && update.accountability && update.accountability !== 'off') {
        // A heads-up, so anyone who'd rather can switch to Cave person first.
        const others = (await activeMembers(clan.id)).filter(m => m.personId !== personId);
        await sendAlerts(others.map(m => ({ personId: m.personId, clanId: clan.id })), 'challengeStarted', { accountability: update.accountability },
          { title: set.name ?? clan.name, body: 'Accountability is on: clanmates can now see your days. You can switch to Cave person anytime.' });
      }
      return { updated: true };
    }
    case 'clan/request/decide': {
      const { clanId, personId: target, approve } = z.object({ clanId: uuid, personId: uuid, approve: z.boolean() }).parse(body);
      requireAdmin(await membership(clanId, personId));
      const clan = await clanRow(clanId);
      const [request] = await db.select().from(clanJoinRequests).where(and(eq(clanJoinRequests.clanId, clanId), eq(clanJoinRequests.personId, target)));
      if (!request) return { decided: true }; // another admin got there first
      if (approve) {
        const members = await activeMembers(clanId);
        if (members.length >= MAX_MEMBERS) throw new APIError(409, 'clan_full', 'This clan is full.');
        // Letting in a third person is when Cave Cals+ comes up, for the admin doing it.
        await requirePlusForGroup(clanId, members.length);
        if (!members.some(m => m.personId === target)) await addMember(clan, members, target, request.anonymous);
        await sendAlerts([{ personId: target, clanId }], 'joinApproved', { clanId }, { title: clan.name, body: 'You’re in! Welcome to the clan.' });
      }
      await db.delete(clanJoinRequests).where(and(eq(clanJoinRequests.clanId, clanId), eq(clanJoinRequests.personId, target)));
      return { decided: true };
    }
    case 'clan/leave': {
      const { clanId } = z.object({ clanId: uuid }).parse(body);
      const member = await membership(clanId, personId);
      await leaveClan(await clanRow(clanId), member, null);
      return { left: true };
    }
    case 'clan/member/remove': {
      const { clanId, personId: target } = z.object({ clanId: uuid, personId: uuid }).parse(body);
      const member = await membership(clanId, personId); requireAdmin(member);
      const them = await membership(clanId, target);
      if (them.role === 'owner' && member.role !== 'owner') throw new APIError(403, 'owner_only', 'Only the clan’s owner can remove them.');
      if (target === personId) throw new APIError(400, 'use_leave', 'Use Leave clan instead.');
      await leaveClan(await clanRow(clanId), them, personId);
      return { removed: true };
    }
    case 'clan/member/role': {
      const { clanId, personId: target, role } = z.object({ clanId: uuid, personId: uuid, role: z.enum(['admin', 'member']) }).parse(body);
      const member = await membership(clanId, personId); requireAdmin(member);
      const them = await membership(clanId, target);
      if (them.role === 'owner') throw new APIError(403, 'owner_only', 'The owner stays an admin.');
      if (role === 'member' && member.role !== 'owner') throw new APIError(403, 'owner_only', 'Only the owner can change admins back.');
      await db.update(clanMembers).set({ role }).where(eq(clanMembers.id, them.id));
      return { updated: true };
    }
    case 'clan/member/settings': {
      const update = z.object({ clanId: uuid, anonymous: z.boolean().optional(), muted: z.boolean().optional(), rule: clanRuleSchema.nullable().optional() }).parse(body);
      const member = await membership(update.clanId, personId);
      const set: Partial<typeof clanMembers.$inferInsert> = {};
      if (update.anonymous !== undefined && update.anonymous !== member.anonymous) {
        set.anonymous = update.anonymous;
        set.anonNumber = update.anonymous ? await nextAnonNumber(update.clanId) : null;
      }
      if (update.muted !== undefined) set.muted = update.muted;
      if (update.rule !== undefined) {
        const clan = await clanRow(update.clanId);
        if (clan.ruleChoice !== 'member') throw new APIError(403, 'clan_rule', 'This clan uses one range for everyone.');
        set.rule = update.rule;
      }
      if (Object.keys(set).length) await db.update(clanMembers).set(set).where(eq(clanMembers.id, member.id));
      return { updated: true };
    }
    case 'clan/code/reset': {
      const { clanId } = z.object({ clanId: uuid }).parse(body);
      requireAdmin(await membership(clanId, personId));
      const code = await newInviteCode();
      await db.update(clans).set({ inviteCode: code }).where(eq(clans.id, clanId));
      return { inviteCode: code };
    }
    case 'clan/delete': {
      const { clanId } = z.object({ clanId: uuid }).parse(body);
      const member = await membership(clanId, personId);
      if (member.role !== 'owner') throw new APIError(403, 'owner_only', 'Only the clan’s owner can delete it.');
      await db.delete(clans).where(eq(clans.id, clanId));
      return { deleted: true };
    }
    case 'clan/days': return saveDays(personId, body, now);
    case 'clan/challenge/create': return createChallenge(personId, challengeCreate.parse(body), now);
    case 'clan/challenge/join': {
      const { challengeId, notClinicianLed, adult } = z.object({ challengeId: uuid, notClinicianLed: z.boolean().optional(), adult: z.boolean().optional() }).parse(body);
      const challenge = await challengeRow(challengeId);
      await membership(challenge.clanId, personId);
      const person = await me(personId);
      if (localDay(now, person.timeZone) > challenge.startsOn || challenge.status === 'ended' || challenge.status === 'canceled') {
        throw new APIError(409, 'challenge_started', 'This challenge already started. Join the next one!');
      }
      if (challenge.kind === 'weightLoss') await requireWeightEligible(person, notClinicianLed, adult);
      await db.insert(clanEntrants).values({ challengeId, personId }).onConflictDoUpdate({
        target: [clanEntrants.challengeId, clanEntrants.personId], set: { status: 'in', leftOn: null },
      });
      return { joined: true };
    }
    case 'clan/challenge/leave': {
      const { challengeId } = z.object({ challengeId: uuid }).parse(body);
      const challenge = await challengeRow(challengeId);
      const person = await me(personId);
      const today = localDay(now, person.timeZone);
      // Before it starts, leaving just takes you off the list.
      if (today < challenge.startsOn) await db.delete(clanEntrants).where(and(eq(clanEntrants.challengeId, challengeId), eq(clanEntrants.personId, personId)));
      else await db.update(clanEntrants).set({ status: 'left', leftOn: today }).where(and(eq(clanEntrants.challengeId, challengeId), eq(clanEntrants.personId, personId)));
      return { left: true };
    }
    case 'clan/challenge/end': {
      const { challengeId } = z.object({ challengeId: uuid }).parse(body);
      const challenge = await challengeRow(challengeId);
      requireAdmin(await membership(challenge.clanId, personId));
      await finishChallenge(challenge, await clanRow(challenge.clanId), now, true);
      return { ended: true };
    }
    case 'clan/challenge/weight': {
      const report = z.object({
        challengeId: uuid, startReady: z.boolean(), changePct: z.number().min(-50).max(50).nullable(),
        finalPct: z.number().min(-50).max(50).nullable(), endReady: z.boolean(),
      }).parse(body);
      const challenge = await challengeRow(report.challengeId);
      if (challenge.kind !== 'weightLoss') throw new APIError(400, 'not_weight', 'This isn’t a weight challenge.');
      const { challengeId, ...weight } = report;
      const result = await db.update(clanEntrants).set({ weight })
        .where(and(eq(clanEntrants.challengeId, challengeId), eq(clanEntrants.personId, personId), eq(clanEntrants.status, 'in'))).returning();
      if (!result.length) throw new APIError(404, 'not_entered', 'You’re not in this challenge.');
      return { saved: true };
    }
    case 'clan/nudge': {
      const { clanId, personId: target, kind, message } = z.object({
        clanId: uuid, personId: uuid, kind: z.enum(['nudge', 'cheer']), message: z.number().int().min(0).max(2).default(0),
      }).parse(body);
      if (target === personId) throw new APIError(400, 'not_yourself', 'Nudge someone else.');
      await membership(clanId, personId); await membership(clanId, target);
      const [block] = await db.select().from(clanBlocks).where(or(
        and(eq(clanBlocks.blockerId, target), eq(clanBlocks.blockedId, personId)),
        and(eq(clanBlocks.blockerId, personId), eq(clanBlocks.blockedId, target))));
      if (block) throw new APIError(403, 'blocked', 'You can’t nudge this person.');
      const today = localDay(now, (await me(personId)).timeZone);
      const inserted = await db.insert(clanNudges).values({ fromId: personId, toId: target, clanId, day: today, kind }).onConflictDoNothing().returning();
      if (!inserted.length) throw new APIError(409, 'already_sent', kind === 'nudge' ? 'You already nudged them today.' : 'You already cheered them today.');
      const clan = await clanRow(clanId), name = await alertName(clanId, personId);
      const text = (kind === 'nudge' ? NUDGES : CHEERS)[message];
      await sendAlerts([{ personId: target, clanId }], kind as AlertKind, { from: personId, message }, { title: clan.name, body: `${name}: ${text}` });
      return { sent: true };
    }
    case 'clan/alerts': {
      const rows = await db.select({ alert: clanAlerts, clanName: clans.name }).from(clanAlerts)
        .leftJoin(clans, eq(clans.id, clanAlerts.clanId)).where(eq(clanAlerts.personId, personId))
        .orderBy(desc(clanAlerts.createdAt)).limit(50);
      return {
        unread: rows.filter(r => !r.alert.readAt).length,
        alerts: rows.map(r => ({ id: r.alert.id, clanId: r.alert.clanId, clanName: r.clanName, kind: r.alert.kind, payload: r.alert.payload, createdAt: r.alert.createdAt.toISOString(), read: !!r.alert.readAt })),
      };
    }
    case 'clan/alerts/read': {
      const { clanId } = z.object({ clanId: uuid.optional() }).parse(body);
      await db.update(clanAlerts).set({ readAt: now }).where(and(eq(clanAlerts.personId, personId), isNull(clanAlerts.readAt), ...(clanId ? [eq(clanAlerts.clanId, clanId)] : [])));
      return { read: true };
    }
    case 'clan/block': {
      const { personId: target, blocked } = z.object({ personId: uuid, blocked: z.boolean() }).parse(body);
      if (target === personId) throw new APIError(400, 'not_yourself', 'You can’t block yourself.');
      if (blocked) await db.insert(clanBlocks).values({ blockerId: personId, blockedId: target }).onConflictDoNothing();
      else await db.delete(clanBlocks).where(and(eq(clanBlocks.blockerId, personId), eq(clanBlocks.blockedId, target)));
      return { blocked };
    }
    case 'clan/report': {
      const report = z.object({ kind: z.enum(['name', 'photo', 'clanName']), personId: uuid.optional(), clanId: uuid, reason: z.string().max(500).default('') }).parse(body);
      await membership(report.clanId, personId);
      await consume(`clan-report:${personId}:${now.toISOString().slice(0, 10)}`, 20, tomorrow());
      let snapshot = '';
      if (report.kind === 'clanName') snapshot = (await clanRow(report.clanId)).name;
      else {
        if (!report.personId) throw new APIError(400, 'invalid_request', 'Some request fields are invalid.');
        await membership(report.clanId, report.personId);
        const target = await me(report.personId);
        snapshot = report.kind === 'name' ? target.displayName : target.photoId ?? '';
      }
      await db.insert(clanReports).values({
        id: randomUUID(), reporterId: personId, kind: report.kind, targetPersonId: report.personId ?? null, targetClanId: report.clanId,
        snapshot, reason: report.reason.trim(),
      });
      return { reported: true };
    }
    case 'clan/signout': {
      await db.delete(clanSessions).where(eq(clanSessions.tokenHash, session.tokenHash));
      return { signedOut: true };
    }
    case 'clan/account/delete': return deleteClanPerson(session.personId);
  }
  throw new APIError(404, 'not_found', 'Not found.');
}

const RESULTS_SHOWN_MS = 3 * 86_400_000;
// Admins see who's asking by their real name and photo, so they know who they're letting in.
async function joinRequests(clanId: string) {
  const rows = await database().select({ request: clanJoinRequests, person: clanPeople }).from(clanJoinRequests)
    .innerJoin(clanPeople, eq(clanPeople.id, clanJoinRequests.personId))
    .where(eq(clanJoinRequests.clanId, clanId)).orderBy(clanJoinRequests.createdAt);
  return rows.map(r => ({ personId: r.person.id, name: r.person.displayName || 'Someone', photoId: r.person.photoId, requestedAt: r.request.createdAt.toISOString() }));
}
async function addMember(clan: ClanRow, members: MemberRow[], personId: string, anonymous: boolean) {
  const db = database();
  const anonNumber = anonymous ? await nextAnonNumber(clan.id) : null;
  try {
    await db.insert(clanMembers).values({ id: randomUUID(), clanId: clan.id, personId, anonymous, anonNumber });
  } catch { return; } // a double tap raced the unique index
  const name = await alertName(clan.id, personId);
  await sendAlerts(members.filter(isAdmin).map(m => ({ personId: m.personId, clanId: clan.id })), 'memberJoined', { personId },
    { title: clan.name, body: `${name} joined the clan.` });
}
function profile(person: typeof clanPeople.$inferSelect) {
  return {
    personId: person.id, displayName: person.displayName, photoId: person.photoId, birthYear: person.birthYear, birthMonth: person.birthMonth,
    alertPrefs: person.alertPrefs, needsName: !person.displayName,
    email: person.email, emailPrivate: person.emailPrivate, newsOptIn: person.newsOptIn,
  };
}
async function nextAnonNumber(clanId: string) {
  const [row] = await database().select({ n: max(clanMembers.anonNumber) }).from(clanMembers).where(eq(clanMembers.clanId, clanId));
  return (row?.n ?? 0) + 1;
}
async function challengeRow(challengeId: string) {
  const [challenge] = await database().select().from(clanChallenges).where(eq(clanChallenges.id, challengeId));
  if (!challenge) throw new APIError(404, 'challenge_not_found', 'This challenge no longer exists.');
  return challenge;
}
async function requireWeightEligible(person: typeof clanPeople.$inferSelect, notClinicianLed: boolean | undefined, adult: boolean | undefined) {
  // The app confirms 18+ from the calorie plan's age or by asking (nothing is stored). Older apps sent a birth
  // month and year instead.
  const byBirth = adultByBirth(person.birthYear, person.birthMonth);
  if (adult !== true && byBirth === null) throw new APIError(400, 'adult_needed', 'Confirm you’re 18 or older to join weight challenges.');
  if (adult === false || byBirth === false) throw new APIError(403, 'adults_only', 'Weight challenges are for adults 18 and older.');
  // The app checks the doctor-led plan question, which never leaves the phone.
  if (notClinicianLed !== true) throw new APIError(403, 'clinician_plan', 'Weight challenges aren’t available with a doctor-led plan.');
}

async function saveDays(personId: string, body: unknown, now: Date) {
  const { timeZone, days } = z.object({ timeZone: z.string().max(64), days: z.array(dayReport).min(1).max(3) }).parse(body);
  if (!validTimeZone(timeZone)) throw new APIError(400, 'invalid_time_zone', 'Some request fields are invalid.');
  const db = database();
  await db.update(clanPeople).set({ timeZone }).where(eq(clanPeople.id, personId));
  const today = localDay(now, timeZone);
  const accepted: string[] = [];
  for (const report of days) {
    // Locked days (9 AM the next morning) and future days are left alone.
    if (report.day > today || isLocked(report.day, timeZone, now)) continue;
    const values = { ...report, personId, reportedAt: now };
    await db.insert(clanDays).values(values).onConflictDoUpdate({ target: [clanDays.personId, clanDays.day], set: { ...report, reportedAt: now } });
    accepted.push(report.day);
  }
  return { accepted };
}

async function createChallenge(personId: string, input: z.infer<typeof challengeCreate>, now: Date) {
  const member = await membership(input.clanId, personId); requireAdmin(member);
  const clan = await clanRow(input.clanId);
  if (await currentChallenge(clan.id)) throw new APIError(409, 'challenge_running', 'This clan already has a challenge. End it to start another.');
  const members = await activeMembers(clan.id);
  await requirePlusForGroup(clan.id, members.length - 1);
  const person = await me(personId);
  const today = localDay(now, person.timeZone);
  if (input.startsOn < today || daysBetween(today, input.startsOn) > 30) throw new APIError(400, 'invalid_start', 'Pick a start date within the next 30 days.');
  const kind = input.kind as ChallengeKind;
  let endsOn: string | null = null;
  if (kind === 'loggingDays' || kind === 'onTargetDays' || kind === 'teamTotal') {
    if (!input.lengthDays) throw new APIError(400, 'length_needed', 'Pick how long the challenge runs.');
    endsOn = addDays(input.startsOn, input.lengthDays - 1);
  } else if (kind === 'survivor') {
    endsOn = input.lengthDays ? addDays(input.startsOn, input.lengthDays - 1) : null;
  } else if (kind === 'weightLoss') {
    if (!input.weeks) throw new APIError(400, 'length_needed', 'Pick how many weeks the challenge runs.');
    endsOn = addDays(input.startsOn, input.weeks * 7 - 1);
  }
  const basis = kind === 'onTargetDays' ? 'onTarget' : kind === 'loggingDays' ? 'logging' : input.settings.basis;
  // Each challenge keeps its own range from the start, so editing the clan's (an accountability setting) never
  // changes a running challenge.
  const settings = { ...input.settings, basis, ...(basis === 'onTarget' && !input.settings.rule ? { rule: ruleOf(clan.rule) } : {}) };
  const id = randomUUID();
  await database().insert(clanChallenges).values({
    id, clanId: clan.id, kind, settings, startsOn: input.startsOn, endsOn, createdBy: personId,
    savesCount: kind === 'streak' || kind === 'survivor' ? input.savesCount : 0,
    savesPeriod: kind === 'streak' || kind === 'survivor' ? input.savesPeriod : 'challenge',
  });
  // The creator is in from the start, except weight loss, which asks the eligibility questions first.
  if (kind !== 'weightLoss') await database().insert(clanEntrants).values({ challengeId: id, personId });
  const name = CHALLENGE_NAMES[kind];
  const others = members.filter(m => m.personId !== personId);
  await sendAlerts(others.map(m => ({ personId: m.personId, clanId: clan.id })), 'challengeStarted', { challengeId: id, phase: 'created' },
    { title: clan.name, body: input.startsOn === today ? `New challenge: ${name} starts today. Join now!` : `New challenge: ${name}. Tap to join before it starts.` });
  return { challengeId: id };
}

async function listClans(personId: string, now: Date) {
  const db = database();
  const memberships = await db.select().from(clanMembers).where(and(eq(clanMembers.personId, personId), isNull(clanMembers.leftAt)));
  const unreadRows = await db.select({ clanId: clanAlerts.clanId, n: sql<number>`count(*)`.mapWith(Number) }).from(clanAlerts)
    .where(and(eq(clanAlerts.personId, personId), isNull(clanAlerts.readAt))).groupBy(clanAlerts.clanId);
  const unread = new Map(unreadRows.map(r => [r.clanId, r.n]));
  const result = [];
  for (const m of memberships) {
    const clan = await clanRow(m.clanId);
    const members = await activeMembers(clan.id);
    const challenge = await currentChallenge(clan.id);
    let summary = null;
    if (challenge) {
      const state = await challengeState(challenge, clan, now);
      const people = await peopleById(members.map(x => x.personId));
      const shown = new Map(shownMembers(personId, members, people, await blockedBy(personId)).map(s => [s.personId, s]));
      const board = boardJSON(challenge, clan, state, personId, shown, now);
      const mine = board.entrants.find(e => e.isMe);
      summary = {
        id: board.id, kind: board.kind, name: board.name, status: board.status, dayNumber: board.dayNumber, totalDays: board.totalDays,
        joined: board.joined, canJoin: board.canJoin, startsOn: board.startsOn,
        myStatus: mine?.status ?? null, myRank: mine?.rank ?? null, myLivesLeft: mine?.livesLeft ?? null, myLossPct: mine?.creditedLossPct ?? null,
        madeToday: mine?.madeToday ?? false, inToday: board.inToday, inCount: board.inCount,
        streak: board.streak, team: board.team,
      };
    }
    result.push({ id: clan.id, name: clan.name, memberCount: members.length, role: m.role, unread: unread.get(clan.id) ?? 0, challenge: summary });
  }
  // Clans this person asked to join and an admin hasn't answered yet.
  const pending = await db.select({ clanId: clans.id, name: clans.name }).from(clanJoinRequests)
    .innerJoin(clans, eq(clans.id, clanJoinRequests.clanId)).where(eq(clanJoinRequests.personId, personId));
  return { clans: result, pending, unread: [...unread.values()].reduce((a, b) => a + b, 0) };
}

async function clanDetail(clan: ClanRow, member: MemberRow, personId: string, weekStart: string | undefined, now: Date) {
  const members = await activeMembers(clan.id);
  const people = await peopleById(members.map(m => m.personId));
  const blocked = await blockedBy(personId);
  const shown = shownMembers(personId, members, people, blocked);
  const shownById = new Map(shown.map(s => [s.personId, s]));
  const viewer = people.get(personId)!;
  const today = localDay(now, viewer.timeZone);
  const start = weekStart ?? addDays(today, -6);
  const days = Array.from({ length: 7 }, (_, i) => addDays(start, i));
  const reports = await reportsFor(members.map(m => m.personId), days[0], days[6]);
  const challenge = await currentChallenge(clan.id);
  const board = challenge ? boardJSON(challenge, clan, await challengeState(challenge, clan, now), personId, shownById, now) : null;
  const history = await database().select().from(clanChallenges)
    .where(and(eq(clanChallenges.clanId, clan.id), eq(clanChallenges.status, 'ended'))).orderBy(desc(clanChallenges.endedAt)).limit(10);
  // The challenge that just ended stays on the clan page with its final standings for three days.
  const [recent] = challenge ? [] : await database().select().from(clanChallenges)
    .where(and(eq(clanChallenges.clanId, clan.id), eq(clanChallenges.status, 'ended'), gte(clanChallenges.endedAt, new Date(now.getTime() - RESULTS_SHOWN_MS))))
    .orderBy(desc(clanChallenges.endedAt)).limit(1);
  const lastChallenge = recent ? boardJSON(recent, clan, await challengeState(recent, clan, now), personId, shownById, now) : null;
  const requests = isAdmin(member) ? await joinRequests(clan.id) : [];
  return {
    clan: {
      id: clan.id, name: clan.name, inviteCode: clan.inviteCode, accountability: clan.accountability, rule: clan.rule, ruleChoice: clan.ruleChoice,
      bestStreak: clan.bestStreak, createdAt: clan.createdAt.toISOString(), joinMode: clan.joinMode,
    },
    me: { role: member.role, anonymous: member.anonymous, muted: member.muted, rule: member.rule, today },
    hasPlus: isAdmin(member) ? await clanHasPlus(clan.id) : undefined,
    members: shown,
    accountability: accountabilityWeek(clan, members, people, reports, days, now),
    challenge: board,
    lastChallenge,
    requests,
    history: history.map(h => ({ id: h.id, kind: h.kind, name: CHALLENGE_NAMES[h.kind as ChallengeKind], startsOn: h.startsOn, endsOn: h.endsOn, endedAt: h.endedAt?.toISOString() ?? null, result: h.result })),
  };
}

// Account deletion (and the admin page's removal of someone who broke the rules).
export async function deleteClanPerson(personId: string) {
  const db = database();
  const memberships = await db.select().from(clanMembers).where(and(eq(clanMembers.personId, personId), isNull(clanMembers.leftAt)));
  for (const m of memberships) await leaveClan(await clanRow(m.clanId), m, null);
  const person = await me(personId);
  const identities = await db.select().from(clanIdentities).where(eq(clanIdentities.personId, personId));
  for (const identity of identities) if (identity.provider === 'apple') await revokeAppleToken(identity.appleRefreshToken);
  await deletePhoto(person.photoId);
  // Past results keep their standings, without the name.
  const won = await db.select({ id: clanChallenges.id, result: clanChallenges.result }).from(clanChallenges)
    .where(sql`${clanChallenges.result} -> 'winners' @> ${JSON.stringify([personId])}::jsonb`);
  for (const row of won) {
    const result = row.result as { winners?: string[]; winnerNames?: string[] };
    const names = (result.winners ?? []).map((id, i) => (id === personId ? 'A former member' : result.winnerNames?.[i] ?? ''));
    await db.update(clanChallenges).set({ result: { ...result, winnerNames: names } }).where(eq(clanChallenges.id, row.id));
  }
  // Everything else (identities, sessions, days, alerts, nudges, blocks, entries) goes with the person.
  await db.delete(clanPeople).where(eq(clanPeople.id, personId));
  return { deleted: true };
}

// GET /api/v1/clan-photo/<id>: the person themselves, or a clanmate in a clan where they aren't a Cave person.
export async function photoResponse(request: Request, photoId: string): Promise<Response> {
  const { personId } = await clanSession(request);
  const db = database();
  const [owner] = await db.select({ id: clanPeople.id }).from(clanPeople).where(eq(clanPeople.photoId, uuid.parse(photoId)));
  if (!owner) throw new APIError(404, 'not_found', 'Not found.');
  if (owner.id !== personId) {
    const [blocked] = await db.select().from(clanBlocks).where(and(eq(clanBlocks.blockerId, personId), eq(clanBlocks.blockedId, owner.id)));
    const theirs = db.select({ clanId: clanMembers.clanId }).from(clanMembers)
      .where(and(eq(clanMembers.personId, owner.id), isNull(clanMembers.leftAt), eq(clanMembers.anonymous, false)));
    const [shared] = await db.select({ id: clanMembers.id }).from(clanMembers)
      .where(and(eq(clanMembers.personId, personId), isNull(clanMembers.leftAt), inArray(clanMembers.clanId, theirs))).limit(1);
    if (blocked || !shared) throw new APIError(404, 'not_found', 'Not found.');
  }
  const bytes = await readPhoto(photoId);
  if (!bytes) throw new APIError(404, 'not_found', 'Not found.');
  // A photo ID never changes content, so the app can keep it.
  return new Response(new Uint8Array(bytes), { headers: { 'Content-Type': 'image/jpeg', 'Cache-Control': 'private, max-age=604800, immutable' } });
}
