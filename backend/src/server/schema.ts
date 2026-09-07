import { pgTable, uuid, text, integer, timestamp, jsonb, index } from 'drizzle-orm/pg-core';
export const accounts = pgTable('ai_accounts', {
  id: uuid('id').primaryKey(),
  originalTransactionId: text('original_transaction_id').unique(),
  environment: text('environment'),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
});
export const devices = pgTable('ai_devices', {
  keyId: text('key_id').primaryKey(), accountId: uuid('account_id').notNull().references(() => accounts.id),
  publicKey: text('public_key').notNull(), signCount: integer('sign_count').notNull().default(0),
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
  state: text('state').notNull().default('pending'), result: jsonb('result'),
  expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, t => [index('ai_uploads_expiry_idx').on(t.expiresAt)]);
