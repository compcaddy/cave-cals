import { GoogleAuth } from 'google-auth-library';
import { z } from 'zod';

export const pushRegistration = z.discriminatedUnion('environment', [
  z.object({ environment: z.literal('android'), token: z.string().min(20).max(4096).regex(/^[A-Za-z0-9_:\-]+$/) }),
  z.object({ environment: z.literal('sandbox'), token: z.string().regex(/^[a-f0-9]{64,200}$/) }),
  z.object({ environment: z.literal('production'), token: z.string().regex(/^[a-f0-9]{64,200}$/) }),
]);
export type AndroidPush = { token: string; title: string; body: string; clanId: string; kind: string; collapse?: string };
let cached: { source: string; auth: GoogleAuth; project: string } | undefined;
export function firebaseMessage(item: AndroidPush) {
  // Data messages let the app suppress stale notifications after sign-out and route the tap explicitly.
  return { message: { token: item.token, data: { title: item.title, body: item.body, clanId: item.clanId, kind: item.kind },
    android: { priority: 'HIGH', ttl: '3600s', ...(item.collapse ? { collapse_key: item.collapse } : {}) } } };
}
export function deadFirebaseToken(value: unknown): boolean {
  const parsed = z.object({ error: z.object({ details: z.array(z.object({ '@type': z.string().optional(), errorCode: z.string().optional() })).optional() }) }).safeParse(value);
  return parsed.success && !!parsed.data.error.details?.some(d => d['@type'] === 'type.googleapis.com/google.firebase.fcm.v1.FcmError' && d.errorCode === 'UNREGISTERED');
}
export async function deliverAndroidPush(items: AndroidPush[]): Promise<string[]> {
  const source = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (!source || !items.length) return [];
  if (cached?.source !== source) {
    const credentials = JSON.parse(source);
    if (credentials.type !== 'service_account' || typeof credentials.project_id !== 'string' || !/^[a-z][a-z0-9-]{4,62}$/.test(credentials.project_id)) throw new Error('Invalid Firebase service account configuration');
    cached = { source, project: credentials.project_id, auth: new GoogleAuth({ credentials, scopes: ['https://www.googleapis.com/auth/firebase.messaging'] }) };
  }
  const provider = cached, dead: string[] = [];
  // A modest batch bounds the number of in-flight HTTP requests when a large clan is notified.
  for (let offset = 0; offset < items.length; offset += 10) {
    await Promise.all(items.slice(offset, offset + 10).map(async item => {
      try {
        const result = await provider.auth.request({ url: `https://fcm.googleapis.com/v1/projects/${provider.project}/messages:send`,
          method: 'POST', data: firebaseMessage(item), timeout: 10_000, retry: false, validateStatus: () => true });
        if (deadFirebaseToken(result.data)) dead.push(item.token);
      } catch { /* Temporary delivery failures must not erase a valid token or fail the user's action. */ }
    }));
  }
  return dead;
}
