# Backend setup and release checklist

The backend is implemented in `backend/`: Next.js API routes, Neon Postgres, private Vercel Blob uploads, OpenAI, App Attest and StoreKit subscriptions. The SwiftUI app now records voice, accepts camera/library images, calls the backend, and presents editable estimates before logging them to the selected day. Manual logging still works without a subscription.

## 1. Try it locally

Use Node 22 (`nvm use` if you use nvm), then run from the repository root:

```sh
npm ci
npm run dev
```

The private, ignored `.env.development.local` file has already been created with the isolated Neon development database and a random `DEV_API_TOKEN`. Add your own **OpenAI project API key** to its `OPENAI_API_KEY=` line. Do not paste the key into chat, the website, Swift source, or a `NEXT_PUBLIC_` variable. Restart `npm run dev` after changing environment variables.

Open http://127.0.0.1:3000/test. Copy only `DEV_API_TOKEN` from that file into the page's local test token field. Choose a JPEG/PNG/WebP photo or a supported audio recording, or record up to 60 seconds. Press Analyze to send that media to OpenAI. Real requests use your OpenAI billing account. Set a project budget in OpenAI and start with a few examples.

In the iOS Simulator, open Settings → Developer settings, enter `http://127.0.0.1:3000` and the same developer token, then Save and test connection. These controls exist only in Debug builds. The simulator shares the Mac's loopback network. A physical iPhone needs the HTTPS staging backend and real App Attest; the development bypass deliberately does not work over a LAN address.

Local mode bypasses subscriptions only with the long development token, on loopback, outside Vercel, and in development. Local media is written to ignored `.local-uploads` storage under the backend working directory. Do not deploy `DEV_API_TOKEN` or `LOCAL_UPLOADS`.

The development database is Neon branch `backend-dev`, separate from `production`. It was created with an October 4, 2026 expiration; extend its lifetime in Neon or create a new development branch and update the local connection URLs before then. Integration tests intentionally check the expected development endpoint before running.

## 2. Create the Apple app and subscriptions

- [x] Registered `com.philstarkovich.cavecals` and widget `com.philstarkovich.cavecals.QuickLogWidget` under team `J877QX85N5`.
- [ ] Enable App Attest for the identifier and refresh the app's signing/provisioning profiles. The project uses development App Attest in Debug and production App Attest in Release.
- [x] Created **Cave Cals**, Apple App ID `6809208501`, SKU `com.philstarkovich.cavecals`, primary language English (U.S.).
- [ ] Complete paid-app agreements, banking, and tax details.
- [ ] Create an auto-renewable subscription group. Add the plans you want, for example monthly and yearly. Choose your own stable product IDs, prices, localized names/descriptions and review screenshot. Keep Family Sharing disabled: this implementation supports an individual purchaser restoring across up to five installations.
- [ ] Create an **In-App Purchase API key** in App Store Connect → Users and Access → Integrations. Save the `.p8` securely, and record the key ID and issuer ID.
- [ ] Add all product IDs to `APPLE_PRODUCT_IDS`, comma-separated. The app fetches these from the backend and displays Apple's localized product names/prices; there are no hardcoded product IDs to replace in Swift.
- [ ] Create Sandbox testers and use a separate staging/preview deployment with `APPLE_ENVIRONMENT=Sandbox`. Connect it to a separate Neon branch and Blob store. Production uses `APPLE_ENVIRONMENT=Production` and rejects Sandbox configuration.
- [ ] Test purchase, cancellation, renewal, expiration, refund/revocation, Restore Purchases on another installation, and interrupted purchase verification on a signed physical iPhone. StoreKit's local Xcode test environment is not accepted by the real Apple verifier. TestFlight purchases use Sandbox and must point at the staging service for this validation.

No signup screen or iCloud identity is used for API authentication. App Attest registers a device and an anonymous server UUID. StoreKit purchases carry that UUID as Apple's signed `appAccountToken`. The backend verifies Apple's signed transaction and queries current subscription status before billable operations. Restoring a verified purchase links another installation to the original server identity, so usage limits are shared. The diary still syncs separately through private CloudKit.

The current installation limit is five. Reinstallations may consume another device slot; add a support process to remove obsolete `ai_devices` rows after verifying the purchaser. Do not delete the purchase's `ai_accounts` row while the subscription remains in use, since it holds its original account association.

## 3. Configure and publish Vercel

- [ ] Import this repository into Vercel. Set **Root Directory: `backend`**, Framework: Next.js, Node.js: 22.x. Use its default install/build commands. Include files outside the root directory when prompted so the workspace lockfile is available.
- [ ] Create a **private** Vercel Blob store and connect it to the deployment. Its `BLOB_READ_WRITE_TOKEN` must be available only to the backend.
- [ ] Add the variables below to the appropriate Vercel environment. Never copy the local test token into Vercel.

| Variable | Value |
| --- | --- |
| `DATABASE_URL` | Production Neon's pooled connection URL; already saved privately in root `.env.local` |
| `OPENAI_API_KEY` | Your OpenAI project key |
| `OPENAI_IDENTIFICATION_MODEL` | `gpt-6-astra` (configurable) |
| `OPENAI_TRANSCRIPTION_MODEL` | `gpt-transcribe` (configurable) |
| `BLOB_READ_WRITE_TOKEN` | From the private Blob store |
| `APPLE_BUNDLE_ID` | `com.philstarkovich.cavecals` |
| `APPLE_TEAM_ID` | `J877QX85N5` |
| `APPLE_APP_ID` | `6809208501` |
| `APPLE_KEY_ID` | In-App Purchase key ID |
| `APPLE_ISSUER_ID` | Key issuer ID |
| `APPLE_PRIVATE_KEY` | Complete `.p8` contents, including BEGIN/END lines; actual newlines or literal `\n` are accepted |
| `APPLE_PRODUCT_IDS` | Your comma-separated subscription product IDs |
| `APPLE_ENVIRONMENT` | `Production`; `Sandbox` only for staging/preview |
| `CRON_SECRET` | A separately generated random secret of at least 32 characters |
| `APP_STORE_URL` | Optional `https://apps.apple.com/...` override; the home page defaults to Cave Cals' verified public listing |
| `AI_DAILY_LIMIT` | Optional, defaults to 30 attempts per user per UTC day |
| `AI_MONTHLY_LIMIT` | Optional, defaults to 300 attempts per user per UTC calendar month |
| `AI_GLOBAL_DAILY_LIMIT` | Optional, defaults to 1,000 attempts across the service per UTC day |

`backend/vercel.json` chooses Ohio (`cle1`) near your Neon Ohio database and schedules `/api/cron/cleanup` daily. Verify the cron job runs successfully after deployment. It requires `CRON_SECRET`.

The initial schema has been applied to both your development and production Neon branches. Schema changes are tracked in `drizzle/`. To apply them to the production URL in `.env.local`, run from the repository root:

```sh
NODE_ENV=production npm run db:migrate
```

The migration command uses `DATABASE_URL_UNPOOLED` (direct connection) and does not print credentials. The application uses the pooled URL. Future changes: `npm run db:generate`, review the SQL, migrate/test the development branch first, then migrate production. Deployments do not automatically run migrations during build.

- [ ] Deploy Vercel, then verify `/` and `/privacy`, `/test` returns 404, and unsigned POSTs to `/api/v1/account/status` are rejected.
- [ ] Perform a real authorized private Blob upload and photo/voice analysis against staging. Check expired upload URLs, invalid files, unpaid access, duplicate analysis requests and quota responses. Local filesystem tests do not verify Vercel Blob's live service.

## 4. Point the iOS app at the backend

Create ignored `App/Backend.local.xcconfig` containing:

```xcconfig
AI_BACKEND_URL = https:/$()/your-project.vercel.app
```

The unusual `$()` prevents xcconfig from treating `//` as a comment. The resulting app URL is normal HTTPS. Use your staging URL for Sandbox testing and your production URL for App Store submission. Clear any Debug developer URL override before testing a remote deployment. The OpenAI key never belongs in this file or the app.

Select your team in Xcode, test on a signed physical device, then archive a Release build. Also finish the CloudKit production schema setup described in the main README.

## 5. Before public release

- [ ] Replace the publisher/contact placeholder in `backend/src/app/privacy/page.tsx` with your legal identity, support and data deletion contact. Define how support handles backend identity/purchase record deletion and device resets.
- [ ] Review privacy disclosures in App Store Connect against actual hosting/OpenAI settings. The privacy manifest declares the AI data categories linked to the anonymous account, without tracking. Selected photos/audio and estimates leave the phone; the full diary does not.
- [ ] Review the app name, homepage text, App Store listing/download link, subscription pricing and limits. Model estimates are approximate and users must review them before saving.
- [ ] Verify access to the configured OpenAI models, billing and acceptable response time using real examples. Model IDs are configurable if you change providers' model choices later.
- [ ] Set operational alerts for failed requests, database/Blob usage, OpenAI costs and failed cleanup. Do not log request bodies, media, transcripts, keys or purchase JWS values.

## Behavior and retention

The API signs a five-minute upload URL scoped to a server-generated object path, content type and declared size. Images can be up to 20 MB; the native app resizes selected images before uploading. Audio is limited to 4 MB and 65 seconds on the server (the app records at most 60). Media bytes bypass Vercel API request bodies in production. JSON API bodies are capped at 64 KB. The server checks actual bytes, digest and media decoding before OpenAI processing.

App Attest assertions bind the exact request method, path and JSON to a single-use challenge. Counters and quotas are enforced atomically in Postgres. Retry of the same completed upload returns the stored result without another OpenAI call. Attempts that begin processing count toward quotas even if they fail, to limit abuse and costs; new uploads are new attempts. An interrupted server request may remain processing until the upload expires, in which case the user must upload again.

The server requests `store: false` for identification. This does not promise zero retention by OpenAI. It attempts to delete uploaded media immediately after processing. Temporary upload/result records expire after 24 hours, and the daily cleanup normally removes them within 48 hours; outages can delay cleanup. Account/purchase/device records persist for access control, and infrastructure/database backups have separate retention policies.

## Validation performed

- TypeScript typecheck and optimized Next.js production build.
- Nine backend unit/wire tests: production bypass rejection, input bounds, media decoding, model output schema, real OpenAI SDK request formatting against a local fixture server, purchase filters.
- Seven integration tests against the isolated Neon branch: concurrent quotas, signed assertion verification/replay protection, unpaid access denial, invalid API input, upload ownership/idempotency, local upload restrictions and authenticated batch cleanup.
- Production HTTP checks: public pages available, local tester/upload disabled, unsigned API request rejected.
- Native iOS Simulator build and `ECCTests`, including AI estimate/draft mapping, editing, image preparation and URL validation.

The wire tests use deterministic local responses. Live OpenAI image and voice tests also passed on September 6, 2026; see `Documentation/Release/live-ai-smoke.json`. A private production Blob upload/read/delete check passed, including denied anonymous access. Real-device App Attest and sandbox purchases remain release checks.

## References

- [OpenAI models](https://developers.openai.com/api/docs/models) and [data controls](https://developers.openai.com/api/docs/guides/your-data)
- [Apple App Attest](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity)
- [Apple privacy data categories](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatype)
- [Apple required reason APIs](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)

## Cave Cals identity setup

The Xcode project and scheme are `CaveCals`. Display name is **Cave Cals**; deep links use `cavecals://log/…`. The app and widget share `group.com.philstarkovich.cavecals`, registered and assigned to both identifiers. The app uses the registered and assigned CloudKit container `iCloud.com.philstarkovich.cavecals`. App Attest, CloudKit, push notifications, and in-app purchases are enabled for the app.

The app icon uses the meal-scan vector on a solid green 1024×1024 background. The icon appears in App Store Connect after a build is uploaded. No build has been submitted or published. Apple currently shows an updated Developer Program agreement for the Account Holder to review and accept. Physical-device provisioning and production CloudKit schema deployment still need verification before release. Changing the bundle ID creates a separate installation with fresh local data; it does not alter the older app.

## Subscription catalog (September 6, 2026)

Only meal scanning and voice logging require a subscription. Barcode scans, food search, manual calorie entry, history, saved meals, widgets, and diary/iCloud features remain free.

Group: **Cave Cals AI**, Apple ID `22363962`. Both products have level 1 and the same AI entitlement; Family Sharing is disabled.

| Plan | Product ID | Apple subscription ID | US price | Introductory offer |
| --- | --- | --- | --- | --- |
| Monthly | `com.philstarkovich.cavecals.ai.monthly` | `6809209344` | $5.99/month beginning September 25, 2026 | 3-day free trial for eligible subscribers |
| Yearly | `com.philstarkovich.cavecals.ai.yearly` | `6809209211` | $29.99/year beginning September 25, 2026 | None |

Apple equalized prices are configured for 175 storefronts. The September 25 price decreases are scheduled in App Store Connect without preserving the former prices. The client reads localized prices and trial eligibility from StoreKit. Product IDs are configured in `APPLE_PRODUCT_IDS`. Subscription review screenshots, final review metadata, sandbox purchase testing, and Apple approval remain release requirements.

RevenueCat project: **Cave Cals**, project ID `783afc8e`. App `app7a4868ae0e`, entitlement `ai`, and default offering are configured with both Apple products. The published paywall is “Cave Cals AI — Less typing”. The app integrates RevenueCat/RevenueCatUI 5.88.0 using app-managed StoreKit 2 purchases. The backend independently verifies Apple purchases before granting AI access; RevenueCat client state never grants server access. Both production and sandbox Apple server notifications point to RevenueCat. Custom remote Schoolbell font upload is pending Chrome extension file-upload permission. See `Documentation/Release/Readiness.md` for remaining release checks.
