import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { authorizedTestAccess, ownerTestAccess } from '../backend/src/server/test-access';
import { entitlement, requirePaid } from '../backend/src/server/apple';

test('private test capability fails closed and supports explicit free access', async () => {
  const previous = process.env.AI_TEST_ACCESS_KEY_SHA256;
  const key = 'test-only-credential-with-at-least-32-characters';
  try {
    delete process.env.AI_TEST_ACCESS_KEY_SHA256;
    assert.equal(authorizedTestAccess(undefined), undefined);
    assert.throws(() => authorizedTestAccess({ key, active: true }));
    process.env.AI_TEST_ACCESS_KEY_SHA256 = createHash('sha256').update(key).digest('hex');
    assert.throws(() => authorizedTestAccess({ key: 'wrong'.repeat(10), active: true }));
    assert.throws(() => authorizedTestAccess({ key, active: 'true' }));
    assert.equal(authorizedTestAccess({ key, active: true }), true);
    assert.equal(authorizedTestAccess({ key, active: false }), false);
    assert.equal(ownerTestAccess({ key, active: true }, 'account/status'), true);
    assert.equal(ownerTestAccess({ key, active: false }, 'uploads/sign'), false);
    assert.equal(ownerTestAccess({ key, active: true }, 'food/analyze'), true);
    assert.equal(ownerTestAccess({ key, active: true }, 'meal/import'), true);
    assert.equal(ownerTestAccess({ key, active: false }, 'food/macros'), false);
    assert.throws(() => ownerTestAccess(undefined, 'account/status'));
    assert.throws(() => ownerTestAccess({ key, active: true }, 'purchase/verify'));
    assert.throws(() => ownerTestAccess({ key: 'forged'.repeat(8), active: true }, 'account/status'));
    const identity = { accountId: 'test', keyId: 'verified-device', development: false };
    assert.equal((await entitlement({ ...identity, testAccess: true })).active, true);
    await assert.rejects(requirePaid({ ...identity, testAccess: false }), { code: 'subscription_required' });
    delete process.env.AI_TEST_ACCESS_KEY_SHA256;
    assert.throws(() => authorizedTestAccess({ key, active: true }));
  } finally {
    if (previous === undefined) delete process.env.AI_TEST_ACCESS_KEY_SHA256;
    else process.env.AI_TEST_ACCESS_KEY_SHA256 = previous;
  }
});
