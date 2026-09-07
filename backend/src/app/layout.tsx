import type { Metadata } from 'next';
import './style.css';
export const metadata: Metadata = { title: 'Cave Cals', description: 'Simple food and calorie logging.' };
export default function Layout({children}: Readonly<{children:React.ReactNode}>) { return <html lang="en"><body>{children}</body></html>; }
