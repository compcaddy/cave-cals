import type { Metadata } from 'next';
import Link from 'next/link';
import localFont from 'next/font/local';
import ScreenshotCarousel from './screenshot-carousel';
import './landing.css';

const schoolbell = localFont({ src: './fonts/Schoolbell-Regular.ttf', variable: '--font-hand', display: 'swap' });

export const dynamic = 'force-dynamic';
export const metadata: Metadata = {
  title: 'Cave Cals — You eat. App track. Weight drop.',
  description: 'Calorie tracking. Caveman simple. Log food, scan a barcode, snap a meal, or say what you ate. Track calories, macros, and progress with Cave Cals for iPhone.',
  openGraph: {
    title: 'Cave Cals — Calorie tracking. Caveman simple.',
    description: 'You eat. App track. Weight drop. Get Cave Cals for iPhone.',
    type: 'website',
  },
};

export default function Home() {
  const configuredStore = process.env.APP_STORE_URL?.trim();
  const store = configuredStore && /^https:\/\/apps\.apple\.com\//.test(configuredStore)
    ? configuredStore
    : 'https://apps.apple.com/us/app/cave-cals-ai-calorie-tracker/id6809208501';

  return <div className={`landing ${schoolbell.variable}`}>
    <a className="skip-link" href="#main">Skip to content</a>
    <header className="site-header">
      <a className="wordmark" href="/" aria-label="Cave Cals home">Cave Cals<span aria-hidden="true">.</span></a>
      <nav aria-label="Main navigation">
        <a className="see-it-link" href="#see-it">See it in action</a>
        <a className="header-download" href={store}>Get the app</a>
      </nav>
    </header>
    <main className="landing-main" id="main">
      <section className="hero" aria-labelledby="hero-title">
        <div className="hero-copy">
          <img className="hero-mascot" src="/brand/welcome-logo.webp" width="1086" height="1448" alt="Cave Cals caveman scanning a drumstick" fetchPriority="high" />
          <h1 id="hero-title">You eat.<br />App track.<br /><span>Weight drop.</span></h1>
          <p className="hero-description">Calorie tracking. Caveman simple.</p>
          <a className="app-download" href={store}>
            <img src="/brand/CavePhone.svg" width="26" height="32" alt="" />
            <span><small>Download for iPhone</small><strong>Get Cave Cals</strong></span>
          </a>
          <p className="download-note">Free to start. No account needed.</p>
        </div>
        <div className="hero-gallery" id="see-it"><ScreenshotCarousel /></div>
      </section>
      <section className="features" aria-label="Cave Cals features">
        <div className="feature">
          <span className="feature-number" aria-hidden="true">01 /</span>
          <h2>Log it. Your way.</h2>
          <p>Type. Scan. Snap. Speak.<br />Quick Add remembers your usuals.</p>
        </div>
        <div className="feature">
          <span className="feature-number" aria-hidden="true">02 /</span>
          <h2>Know what’s left.</h2>
          <p>Your calorie goal. Your daily total.<br />Macros, if you want ’em.</p>
        </div>
        <div className="feature">
          <span className="feature-number" aria-hidden="true">03 /</span>
          <h2>See progress.</h2>
          <p>Weigh-ins. Weekly recaps.<br />Little habits. Bigger picture.</p>
        </div>
      </section>
      <div className="plus-note"><span>Cave Cals+</span> More snap. More talk. Recipe imports.<small>Photo &amp; voice include introductory free scans. More scans and recipe imports require Cave Cals+.</small></div>
    </main>
    <footer className="site-footer">
      <span className="footer-brand">Small app. Big cave energy.</span>
      <div className="footer-links"><Link href="/privacy">Privacy</Link><Link href="/terms">Terms</Link><a href="https://ascbuddy.com/support/6809208501">Support</a></div>
      <div className="footer-bottom"><span>© {new Date().getFullYear()} Claim727 LLC</span><span>Food search powered by <a href="https://platform.fatsecret.com">fatsecret</a></span></div>
      {process.env.NODE_ENV === 'development' && !process.env.VERCEL && <Link className="local-tester" href="/test">Local AI tester</Link>}
    </footer>
  </div>;
}
