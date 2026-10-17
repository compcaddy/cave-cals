// Clan alerts: each one is saved for the campfire badge and, unless the person turned that kind off or muted
// the clan, sent as a push notification through APNs (token auth with a .p8 key).
import { connect } from 'node:http2';
import { createPrivateKey, randomUUID, sign } from 'node:crypto';
import { and, eq, inArray } from 'drizzle-orm';
import { database } from './db';
import { clanAlerts, clanMembers, clanPeople, clanPushTokens } from './schema';
import { bundleID } from './config';
import { deliverAndroidPush } from './android-push';

export const ALERT_KINDS = [
  'evening', 'nudge', 'cheer', 'challengeStarted', 'challengeEnded', 'lifeLost', 'out', 'streakMilestone', 'streakRecord', 'memberJoined',
  'joinRequest', 'joinApproved',
] as const;
export type AlertKind = typeof ALERT_KINDS[number];
// The Settings → Clans switches; several kinds share one switch.
export const ALERT_SWITCH: Record<AlertKind, string> = {
  evening: 'evening', nudge: 'nudges', cheer: 'nudges', challengeStarted: 'updates', challengeEnded: 'updates',
  lifeLost: 'updates', out: 'updates', streakMilestone: 'milestones', streakRecord: 'milestones', memberJoined: 'members',
  joinRequest: 'members', joinApproved: 'updates',
};
export type Push = { title: string; body: string };

let cachedJWT: { token: string; at: number } | null = null;
function providerToken(): string | null {
  const keyId = process.env.APNS_KEY_ID, team = process.env.APNS_TEAM_ID || process.env.APPLE_TEAM_ID, key = process.env.APNS_KEY;
  if (!keyId || !team || !key) return null;
  // Apple wants a token refreshed between 20 and 60 minutes.
  if (cachedJWT && Date.now() - cachedJWT.at < 40 * 60_000) return cachedJWT.token;
  const encode = (value: object) => Buffer.from(JSON.stringify(value)).toString('base64url');
  const unsigned = `${encode({ alg: 'ES256', kid: keyId })}.${encode({ iss: team, iat: Math.floor(Date.now() / 1000) })}`;
  const signature = sign('sha256', Buffer.from(unsigned), { key: createPrivateKey(key.replace(/\\n/g, '\n')), dsaEncoding: 'ieee-p1363' });
  cachedJWT = { token: `${unsigned}.${signature.toString('base64url')}`, at: Date.now() };
  return cachedJWT.token;
}
type Delivery = { token: string; environment: string; payload: { aps: { alert: Push }; clanId: string | null; kind: string }; collapse?: string };
// Sends a batch over one HTTP/2 connection per environment. Returns tokens Apple says are no longer valid.
async function deliver(items: Delivery[]): Promise<string[]> {
  const dead = await deliverAndroidPush(items.filter(i => i.environment === 'android').map(i => ({ token: i.token, ...i.payload.aps.alert, clanId: i.payload.clanId || '', kind: i.payload.kind, collapse: i.collapse }))).catch(() => [] as string[]);
  const jwt = providerToken();
  if (!jwt || !items.length) return dead;
  for (const environment of ['production', 'sandbox']) {
    const batch = items.filter(i => i.environment === environment);
    if (!batch.length) continue;
    const session = connect(environment === 'production' ? 'https://api.push.apple.com' : 'https://api.sandbox.push.apple.com');
    session.on('error', () => {});
    try {
      await Promise.all(batch.map(item => new Promise<void>(resolve => {
        const request = session.request({
          ':method': 'POST', ':path': `/3/device/${item.token}`, authorization: `bearer ${jwt}`,
          'apns-topic': bundleID(), 'apns-push-type': 'alert', 'apns-priority': '10',
          ...(item.collapse ? { 'apns-collapse-id': item.collapse } : {}),
        });
        request.setTimeout(10_000, () => { request.close(); resolve(); });
        request.on('response', headers => {
          const status = Number(headers[':status']);
          let body = '';
          request.on('data', chunk => { body += chunk; });
          request.on('end', () => {
            if (status === 410 || (status === 400 && /BadDeviceToken|DeviceTokenNotForTopic/.test(body))) dead.push(item.token);
            resolve();
          });
        });
        request.on('error', () => resolve());
        request.end(JSON.stringify(item.payload));
      })));
    } finally { session.close(); }
  }
  return dead;
}

export type AlertTarget = { personId: string; clanId: string | null };
// Records alerts and pushes them. Never throws: alerts must not fail the action that caused them.
export async function sendAlerts(targets: AlertTarget[], kind: AlertKind, payload: Record<string, unknown>, push: Push | ((personId: string) => Push)) {
  if (!targets.length) return;
  try {
    const db = database();
    await db.insert(clanAlerts).values(targets.map(t => ({ id: randomUUID(), personId: t.personId, clanId: t.clanId, kind, payload })));
    const people = await db.select({ id: clanPeople.id, prefs: clanPeople.alertPrefs }).from(clanPeople).where(inArray(clanPeople.id, targets.map(t => t.personId)));
    const muted = new Set((await db.select({ personId: clanMembers.personId, clanId: clanMembers.clanId }).from(clanMembers)
      .where(and(inArray(clanMembers.personId, targets.map(t => t.personId)), eq(clanMembers.muted, true))))
      .map(m => `${m.personId}:${m.clanId}`));
    const allowed = new Set(people.filter(p => (p.prefs as Record<string, boolean>)[ALERT_SWITCH[kind]] !== false).map(p => p.id));
    const wanted = targets.filter(t => allowed.has(t.personId) && !(t.clanId && muted.has(`${t.personId}:${t.clanId}`)));
    if (!wanted.length) return;
    const tokens = await db.select().from(clanPushTokens).where(inArray(clanPushTokens.personId, wanted.map(t => t.personId)));
    const deliveries = tokens.map(token => {
      const target = wanted.find(t => t.personId === token.personId)!;
      const message = typeof push === 'function' ? push(token.personId) : push;
      return {
        token: token.token, environment: token.environment,
        payload: { aps: { alert: message, sound: 'default', ...(target.clanId ? { 'thread-id': target.clanId } : {}) }, clanId: target.clanId, kind },
        collapse: kind === 'evening' ? `evening-${target.clanId}` : undefined,
      };
    });
    const dead = await deliver(deliveries);
    if (dead.length) await db.delete(clanPushTokens).where(inArray(clanPushTokens.token, dead));
  } catch (error) {
    console.error('Clan alert failed', error instanceof Error ? error.name : 'UnknownError');
  }
}
