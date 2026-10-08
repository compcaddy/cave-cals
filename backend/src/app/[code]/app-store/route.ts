import { after } from 'next/server';
import { appStoreLink, countCode, findCode, isBot, linkCode } from '@/server/discount-codes';
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

/** A code page's App Store button: counts the tap, then opens the App Store with the code's campaign token. */
export async function GET(request: Request, context: { params: Promise<{ code: string }> }) {
  const code = linkCode((await context.params).code);
  // A paused or unknown code, or a database hiccup, still reaches the App Store.
  const row = code ? await findCode(code).catch(() => null) : null;
  if (row && !isBot(request.headers.get('user-agent'))) after(() => countCode(row.code, 'storeTaps'));
  return new Response(null, { status: 302, headers: { Location: appStoreLink(row?.campaign), 'Cache-Control': 'no-store' } });
}
