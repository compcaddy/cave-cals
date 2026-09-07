import { and, eq } from 'drizzle-orm';
import { database } from './db';
import { uploads } from './schema';
import { APIError, positiveInt, required } from './config';
import { consume, utcDay, tomorrow } from './rate-limit';
import { identify, type FoodResult } from './ai';
import { readUpload, deleteUpload } from './storage';
import type { Identity } from './auth';
export async function analyze(identity: Identity, uploadId: string, runAI = identify): Promise<FoodResult> {
  required('OPENAI_API_KEY');
  const upload = await database().transaction(async tx => {
    const [row] = await tx.select().from(uploads).where(and(eq(uploads.id, uploadId), eq(uploads.accountId, identity.accountId))).for('update');
    if (!row || row.expiresAt < new Date()) throw new APIError(404, 'not_found', 'The upload has expired. Please upload again.');
    if (row.state === 'done') return row;
    if (row.state === 'processing') throw new APIError(409, 'processing', 'This estimate is still processing. Please retry shortly.');
    if (row.state === 'failed') throw new APIError(409, 'failed', 'This analysis failed. Please upload again.');
    const now = new Date(), month = now.toISOString().slice(0,7);
    const nextMonth = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth()+1,1));
    // Shared database counters serialize concurrent requests across serverless instances/devices.
    await consume(`ai-global:${utcDay()}`, positiveInt('AI_GLOBAL_DAILY_LIMIT', 1000), tomorrow(), tx);
    await consume(`ai:${identity.accountId}:${utcDay()}`, positiveInt('AI_DAILY_LIMIT', 30), tomorrow(), tx);
    await consume(`ai-month:${identity.accountId}:${month}`, positiveInt('AI_MONTHLY_LIMIT', 300), nextMonth, tx);
    await tx.update(uploads).set({ state: 'processing' }).where(eq(uploads.id, row.id));
    return row;
  });
  if (upload.state === 'done') return upload.result as FoodResult;
  let stage = "read-upload";
  try {
    const bytes = await readUpload(upload);
    stage = "openai";
    const result = await runAI(upload, bytes);
    stage = "save-result";
    await database().update(uploads).set({ state: 'done', result }).where(eq(uploads.id, upload.id));
    return result;
  } catch (error) {
    const detail = error as { name?: string; code?: string; status?: number };
    console.error('AI processing failure', { stage, name: detail?.name, code: detail?.code, status: detail?.status });
    await database().update(uploads).set({ state: 'failed' }).where(eq(uploads.id, upload.id));
    if (error instanceof APIError) throw error;
    throw new APIError(502, 'ai_unavailable', 'AI processing is temporarily unavailable. Please check the service configuration or try again later.');
  } finally {
    // Keep the metadata row until expiry so cleanup retries deletion after an outage or late upload.
    await deleteUpload(upload).catch(() => console.error('Temporary upload cleanup deferred'));
  }
}
