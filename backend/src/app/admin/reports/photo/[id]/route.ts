import { requireAdmin } from '../../../require-admin';
import { readPhoto } from '@/server/clan-photos';
export const runtime = 'nodejs';
// Lets the owner see a reported photo.
export async function GET(_request: Request, context: { params: Promise<{ id: string }> }) {
  await requireAdmin();
  const id = (await context.params).id;
  const bytes = /^[0-9a-f-]{36}$/.test(id) ? await readPhoto(id) : null;
  if (!bytes) return new Response('Not found', { status: 404 });
  return new Response(new Uint8Array(bytes), { headers: { 'Content-Type': 'image/jpeg', 'Cache-Control': 'private, no-store' } });
}
