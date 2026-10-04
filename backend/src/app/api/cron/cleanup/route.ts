import { lt, inArray, and, eq } from 'drizzle-orm';
import { del } from '@vercel/blob';
import { database } from '@/server/db';
import { uploads, challenges, limits, usageBatches, usageEvents, appErrors } from '@/server/schema';
import { deleteUpload } from '@/server/storage';
import { APIError, errorResponse, required, safeEqual } from '@/server/config';
export const runtime = 'nodejs';
export const maxDuration = 60;
export async function GET(request: Request) {
  try {
    if (!safeEqual(request.headers.get('authorization') || '', `Bearer ${required('CRON_SECRET')}`)) throw new APIError(401, 'unauthorized', 'Unauthorized.');
    const db = database(); const now = new Date(); let deleted = 0;
    // Drain multiple batches so normal traffic cannot outgrow a fixed daily cleanup cap.
    const deadline = Date.now() + 40000;
    while (Date.now() < deadline) {
      const expired = await db.select().from(uploads).where(lt(uploads.expiresAt, now)).limit(1000);
      if (!expired.length) break;
      const blobPaths = expired.filter(upload => upload.storage === 'blob').map(upload => upload.pathname);
      if (blobPaths.length) await del(blobPaths, { abortSignal: AbortSignal.timeout(10000) });
      await Promise.all(expired.filter(upload => upload.storage === 'local').map(deleteUpload));
      // Retain metadata if any object deletion fails, so the next run can retry safely.
      await db.delete(uploads).where(inArray(uploads.id, expired.map(upload => upload.id)));
      deleted += expired.length;
    }
    await db.delete(challenges).where(lt(challenges.expiresAt, now));
    await db.delete(limits).where(lt(limits.expiresAt, now));
    // Usage stats retention: retry IDs for 60 days, errors and searches that found nothing for 180 days,
    // other events for 400 days. Daily counts are small and kept.
    const daysAgo = (days: number) => new Date(now.getTime() - days * 86_400_000);
    await db.delete(usageBatches).where(lt(usageBatches.receivedAt, daysAgo(60)));
    await db.delete(appErrors).where(lt(appErrors.at, daysAgo(180)));
    await db.delete(usageEvents).where(and(eq(usageEvents.name, 'search.missing'), lt(usageEvents.at, daysAgo(180))));
    await db.delete(usageEvents).where(lt(usageEvents.at, daysAgo(400)));
    return Response.json({ deleted });
  } catch (error) { return errorResponse(error); }
}
