import Link from 'next/link';
import { adminQuery, type Platform } from '@/server/admin-data';

const platforms: [Platform, string][] = [['all', 'All apps'], ['ios', 'iPhone'], ['android', 'Android']];

/** Pills that switch a page between the apps and between store and all builds, keeping the other choice. */
export function FilterPills({ path, all, platform }: { path: string; all: boolean; platform: Platform }) {
  return <>
    {platforms.map(([value, label]) =>
      <Link key={value} className={`pill${platform === value ? ' on' : ''}`} href={`${path}${adminQuery(all, value)}`}>{label}</Link>)}
    <span className="divider" />
    <Link className={`pill${all ? '' : ' on'}`} href={`${path}${adminQuery(false, platform)}`}>Store builds</Link>
    <Link className={`pill${all ? ' on' : ''}`} href={`${path}${adminQuery(true, platform)}`}>All builds</Link>
  </>;
}

/** Which installs a page counts, in words. Android debug builds never report, so its two choices match. */
export function scopeLabel(all: boolean, platform: Platform) {
  if (!all) return { all: 'App Store and Google Play installs', ios: 'App Store installs only', android: 'Google Play installs only' }[platform];
  return { all: 'All builds, including TestFlight and Xcode', ios: 'All iPhone builds, including TestFlight and Xcode', android: 'All Android builds (debug builds don’t report)' }[platform];
}

export const phones: Record<Platform, string> = { all: 'phones', ios: 'iPhones', android: 'Android phones' };
