import { requireAdmin } from '../../require-admin';
import { subscribers } from '@/server/email';
export const runtime = 'nodejs';
// The opted-in list, for importing into another email tool.
export async function GET() {
  await requireAdmin();
  const rows = await subscribers();
  const csv = ['email', ...rows.map(r => `"${r.email.replace(/"/g, '""')}"`)].join('\n') + '\n';
  return new Response(csv, { headers: { 'Content-Type': 'text/csv; charset=utf-8', 'Content-Disposition': 'attachment; filename="cave-cals-news.csv"', 'Cache-Control': 'no-store' } });
}
