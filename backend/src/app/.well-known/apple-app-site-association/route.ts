// Universal Links: CaveCals.com/join/<CODE> opens Cave Cals straight to that clan's Join page.
export const dynamic = 'force-static';
export function GET() {
  const team = process.env.APPLE_TEAM_ID || 'J877QX85N5';
  const app = process.env.APPLE_BUNDLE_ID || 'com.philstarkovich.cavecals';
  return Response.json({
    applinks: { details: [{ appIDs: [`${team}.${app}`], components: [{ '/': '/join/*', comment: 'Clan invites' }] }] },
  }, { headers: { 'Cache-Control': 'public, max-age=3600' } });
}
