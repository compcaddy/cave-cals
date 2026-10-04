import { NextResponse, type NextRequest } from 'next/server';
import { adminAuthorized, adminConfigured, adminLocked, recordAdminFailure } from '@/server/admin-auth';
const signIn = () => new NextResponse('Sign in to view this page.', {
  status: 401,
  headers: { 'WWW-Authenticate': 'Basic realm="Cave Cals admin", charset="UTF-8"', 'Cache-Control': 'no-store' },
});
// The admin pages check the password again themselves; this prompts for it and enforces the lockout.
export async function proxy(request: NextRequest) {
  if (!adminConfigured()) return new NextResponse('Not found.', { status: 404 });
  const header = request.headers.get('authorization');
  if (!header) return signIn();
  try {
    if (await adminLocked(request)) {
      return new NextResponse('Too many wrong passwords. Try again in an hour.', { status: 429, headers: { 'Retry-After': '3600', 'Cache-Control': 'no-store' } });
    }
    if (adminAuthorized(header)) return NextResponse.next();
    await recordAdminFailure(request);
    return signIn();
  } catch {
    // Without the lockout check, stay closed.
    return new NextResponse('Unavailable. Please try again.', { status: 503, headers: { 'Cache-Control': 'no-store' } });
  }
}
export const config = { matcher: ['/admin', '/admin/:path*'] };
