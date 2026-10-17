import { pgTable, uuid, text, integer, timestamp, jsonb, index, uniqueIndex, boolean, date, primaryKey } from 'drizzle-orm/pg-core';
import { sql } from 'drizzle-orm';
export const accounts = pgTable('ai_accounts', {
  id: uuid('id').primaryKey(),
  scansUsed: integer('scans_used').notNull().default(0),
  regularLogCount: integer('regular_log_count').notNull().default(0),
  originalTransactionId: text('original_transaction_id').unique(),
  environment: text('environment'),
  // SHA-256 of the install key the app keeps in its Keychain; reinstalls on the same iPhone carry usage forward.
  trialKeyHash: text('trial_key_hash'),
  // Last Apple-verified subscription state, rechecked after a short TTL or an App Store notification.
  subscriptionExpiresAt: timestamp('subscription_expires_at', { withTimezone: true }),
  subscriptionCheckedAt: timestamp('subscription_checked_at', { withTimezone: true }),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, t => [index('ai_accounts_trial_key_idx').on(t.trialKeyHash)]);
export const devices = pgTable('ai_devices', {
  keyId: text('key_id').primaryKey(), accountId: uuid('account_id').notNull().references(() => accounts.id),
  publicKey: text('public_key').notNull(), signCount: integer('sign_count').notNull().default(0),
  // Identifies the physical iPhone across App Attest key replacements (reinstalls).
  trialKeyHash: text('trial_key_hash'),
  lastSeen: timestamp('last_seen', { withTimezone: true }).defaultNow().notNull(),
}, t => [index('ai_devices_account_idx').on(t.accountId)]);
export const challenges = pgTable('ai_challenges', {
  nonce: text('nonce').primaryKey(), keyId: text('key_id').notNull(), purpose: text('purpose').notNull(),
  expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
});
export const limits = pgTable('ai_limits', {
  bucket: text('bucket').primaryKey(), count: integer('count').notNull(),
  expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
});
export const uploads = pgTable('ai_uploads', {
  id: uuid('id').primaryKey(), accountId: uuid('account_id').notNull().references(() => accounts.id),
  pathname: text('pathname').notNull(), kind: text('kind').notNull(), mime: text('mime').notNull(),
  byteLength: integer('byte_length').notNull(), sha256: text('sha256').notNull(), storage: text('storage').notNull(),
  scanReservedUntil: timestamp('scan_reserved_until', { withTimezone: true }),
  state: text('state').notNull().default('pending'), result: jsonb('result'),
  expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, t => [index('ai_uploads_expiry_idx').on(t.expiresAt)]);

// Anonymous usage statistics. Each iPhone reports under a random ID kept in its Keychain, never linked to
// the AI account or purchases. Counts only: no food names, calories, weights, or Health data. The one piece
// of typed text kept is a search that found nothing anywhere (`search.missing` events).
export const usageInstalls = pgTable('usage_installs', {
  id: uuid('id').primaryKey(),
  firstSeenAt: timestamp('first_seen_at', { withTimezone: true }).defaultNow().notNull(),
  // When this person started: first launch for new installs, earliest diary entry for people who had the app before stats.
  startedAt: timestamp('started_at', { withTimezone: true }).notNull(),
  // The same moment as the person's own calendar day, to compare with their daily counts.
  startedDay: date('started_day').notNull(),
  existingUser: boolean('existing_user').notNull().default(false),
  lastSeenAt: timestamp('last_seen_at', { withTimezone: true }).defaultNow().notNull(),
  // appstore | testflight | debug
  environment: text('environment').notNull(),
  appVersion: text('app_version').notNull(),
  osVersion: text('os_version').notNull(),
  device: text('device').notNull(),
  country: text('country'),
  // Setup and feature state from the latest report (goal set, tracking choices, Cave Cals+, Health, widget…).
  traits: jsonb('traits').notNull().default({}),
  backfilledAt: timestamp('backfilled_at', { withTimezone: true }),
}, t => [index('usage_installs_started_idx').on(t.startedAt)]);
export const usageDaily = pgTable('usage_daily', {
  installId: uuid('install_id').notNull().references(() => usageInstalls.id, { onDelete: 'cascade' }),
  // The person's own calendar day, so "items per day" follows their day, not the server's.
  day: date('day').notNull(),
  metric: text('metric').notNull(),
  count: integer('count').notNull(),
}, t => [primaryKey({ columns: [t.installId, t.day, t.metric] }), index('usage_daily_day_idx').on(t.day)]);
export const usageEvents = pgTable('usage_events', {
  id: uuid('id').primaryKey(),
  installId: uuid('install_id').notNull().references(() => usageInstalls.id, { onDelete: 'cascade' }),
  name: text('name').notNull(),
  at: timestamp('at', { withTimezone: true }).notNull(),
  props: jsonb('props').notNull().default({}),
  appVersion: text('app_version').notNull(),
}, t => [index('usage_events_name_at_idx').on(t.name, t.at), index('usage_events_install_at_idx').on(t.installId, t.at)]);
// Each report is applied once; a retried report with the same ID is acknowledged without counting again.
export const usageBatches = pgTable('usage_batches', {
  id: uuid('id').primaryKey(),
  receivedAt: timestamp('received_at', { withTimezone: true }).defaultNow().notNull(),
}, t => [index('usage_batches_received_idx').on(t.receivedAt)]);
export const appErrors = pgTable('app_errors', {
  id: uuid('id').primaryKey(),
  // Null for backend errors, which aren't tied to an install.
  installId: uuid('install_id').references(() => usageInstalls.id, { onDelete: 'cascade' }),
  source: text('source').notNull(), // app | server
  area: text('area').notNull(),
  code: text('code').notNull(),
  message: text('message').notNull(),
  // file:line in the app, or the API path for backend errors.
  location: text('location').notNull().default(''),
  detail: text('detail').notNull().default(''),
  // Groups repeats of the same error (see `errorFingerprint`).
  fingerprint: text('fingerprint').notNull(),
  appVersion: text('app_version').notNull().default(''),
  osVersion: text('os_version').notNull().default(''),
  at: timestamp('at', { withTimezone: true }).notNull(),
}, t => [index('app_errors_fingerprint_at_idx').on(t.fingerprint, t.at), index('app_errors_at_idx').on(t.at)]);
// Marked fixed in the admin page; a later occurrence reopens the group.
export const errorResolutions = pgTable('error_resolutions', {
  fingerprint: text('fingerprint').primaryKey(),
  resolvedAt: timestamp('resolved_at', { withTimezone: true }).defaultNow().notNull(),
});

// Creator and trainer discount codes, added by the owner on /admin/codes. Each has a page at CaveCals.com/<code>.
export const discountCodes = pgTable('discount_codes', {
  // Capital letters and digits (SARAH). Links and typed codes ignore capitals.
  code: text('code').primaryKey(),
  // Who shares it, shown on the code's page: "Sarah".
  name: text('name').notNull(),
  // App Store Connect campaign token (`ct`) on the page's App Store link.
  campaign: text('campaign').notNull(),
  // The RevenueCat offering the app shows once the code is applied.
  offering: text('offering').notNull().default('discount'),
  active: boolean('active').notNull().default(true),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
});
// Totals per code and Pacific day: page visits, App Store button taps, and codes applied in the app.
// Counts only; no IPs, cookies, or device identifiers are kept.
export const discountCodeDaily = pgTable('discount_code_daily', {
  code: text('code').notNull().references(() => discountCodes.code, { onDelete: 'cascade' }),
  day: date('day').notNull(),
  visits: integer('visits').notNull().default(0),
  storeTaps: integer('store_taps').notNull().default(0),
  applies: integer('applies').notNull().default(0),
}, t => [primaryKey({ columns: [t.code, t.day] })]);

// Clans (Documentation/Clans.md). People sign in with Apple or Google only to use clans. The diary never
// reaches the server: each phone sends one small report per day (logged, full day, % of goal).
export const clanPeople = pgTable('clan_people', {
  id: uuid('id').primaryKey(),
  displayName: text('display_name').notNull(),
  // The current profile photo (512-px JPEG in private storage); null shows initials.
  photoId: uuid('photo_id'),
  birthYear: integer('birth_year'),
  birthMonth: integer('birth_month'),
  // IANA zone from the latest daily report; days lock at 9 AM here.
  timeZone: text('time_zone').notNull().default('America/Los_Angeles'),
  // Alert kinds turned off in Settings → Clans ({ "nudge": false, … }).
  alertPrefs: jsonb('alert_prefs').notNull().default({}),
  // The local day the 7 PM "fire going out" alert last went out, so it goes once a day.
  eveningAlertOn: date('evening_alert_on'),
  termsAcceptedAt: timestamp('terms_accepted_at', { withTimezone: true }).notNull(),
  // From Apple or Google sign-in (verified by them). Apple's may be a private relay address.
  email: text('email'),
  emailPrivate: boolean('email_private').notNull().default(false),
  // "Email me Cave Cals news": off unless the person turns it on, with when they did either.
  newsOptIn: boolean('news_opt_in').notNull().default(false),
  newsOptInAt: timestamp('news_opt_in_at', { withTimezone: true }),
  newsOptOutAt: timestamp('news_opt_out_at', { withTimezone: true }),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
});
export const clanIdentities = pgTable('clan_identities', {
  provider: text('provider').notNull(), // apple | google | dev
  subject: text('subject').notNull(),
  personId: uuid('person_id').notNull().references(() => clanPeople.id, { onDelete: 'cascade' }),
  // Encrypted Apple refresh token, revoked when the clan account is deleted (Apple requires it).
  appleRefreshToken: text('apple_refresh_token'),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, t => [primaryKey({ columns: [t.provider, t.subject] }), index('clan_identities_person_idx').on(t.personId)]);
export const clanSessions = pgTable('clan_sessions', {
  // SHA-256 of the random session token the app keeps in its Keychain.
  tokenHash: text('token_hash').primaryKey(),
  personId: uuid('person_id').notNull().references(() => clanPeople.id, { onDelete: 'cascade' }),
  // The signing-in iPhone's AI account, used to check Cave Cals+ for clans of three or more.
  accountId: uuid('account_id'),
  // Local development and private test access decide Cave Cals+ themselves instead of Apple.
  membershipOverride: boolean('membership_override'),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  lastUsedAt: timestamp('last_used_at', { withTimezone: true }).defaultNow().notNull(),
  expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
}, t => [index('clan_sessions_person_idx').on(t.personId)]);
export const clanPushTokens = pgTable('clan_push_tokens', {
  token: text('token').primaryKey(),
  personId: uuid('person_id').notNull().references(() => clanPeople.id, { onDelete: 'cascade' }),
  environment: text('environment').notNull(), // sandbox | production
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
}, t => [index('clan_push_tokens_person_idx').on(t.personId)]);
export const clans = pgTable('clans', {
  id: uuid('id').primaryKey(),
  name: text('name').notNull(),
  inviteCode: text('invite_code').notNull().unique(),
  accountability: text('accountability').notNull().default('off'), // off | logged | percent
  // What "on target" means here ({ kind: atOrUnder | withinPercent | upToPercentOver, percent }).
  rule: jsonb('rule').notNull().default({ kind: 'atOrUnder', percent: 5 }),
  ruleChoice: text('rule_choice').notNull().default('clan'), // clan | member
  bestStreak: integer('best_streak').notNull().default(0),
  // approval: an admin lets each person in (the default, so a guessed code isn't enough); open: the code is enough.
  joinMode: text('join_mode').notNull().default('approval'),
  createdBy: uuid('created_by').references(() => clanPeople.id, { onDelete: 'set null' }),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
});
// People waiting for an admin to let them in (clans with join_mode approval).
export const clanJoinRequests = pgTable('clan_join_requests', {
  clanId: uuid('clan_id').notNull().references(() => clans.id, { onDelete: 'cascade' }),
  personId: uuid('person_id').notNull().references(() => clanPeople.id, { onDelete: 'cascade' }),
  anonymous: boolean('anonymous').notNull().default(false),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, t => [primaryKey({ columns: [t.clanId, t.personId] }), index('clan_join_requests_person_idx').on(t.personId)]);
export const clanMembers = pgTable('clan_members', {
  id: uuid('id').primaryKey(),
  clanId: uuid('clan_id').notNull().references(() => clans.id, { onDelete: 'cascade' }),
  personId: uuid('person_id').notNull().references(() => clanPeople.id, { onDelete: 'cascade' }),
  role: text('role').notNull().default('member'), // owner | admin | member
  // Shown as "Cave person N" with no photo; admins can't see through it.
  anonymous: boolean('anonymous').notNull().default(false),
  anonNumber: integer('anon_number'),
  muted: boolean('muted').notNull().default(false),
  // The member's own on-target rule, when the clan lets members choose.
  rule: jsonb('rule'),
  joinedAt: timestamp('joined_at', { withTimezone: true }).defaultNow().notNull(),
  leftAt: timestamp('left_at', { withTimezone: true }),
  removedBy: uuid('removed_by'),
}, t => [
  index('clan_members_clan_idx').on(t.clanId), index('clan_members_person_idx').on(t.personId),
  uniqueIndex('clan_members_active_idx').on(t.clanId, t.personId).where(sql`${t.leftAt} is null`),
]);
// One report per person and local day, shared by all of their clans. Locked days never change.
export const clanDays = pgTable('clan_days', {
  personId: uuid('person_id').notNull().references(() => clanPeople.id, { onDelete: 'cascade' }),
  day: date('day').notNull(),
  logged: boolean('logged').notNull(),
  fullDay: boolean('full_day').notNull(),
  // Calories as a whole % of the person's goal; null without a goal. Never calories or the goal itself.
  percentOfGoal: integer('percent_of_goal'),
  // The goal is at least 1,200 (women) / 1,500 (men); lower goals can't earn on-target days.
  goalOk: boolean('goal_ok').notNull(),
  doneEating: boolean('done_eating').notNull().default(false),
  reportedAt: timestamp('reported_at', { withTimezone: true }).defaultNow().notNull(),
}, t => [primaryKey({ columns: [t.personId, t.day] })]);
export const clanChallenges = pgTable('clan_challenges', {
  id: uuid('id').primaryKey(),
  clanId: uuid('clan_id').notNull().references(() => clans.id, { onDelete: 'cascade' }),
  kind: text('kind').notNull(), // loggingDays | onTargetDays | teamTotal | survivor | streak | weightLoss
  // Type-specific rules: basis, anyFood, rule, streak mode/percent, team target, survivor ending.
  settings: jsonb('settings').notNull().default({}),
  savesCount: integer('saves_count').notNull().default(0),
  savesPeriod: text('saves_period').notNull().default('challenge'), // week | month | challenge
  startsOn: date('starts_on').notNull(),
  // Null while open-ended (streaks, open Survivor).
  endsOn: date('ends_on'),
  status: text('status').notNull().default('upcoming'), // upcoming | active | ended | canceled
  result: jsonb('result'),
  evaluatedAt: timestamp('evaluated_at', { withTimezone: true }),
  createdBy: uuid('created_by').references(() => clanPeople.id, { onDelete: 'set null' }),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  endedAt: timestamp('ended_at', { withTimezone: true }),
}, t => [index('clan_challenges_clan_idx').on(t.clanId, t.status)]);
export const clanEntrants = pgTable('clan_entrants', {
  challengeId: uuid('challenge_id').notNull().references(() => clanChallenges.id, { onDelete: 'cascade' }),
  personId: uuid('person_id').notNull().references(() => clanPeople.id, { onDelete: 'cascade' }),
  status: text('status').notNull().default('in'), // in | out | left
  joinedAt: timestamp('joined_at', { withTimezone: true }).defaultNow().notNull(),
  leftOn: date('left_on'),
  outOn: date('out_on'),
  // Cached by the last evaluation, for lists and the Home strip.
  points: integer('points').notNull().default(0),
  livesLeft: integer('lives_left'),
  rank: integer('rank'),
  // Weight challenges: only percentages from the phone ({ startReady, changePct, finalPct, endReady }).
  weight: jsonb('weight'),
}, t => [primaryKey({ columns: [t.challengeId, t.personId] }), index('clan_entrants_person_idx').on(t.personId)]);
export const clanAlerts = pgTable('clan_alerts', {
  id: uuid('id').primaryKey(),
  personId: uuid('person_id').notNull().references(() => clanPeople.id, { onDelete: 'cascade' }),
  clanId: uuid('clan_id').references(() => clans.id, { onDelete: 'cascade' }),
  kind: text('kind').notNull(),
  payload: jsonb('payload').notNull().default({}),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  readAt: timestamp('read_at', { withTimezone: true }),
}, t => [index('clan_alerts_person_idx').on(t.personId, t.readAt)]);
// One nudge (or cheer) per sender, person, and day.
export const clanNudges = pgTable('clan_nudges', {
  fromId: uuid('from_id').notNull().references(() => clanPeople.id, { onDelete: 'cascade' }),
  toId: uuid('to_id').notNull().references(() => clanPeople.id, { onDelete: 'cascade' }),
  clanId: uuid('clan_id').notNull().references(() => clans.id, { onDelete: 'cascade' }),
  day: date('day').notNull(),
  kind: text('kind').notNull(), // nudge | cheer
}, t => [primaryKey({ columns: [t.fromId, t.toId, t.day, t.kind] })]);
export const clanBlocks = pgTable('clan_blocks', {
  blockerId: uuid('blocker_id').notNull().references(() => clanPeople.id, { onDelete: 'cascade' }),
  blockedId: uuid('blocked_id').notNull().references(() => clanPeople.id, { onDelete: 'cascade' }),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, t => [primaryKey({ columns: [t.blockerId, t.blockedId] })]);
// Reported names and photos, handled by the owner on /admin/reports.
export const clanReports = pgTable('clan_reports', {
  id: uuid('id').primaryKey(),
  reporterId: uuid('reporter_id').references(() => clanPeople.id, { onDelete: 'set null' }),
  kind: text('kind').notNull(), // name | photo | clanName
  targetPersonId: uuid('target_person_id').references(() => clanPeople.id, { onDelete: 'set null' }),
  targetClanId: uuid('target_clan_id').references(() => clans.id, { onDelete: 'set null' }),
  // What was reported, as it was then (the name, or the photo's ID).
  snapshot: text('snapshot').notNull(),
  reason: text('reason').notNull().default(''),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  resolvedAt: timestamp('resolved_at', { withTimezone: true }),
  resolution: text('resolution'),
}, t => [index('clan_reports_open_idx').on(t.resolvedAt, t.createdAt)]);

// News emails written and sent on /admin/email (Amazon SES), only to people who opted in.
export const emailCampaigns = pgTable('email_campaigns', {
  id: uuid('id').primaryKey(),
  subject: text('subject').notNull(),
  body: text('body').notNull(),
  status: text('status').notNull().default('sending'), // sending | sent | failed
  recipients: integer('recipients').notNull().default(0),
  sent: integer('sent').notNull().default(0),
  failed: integer('failed').notNull().default(0),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  finishedAt: timestamp('finished_at', { withTimezone: true }),
});
