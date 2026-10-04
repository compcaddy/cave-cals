'use client';
import { useState } from 'react';
export default function CopyButton({ text, label, primary = false }: { text: string; label: string; primary?: boolean }) {
  const [copied, setCopied] = useState(false);
  return <button type="button" className={`admin-button${primary ? ' primary' : ''}`} onClick={async () => {
    await navigator.clipboard.writeText(text);
    setCopied(true); setTimeout(() => setCopied(false), 2000);
  }}>{copied ? 'Copied' : label}</button>;
}
