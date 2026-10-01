import { pgTable, uuid, text, integer, timestamp, jsonb, index } from 'drizzle-orm/pg-core';
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
