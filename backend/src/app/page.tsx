import type { Metadata } from 'next';
import Link from 'next/link';
import localFont from 'next/font/local';
import ScreenshotCarousel from './screenshot-carousel';
import SocialLinks from './social-links';
import { appStoreLink } from '@/server/discount-codes';
import './landing.css';

const schoolbell = localFont({ src: './fonts/Schoolbell-Regular.ttf', variable: '--font-hand', display: 'swap' });

export const dynamic = 'force-dynamic';
const description = 'The easiest calorie counter for weight loss. Type it, scan it, snap it, or say it. Cave Cals does the math so the weight comes off. Free for iPhone.';
export const metadata: Metadata = {
  title: 'Cave Cals — Simple calorie counting for weight loss',
  description,
  alternates: { canonical: '/' },
  openGraph: {
    title: 'Cave Cals — You eat. App track. Weight drop.',
    description,
    url: '/',
    siteName: 'Cave Cals',
    type: 'website',
  },
  twitter: {
    card: 'summary_large_image',
    site: '@CaveCals',
    creator: '@CaveCals',
    title: 'Cave Cals — You eat. App track. Weight drop.',
    description,
  },
};

const PLAY_STORE_URL = 'https://play.google.com/store/apps/details?id=com.philstarkovich.cavecals';

const features = [
  { file: 6, title: 'Track it.', detail: 'Calories left, macros, and everything you ate, on one screen. Nothing else in the way.', alt: 'Cave Cals daily diary showing calories, macros, and logged foods' },
  { file: 2, title: 'Snap it.', detail: 'Take a photo of your plate. Cave Cals spots the foods and counts the calories.', alt: 'Meal Scan estimating a plate of chicken, sweet potatoes, and broccoli' },
  { file: 3, title: 'Scan it.', detail: 'Point at a barcode. Calories in. Done before the snack is open.', alt: 'Barcode Scan looking up a bag of almonds' },
  { file: 4, title: 'Say it.', detail: 'Tell the app what you ate, like you’d tell a friend. App write it down.', alt: 'Voice logging listening to a spoken meal description' },
  { file: 5, title: 'Find it.', detail: 'Search any food. Your usuals stay one tap away with Quick Add.', alt: 'Food search showing egg dishes and their calories' },
  { file: 7, title: 'See progress.', detail: 'Weigh-ins and weekly recaps show the weight coming off.', alt: 'Weekly Recap showing weight trends and average daily calories' },
];

export default function Home() {
  const store = appStoreLink('website');

  return <div className={`landing ${schoolbell.variable}`}>
    <a className="skip-link" href="#main">Skip to content</a>
    <header className="site-header">
      <a className="wordmark" href="/" aria-label="Cave Cals home">Cave Cals<span aria-hidden="true">.</span></a>
      <nav aria-label="Main navigation">
        <a className="see-it-link" href="#see-it">See it in action</a>
        <SocialLinks className="header-social" />
        <a className="header-download" href={store}>Get the app</a>
      </nav>
    </header>
    <main className="landing-main" id="main">
      <section className="hero" aria-labelledby="hero-title">
        <div className="hero-copy">
          <img className="hero-mascot" src="/brand/welcome-logo.webp" width="1086" height="1448" alt="Cave Cals caveman scanning a drumstick" fetchPriority="high" />
          <h1 id="hero-title">You eat.<br />App track.<br /><span>Weight drop.</span></h1>
          <p className="hero-description">Simple calorie counting for weight loss.</p>
          <div className="store-badges">
            <a href={store}><img src="/brand/app-store-badge.svg" width="120" height="40" alt="Download on the App Store" /></a>
            <a href={PLAY_STORE_URL}><img src="/brand/google-play-badge.svg" width="135" height="40" alt="Get it on Google Play" /></a>
          </div>
          <p className="download-note">Free install. No account needed.</p>
        </div>
        <div className="hero-gallery" id="see-it"><ScreenshotCarousel /></div>
      </section>
      <section className="features" aria-label="Cave Cals features">
        {features.map((feature, index) => <article className="feature" key={feature.file}>
          <span className="feature-number" aria-hidden="true">{String(index + 1).padStart(2, '0')} /</span>
          <h2>{feature.title}</h2>
          <p>{feature.detail}</p>
          <img src={`/screenshots/slide${feature.file}.webp`} width="900" height="1948" alt={feature.alt} loading="lazy" />
        </article>)}
      </section>
      <div className="plus-note"><span>Cave Cals+</span> More snap. More talk. Recipe imports.<small>Photo &amp; voice include introductory free scans. More scans and recipe imports require Cave Cals+.</small></div>
    </main>
    <footer className="site-footer">
      <span className="footer-brand">Small app. Big cave energy.</span>
      <SocialLinks />
      <div className="footer-links"><Link href="/privacy">Privacy</Link><Link href="/terms">Terms</Link><a href="https://ascbuddy.com/support/6809208501">Support</a></div>
      <div className="footer-bottom"><span>© {new Date().getFullYear()} Claim727 LLC</span><span>Food search powered by <a href="https://platform.fatsecret.com">fatsecret</a></span></div>
      {process.env.NODE_ENV === 'development' && !process.env.VERCEL && <Link className="local-tester" href="/test">Local AI tester</Link>}
    </footer>
    <aside className="qr-badge" aria-label="Download Cave Cals">
      <p>Download now!</p>
      <img className="qr-code" src="/brand/app-store-qr.svg" width="112" height="112" alt="QR code for Cave Cals on the App Store" />
      <a href={store}><img src="/brand/app-store-badge.svg" width="102" height="34" alt="Download on the App Store" /></a>
    </aside>
  </div>;
}
