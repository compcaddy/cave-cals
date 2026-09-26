import { createHash } from 'node:crypto';
import { z } from 'zod';
import { APIError, safeEqual } from './config';

// Private owner capability: also authorizes the explicitly scoped test routes.
// The capability is never bundled in the app. Revocation takes effect on every request.
export function authorizedTestAccess(input: unknown): boolean | undefined {
  if (input === undefined) return undefined;
  const parsed = z.object({ key: z.string().min(32).max(256), active: z.boolean() }).safeParse(input);
  const expected = process.env.AI_TEST_ACCESS_KEY_SHA256;
  if (!parsed.success || !expected || !/^[a-f0-9]{64}$/.test(expected) ||
      !safeEqual(createHash('sha256').update(parsed.data.key).digest('hex'), expected)) {
    throw new APIError(403, 'test_access_denied', 'The private test-access key is invalid or has been revoked.');
  }
  return parsed.data.active;
}

export function ownerTestAccess(input: unknown, path: string): boolean {
  const active = authorizedTestAccess(input);
  if (active === undefined) throw new APIError(403, 'test_access_denied', 'A private test-access key is required.');
  if (!['account/status', 'uploads/sign', 'food/analyze', 'food/describe', 'meal/import', 'food/macros'].includes(path)) {
    throw new APIError(403, 'test_route_denied', 'Private testing cannot modify purchases or device registrations.');
  }
  return active;
}
