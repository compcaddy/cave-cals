# Ad attribution

Added October 19, 2026 (app local, not yet in a build). Paid ads on each platform can report which ads led to installs and subscriptions, without an ad SDK, the advertising identifier (IDFA), or an App Tracking Transparency prompt. The paid-ads plan is in `Marketing/2026-10-growth-playbook/07-Paid-Ads.md`.

## What the app does

1. **Apple Ads → RevenueCat.** Right after RevenueCat is configured, `AISubscriptions.connectRevenueCat()` calls `Purchases.shared.attribution.enableAdServicesAttributionTokenCollection()`. RevenueCat sends Apple's AdServices token once per install and asks Apple which campaign, ad group, and keyword led to it, so RevenueCat's charts and customer pages show revenue by Apple Ads campaign. This is Apple's standard attribution and needs no tracking permission. RevenueCat is configured once the backend account loads (the post-onboarding offer, Settings, About You, a scan, or the paywall), so nearly every new install sends it within minutes.
2. **Every other ad network → Apple's postbacks.** `App/AdAttribution.swift` keeps the install's SKAdNetwork conversion value current (Apple mirrors it into AdAttributionKit, so one call covers both). After an install from an ad on Meta (Facebook/Instagram), TikTok, Google/YouTube, X, Snap, or another registered network, iOS sends that network delayed, anonymous postbacks with the value. **Apple only starts a postback once the app updates the value, so before this change, installs from those ads produced no postbacks at all.** For installs that didn't come from an ad, iOS ignores the update.

Both are off in Dev, UI tests, screenshots, previews, and unit tests (`UsageStats.recordingAllowed`), and when **Settings → Usage stats → Share anonymous usage stats** is off; its footer mentions them.

## Conversion value schema

Ad networks (or an attribution partner) need this table to read the values. Windows are counted from the first launch after install (`adAttributionInstalledAt.v1`). Only food *entered* since then counts (`createdAt`), so iCloud history from an earlier install and backfilled days don't look like activity.

**Fine value** (0–63, first postback only, days 0–2, and only when enough people installed from the same ad): add up the milestones reached.

| Bit | Value | Milestone |
| --- | --- | --- |
| 0 | 1 | Finished setup (a plan, a manual goal, or Just start tracking) |
| 1 | 2 | Logged food |
| 2 | 4 | Logged food on 2 different calendar days |
| 3 | 8 | Logged food from a Meal Scan or Voice Log |
| 4 | 16 | Joined Cave Cals+ (any plan) |
| 5 | 32 | Joined Cave Cals+ yearly (always with 16) |

Examples: 3 = set up and logged; 7 = logged on two days; 23 = logged on two days and joined monthly; 55 = the same, yearly.

**Coarse value** (every postback; it's all small campaigns get):

| Window | low | medium | high |
| --- | --- | --- | --- |
| 1 (first 2 days) | opened | logged food | joined Cave Cals+ |
| 2 (days 3–7) | opened | logged food on 2+ days in this window | joined Cave Cals+ |
| 3 (days 8–35) | opened | logged food on 2+ days in this window | joined Cave Cals+ |

Joining is remembered for the install (`adAttributionPlus.v1`), even if the membership later ends. The plan is known when bought in the app (`AISubscriptions.buy`); a membership found at an account check (a restore, say) sets 16 only. Values are sent only when they change, and on the first launch, so each install makes a handful of calls; nothing is sent after day 35. Only the first failure per install is reported to usage stats (area `adAttribution`), because the simulator answers every update with `SKANErrorDomain` 10 (unknown).

## Setting up each platform

| Platform | What works now | What's needed to optimize for subscriptions |
| --- | --- | --- |
| **Apple Ads** | Full: RevenueCat shows installs and revenue by campaign and keyword | RevenueCat's **Apple Search Ads** integration was added October 19, 2026 (Basic: Done). **Advanced** (campaign names and spend) needs the owner to click **Sign in with Apple** there with the Apple Ads account. The app side ships with the next build |
| **Meta (Facebook + Instagram)** | SKAN postbacks reach Meta | Meta's iOS app-install campaigns expect the Meta SDK or an attribution partner, which also sets up the schema in Events Manager. RevenueCat's Meta integration requires the Meta SDK too |
| **TikTok** | SKAN postbacks reach TikTok | The value map lives in TikTok's Conversion Hub, normally set up through the TikTok SDK or an attribution partner |
| **Google / YouTube** | SKAN postbacks reach Google | iOS App campaigns need Firebase (Google Analytics) or an attribution partner for conversion tracking and the schema |
| **X** | SKAN postbacks reach X | An attribution partner |

**Owner decision pending:** the Meta SDK, TikTok SDK, Firebase, or an attribution partner (AppsFlyer, Adjust, Branch, Singular) would let those platforms optimize for purchases. Each adds a third-party SDK to a health app: new App Store privacy answers and privacy policy text, a review of what it sends (turn off automatic event logging), and care with state health-data laws such as Washington's My Health My Data Act. One attribution partner covers all four platforms and RevenueCat can feed it purchases; it beats adding three ad SDKs. If one is added, let it own conversion values and remove `AdAttribution`'s updates, since only one party should set them.

**Without any SDK**, measure the other platforms with:
- **App Store campaign links.** Point ads at `https://apps.apple.com/app/apple-store/id6809208501?pt=967948&ct=<campaign>&mt=8` (one `ct` per platform or ad, up to 40 characters). App Store Connect → Analytics → Acquisition → Campaigns shows page views, downloads, and proceeds per link. The provider token `967948` is the same one the creator code pages use.
- **Each network's own SKAN reports** of installs (now that postbacks exist).
- **“Where did you hear about Cave Cals?”** answers on the admin page (`onboarding.source`).

## Privacy

No identifiers, diary entries, calories, weights, or Health data go to any ad network. Postbacks come from Apple, arrive a day or more later, and drop detail when few people installed from the same ad. Cave Cals doesn't read the IDFA, ask to track, or include ad SDKs, so `PrivacyInfo.xcprivacy` is unchanged (`NSPrivacyTracking` stays false). The privacy policy's **Ad measurement** section describes both pieces; it went live October 19, 2026 as `dpl_fK2UwbUeQmSjNshvJx9h7G8WH8cp`. Production was running `codex/android-parity-backend` (`906eac7`, deployed by Codex October 17), so that deploy is `906eac7`'s exact files (SHA-1 checked against the live deployment) plus only the privacy page. Before the build that ships this goes to review, recheck App Store Connect's privacy answers for the Apple Ads campaign data RevenueCat now keeps with the purchase account.

## Checking it

`Tests/AdAttributionTests.swift` covers the windows, schema, and sending rules. A simulator launch shows the first-launch update reaching StoreKit (`SKAdNetwork: Error while updating conversion value … Code=10`, expected there). Real postbacks need a signed build installed from an ad; for a device check, iOS Settings → Developer has SKAdNetwork and AdAttributionKit testing options for test postbacks. Apple Ads attribution appears in RevenueCat only for installs from real Apple Ads.
