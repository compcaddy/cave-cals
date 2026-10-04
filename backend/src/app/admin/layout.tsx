import type { Metadata } from 'next';
import { requireAdmin } from './require-admin';
import './admin.css';
export const metadata: Metadata = { title: 'Cave Cals stats', robots: { index: false, follow: false } };
export default async function AdminLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  await requireAdmin();
  return <div className="admin">{children}</div>;
}
