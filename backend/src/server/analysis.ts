import { z } from 'zod';
import { and, eq, sql } from 'drizzle-orm';
import { database, type DBTransaction } from './db';
import { accounts, uploads } from './schema';
import { APIError, positiveInt, required } from './config';
import { consume, utcDay, tomorrow } from './rate-limit';
import { identify, identifyText, type FoodResult } from './ai';
import { readUpload, deleteUpload } from './storage';
import type { Identity } from './auth';
import { entitlement } from './apple';
import { requireScanAccess, SCAN_RESERVATION_MS } from './scan-access';
export async function reserveAIUsage(identity: Identity, tx: DBTransaction | ReturnType<typeof database> = database()) {
  const now = new Date(), month = now.toISOString().slice(0,7);
  const nextMonth = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth()+1,1));
  await consume(`ai-global:${utcDay()}`, positiveInt('AI_GLOBAL_DAILY_LIMIT', 1000), tomorrow(), tx);
  await consume(`ai:${identity.accountId}:${utcDay()}`, positiveInt('AI_DAILY_LIMIT', 30), tomorrow(), tx);
  await consume(`ai-month:${identity.accountId}:${month}`, positiveInt('AI_MONTHLY_LIMIT', 300), nextMonth, tx);
}
export async function analyze(identity: Identity, uploadId: string, runAI = identify, regularLogCount = 0): Promise<FoodResult> {
  required('OPENAI_API_KEY');
  const { active } = await entitlement(identity);
  const upload = await database().transaction(async tx => {
    await tx.select({ id: accounts.id }).from(accounts).where(eq(accounts.id, identity.accountId)).for('update');
    const [row] = await tx.select().from(uploads).where(and(eq(uploads.id, uploadId), eq(uploads.accountId, identity.accountId))).for('update');
    if (!row || row.expiresAt < new Date()) throw new APIError(404, 'not_found', 'The upload has expired. Please upload again.');
    if (row.state === 'done') return row;
    if (row.state === 'processing' && (!row.scanReservedUntil || row.scanReservedUntil < new Date())) throw new APIError(409, 'failed', 'This analysis was interrupted. Please upload again.');
    if (row.state === 'processing') throw new APIError(409, 'processing', 'This estimate is still processing. Please retry shortly.');
    if (row.state === 'failed') throw new APIError(409, 'failed', 'This analysis failed. Please upload again.');
    // Shared database counters serialize concurrent requests across serverless instances/devices.
    await requireScanAccess(identity, active, regularLogCount, tx);
    await reserveAIUsage(identity, tx);
    await tx.update(uploads).set({ state: 'processing', scanReservedUntil: new Date(Date.now() + SCAN_RESERVATION_MS) }).where(eq(uploads.id, row.id));
    return row;
  });
  if (upload.state === 'done') return upload.result as FoodResult;
  let stage = "read-upload";
  try {
    const bytes = await readUpload(upload);
    stage = "openai";
    const result = await runAI(upload, bytes);
    stage = "save-result";
    await database().transaction(async tx => {
      await tx.select({ id: accounts.id }).from(accounts).where(eq(accounts.id, identity.accountId)).for('update');
      const [current] = await tx.select().from(uploads).where(eq(uploads.id, upload.id)).for('update');
      if (current?.state !== 'processing' || !current.scanReservedUntil || current.scanReservedUntil < new Date()) {
        throw new APIError(409, 'failed', 'This analysis was interrupted. Please upload again.');
      }
      await tx.update(accounts).set({ scansUsed: sql`${accounts.scansUsed} + 1` }).where(eq(accounts.id, identity.accountId));
      await tx.update(uploads).set({ state: 'done', result, scanReservedUntil: null }).where(eq(uploads.id, upload.id));
    });
    return result;
  } catch (error) {
    const detail = error as { name?: string; code?: string; status?: number };
    console.error('AI processing failure', { stage, name: detail?.name, code: detail?.code, status: detail?.status });
    await database().update(uploads).set({ state: 'failed', scanReservedUntil: null }).where(and(eq(uploads.id, upload.id), eq(uploads.state, 'processing')));
    if (error instanceof APIError) throw error;
    throw new APIError(502, 'ai_unavailable', 'AI processing is temporarily unavailable. Please check the service configuration or try again later.');
  } finally {
    // Keep the metadata row until expiry so cleanup retries deletion after an outage or late upload.
    await deleteUpload(upload).catch(() => console.error('Temporary upload cleanup deferred'));
  }
}

export const describeInput = z.object({ text: z.string().trim().min(2).max(500).refine(value => !/[\x00-\x1f\x7f]/.test(value)) });
// A spoken description (Siri/Shortcuts) uses one scan, like a voice recording. The scan is charged under the
// account lock before OpenAI is called, so concurrent requests cannot exceed the allowance, and refunded on failure.
export async function describe(identity: Identity, text: string, runAI: (text: string) => Promise<FoodResult> = identifyText, regularLogCount = 0): Promise<FoodResult> {
  required('OPENAI_API_KEY');
  const { active } = await entitlement(identity);
  await database().transaction(async tx => {
    await requireScanAccess(identity, active, regularLogCount, tx);
    await reserveAIUsage(identity, tx);
    await tx.update(accounts).set({ scansUsed: sql`${accounts.scansUsed} + 1` }).where(eq(accounts.id, identity.accountId));
  });
  try { return await runAI(text); }
  catch (error) {
    const detail = error as { name?: string; code?: string; status?: number };
    console.error('AI text processing failure', { name: detail?.name, code: detail?.code, status: detail?.status });
    await database().update(accounts).set({ scansUsed: sql`greatest(${accounts.scansUsed} - 1, 0)` }).where(eq(accounts.id, identity.accountId));
    if (error instanceof APIError) throw error;
    throw new APIError(502, 'ai_unavailable', 'AI processing is temporarily unavailable. Please try again later.');
  }
}
