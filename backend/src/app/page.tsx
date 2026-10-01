import Link from 'next/link';
export const dynamic = 'force-dynamic';
export default function Home() {
  const configuredStore = process.env.APP_STORE_URL?.trim();
  const store = configuredStore && /^https:\/\/apps\.apple\.com\//.test(configuredStore)
    ? configuredStore
    : 'https://apps.apple.com/us/app/cave-cals-ai-calorie-tracker/id6809208501';
  return <main><p className="eyebrow">CAVE CALS</p><h1>You eat.<br/>App count.</h1><p className="intro">A simple calorie diary. Add calories, find foods, or review a photo or voice estimate. Then get on with your day.</p>
    <a className="button" href={store}>Download for iPhone</a>
    <p className="muted">Your diary stays on your devices and in private iCloud storage. Photo and voice identification send the selected media to our backend and OpenAI when you choose to analyze it.</p>
    {process.env.NODE_ENV === 'development' && !process.env.VERCEL && <Link href="/test">Open local AI tester →</Link>}
    <p><a href="https://platform.fatsecret.com">Powered by fatsecret Platform API</a></p>
    <p><Link href="/privacy">Privacy</Link></p>
  </main>;
}
