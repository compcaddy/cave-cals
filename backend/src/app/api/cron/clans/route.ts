import { runClanJobs } from '@/server/clan-jobs';
import { APIError, errorResponse, required, safeEqual } from '@/server/config';
export const runtime = 'nodejs';
export const maxDuration = 60;
// Every 15 minutes (vercel.json), so 9 AM locks and 7 PM alerts land on time in every time zone.
export async function GET(request: Request) {
  try {
    if (!safeEqual(request.headers.get('authorization') || '', `Bearer ${required('CRON_SECRET')}`)) throw new APIError(401, 'unauthorized', 'Unauthorized.');
    await runClanJobs();
    return Response.json({ ok: true }, { headers: { 'Cache-Control': 'no-store' } });
  } catch (error) { return errorResponse(error); }
}
