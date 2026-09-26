import test from 'node:test';
import assert from 'node:assert/strict';
import { cachedEntitlement, ACTIVE_ENTITLEMENT_TTL_MS, INACTIVE_ENTITLEMENT_TTL_MS } from '../backend/src/server/apple';
import { trialKeyPattern, trialKeyHash } from '../backend/src/server/auth';
import { describeInput } from '../backend/src/server/analysis';
import { randomBytes } from 'node:crypto';

test('a verified subscription is reused briefly but never past its expiry', () => {
  const now = Date.UTC(2026, 8, 25, 12);
  const checked = new Date(now - 60_000);
  const expires = new Date(now + 30 * 86_400_000);
  assert.deepEqual(cachedEntitlement(expires, checked, now), { active: true, expiresAt: expires.toISOString() });
  assert.equal(cachedEntitlement(expires, new Date(now - ACTIVE_ENTITLEMENT_TTL_MS), now), undefined);
  assert.equal(cachedEntitlement(new Date(now - 1), checked, now)?.active, false);
  assert.equal(cachedEntitlement(expires, null, now), undefined);
  // A clock-skewed future check time is never trusted.
  assert.equal(cachedEntitlement(expires, new Date(now + 60_000), now), undefined);
});

test('an inactive answer is only cached for a few minutes, so new purchases show up quickly', () => {
  const now = Date.UTC(2026, 8, 25, 12);
  assert.deepEqual(cachedEntitlement(null, new Date(now - 60_000), now), { active: false, expiresAt: null });
  assert.equal(cachedEntitlement(null, new Date(now - INACTIVE_ENTITLEMENT_TTL_MS), now), undefined);
});

test('install keys have a fixed high-entropy shape and are stored only as hashes', () => {
  const key = randomBytes(32).toString('base64url');
  assert.match(key, trialKeyPattern);
  for (const bad of ['', 'short', `${key}=`, `${key.slice(0, 42)}/`]) assert.doesNotMatch(bad, trialKeyPattern);
  assert.match(trialKeyHash(key), /^[a-f0-9]{64}$/);
  assert.notEqual(trialKeyHash(key), key);
});

test('spoken descriptions are bounded plain text', () => {
  assert.equal(describeInput.parse({ text: '  two eggs and toast ' }).text, 'two eggs and toast');
  for (const text of ['', 'x', 'a'.repeat(501), 'eggs\u0000', 42]) assert.equal(describeInput.safeParse({ text }).success, false);
});
