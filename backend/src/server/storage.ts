import { randomUUID, createHash } from 'node:crypto';
import { mkdir, readFile, writeFile, unlink } from 'node:fs/promises';
import path from 'node:path';
import { eq, and, gt } from 'drizzle-orm';
import { get, del, issueSignedToken, presignUrl } from '@vercel/blob';
import { z } from 'zod';
import { database } from './db';
import { uploads } from './schema';
import { APIError, imageTypes, audioTypes, MAX_IMAGE_BYTES, MAX_AUDIO_BYTES, localDevelopment, isDevelopmentUser, DEV_ACCOUNT, readLimited } from './config';
import type { Identity } from './auth';
import { consume, tomorrow, utcDay } from './rate-limit';
export const uploadInput = z.object({ kind: z.enum(['image','audio']), mime: z.string().max(80), byteLength: z.number().int().positive(), sha256: z.string().regex(/^[a-f0-9]{64}$/) });
export type Upload = typeof uploads.$inferSelect;
export function validateUpload(input: z.infer<typeof uploadInput>) {
  const types: readonly string[] = input.kind === 'image' ? imageTypes : audioTypes;
  const max = input.kind === 'image' ? MAX_IMAGE_BYTES : MAX_AUDIO_BYTES;
  if (!types.includes(input.mime)) throw new APIError(415, 'unsupported_file', 'Choose a JPEG, PNG, WebP image or supported audio recording.');
  if (input.byteLength > max) throw new APIError(413, 'too_large', input.kind === 'image' ? 'Choose an image smaller than 20 MB.' : 'Choose a shorter recording (maximum 4 MB).');
}
export async function signUpload(request: Request, identity: Identity, input: z.infer<typeof uploadInput>) {
  validateUpload(input);
  await consume(`uploads:${identity.accountId}:${utcDay()}`, 100, tomorrow());
  const id = randomUUID();
  const pathname = `temporary/${identity.accountId}/${id}`;
  const storage = localDevelopment(request) && process.env.LOCAL_UPLOADS === 'true' ? 'local' : 'blob';
  const upload: Upload = { id, accountId: identity.accountId, pathname, ...input, storage, state: 'pending', result: null, createdAt: new Date(), expiresAt: new Date(Date.now() + 24*3600000) };
  let uploadURL: string;
  if (storage === 'local') uploadURL = `${new URL(request.url).origin}/api/dev/upload/${id}`;
  else {
    const token = await issueSignedToken({ pathname, operations: ['put'], validUntil: Date.now() + 5*60000, allowedContentTypes: [input.mime], maximumSizeInBytes: input.byteLength });
    uploadURL = (await presignUrl(token, { operation: 'put', pathname, access: 'private', allowedContentTypes: [input.mime], allowOverwrite: false, addRandomSuffix: false, maximumSizeInBytes: input.byteLength })).presignedUrl;
  }
  await database().insert(uploads).values(upload);
  return { uploadId: id, uploadURL, method: 'PUT', contentType: input.mime };
}
export const localPath = (id: string) => path.join(process.cwd(), '.local-uploads', `${z.string().uuid().parse(id)}.bin`);
export async function localUpload(request: Request, id: string) {
  if (!isDevelopmentUser(request)) throw new APIError(404, 'not_found', 'Not found.');
  const [upload] = await database().select().from(uploads).where(and(eq(uploads.id, z.string().uuid().parse(id)), eq(uploads.accountId, DEV_ACCOUNT), eq(uploads.storage, 'local'), eq(uploads.state, 'pending'), gt(uploads.expiresAt, new Date())));
  if (!upload || upload.createdAt.getTime() + 5*60000 < Date.now()) throw new APIError(404, 'not_found', 'Upload expired.');
  const bytes = await readLimited(request, upload.byteLength);
  verifyBytes(upload, bytes);
  await mkdir(path.dirname(localPath(id)), { recursive: true });
  try { await writeFile(localPath(id), bytes, { flag: 'wx', mode: 0o600 }); }
  catch (error) { if ((error as NodeJS.ErrnoException).code !== 'EEXIST') throw error; throw new APIError(409, 'already_uploaded', 'This upload already exists.'); }
  return Response.json({ uploaded: true });
}
export function verifyBytes(upload: Pick<Upload,'byteLength'|'sha256'>, bytes: Buffer) {
  if (bytes.length !== upload.byteLength || createHash('sha256').update(bytes).digest('hex') !== upload.sha256) throw new APIError(400, 'file_mismatch', 'The uploaded file did not match. Please upload it again.');
}
export async function readUpload(upload: Upload): Promise<Buffer> {
  let bytes: Buffer;
  if (upload.storage === 'local') {
    if (process.env.VERCEL || process.env.NODE_ENV !== 'development') throw new APIError(403, 'local_only', 'Local uploads are disabled.');
    try { bytes = await readFile(localPath(upload.id)); } catch { throw new APIError(409, 'upload_missing', 'Finish uploading before analysis.'); }
  } else {
    const blob = await get(upload.pathname, { access: 'private', useCache: false, abortSignal: AbortSignal.timeout(30000) });
    if (!blob || blob.statusCode !== 200) throw new APIError(409, 'upload_missing', 'Finish uploading before analysis.');
    if (blob.blob.size !== upload.byteLength) throw new APIError(400, 'file_mismatch', 'Invalid upload size.');
    const reader = blob.stream.getReader(); const chunks: Uint8Array[] = []; let size = 0;
    while (true) { const { done, value } = await reader.read(); if (done) break; size += value.length; if (size > upload.byteLength) { await reader.cancel(); throw new APIError(413, 'too_large', 'Invalid upload size.'); } chunks.push(value); }
    bytes = Buffer.concat(chunks);
  }
  verifyBytes(upload, bytes); return bytes;
}
export async function deleteUpload(upload: Upload) {
  if (upload.storage === 'local') { await unlink(localPath(upload.id)).catch(error => { if (error.code !== 'ENOENT') throw error; }); }
  else await del(upload.pathname);
}
