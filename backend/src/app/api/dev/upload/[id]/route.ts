import { localUpload } from '@/server/storage';
import { errorResponse } from '@/server/config';
export const runtime = 'nodejs';
export async function PUT(request: Request, context: { params: Promise<{id:string}> }) {
  try { return await localUpload(request, (await context.params).id); } catch (error) { return errorResponse(error); }
}
