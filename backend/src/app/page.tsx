import Link from 'next/link';
export const dynamic = 'force-dynamic';
export default function Home() {
  const store = process.env.APP_STORE_URL;
  const valid = store && /^https:\/\/apps\.apple\.com\//.test(store);
  return <main><p className="eyebrow">CAVE CALS</p><h1>You eat.<br/>App count.</h1><p className="intro">A simple food diary. Log meals by photo or voice, review the estimate, and get on with your day.</p>
    {valid ? <a className="button" href={store}>Download for iPhone</a> : <p>Coming to the App Store.</p>}
    <p className="muted">Your diary stays on your devices and in private iCloud storage. Photo and voice identification send the selected media to our backend and OpenAI when you choose to analyze it.</p>
    {process.env.NODE_ENV === 'development' && !process.env.VERCEL && <Link href="/test">Open local AI tester →</Link>}
  </main>;
}
