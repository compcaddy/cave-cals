import { photoResponse } from '@/server/clan-api';
import { errorResponse } from '@/server/config';
export const runtime = 'nodejs';
export async function GET(request: Request, context: { params: Promise<{ id: string }> }) {
  try { return await photoResponse(request, (await context.params).id); }
  catch (error) { return errorResponse(error); }
}
