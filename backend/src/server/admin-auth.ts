import { safeEqual } from './config';
/** The admin pages need ADMIN_PASSWORD (16+ characters) in the deployment's environment; without it they're a 404. */
export function adminConfigured() { return (process.env.ADMIN_PASSWORD?.length ?? 0) >= 16; }
/** HTTP Basic authentication: any user name, the configured password. */
export function adminAuthorized(header: string | null): boolean {
  const password = process.env.ADMIN_PASSWORD;
  if (!password || password.length < 16 || !header?.startsWith('Basic ')) return false;
  const decoded = Buffer.from(header.slice(6), 'base64').toString('utf8');
  const separator = decoded.indexOf(':');
  return separator >= 0 && safeEqual(decoded.slice(separator + 1), password);
}
