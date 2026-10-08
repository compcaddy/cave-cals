import { pgTable, uuid, text, integer, timestamp, jsonb, index, boolean, date, primaryKey } from 'drizzle-orm/pg-core';
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
