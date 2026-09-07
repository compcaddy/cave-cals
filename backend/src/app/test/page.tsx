import { notFound } from 'next/navigation';
import Tester from './tester';
export const dynamic = 'force-dynamic';
export default function Page() {
  if (process.env.NODE_ENV !== 'development' || process.env.VERCEL) notFound();
  return <Tester />;
}
