'use client';
import { useState } from 'react';

/** Copies inside the tap itself, so the code is on the clipboard before the App Store opens. */
function copy(code: string) {
  try {
    const field = document.createElement('textarea');
    field.value = code;
    field.setAttribute('readonly', '');
    field.style.position = 'fixed';
    field.style.opacity = '0';
    document.body.appendChild(field);
    field.select();
    field.setSelectionRange(0, code.length);
    document.execCommand('copy');
    field.remove();
  } catch {
    // The asynchronous clipboard below still tries.
  }
  navigator.clipboard?.writeText(code).catch(() => {});
}

export function CopyCodeButton({ code }: { code: string }) {
  const [copied, setCopied] = useState(false);
  return <button type="button" className="code-copy" onClick={() => {
    copy(code);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }}>{copied ? 'Copied' : 'Copy'}</button>;
}

/** A real link, so the App Store opens from the tap; the code is copied on the way. */
export function GetAppButton({ code, href }: { code: string; href: string }) {
  return <a className="app-download code-go" href={href} onClick={() => copy(code)}>
    <img src="/brand/CavePhone.svg" width="26" height="32" alt="" />
    <span><small>Copies {code}, then</small><strong>Get Cave Cals</strong></span>
  </a>;
}
