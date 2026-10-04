import { createHash, randomUUID } from 'node:crypto';
import { sql } from 'drizzle-orm';
import { z } from 'zod';
import { database } from './db';
import { usageBatches, usageInstalls, usageDaily, usageEvents, appErrors } from './schema';
import { consume, tomorrow, utcDay } from './rate-limit';

const name = z.string().regex(/^[a-z][A-Za-z0-9.]{0,47}$/);
const key = z.string().regex(/^[a-z][A-Za-z0-9]{0,31}$/);
const value = z.union([z.string().max(200), z.number().finite(), z.boolean()]);
const props = z.record(key, value).refine(p => Object.keys(p).length <= 16, 'Too many properties.');
const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);
const time = z.iso.datetime();
export const statsInput = z.object({
  install: z.uuid(),
  batch: z.uuid(),
  app: z.object({
    version: z.string().min(1).max(20),
    build: z.string().max(20),
    os: z.string().min(1).max(20),
    device: z.string().min(1).max(20),
    environment: z.enum(['appstore', 'testflight', 'debug']),
  }),
  startedAt: time,
  startedDay: day,
  existingUser: z.boolean(),
  traits: z.record(key, value).refine(t => Object.keys(t).length <= 40, 'Too many traits.'),
  // A one-time report of the diary's history from before stats existed on this iPhone.
  backfill: z.boolean().default(false),
  days: z.array(z.object({
    day,
    counts: z.record(name, z.number().int().min(-10_000).max(100_000)).refine(c => Object.keys(c).length <= 60, 'Too many metrics.'),
  })).max(1000),
  events: z.array(z.object({ id: z.uuid(), name, at: time, props })).max(300),
  errors: z.array(z.object({
    id: z.uuid(),
    area: name,
    code: z.string().min(1).max(80),
    message: z.string().max(500),
    location: z.string().max(120),
    detail: z.string().max(2000),
    at: time,
  })).max(100),
});
export type StatsInput = z.infer<typeof statsInput>;

/** Repeats of one error share a fingerprint; numbers and IDs in messages vary, so they're normalized away. */
export function errorFingerprint(e: { source: string; area: string; code: string; message: string; location: string }) {
  const message = e.message.toLowerCase()
    .replace(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/g, '<id>')
    .replace(/\d+(\.\d+)?/g, '#');
  // Line numbers move with every edit, so group by file and keep the exact line in `location` only.
  const file = e.location.replace(/:\d+$/, '');
  return createHash('sha256').update([e.source, e.area, e.code, message, file].join('\n')).digest('hex').slice(0, 16);
}

/** Keeps reported times sensible: phone clocks drift, and nothing predates the app. */
export function clampTime(value: string | Date, now = new Date()) {
  const time = new Date(value).getTime();
  return new Date(Math.min(Math.max(time, Date.UTC(2025, 0, 1)), now.getTime()));
}

/** Merges a report's daily counts into one row per day and metric, skipping zeros. */
export function dailyRows(installId: string, days: StatsInput['days'], now = new Date()) {
  const latest = new Date(now.getTime() + 36 * 3600_000).toISOString().slice(0, 10);
  const totals = new Map<string, { installId: string; day: string; metric: string; count: number }>();
  for (const { day, counts } of days) {
    if (day < '2025-01-01' || day > latest) continue;
    for (const [metric, count] of Object.entries(counts)) {
      const id = `${day}|${metric}`;
      const row = totals.get(id) ?? { installId, day, metric, count: 0 };
      row.count += count;
      totals.set(id, row);
    }
  }
  return [...totals.values()].filter(row => row.count !== 0);
}

async function limitStats(request: Request, install: string) {
  const ip = process.env.VERCEL ? request.headers.get('x-vercel-forwarded-for') || 'unknown' : 'local';
  const hash = createHash('sha256').update(`stats:${utcDay()}:${ip}`).digest('hex');
  // Separate buckets from device registration, so stats traffic can never use up that budget.
  await consume(`stats:${hash}:${new Date().toISOString().slice(0, 13)}`, 120, tomorrow());
  await consume(`stats-install:${install}:${utcDay()}`, 100, tomorrow());
  await consume(`stats-global:${utcDay()}`, 250_000, tomorrow());
}

export async function recordStats(request: Request, input: StatsInput) {
  await limitStats(request, input.install);
  const now = new Date();
  const country = process.env.VERCEL ? request.headers.get('x-vercel-ip-country')?.slice(0, 2) || null : null;
  const install = {
    id: input.install,
    startedAt: clampTime(input.startedAt, now),
    startedDay: input.startedDay,
    existingUser: input.existingUser,
    environment: input.app.environment,
    appVersion: input.app.version,
    osVersion: input.app.os,
    device: input.app.device,
    country,
    traits: { ...input.traits, build: input.app.build },
  };
  await database().transaction(async tx => {
    const [fresh] = await tx.insert(usageBatches).values({ id: input.batch }).onConflictDoNothing().returning({ id: usageBatches.id });
    // A retry of a report that already arrived: acknowledge it without counting anything twice.
    if (!fresh) return;
    const [stored] = await tx.insert(usageInstalls).values(install).onConflictDoUpdate({
      target: usageInstalls.id,
      set: {
        lastSeenAt: sql`now()`,
        // Diary history can arrive from iCloud after the first report, revealing an earlier start.
        startedAt: sql`least(${usageInstalls.startedAt}, excluded.started_at)`,
        startedDay: sql`least(${usageInstalls.startedDay}, excluded.started_day)`,
        existingUser: sql`${usageInstalls.existingUser} or excluded.existing_user`,
        environment: install.environment, appVersion: install.appVersion, osVersion: install.osVersion,
        device: install.device, traits: install.traits,
        country: sql`coalesce(excluded.country, ${usageInstalls.country})`,
      },
    }).returning({ backfilledAt: usageInstalls.backfilledAt });
    // History is counted once per install, even if the app loses track of having sent it.
    const days = input.backfill && stored.backfilledAt ? [] : input.days;
    if (input.backfill && !stored.backfilledAt) {
      await tx.update(usageInstalls).set({ backfilledAt: now }).where(sql`${usageInstalls.id} = ${input.install}`);
    }
    const rows = dailyRows(input.install, days, now);
    for (let i = 0; i < rows.length; i += 500) {
      await tx.insert(usageDaily).values(rows.slice(i, i + 500)).onConflictDoUpdate({
        target: [usageDaily.installId, usageDaily.day, usageDaily.metric],
        set: { count: sql`${usageDaily.count} + excluded.count` },
      });
    }
    if (input.events.length) {
      await tx.insert(usageEvents).values(input.events.map(event => ({
        id: event.id, installId: input.install, name: event.name, at: clampTime(event.at, now), props: event.props, appVersion: input.app.version,
      }))).onConflictDoNothing();
    }
    if (input.errors.length) {
      await tx.insert(appErrors).values(input.errors.map(error => ({
        ...error, installId: input.install, source: 'app', at: clampTime(error.at, now),
        fingerprint: errorFingerprint({ ...error, source: 'app' }),
        appVersion: input.app.version, osVersion: input.app.os,
      }))).onConflictDoNothing();
    }
  });
}

/**
 * Records an unexpected backend failure for the admin error list. Only the error's type, code, and stack
 * frames are kept: messages can echo upstream responses, SQL parameters, or request content.
 */
export async function recordServerError(path: string, error: unknown) {
  const name = error instanceof Error ? error.name : 'UnknownError';
  const code = typeof (error as { code?: unknown })?.code === 'string' || typeof (error as { code?: unknown })?.code === 'number'
    ? String((error as { code: string | number }).code).slice(0, 40) : '';
  const frames = error instanceof Error && error.stack
    ? error.stack.split('\n').filter(line => line.trimStart().startsWith('at ')).slice(0, 12).map(line => line.trim()).join('\n')
    : '';
  const report = { source: 'server', area: path.slice(0, 48) || 'unknown', code: code ? `${name}:${code}` : name, message: name, location: `api/v1/${path}`.slice(0, 120) };
  await database().insert(appErrors).values({
    id: randomUUID(), ...report, detail: frames.slice(0, 2000), fingerprint: errorFingerprint(report), at: new Date(),
  });
}
