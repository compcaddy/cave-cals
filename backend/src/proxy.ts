import { NextResponse, type NextRequest } from 'next/server';
import { adminAuthorized, adminConfigured } from '@/server/admin-auth';
// The admin pages check again themselves; this answers with the browser's sign-in prompt.
export function proxy(request: NextRequest) {
  if (!adminConfigured()) return new NextResponse('Not found.', { status: 404 });
  if (adminAuthorized(request.headers.get('authorization'))) return NextResponse.next();
  return new NextResponse('Sign in to view this page.', {
    status: 401,
    headers: { 'WWW-Authenticate': 'Basic realm="Cave Cals admin", charset="UTF-8"', 'Cache-Control': 'no-store' },
  });
}
export const config = { matcher: ['/admin', '/admin/:path*'] };
