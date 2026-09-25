import { z } from 'zod';
import { foodSearchClient, foodSearchInput, limitFoodSearch } from './food-search';
import { APIError, errorResponse, readLimited, positiveInt } from './config';
import { authenticate, challenge, register } from './auth';
import { products, entitlement, requirePaid, verifyPurchase, verifyNotification } from './apple';
import { signUpload, uploadInput } from './storage';
import { analyze, reserveAIUsage } from './analysis';
import { importMealFromWebsite } from './ai';
import { estimateMacros, macroInput, withLegacyItems, withLegacyNetCarbs } from './macros';
import { consume, tomorrow, limitPublic } from './rate-limit';
import { database } from './db';
import { accounts } from './schema';
import { authorizedTestAccess, ownerTestAccess } from './test-access';
import { scanAccess, scanUsageInput, requireScanAccess } from './scan-access';
const nonceSchema = z.string().min(1).max(200);
const keySchema = z.string().min(1).max(200);
export async function api(request: Request, path: string): Promise<Response> {
  try {
    if (request.method !== 'POST') throw new APIError(405, 'method', 'Use POST.');
    if (!request.headers.get('content-type')?.startsWith('application/json')) throw new APIError(415, 'content_type', 'Use application/json.');
    const raw = (await readLimited(request, path === 'foods/search' ? 1024 : 64 * 1024)).toString('utf8');
    let body: unknown;
    try { body = JSON.parse(raw); } catch { throw new APIError(400, 'invalid_json', 'Invalid request.'); }
    const ok = (value: unknown) => Response.json(value, { headers: { 'Cache-Control':'no-store' } });
    if (path === 'foods/search') {
      const input = foodSearchInput.parse(body);
      const provider = foodSearchClient();
      await limitFoodSearch(request);
      const page = await provider.search(input.query);
      return ok({ ...page, results: page.results.map(food => food.macros ? { ...food, macros: withLegacyNetCarbs(food.macros) } : food) });
    }
    if (path === 'device/challenge') {
      const input = z.object({ keyId: keySchema, purpose: z.enum(['register','request']) }).parse(body);
      return ok(await challenge(request, input.keyId, input.purpose));
    }
    if (path === 'device/register') {
      await limitPublic(request);
      const input = z.object({ keyId: keySchema, nonce: nonceSchema, attestation: z.string().min(1).max(20000) }).parse(body);
      return ok(await register(input.keyId, input.nonce, input.attestation));
    }
    if (path === 'apple/notifications') {
      const { signedPayload } = z.object({ signedPayload: z.string().max(60000) }).parse(body);
      await verifyNotification(signedPayload);
      // No stale entitlement cache to invalidate: every billable action queries Apple live.
      return ok({ received: true });
    }
    const { nonce } = z.object({ nonce: nonceSchema }).parse(body);
    let identity;
    if (request.headers.get('x-cave-owner-test') === '1') {
      await limitPublic(request);
      const testAccess = ownerTestAccess((body as { testAccess?: unknown }).testAccess, path);
      // One fixed owner identity keeps usage quotas shared across reinstalls and test clients.
      const accountId = '00000000-0000-4000-8000-000000000002';
      await database().insert(accounts).values({ id: accountId }).onConflictDoNothing();
      identity = { accountId, keyId: 'owner-test', development: false, testAccess };
    } else {
      identity = await authenticate(request, raw, nonce);
    }
    identity.testAccess = authorizedTestAccess((body as { testAccess?: unknown }).testAccess);
    await consume(`requests:${identity.accountId}:${new Date().toISOString().slice(0,16)}`, 30, tomorrow());
    if (path === 'account/status') {
      const { regularLogCount } = scanUsageInput.parse(body);
      const membership = await entitlement(identity);
      return ok({ accountId: identity.accountId, ...membership, ...await scanAccess(identity, membership.active, regularLogCount), productIds: products(), dailyLimit: positiveInt('AI_DAILY_LIMIT',30), monthlyLimit: positiveInt('AI_MONTHLY_LIMIT',300) });
    }
    if (path === 'purchase/verify') {
      const input = z.object({ signedTransaction: z.string().min(1).max(50000) }).parse(body);
      return ok(await verifyPurchase(identity, input.signedTransaction));
    }
    if (path === 'uploads/sign') {
      const input = uploadInput.parse(body);
      const { regularLogCount } = scanUsageInput.parse(body);
      const { active } = await entitlement(identity);
      await scanAccess(identity, active, regularLogCount);
      await database().transaction(tx => requireScanAccess(identity, active, regularLogCount, tx));
      return ok(await signUpload(request, identity, input));
    }
    if (path === 'food/analyze') {
      const { uploadId } = z.object({ uploadId: z.string().uuid() }).parse(body);
      const { regularLogCount } = scanUsageInput.parse(body);
      // Persist the high-water mark even if access is denied inside the analysis transaction.
      await scanAccess(identity, false, regularLogCount);
      return ok(withLegacyItems(await analyze(identity, uploadId, undefined, regularLogCount)));
    }
    if (path === 'food/macros') {
      const input = macroInput.parse(body);
      // Free, explicit text estimates: authenticated and budgeted, no scan allowance consumed.
      await database().transaction(async tx => {
        await consume(`macro-estimate:${identity.accountId}:${new Date().toISOString().slice(0,10)}`, positiveInt('MACRO_ESTIMATE_DAILY_LIMIT', 10), tomorrow(), tx);
        await reserveAIUsage(identity, tx);
      });
      return ok(withLegacyNetCarbs(await estimateMacros(input)));
    }
    if (path === 'meal/import') {
      const { url } = z.object({ url: z.string().url().max(2048) }).parse(body);
      await requirePaid(identity);
      await reserveAIUsage(identity);
      return ok(withLegacyItems(await importMealFromWebsite(url)));
    }
    throw new APIError(404, 'not_found', 'Not found.');
  } catch (error) {
    return errorResponse(error instanceof z.ZodError ? new APIError(400, 'invalid_request', 'Some request fields are invalid.') : error);
  }
}
