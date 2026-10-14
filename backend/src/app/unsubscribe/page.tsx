import type { Metadata } from 'next';
import Link from 'next/link';
import '../landing.css';

export const metadata: Metadata = { title: 'Unsubscribe · Cave Cals', robots: { index: false, follow: false } };
type Props = { searchParams: Promise<{ p?: string; t?: string; done?: string; failed?: string }> };

/** Opening the link only shows a button, so link scanners in mail apps can't unsubscribe anyone by accident. */
export default async function UnsubscribePage({ searchParams }: Props) {
  const { p, t, done, failed } = await searchParams;
  return <div className="landing">
    <header className="site-header"><Link className="wordmark" href="/">Cave Cals<span aria-hidden="true">.</span></Link></header>
    <main style={{ maxWidth: 520, margin: '0 auto', padding: '24px', textAlign: 'center' }}>
      {done ? <>
        <h1>You’re unsubscribed</h1>
        <p>No more Cave Cals news emails. You can turn them back on anytime in the app: About You → your account.</p>
      </> : failed || !p || !t ? <>
        <h1>That link didn’t work</h1>
        <p>Use the unsubscribe link from the latest email, or turn off “Email me Cave Cals news” in the app under About You → your account.</p>
      </> : <>
        <h1>Unsubscribe from Cave Cals news?</h1>
        <form method="post" action="/api/unsubscribe">
          <input type="hidden" name="p" value={p} />
          <input type="hidden" name="t" value={t} />
          <button type="submit" className="app-download" style={{ border: 'none', cursor: 'pointer', margin: '16px auto' }}>
            <span><strong>Unsubscribe</strong></span>
          </button>
        </form>
      </>}
    </main>
  </div>;
}
