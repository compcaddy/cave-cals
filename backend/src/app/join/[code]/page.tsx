import type { Metadata } from 'next';
import Link from 'next/link';
import localFont from 'next/font/local';
import { notFound } from 'next/navigation';
import { appStoreLink } from '@/server/discount-codes';
import { normalizeInviteCode } from '@/server/clan-rules';
import '../../landing.css';
import '../../[code]/code.css';

const schoolbell = localFont({ src: '../../fonts/Schoolbell-Regular.ttf', variable: '--font-hand', display: 'swap' });
export const dynamic = 'force-dynamic';
type Props = { params: Promise<{ code: string }> };

export const metadata: Metadata = {
  title: 'Join my clan on Cave Cals',
  description: 'Keep each other on track: streaks, challenges, and a campfire for your crew.',
  openGraph: { title: 'Join my clan on Cave Cals', description: 'Keep each other on track: streaks, challenges, and a campfire for your crew.', type: 'website' },
  robots: { index: false, follow: false },
};

/**
 * CaveCals.com/join/<CODE>. With Cave Cals installed this is a Universal Link and opens the clan's Join page
 * directly; this page is only seen without the app, or inside in-app browsers that don't open apps.
 * It doesn't look the clan up, so a link never reveals a clan's name or members.
 */
export default async function JoinPage({ params }: Props) {
  const code = normalizeInviteCode(decodeURIComponent((await params).code));
  if (!/^[A-Z2-9]{6}$/.test(code)) notFound();
  return <div className={`landing code-page ${schoolbell.variable}`}>
    <header className="site-header">
      <Link className="wordmark" href="/" aria-label="Cave Cals home">Cave Cals<span aria-hidden="true">.</span></Link>
    </header>
    <main className="code-main">
      <img className="code-mascot" src="/brand/welcome-logo.webp" width="1086" height="1448" alt="" />
      <p className="code-from">You’re invited to a clan</p>
      <h1>Join the fire</h1>
      <p className="code-pitch">A clan keeps each other on track in Cave Cals: streaks, challenges, and a nudge when someone forgets to log.</p>
      <div className="code-card">
        <div><small>Clan code</small><strong>{code}</strong></div>
      </div>
      <a className="app-download code-go" href={appStoreLink(null)}>
        <img src="/brand/CavePhone.svg" width="26" height="32" alt="" />
        <span><small>Free on the App Store</small><strong>Get Cave Cals</strong></span>
      </a>
      <ol className="code-steps">
        <li>Get Cave Cals on the App Store.</li>
        <li>Installed? Come back and tap this link again. It opens the clan.</li>
        <li>Or open Cave Cals, tap the campfire, then Join with code and type {code}.</li>
      </ol>
      <p className="download-note">Have Cave Cals already? <a href={`cavecals://join/${code}`}>Open the clan in Cave Cals</a></p>
    </main>
    <footer className="site-footer">
      <span className="footer-brand">Small app. Big cave energy.</span>
      <div className="footer-links"><Link href="/privacy">Privacy</Link><Link href="/terms">Terms</Link><a href="https://ascbuddy.com/support/6809208501">Support</a></div>
    </footer>
  </div>;
}
