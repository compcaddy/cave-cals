import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { statsInput, dailyRows, errorFingerprint, clampTime } from '../backend/src/server/stats';
import { adminAuthorized, adminConfigured } from '../backend/src/server/admin-auth';

const report = () => ({
  install: randomUUID(), batch: randomUUID(),
  app: { version: '1.0.5', build: '1', os: '26.0', device: 'iPhone', environment: 'appstore' },
  startedAt: '2026-10-01T15:00:00Z', startedDay: '2026-10-01', existingUser: false, traits: { goal: true, intent: 'lose' },
  days: [{ day: '2026-10-03', counts: { opens: 2, 'items.quickAdd': 3 } }],
  events: [{ id: randomUUID(), name: 'paywall.shown', at: '2026-10-03T16:00:00.123Z', props: { trigger: 'mealScanOpen' } }],
  errors: [{ id: randomUUID(), area: 'mealScan', code: 'no_estimate', message: 'No food found.', location: 'App/AIInputSheet.swift:443', detail: '', at: '2026-10-03T16:01:00Z' }],
});

test('a well-formed stats report is accepted', () => {
  const parsed = statsInput.parse(report());
  assert.equal(parsed.backfill, false);
  assert.equal(parsed.days[0].counts['items.quickAdd'], 3);
});

test('stats reports reject unknown environments, bad names, oversized text, and fractional counts', () => {
  const bad = [
    { ...report(), app: { ...report().app, environment: 'production' } },
    { ...report(), install: 'not-a-uuid' },
    { ...report(), days: [{ day: '2026-10-03', counts: { 'Items quickAdd': 1 } }] },
    { ...report(), days: [{ day: '2026-10-03', counts: { opens: 1.5 } }] },
    { ...report(), days: [{ day: '10/03/2026', counts: { opens: 1 } }] },
    { ...report(), events: [{ id: randomUUID(), name: 'search.missing', at: '2026-10-03T16:00:00Z', props: { query: 'x'.repeat(201) } }] },
    { ...report(), errors: [{ ...report().errors[0], message: 'x'.repeat(501) }] },
    { ...report(), traits: Object.fromEntries(Array.from({ length: 41 }, (_, i) => [`trait${i}`, true])) },
  ];
  for (const value of bad) assert.equal(statsInput.safeParse(value).success, false, JSON.stringify(value).slice(0, 120));
});

test('daily counts merge duplicates, drop zeros, and ignore impossible days', () => {
  const now = new Date('2026-10-03T20:00:00Z');
  const rows = dailyRows('install', [
    { day: '2026-10-03', counts: { opens: 1, 'items.manual': 2 } },
    { day: '2026-10-03', counts: { 'items.manual': 1, undos: 0 } },
    { day: '2024-12-31', counts: { opens: 1 } },
    { day: '2026-10-09', counts: { opens: 1 } },
  ], now);
  assert.deepEqual(rows.map(row => [row.day, row.metric, row.count]).sort(), [['2026-10-03', 'items.manual', 3], ['2026-10-03', 'opens', 1]]);
});

test('error fingerprints ignore numbers, IDs, and line numbers but not the file or code', () => {
  const base = { source: 'app', area: 'mealScan', code: 'server', message: 'Upload 3 of 5 failed for 2f1c2a8e-1b6f-4c1e-9a55-0c8d2b1f3e4a', location: 'App/AIInputSheet.swift:443' };
  assert.equal(errorFingerprint(base), errorFingerprint({ ...base, message: 'Upload 1 of 2 failed for 11111111-2222-4333-8444-555555555555', location: 'App/AIInputSheet.swift:450' }));
  assert.notEqual(errorFingerprint(base), errorFingerprint({ ...base, code: 'timeout' }));
  assert.notEqual(errorFingerprint(base), errorFingerprint({ ...base, location: 'App/BarcodeScanner.swift:70' }));
});

test('reported times are kept between the app launch era and now', () => {
  const now = new Date('2026-10-03T20:00:00Z');
  assert.equal(clampTime('2030-01-01T00:00:00Z', now).toISOString(), now.toISOString());
  assert.equal(clampTime('2001-01-01T00:00:00Z', now).toISOString(), '2025-01-01T00:00:00.000Z');
  assert.equal(clampTime('2026-10-02T00:00:00Z', now).toISOString(), '2026-10-02T00:00:00.000Z');
});

test('admin pages need a long password and accept it with any user name', () => {
  const env = process.env as Record<string, string | undefined>, before = env.ADMIN_PASSWORD;
  const basic = (value: string) => `Basic ${Buffer.from(value).toString('base64')}`;
  try {
    env.ADMIN_PASSWORD = 'short';
    assert.equal(adminConfigured(), false);
    assert.equal(adminAuthorized(basic('admin:short')), false);
    env.ADMIN_PASSWORD = 'correct horse battery staple';
    assert.equal(adminConfigured(), true);
    assert.equal(adminAuthorized(basic('phil:correct horse battery staple')), true);
    assert.equal(adminAuthorized(basic(':correct horse battery staple')), true);
    assert.equal(adminAuthorized(basic('admin:correct horse battery stapl')), false);
    assert.equal(adminAuthorized(basic('correct horse battery staple')), false);
    assert.equal(adminAuthorized(null), false);
    assert.equal(adminAuthorized('Bearer correct horse battery staple'), false);
  } finally { if (before === undefined) delete env.ADMIN_PASSWORD; else env.ADMIN_PASSWORD = before; }
});
