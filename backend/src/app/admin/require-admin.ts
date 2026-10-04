import { headers } from 'next/headers';
import { notFound } from 'next/navigation';
import { adminAuthorized } from '@/server/admin-auth';
/** The proxy prompts for the password; pages and actions check it again rather than relying on it alone. */
export async function requireAdmin() {
  if (!adminAuthorized((await headers()).get('authorization'))) notFound();
}
