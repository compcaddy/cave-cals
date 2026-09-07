import { lt, inArray } from 'drizzle-orm';
import { del } from '@vercel/blob';
import { database } from '@/server/db';
import { uploads, challenges, limits } from '@/server/schema';
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
    return Response.json({ deleted });
  } catch (error) { return errorResponse(error); }
}
