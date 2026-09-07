import { api } from '@/server/api';
export const runtime = 'nodejs';
export const maxDuration = 240;
export async function POST(request: Request, context: { params: Promise<{path:string[]}> }) {
  return api(request, (await context.params).path.join('/'));
}
