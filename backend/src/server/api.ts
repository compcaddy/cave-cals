import { z } from 'zod';
import { foodSearchClient, foodSearchInput, limitFoodSearch } from './food-search';
import { APIError, errorResponse, readLimited, positiveInt } from './config';
import { authenticate, challenge, register, issueTrialKey, trialKeyPattern, OWNER_TEST_KEY } from './auth';
import { products, entitlement, requirePaid, verifyPurchase, applyNotification } from './apple';
import { signUpload, uploadInput } from './storage';
import { analyze, describe, describeInput, importRecipeUploads, reserveAIUsage } from './analysis';
import { importMealFromText, importMealFromWebsite, MAX_RECIPE_PAGES, MAX_RECIPE_TEXT } from './ai';
import { estimateMacros, macroInput, withLegacyItems, withLegacyNetCarbs } from './macros';
import { consume, tomorrow, limitPublic } from './rate-limit';
import { database } from './db';
import { accounts } from './schema';
import { authorizedTestAccess, ownerTestAccess } from './test-access';
import { scanAccess, scanUsageInput, requireScanAccess } from './scan-access';
import { statsInput, recordStats, recordServerError } from './stats';
import { checkDiscountCode, discountCheckInput } from './discount-codes';
import { coach, coachInput, coachTips } from './coach';
import { waitUntil } from '@vercel/functions';
const nonceSchema = z.string().min(1).max(200);
const keySchema = z.string().min(1).max(200);
// One source per recipe import. `wholeRecipe` asks a link import for the full batch plus its serving count;
// released apps omit it and keep one-serving results. Pasted text and photos always import the whole recipe.
export const mealImportInput = z.union([
  z.object({ url: z.string().url().max(2048), wholeRecipe: z.boolean().optional() }),
  z.object({ text: z.string().trim().min(20).max(MAX_RECIPE_TEXT).refine(value => !/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(value)) }),
  z.object({ uploadIds: z.array(z.string().uuid()).min(1).max(MAX_RECIPE_PAGES).refine(ids => new Set(ids).size === ids.length) }),
]);
export async function api(request: Request, path: string): Promise<Response> {
  try {
    if (request.method !== 'POST') throw new APIError(405, 'method', 'Use POST.');
    if (!request.headers.get('content-type')?.startsWith('application/json')) throw new APIError(415, 'content_type', 'Use application/json.');
    const raw = (await readLimited(request, path === 'foods/search' || path === 'discount/check' ? 1024 : path === 'stats' || path === 'meal/import' ? 256 * 1024 : 64 * 1024)).toString('utf8');
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
      const input = z.object({ keyId: keySchema, nonce: nonceSchema, attestation: z.string().min(1).max(20000), trialKey: z.string().regex(trialKeyPattern).optional() }).parse(body);
      return ok(await register(input.keyId, input.nonce, input.attestation, input.trialKey));
    }
    if (path === 'stats') {
      // Anonymous usage counts and error reports. Unsigned on purpose: no App Attest or account needed.
      await recordStats(request, statsInput.parse(body));
      return ok({ received: true });
    }
    if (path === 'discount/check') {
      // Unsigned on purpose: codes are shared publicly, and setup asks for one before the device is verified.
      return ok(await checkDiscountCode(request, discountCheckInput.parse(body)));
    }
    if (path === 'apple/notifications') {
      const { signedPayload } = z.object({ signedPayload: z.string().max(60000) }).parse(body);
      await applyNotification(signedPayload);
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
      identity = { accountId, keyId: OWNER_TEST_KEY, development: false, testAccess };
    } else {
      identity = await authenticate(request, raw, nonce);
    }
    identity.testAccess = authorizedTestAccess((body as { testAccess?: unknown }).testAccess);
    await consume(`requests:${identity.accountId}:${new Date().toISOString().slice(0,16)}`, 30, tomorrow());
    if (path === 'account/status') {
      const { regularLogCount } = scanUsageInput.parse(body);
      const { issueTrialKey: wantsTrialKey } = z.object({ issueTrialKey: z.boolean().optional() }).parse(body);
      const membership = await entitlement(identity);
      const access = await scanAccess(identity, membership.active, regularLogCount);
      // Only attested installs keep an install key; developer and owner-test identities are shared.
      const trialKey = wantsTrialKey && !identity.development && identity.keyId !== OWNER_TEST_KEY ? await issueTrialKey(identity) : undefined;
      return ok({ accountId: identity.accountId, ...membership, ...access, productIds: products(), dailyLimit: positiveInt('AI_DAILY_LIMIT',30), monthlyLimit: positiveInt('AI_MONTHLY_LIMIT',300), ...(trialKey ? { trialKey } : {}) });
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
    if (path === 'food/describe') {
      const { text } = describeInput.parse(body);
      const { regularLogCount } = scanUsageInput.parse(body);
      // Persist the high-water mark even if access is denied inside the charging transaction.
      await scanAccess(identity, false, regularLogCount);
      return ok(withLegacyItems(await describe(identity, text, undefined, regularLogCount)));
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
    if (path === 'insights/coach') {
      // Cave Cals+: the app's on-device summary of good vs. over days, written up by the model.
      const input = coachInput.parse(body);
      await requirePaid(identity);
      await database().transaction(async tx => {
        await consume(`coach:${identity.accountId}:${new Date().toISOString().slice(0,10)}`, positiveInt('COACH_DAILY_LIMIT', 3), tomorrow(), tx);
        await reserveAIUsage(identity, tx);
      });
      return ok(input.format === 'tips' ? await coachTips(input) : await coach(input));
    }
    if (path === 'meal/import') {
      const input = mealImportInput.parse(body);
      await requirePaid(identity);
      if ('uploadIds' in input) return ok(withLegacyItems(await importRecipeUploads(identity, input.uploadIds)));
      await reserveAIUsage(identity);
      if ('text' in input) return ok(withLegacyItems(await importMealFromText(input.text)));
      return ok(withLegacyItems(await importMealFromWebsite(input.url, input.wholeRecipe === true)));
    }
    throw new APIError(404, 'not_found', 'Not found.');
  } catch (error) {
    if (!(error instanceof APIError) && !(error instanceof z.ZodError)) {
      // Keep the function alive to store it after responding; a failure to record must never surface.
      const recorded = recordServerError(path, error).catch(() => {});
      waitUntil(recorded);
    }
    return errorResponse(error instanceof z.ZodError ? new APIError(400, 'invalid_request', 'Some request fields are invalid.') : error);
  }
}
