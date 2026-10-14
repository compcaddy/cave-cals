import { unsubscribe } from '@/server/email';
export const runtime = 'nodejs';
// One-click unsubscribe: mail apps post here (List-Unsubscribe-Post), and so does the button on /unsubscribe.
export async function POST(request: Request) {
  const url = new URL(request.url);
  let p = url.searchParams.get('p') ?? '', t = url.searchParams.get('t') ?? '';
  if ((!p || !t) && request.headers.get('content-type')?.includes('application/x-www-form-urlencoded')) {
    const form = new URLSearchParams(await request.text());
    p = form.get('p') ?? p; t = form.get('t') ?? t;
  }
  const done = await unsubscribe(p, t).catch(() => false);
  // The page's button comes back to a confirmation; mail apps only need the status.
  if (request.headers.get('accept')?.includes('text/html')) {
    return Response.redirect(new URL(done ? '/unsubscribe?done=1' : '/unsubscribe?failed=1', url.origin), 303);
  }
  return new Response(done ? 'Unsubscribed' : 'Invalid link', { status: done ? 200 : 400 });
}
