import test from 'node:test';
import assert from 'node:assert/strict';
import { scanAllowance, scanUsageInput } from '../backend/src/server/scan-access';

test('free scans end at either exact lifetime threshold; paid access stays separate', () => {
  assert.equal(scanAllowance(false, 0, 0).freeScansRemaining, 10);
  assert.equal(scanAllowance(false, 9, 99).canScan, true);
  assert.equal(scanAllowance(false, 10, 0).canScan, false);
  assert.equal(scanAllowance(false, 0, 100).canScan, false);
  assert.equal(scanAllowance(true, 1000, 100).canScan, true);
  assert.equal(scanAllowance(false, 1000, 100).freeScansRemaining, 0);
});

test('usage claims reject negative, fractional, string and excessive counts', () => {
  for (const regularLogCount of [-1, 1.2, '100', 1_000_001, null]) {
    assert.equal(scanUsageInput.safeParse({ regularLogCount }).success, false);
  }
  assert.equal(scanUsageInput.parse({}).regularLogCount, 0);
});
