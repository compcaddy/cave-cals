import { createHash } from 'node:crypto';
import { and, eq, sql, type SQL } from 'drizzle-orm';
import { z } from 'zod';
import { APIError, positiveInt } from './config';
import { database } from './db';
import { consume, tomorrow, utcDay } from './rate-limit';
import { discountCodes, discountCodeDaily } from './schema';

// Creator and trainer discount codes. Each code has a page at CaveCals.com/<code> (any capitalization) whose
// App Store button carries the code's App Store Connect campaign token, and the app checks typed codes here.
// A code only picks which RevenueCat offering the app shows; Apple sets the prices.

/** Cave Cals on the App Store. */
export const APP_STORE_ID = '6809208501';
export const SITE = 'cavecals.com';
const DEFAULT_STORE_URL = `https://apps.apple.com/us/app/cave-cals-ai-calorie-tracker/id${APP_STORE_ID}`;
const TZ = sql.raw(`'America/Los_Angeles'`);
/** Days follow the owner's time zone, like the admin pages. */
const TODAY = sql`(now() at time zone ${TZ})::date`;

export const CODE_PATTERN = /^[A-Z0-9]{2,30}$/;
/** Typed codes ignore capitals, spaces, and punctuation: "sarah-30 " is SARAH30. */
export function normalizeCode(value: string) {
  return value.normalize('NFKC').toUpperCase().replace(/[^A-Z0-9]/g, '');
}
/** A page address (CaveCals.com/Sarah) in any capitalization. Anything else, like favicon.ico, isn't a code. */
export function linkCode(segment: string) {
  return /^[A-Za-z0-9]{2,30}$/.test(segment) ? segment.toUpperCase() : null;
}
/** Names the site uses, or may use, for its own pages. The admin form refuses them as codes. */
export const RESERVED_CODES = new Set([
  'ADMIN', 'API', 'APP', 'APPS', 'BLOG', 'BRAND', 'DOWNLOAD', 'FAVICON', 'HELP', 'HOME', 'LOGIN', 'PRIVACY',
  'ROBOTS', 'SCREENSHOTS', 'SITEMAP', 'STATS', 'SUPPORT', 'TERMS', 'TEST',
]);

export const CAMPAIGN_PATTERN = /^[a-z0-9_-]{1,40}$/;
/** The `ct` value Apple reports a code's App Store visits under; the code in lower case unless set. */
export function campaignToken(value: string | null | undefined, code: string) {
  const clean = (value ?? '').trim().toLowerCase().replace(/[^a-z0-9_-]/g, '');
  return (clean || code.toLowerCase()).slice(0, 40);
}

/**
 * The App Store link for a code's page. With the provider token from App Store Connect (Analytics → Acquisition →
 * Campaigns), Apple counts product page views, downloads, and sales per campaign. Without it, the plain listing.
 */
export function appStoreLink(campaign?: string | null) {
  const provider = process.env.APP_STORE_PROVIDER_TOKEN?.trim();
  if (campaign && provider && /^\d{1,20}$/.test(provider)) {
    return `https://apps.apple.com/app/apple-store/id${APP_STORE_ID}?${new URLSearchParams({ pt: provider, ct: campaign, mt: '8' })}`;
  }
  const configured = process.env.APP_STORE_URL?.trim();
  return configured && /^https:\/\/apps\.apple\.com\//.test(configured) ? configured : DEFAULT_STORE_URL;
}

/** Link previews and crawlers fetch pages nobody looked at, so they aren't counted. In-app browsers are. */
export function isBot(userAgent: string | null) {
  return !userAgent || /bot\b|bot\/|crawl|spider|slurp|facebookexternalhit|whatsapp|preview|embedly|bytespider|headless|curl\/|wget|python/i.test(userAgent);
}

/** What a code gets, by RevenueCat offering, for its page and the app's confirmation. */
export function dealLine(offering: string) {
  return offering === 'discount' ? 'Half price on Cave Cals+' : 'A Cave Cals+ deal';
}

/** "Sarah" for SARAH when the name spells the code, so links read CaveCals.com/Sarah. */
export function prettyCode(code: string, name: string) {
  const spelled = name.replace(/[^A-Za-z0-9]/g, '');
  return spelled.toUpperCase() === code ? spelled : code.charAt(0) + code.slice(1).toLowerCase();
}

export type DiscountCode = typeof discountCodes.$inferSelect;
/** An active code, or null. */
export async function findCode(code: string): Promise<DiscountCode | null> {
  if (!CODE_PATTERN.test(code)) return null;
  const [row] = await database().select().from(discountCodes)
    .where(and(eq(discountCodes.code, code), eq(discountCodes.active, true)));
  return row ?? null;
}

type Counter = 'visits' | 'storeTaps' | 'applies';
/** Adds one to today's total for a code. Counting must never break a page, a link, or a code check. */
export async function countCode(code: string, counter: Counter) {
  const one = { visits: counter === 'visits' ? 1 : 0, storeTaps: counter === 'storeTaps' ? 1 : 0, applies: counter === 'applies' ? 1 : 0 };
  const next = counter === 'visits' ? { visits: sql`${discountCodeDaily.visits} + 1` }
    : counter === 'storeTaps' ? { storeTaps: sql`${discountCodeDaily.storeTaps} + 1` }
    : { applies: sql`${discountCodeDaily.applies} + 1` };
  try {
    await database().insert(discountCodeDaily).values({ code, day: TODAY, ...one })
      .onConflictDoUpdate({ target: [discountCodeDaily.code, discountCodeDaily.day], set: next });
  } catch {
    // A code removed in the meantime, or a database hiccup: skip this count.
  }
}

export const discountCheckInput = z.object({
  code: z.string().min(1).max(60),
  // Developer previews check codes without counting them.
  count: z.boolean().optional(),
});
async function limitChecks(request: Request) {
  const ip = process.env.VERCEL ? request.headers.get('x-vercel-forwarded-for') || 'unknown' : 'local';
  const hash = createHash('sha256').update(`${utcDay()}:${ip}`).digest('hex');
  // Their own buckets, never the device-registration budget. Phone carriers share addresses, so the hourly cap is roomy.
  await consume(`discount-check:${hash}:${new Date().toISOString().slice(0, 13)}`, 60, tomorrow());
  await consume(`discount-check-global:${utcDay()}`, positiveInt('DISCOUNT_CHECK_DAILY_LIMIT', 20000), tomorrow());
}
/** Checks a code typed in the app. Unknown and paused codes are a 404 so the app can say so. */
export async function checkDiscountCode(request: Request, input: z.infer<typeof discountCheckInput>) {
  await limitChecks(request);
  const row = await findCode(normalizeCode(input.code));
  if (!row) throw new APIError(404, 'code_not_found', 'That code doesn’t work. Check the spelling and try again.');
  if (input.count !== false) await countCode(row.code, 'applies');
  return { code: row.code, name: row.name, offering: row.offering, deal: dealLine(row.offering) };
}

// MARK: Admin

async function rows<T>(query: SQL): Promise<T[]> {
  return (await database().execute(query)).rows as T[];
}
export type CodeStats = DiscountCode & {
  visits7: number; visits30: number; visitsAll: number;
  taps7: number; taps30: number; tapsAll: number;
  applies7: number; applies30: number; appliesAll: number;
  /** From anonymous usage stats: iPhones that applied the code, and paywall purchases or trials with it applied. */
  appliedInApp: number; purchases: number;
};
/** Everything /admin/codes shows. `all` includes TestFlight and Xcode builds in the usage-stats numbers. */
export async function loadCodesPage(all: boolean) {
  const env = all ? sql`true` : sql`i.environment = 'appstore'`;
  const [codes, usage, sources, others] = await Promise.all([
    rows<Omit<CodeStats, 'appliedInApp' | 'purchases'>>(sql`
      select c.code, c.name, c.campaign, c.offering, c.active, c.created_at as "createdAt", c.updated_at as "updatedAt",
        coalesce(sum(d.visits) filter (where d.day > ${TODAY} - 7), 0)::int as "visits7",
        coalesce(sum(d.visits) filter (where d.day > ${TODAY} - 30), 0)::int as "visits30",
        coalesce(sum(d.visits), 0)::int as "visitsAll",
        coalesce(sum(d.store_taps) filter (where d.day > ${TODAY} - 7), 0)::int as "taps7",
        coalesce(sum(d.store_taps) filter (where d.day > ${TODAY} - 30), 0)::int as "taps30",
        coalesce(sum(d.store_taps), 0)::int as "tapsAll",
        coalesce(sum(d.applies) filter (where d.day > ${TODAY} - 7), 0)::int as "applies7",
        coalesce(sum(d.applies) filter (where d.day > ${TODAY} - 30), 0)::int as "applies30",
        coalesce(sum(d.applies), 0)::int as "appliesAll"
      from discount_codes c left join discount_code_daily d on d.code = c.code
      group by c.code order by c.active desc, c.created_at desc`),
    rows<{ code: string; appliedInApp: number; purchases: number }>(sql`
      select upper(e.props->>'code') as "code",
        count(distinct e.install_id) filter (where e.name = 'discount.code' and e.props->>'result' = 'applied')::int as "appliedInApp",
        count(*) filter (where e.name = 'paywall.result' and e.props->>'result' in ('purchased', 'trial'))::int as "purchases"
      from usage_events e join usage_installs i on i.id = e.install_id
      where e.name in ('discount.code', 'paywall.result') and coalesce(e.props->>'code', '') <> '' and ${env}
      group by 1`),
    rows<{ source: string; last30: number; allTime: number }>(sql`
      select coalesce(nullif(e.props->>'source', ''), 'skipped') as "source",
        count(distinct e.install_id) filter (where e.at > now() - interval '30 days')::int as "last30",
        count(distinct e.install_id)::int as "allTime"
      from usage_events e join usage_installs i on i.id = e.install_id
      where e.name = 'onboarding.source' and ${env}
      group by 1 order by "allTime" desc`),
    rows<{ text: string; day: string }>(sql`
      select e.props->>'other' as "text", to_char(e.at at time zone ${TZ}, 'Mon DD') as "day"
      from usage_events e join usage_installs i on i.id = e.install_id
      where e.name = 'onboarding.source' and e.props->>'source' = 'other' and coalesce(e.props->>'other', '') <> '' and ${env}
      order by e.at desc limit 50`),
  ]);
  const byCode = new Map(usage.map(row => [row.code, row]));
  return {
    codes: codes.map(row => ({ ...row, appliedInApp: byCode.get(row.code)?.appliedInApp ?? 0, purchases: byCode.get(row.code)?.purchases ?? 0 })),
    sources,
    others,
  };
}
