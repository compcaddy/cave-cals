import type { Metadata } from 'next';
import './style.css';
export const metadata: Metadata = {
  metadataBase: new URL('https://cavecals.com'),
  title: 'Cave Cals',
  description: 'Simple calorie counting for weight loss.',
  openGraph: { siteName: 'Cave Cals', type: 'website' },
  twitter: { card: 'summary_large_image', site: '@CaveCals' },
};
export default function Layout({children}: Readonly<{children:React.ReactNode}>) { return <html lang="en"><body>{children}</body></html>; }
