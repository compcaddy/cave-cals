import { androidPackage } from '../../../server/android-integrity';

export const dynamic = 'force-dynamic';
export function GET() {
  const digests = (process.env.ANDROID_SIGNING_CERTIFICATE_SHA256 || '').split(',').map(s => s.trim()).filter(s => /^[A-Za-z0-9_-]{43}$/.test(s));
  const statements = digests.length ? [{ relation: ['delegate_permission/common.handle_all_urls'], target: {
    namespace: 'android_app', package_name: androidPackage(),
    sha256_cert_fingerprints: digests.map(s => Buffer.from(s, 'base64url').toString('hex').toUpperCase().match(/.{2}/g)!.join(':')),
  } }] : [];
  return Response.json(statements, { headers: { 'Cache-Control': 'public, max-age=3600' } });
}
