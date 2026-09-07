import { timingSafeEqual } from 'node:crypto';
export class APIError extends Error {
  constructor(public status: number, public code: string, message: string) { super(message); }
}
export function required(name: string): string {
  const value = process.env[name];
  if (!value) throw new APIError(503, 'not_configured', `The service is not configured (${name}).`);
  return value;
}
export function positiveInt(name: string, fallback: number): number {
  const value = Number(process.env[name] ?? fallback);
  if (!Number.isSafeInteger(value) || value < 1) throw new APIError(503, 'not_configured', `Invalid ${name}.`);
  return value;
}
export const bundleID = () => process.env.APPLE_BUNDLE_ID || 'com.philstarkovich.cavecals';
export function localDevelopment(request: Request): boolean {
  const url = new URL(request.url);
  return process.env.NODE_ENV === 'development' && !process.env.VERCEL &&
    ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname) &&
    (!request.headers.get('origin') || request.headers.get('origin') === url.origin);
}
export function safeEqual(a: string, b: string): boolean {
  const aa = Buffer.from(a), bb = Buffer.from(b);
  return aa.length === bb.length && timingSafeEqual(aa, bb);
}
export function isDevelopmentUser(request: Request): boolean {
  const token = process.env.DEV_API_TOKEN;
  return localDevelopment(request) && !!token && token.length >= 32 &&
    safeEqual(request.headers.get('authorization') || '', `Bearer ${token}`);
}
export const DEV_ACCOUNT = '00000000-0000-4000-8000-000000000001';
export const imageTypes = ['image/jpeg', 'image/png', 'image/webp'] as const;
export const audioTypes = ['audio/mp4', 'audio/m4a', 'audio/x-m4a', 'audio/webm', 'audio/wav', 'audio/mpeg'] as const;
export const MAX_IMAGE_BYTES = 20 * 1024 * 1024;
export const MAX_AUDIO_BYTES = 4 * 1024 * 1024;
export function errorResponse(error: unknown): Response {
  if (error instanceof APIError) return Response.json({ error: { code: error.code, message: error.message } }, { status: error.status, headers: { 'Cache-Control': 'no-store' } });
  // Never log request bodies, credentials, SQL parameters, image/audio data, or raw upstream errors.
  console.error('Backend request failed', error instanceof Error ? error.name : 'UnknownError');
  return Response.json({ error: { code: 'internal_error', message: 'Something went wrong. Please try again.' } }, { status: 500, headers: { 'Cache-Control': 'no-store' } });
}
export async function readLimited(request: Request, max = 64 * 1024): Promise<Buffer> {
  if (Number(request.headers.get('content-length')) > max) throw new APIError(413, 'too_large', 'The request is too large.');
  const reader = request.body?.getReader();
  if (!reader) return Buffer.alloc(0);
  const parts: Uint8Array[] = []; let size = 0;
  while (true) {
    const { done, value } = await reader.read(); if (done) break;
    size += value.length;
    if (size > max) { await reader.cancel(); throw new APIError(413, 'too_large', 'The request is too large.'); }
    parts.push(value);
  }
  return Buffer.concat(parts);
}
