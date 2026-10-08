import type { Metadata } from 'next';
import Link from 'next/link';
import localFont from 'next/font/local';
import { headers } from 'next/headers';
import { notFound, redirect } from 'next/navigation';
import { after } from 'next/server';
import { cache } from 'react';
import { countCode, dealLine, findCode, isBot, linkCode } from '@/server/discount-codes';
import { CopyCodeButton, GetAppButton } from './copy-code';
import '../landing.css';
import './code.css';

const schoolbell = localFont({ src: '../fonts/Schoolbell-Regular.ttf', variable: '--font-hand', display: 'swap' });

export const dynamic = 'force-dynamic';

type Props = { params: Promise<{ code: string }> };
// The page and its link-preview metadata share one lookup per request.
const lookup = cache(async (segment: string) => {
  const code = linkCode(segment);
  return code ? findCode(code) : null;
});

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const row = await lookup((await params).code);
  if (!row) return { title: 'Cave Cals' };
  const title = `${dealLine(row.offering)} with code ${row.code}`;
  return {
    title: `${title} · Cave Cals`,
    description: `${row.name} sent you a Cave Cals deal. Get the app, then paste code ${row.code}.`,
    openGraph: { title, description: `${row.name} sent you a Cave Cals deal.`, type: 'website' },
    // Campaign pages stay out of search results.
    robots: { index: false, follow: false },
  };
}

/** A creator's or trainer's page: CaveCals.com/Sarah in any capitalization. */
export default async function CodePage({ params }: Props) {
  const segment = (await params).code;
  // favicon.ico and other non-code paths are a plain 404.
  if (!linkCode(segment)) notFound();
  const row = await lookup(segment);
  // An unknown or paused code still lands somewhere useful.
  if (!row) redirect('/');
  if (!isBot((await headers()).get('user-agent'))) after(() => countCode(row.code, 'visits'));

  return <div className={`landing code-page ${schoolbell.variable}`}>
    <header className="site-header">
      <Link className="wordmark" href="/" aria-label="Cave Cals home">Cave Cals<span aria-hidden="true">.</span></Link>
    </header>
    <main className="code-main">
      <img className="code-mascot" src="/brand/welcome-logo.webp" width="1086" height="1448" alt="" />
      <p className="code-from">{row.name} sent you a deal</p>
      <h1>{dealLine(row.offering).replace('Cave Cals+', 'Cave Cals+')}</h1>
      <p className="code-pitch">Cave Cals+ adds photo and voice logging to the calorie tracker that’s caveman simple. Monthly or yearly.</p>
      <div className="code-card">
        <div><small>Your code</small><strong>{row.code}</strong></div>
        <CopyCodeButton code={row.code} />
      </div>
      <GetAppButton code={row.code} href={`/${segment}/app-store`} />
      <ol className="code-steps">
        <li>Get Cave Cals on the App Store.</li>
        <li>After setup, Cave Cals asks where you found it. Pick Social media or Trainer or coach.</li>
        <li>Paste your code and tap Apply.</li>
      </ol>
      <p className="download-note">Already have Cave Cals? Tap “Have a code?” at the bottom of the Cave Cals+ screen.</p>
    </main>
    <footer className="site-footer">
      <span className="footer-brand">Small app. Big cave energy.</span>
      <div className="footer-links"><Link href="/privacy">Privacy</Link><Link href="/terms">Terms</Link><a href="https://ascbuddy.com/support/6809208501">Support</a></div>
    </footer>
  </div>;
}
