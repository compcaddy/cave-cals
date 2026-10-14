// Clan sign-in: Sign in with Apple and Sign in with Google identity tokens, verified here against each
// provider's published keys, become a clan person and a session token the app keeps in its Keychain.
import { createCipheriv, createDecipheriv, createHash, createPrivateKey, createPublicKey, randomBytes, randomUUID, sign, verify, type JsonWebKeyInput } from 'node:crypto';
import { and, eq, gt, sql } from 'drizzle-orm';
import { z } from 'zod';
import { database } from './db';
import { clanIdentities, clanPeople, clanSessions } from './schema';
import { APIError, bundleID } from './config';
import type { Identity } from './auth';
import { cleanDisplayName } from './clan-names';
import { photoFromURL } from './clan-photos';

export const SESSION_DAYS = 180;
export const sessionHash = (token: string) => createHash('sha256').update(token).digest('hex');

// MARK: Identity tokens

type JWK = JsonWebKeyInput["key"] & { kid?: string; alg?: string };
const keyCache = new Map<string, { keys: JWK[]; fetchedAt: number }>();
async function providerKeys(url: string, refresh = false): Promise<JWK[]> {
  const cached = keyCache.get(url);
  if (!refresh && cached && Date.now() - cached.fetchedAt < 3600_000) return cached.keys;
  let response: Response;
  try { response = await fetch(url, { signal: AbortSignal.timeout(10_000) }); }
  catch { throw new APIError(503, 'sign_in_unavailable', 'Sign-in is unavailable right now. Please try again.'); }
  if (!response.ok) throw new APIError(503, 'sign_in_unavailable', 'Sign-in is unavailable right now. Please try again.');
  const keys = ((await response.json()) as { keys: JWK[] }).keys;
  keyCache.set(url, { keys, fetchedAt: Date.now() });
  return keys;
}
const base64url = (part: string) => Buffer.from(part, 'base64url');
export type TokenClaims = {
  iss: string; aud: string | string[]; sub: string; exp: number; iat?: number; nonce?: string; name?: string; given_name?: string; picture?: string;
  // Apple sends booleans as strings ("true").
  email?: string; email_verified?: boolean | string; is_private_email?: boolean | string;
};
const yes = (value: boolean | string | undefined) => value === true || value === 'true';
/** A verified email from the identity token, or nothing. */
export function verifiedEmail(claims: TokenClaims): { email: string; emailPrivate: boolean } | null {
  const email = claims.email?.trim().toLowerCase();
  if (!email || email.length > 254 || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) || !yes(claims.email_verified)) return null;
  return { email, emailPrivate: yes(claims.is_private_email) || email.endsWith('@privaterelay.appleid.com') };
}
// Verifies an RS256 JWT's signature with the provider's key, then its issuer, audience, expiry, and nonce.
export async function verifyIdentityToken(token: string, options: { keysURL: string; issuers: string[]; audiences: string[]; nonce: string; now?: number }): Promise<TokenClaims> {
  const invalid = () => new APIError(401, 'invalid_sign_in', 'Sign-in couldn’t be verified. Please try again.');
  const [head, body, signature] = token.split('.');
  if (!head || !body || !signature || token.length > 8000) throw invalid();
  let header: { alg?: string; kid?: string }, claims: TokenClaims;
  try { header = JSON.parse(base64url(head).toString('utf8')); claims = JSON.parse(base64url(body).toString('utf8')); } catch { throw invalid(); }
  if (header.alg !== 'RS256' || !header.kid) throw invalid();
  let key = (await providerKeys(options.keysURL)).find(k => k.kid === header.kid);
  // Providers rotate keys; refetch once for a key we haven't seen.
  if (!key) key = (await providerKeys(options.keysURL, true)).find(k => k.kid === header.kid);
  if (!key) throw invalid();
  const valid = verify('RSA-SHA256', Buffer.from(`${head}.${body}`), createPublicKey({ key, format: 'jwk' }), base64url(signature));
  if (!valid) throw invalid();
  const now = (options.now ?? Date.now()) / 1000;
  const audiences = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
  if (!options.issuers.includes(claims.iss) || !audiences.some(a => options.audiences.includes(a)) || !claims.sub || claims.exp < now - 60) throw invalid();
  // The app sends its random nonce; the token carries its SHA-256, so a captured token can't be replayed.
  if (claims.nonce !== createHash('sha256').update(options.nonce).digest('hex')) throw invalid();
  return claims;
}
export const appleAudiences = () => [bundleID(), `${bundleID()}.dev`];
export const googleAudiences = () => (process.env.GOOGLE_CLIENT_IDS || '').split(',').map(s => s.trim()).filter(Boolean);

// MARK: Apple refresh tokens (revoked when the clan account is deleted)

function appleClientSecret(): string | null {
  const keyId = process.env.APPLE_SIGNIN_KEY_ID, privateKey = process.env.APPLE_SIGNIN_PRIVATE_KEY, team = process.env.APPLE_TEAM_ID;
  if (!keyId || !privateKey || !team) return null;
  const now = Math.floor(Date.now() / 1000);
  const encode = (value: object) => Buffer.from(JSON.stringify(value)).toString('base64url');
  const unsigned = `${encode({ alg: 'ES256', kid: keyId })}.${encode({ iss: team, iat: now, exp: now + 300, aud: 'https://appleid.apple.com', sub: bundleID() })}`;
  const signature = sign('sha256', Buffer.from(unsigned), { key: createPrivateKey(privateKey.replace(/\\n/g, '\n')), dsaEncoding: 'ieee-p1363' });
  return `${unsigned}.${signature.toString('base64url')}`;
}
function tokenKey(): Buffer | null {
  const key = process.env.CLAN_TOKEN_KEY ? Buffer.from(process.env.CLAN_TOKEN_KEY, 'base64') : null;
  return key?.length === 32 ? key : null;
}
export function sealToken(token: string, key = tokenKey()): string | null {
  if (!key) return null;
  const iv = randomBytes(12), cipher = createCipheriv('aes-256-gcm', key, iv);
  const sealed = Buffer.concat([cipher.update(token, 'utf8'), cipher.final()]);
  return [iv, cipher.getAuthTag(), sealed].map(b => b.toString('base64url')).join('.');
}
export function openToken(sealed: string, key = tokenKey()): string | null {
  if (!key) return null;
  const [iv, tag, data] = sealed.split('.').map(p => Buffer.from(p, 'base64url'));
  try {
    const decipher = createDecipheriv('aes-256-gcm', key, iv); decipher.setAuthTag(tag);
    return Buffer.concat([decipher.update(data), decipher.final()]).toString('utf8');
  } catch { return null; }
}
async function appleRequest(path: string, form: Record<string, string>) {
  const secret = appleClientSecret();
  if (!secret) return null;
  try {
    const response = await fetch(`https://appleid.apple.com/auth/${path}`, {
      method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ client_id: bundleID(), client_secret: secret, ...form }), signal: AbortSignal.timeout(10_000),
    });
    return response.ok ? (path === 'token' ? await response.json() as { refresh_token?: string } : {}) : null;
  } catch { return null; }
}
// Best effort: without the Sign in with Apple key configured, nothing is stored and nothing is revoked.
export async function appleRefreshToken(authorizationCode: string | undefined): Promise<string | null> {
  if (!authorizationCode) return null;
  const result = await appleRequest('token', { code: authorizationCode, grant_type: 'authorization_code' });
  return result?.refresh_token ? sealToken(result.refresh_token) : null;
}
export async function revokeAppleToken(sealed: string | null) {
  const token = sealed ? openToken(sealed) : null;
  if (token) await appleRequest('revoke', { token, token_type_hint: 'refresh_token' });
}

// MARK: Sign-in and sessions

export const signInInput = z.object({
  provider: z.enum(['apple', 'google', 'dev']),
  identityToken: z.string().min(1).max(8000).optional(),
  // The raw nonce whose SHA-256 the identity token carries.
  rawNonce: z.string().min(16).max(200).optional(),
  authorizationCode: z.string().max(2000).optional(),
  // Apple shares the name only with the app, and only on the first sign-in.
  name: z.string().max(200).optional(),
  acceptedTerms: z.boolean().optional(),
  // "Email me Cave Cals news" on the sign-in screen (off unless ticked).
  newsOptIn: z.boolean().optional(),
  // Google: the picture from its userinfo endpoint, used when the ID token leaves it out (Google image hosts only).
  pictureURL: z.string().url().max(2000).optional(),
  // Local development only.
  devSubject: z.string().min(1).max(100).optional(),
  devEmail: z.string().email().max(254).optional(),
});
export type SignInResult = { session: string; personId: string; isNew: boolean; displayName: string };

export async function signIn(identity: Identity, input: z.infer<typeof signInInput>): Promise<SignInResult> {
  let subject: string, suggestedName = input.name ?? '', pictureURL: string | undefined, refreshToken: string | null = null;
  let email: { email: string; emailPrivate: boolean } | null = null;
  if (input.provider === 'dev') {
    if (!identity.development || !input.devSubject) throw new APIError(403, 'dev_only', 'Development sign-in is local only.');
    subject = input.devSubject;
    if (input.devEmail) email = { email: input.devEmail.toLowerCase(), emailPrivate: false };
  } else {
    if (!input.identityToken || !input.rawNonce) throw new APIError(400, 'invalid_request', 'Some request fields are invalid.');
    const apple = input.provider === 'apple';
    if (!apple && !googleAudiences().length) throw new APIError(503, 'not_configured', 'Google sign-in is not set up yet.');
    const claims = await verifyIdentityToken(input.identityToken, apple
      ? { keysURL: 'https://appleid.apple.com/auth/keys', issuers: ['https://appleid.apple.com'], audiences: appleAudiences(), nonce: input.rawNonce }
      : { keysURL: 'https://www.googleapis.com/oauth2/v3/certs', issuers: ['https://accounts.google.com', 'accounts.google.com'], audiences: googleAudiences(), nonce: input.rawNonce });
    subject = claims.sub;
    email = verifiedEmail(claims);
    if (!apple) { suggestedName = claims.given_name || claims.name || suggestedName; pictureURL = claims.picture || input.pictureURL; }
    else refreshToken = await appleRefreshToken(input.authorizationCode);
  }
  const db = database();
  const [existing] = await db.select().from(clanIdentities).where(and(eq(clanIdentities.provider, input.provider), eq(clanIdentities.subject, subject)));
  let personId = existing?.personId, isNew = false, displayName = '';
  const now = new Date();
  if (personId) {
    if (refreshToken) await db.update(clanIdentities).set({ appleRefreshToken: refreshToken }).where(and(eq(clanIdentities.provider, input.provider), eq(clanIdentities.subject, subject)));
    const [person] = await db.select({ displayName: clanPeople.displayName, newsOptIn: clanPeople.newsOptIn, photoId: clanPeople.photoId }).from(clanPeople).where(eq(clanPeople.id, personId));
    displayName = person?.displayName ?? '';
    // Keep the latest email the provider vouches for; ticking the news box again opts back in.
    const update: Partial<typeof clanPeople.$inferInsert> = email ? { ...email } : {};
    if (input.newsOptIn === true && !person?.newsOptIn) Object.assign(update, { newsOptIn: true, newsOptInAt: now });
    // No photo yet (or the first try failed): use the Google picture.
    if (!person?.photoId && pictureURL) { const photoId = await photoFromURL(pictureURL); if (photoId) update.photoId = photoId; }
    if (Object.keys(update).length) await db.update(clanPeople).set(update).where(eq(clanPeople.id, personId));
  } else {
    if (input.acceptedTerms !== true) throw new APIError(400, 'terms_required', 'Agree to the terms to continue.');
    // A first name from the provider, if it passes the filter; otherwise the app asks for one.
    try { displayName = suggestedName ? cleanDisplayName(suggestedName.split(' ')[0]) : ''; } catch { displayName = ''; }
    personId = randomUUID(); isNew = true;
    await db.transaction(async tx => {
      await tx.insert(clanPeople).values({
        id: personId!, displayName, termsAcceptedAt: now, ...(email ?? {}),
        newsOptIn: input.newsOptIn === true, newsOptInAt: input.newsOptIn === true ? now : null,
      });
      await tx.insert(clanIdentities).values({ provider: input.provider, subject, personId: personId!, appleRefreshToken: refreshToken });
    });
    // A Google profile picture becomes the first photo (re-encoded and stored like any other).
    const photoId = pictureURL ? await photoFromURL(pictureURL) : null;
    if (photoId) await db.update(clanPeople).set({ photoId }).where(eq(clanPeople.id, personId));
  }
  const session = randomBytes(32).toString('base64url');
  await db.insert(clanSessions).values({
    tokenHash: sessionHash(session), personId, accountId: identity.development ? null : identity.accountId,
    membershipOverride: identity.development ? true : identity.testAccess ?? null,
    expiresAt: new Date(Date.now() + SESSION_DAYS * 86_400_000),
  });
  return { session, personId, isNew, displayName };
}

export type ClanSession = { personId: string; accountId: string | null; membershipOverride: boolean | null; tokenHash: string };
// Session routes send the token in `x-clan-session`. Sessions slide forward while they're used.
export async function clanSession(request: Request): Promise<ClanSession> {
  const token = request.headers.get('x-clan-session');
  if (!token || token.length > 100) throw new APIError(401, 'signed_out', 'Sign in to use clans.');
  const hash = sessionHash(token);
  const [row] = await database().select().from(clanSessions).where(and(eq(clanSessions.tokenHash, hash), gt(clanSessions.expiresAt, new Date())));
  if (!row) throw new APIError(401, 'signed_out', 'Sign in to use clans.');
  if (Date.now() - row.lastUsedAt.getTime() > 86_400_000) {
    await database().update(clanSessions).set({ lastUsedAt: sql`now()`, expiresAt: new Date(Date.now() + SESSION_DAYS * 86_400_000) }).where(eq(clanSessions.tokenHash, hash));
  }
  return { personId: row.personId, accountId: row.accountId, membershipOverride: row.membershipOverride, tokenHash: hash };
}
