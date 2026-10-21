import assert from 'node:assert/strict';

// Exact known development endpoints only. Android tests use an empty database on their isolated branch,
// so expiry/cleanup tests never operate on the production data copied when the branch was created.
export function assertTestDatabase() {
  const url = new URL(process.env.DATABASE_URL || 'postgres://invalid');
  const host = url.hostname.replace('-pooler.', '.');
  const branch = process.env.NEON_TEST_BRANCH;
  const existing = branch === 'backend-dev' && host === 'ep-lingering-unit-axuq6fwj.c-4.us-east-2.aws.neon.tech' && url.pathname === '/neondb';
  const android = branch === 'codex/android-parity' && host === 'ep-raspy-brook-axiqvsj8.c-4.us-east-2.aws.neon.tech' && url.pathname === '/android_test';
  assert.ok(existing || android, 'Refusing to run integration tests outside a known development database.');
}
