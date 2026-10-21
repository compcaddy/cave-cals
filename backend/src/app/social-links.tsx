const links = [
  { name: 'X', href: 'https://x.com/CaveCals', icon: <path fill="currentColor" d="M18.901 1.153h3.68l-8.04 9.19L24 22.846h-7.406l-5.8-7.584-6.638 7.584H.474l8.6-9.83L0 1.154h7.594l5.243 6.932ZM17.61 20.644h2.039L6.486 3.24H4.298Z" /> },
  { name: 'Instagram', href: 'https://www.instagram.com/cavecals/', icon: <g fill="none" stroke="currentColor" strokeWidth="2.2"><rect x="2.2" y="2.2" width="19.6" height="19.6" rx="5.6" /><circle cx="12" cy="12" r="4.6" /><circle cx="17.6" cy="6.4" r=".6" fill="currentColor" /></g> },
  { name: 'YouTube', href: 'https://www.youtube.com/@CaveCals', icon: <path fill="currentColor" d="M23.498 6.186a3.016 3.016 0 0 0-2.122-2.136C19.505 3.545 12 3.545 12 3.545s-7.505 0-9.377.505A3.017 3.017 0 0 0 .502 6.186C0 8.07 0 12 0 12s0 3.93.502 5.814a3.016 3.016 0 0 0 2.122 2.136c1.871.505 9.376.505 9.376.505s7.505 0 9.377-.505a3.015 3.015 0 0 0 2.122-2.136C24 15.93 24 12 24 12s0-3.93-.502-5.814zM9.545 15.568V8.432L15.818 12l-6.273 3.568z" /> },
];

/** @CaveCals on X, Instagram, and YouTube. */
export default function SocialLinks({ className = '' }: { className?: string }) {
  return <ul className={`social-links ${className}`} aria-label="Cave Cals on social media">
    {links.map(link => <li key={link.name}>
      <a href={link.href} target="_blank" rel="noopener noreferrer" aria-label={`Cave Cals on ${link.name}`}>
        <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true">{link.icon}</svg>
      </a>
    </li>)}
  </ul>;
}
