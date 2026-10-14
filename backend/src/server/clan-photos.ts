// Clan profile photos: re-encoded here as a 512-px square JPEG with no metadata (no location), kept in private
// storage, and served only to clanmates who can see the person (never while they're a Cave person).
import { randomUUID } from 'node:crypto';
import { mkdir, readFile, unlink, writeFile } from 'node:fs/promises';
import path from 'node:path';
import sharp from 'sharp';
import { del, get, put } from '@vercel/blob';
import { APIError } from './config';

export const PHOTO_SIZE = 512;
export const MAX_PHOTO_INPUT_BYTES = 1_500_000;
const useLocal = () => process.env.NODE_ENV === 'development' && !process.env.VERCEL && process.env.LOCAL_UPLOADS === 'true';
const localFile = (id: string) => path.join(process.cwd(), '.local-uploads', 'clan-photos', `${id}.jpg`);
const blobPath = (id: string) => `clan-photos/${id}.jpg`;

// Re-encoding drops EXIF, GPS, and every other piece of metadata; sharp keeps none unless asked.
export async function normalizePhoto(bytes: Buffer): Promise<Buffer> {
  if (bytes.length === 0 || bytes.length > MAX_PHOTO_INPUT_BYTES) throw new APIError(413, 'photo_too_large', 'Choose a smaller photo.');
  try {
    return await sharp(bytes, { limitInputPixels: 40_000_000 }).rotate()
      .resize(PHOTO_SIZE, PHOTO_SIZE, { fit: 'cover' }).jpeg({ quality: 82, mozjpeg: true }).toBuffer();
  } catch { throw new APIError(415, 'unsupported_photo', 'That photo couldn’t be read. Try another one.'); }
}
export async function storePhoto(bytes: Buffer): Promise<string> {
  const id = randomUUID(), jpeg = await normalizePhoto(bytes);
  if (useLocal()) { await mkdir(path.dirname(localFile(id)), { recursive: true }); await writeFile(localFile(id), jpeg, { mode: 0o600 }); }
  else await put(blobPath(id), jpeg, { access: 'private', contentType: 'image/jpeg', addRandomSuffix: false, allowOverwrite: false });
  return id;
}
export async function readPhoto(id: string): Promise<Buffer | null> {
  if (useLocal()) { try { return await readFile(localFile(id)); } catch { return null; } }
  const blob = await get(blobPath(id), { access: 'private', useCache: false, abortSignal: AbortSignal.timeout(15_000) }).catch(() => null);
  if (!blob || blob.statusCode !== 200) return null;
  return Buffer.from(await new Response(blob.stream).arrayBuffer());
}
export async function deletePhoto(id: string | null | undefined) {
  if (!id) return;
  if (useLocal()) await unlink(localFile(id)).catch(() => {});
  else await del(blobPath(id)).catch(() => {});
}
// A Google sign-in's profile picture becomes the first photo. Only Google's own image hosts are fetched, and
// redirects are followed only to them.
const googleImageHost = (host: string) => /(^|\.)(googleusercontent|ggpht)\.com$/.test(host);
export async function photoFromURL(url: string): Promise<string | null> {
  let parsed: URL;
  // Google's picture links end in a size (=s96-c); ask for one big enough to crop.
  try { parsed = new URL(url.replace(/=s\d+-c$/, '=s512-c')); } catch { return null; }
  if (parsed.protocol !== 'https:' || !googleImageHost(parsed.hostname)) return null;
  try {
    const response = await fetch(parsed, { signal: AbortSignal.timeout(10_000) });
    const final = new URL(response.url || parsed.toString());
    if (!response.ok || final.protocol !== 'https:' || !googleImageHost(final.hostname)) {
      console.error('Google photo fetch refused', response.status, final.hostname);
      return null;
    }
    if (Number(response.headers.get('content-length') ?? 0) > MAX_PHOTO_INPUT_BYTES) { console.error('Google photo too large'); return null; }
    return await storePhoto(Buffer.from(await response.arrayBuffer()));
  } catch (error) {
    console.error('Google photo failed', error instanceof Error ? `${error.name}: ${error.message}` : 'UnknownError');
    return null;
  }
}
