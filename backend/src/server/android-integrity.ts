import { createHash, createPublicKey, verify } from 'node:crypto';
import { GoogleAuth } from 'google-auth-library';
import { z } from 'zod';
import { APIError, required, safeEqual } from './config';

export const ANDROID_ENVIRONMENT = 'GooglePlay';
export const androidKeyPattern = /^android:[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
export const androidPackage = () => process.env.ANDROID_PACKAGE_NAME || 'com.philstarkovich.cavecals';
export const androidPayload = (request: Request, raw: string) => `${request.method}\n${new URL(request.url).pathname}\n${raw}`;
export const requestHash = (payload: string) => createHash('sha256').update(payload).digest('base64url');
const invalid = () => new APIError(401, 'invalid_integrity', 'Google Play could not verify this installation. Please update Cave Cals from Google Play.');
const verdict = z.object({
  requestDetails: z.object({ requestPackageName: z.string(), requestHash: z.string(), timestampMillis: z.string() }),
  appIntegrity: z.object({ appRecognitionVerdict: z.string(), packageName: z.string(), certificateSha256Digest: z.array(z.string()), versionCode: z.string() }),
  deviceIntegrity: z.object({ deviceRecognitionVerdict: z.array(z.string()) }),
  accountDetails: z.object({ appLicensingVerdict: z.string() }),
});
export type IntegrityPolicy = { packageName: string; certificates: string[]; minimumVersion: number };
export function integrityPolicy(): IntegrityPolicy {
  const certificates = required('ANDROID_SIGNING_CERTIFICATE_SHA256').split(',').map(s => s.trim());
  const minimumVersion = Number(process.env.ANDROID_MIN_VERSION_CODE || '1');
  if (!certificates.length || certificates.some(s => !/^[A-Za-z0-9_-]{43}$/.test(s)) || !Number.isSafeInteger(minimumVersion) || minimumVersion < 1) {
    throw new APIError(503, 'not_configured', 'Android verification is not configured.');
  }
  return { packageName: androidPackage(), certificates, minimumVersion };
}
// Google's Standard verdict binds the exact method, route, and JSON body, including the one-use nonce.
// There is deliberately no debug/sideload exception in the deployed verifier.
export function validateIntegrity(value: unknown, payload: string, policy: IntegrityPolicy, now = Date.now()) {
  const parsed = verdict.safeParse(value);
  if (!parsed.success) throw invalid();
  const v = parsed.data, timestamp = Number(v.requestDetails.timestampMillis), version = Number(v.appIntegrity.versionCode);
  if (v.requestDetails.requestPackageName !== policy.packageName || v.appIntegrity.packageName !== policy.packageName ||
      !safeEqual(v.requestDetails.requestHash, requestHash(payload)) || !Number.isSafeInteger(timestamp) || timestamp < now - 120_000 || timestamp > now + 30_000 ||
      v.appIntegrity.appRecognitionVerdict !== 'PLAY_RECOGNIZED' || !v.appIntegrity.certificateSha256Digest.some(s => policy.certificates.includes(s)) ||
      !Number.isSafeInteger(version) || version < policy.minimumVersion) throw invalid();
  if (v.accountDetails.appLicensingVerdict !== 'LICENSED') throw new APIError(401, 'play_install_required', 'Install Cave Cals from Google Play using the Google account that downloaded it. Manual logging still works. If this continues, contact Cave Cals support.');
  if (!v.deviceIntegrity.deviceRecognitionVerdict.includes('MEETS_DEVICE_INTEGRITY')) throw new APIError(401, 'unsupported_device', 'Google Play could not certify this device for AI features. Check Play Store Settings → About → Play Protect certification. Manual logging still works. Contact Cave Cals support for help with an existing subscription.');
}
export function androidPublicKey(encoded: string): string {
  try {
    if (!/^[A-Za-z0-9+/]+={0,2}$/.test(encoded) || encoded.length > 512) throw invalid();
    const key = createPublicKey({ key: Buffer.from(encoded, 'base64'), type: 'spki', format: 'der' });
    if (key.asymmetricKeyType !== 'ec' || key.asymmetricKeyDetails?.namedCurve !== 'prime256v1') throw invalid();
    return key.export({ type: 'spki', format: 'pem' }).toString();
  } catch { throw invalid(); }
}
export function verifyAndroidSignature(publicKey: string, signature: string, payload: string) {
  try {
    if (!/^[A-Za-z0-9_-]{80,144}$/.test(signature) || !verify('sha256', Buffer.from(payload), publicKey, Buffer.from(signature, 'base64url'))) throw invalid();
  } catch { throw invalid(); }
}
let auth: { source: string; client: GoogleAuth } | undefined;
export async function verifyIntegrityToken(token: string, payload: string) {
  const policy = integrityPolicy();
  const source = required('GOOGLE_PLAY_SERVICE_ACCOUNT_JSON');
  if (!auth || auth.source !== source) {
    try {
      const credentials = JSON.parse(source);
      if (credentials.type !== 'service_account' || typeof credentials.client_email !== 'string' || typeof credentials.private_key !== 'string') throw new Error();
      auth = { source, client: new GoogleAuth({ credentials, scopes: ['https://www.googleapis.com/auth/playintegrity'] }) };
    } catch { throw new APIError(503, 'not_configured', 'Android verification is not configured.'); }
  }
  let response;
  try {
    response = await auth.client.request<{ tokenPayloadExternal?: unknown }>({
      url: `https://playintegrity.googleapis.com/v1/${encodeURIComponent(policy.packageName)}:decodeIntegrityToken`,
      method: 'POST', data: { integrity_token: token }, timeout: 10_000, retry: false,
    });
  } catch {
    // Upstream errors can contain the submitted token or service credentials. Never surface/log them.
    throw new APIError(503, 'integrity_unavailable', 'Google Play verification is temporarily unavailable. Please try again.');
  }
  validateIntegrity(response.data.tokenPayloadExternal, payload, policy);
}
export function androidHeaders(request: Request) {
  const keyId = request.headers.get('x-app-key') || '', signature = request.headers.get('x-android-signature') || '', token = request.headers.get('x-android-integrity') || '';
  if (!androidKeyPattern.test(keyId) || !signature || signature.length > 144 || !token || token.length > 30_000 || request.headers.has('x-app-assertion')) throw invalid();
  return { keyId, signature, token };
}
