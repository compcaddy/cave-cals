# Free photo and voice scans

Implemented September 21, 2026. The owner chose **100 regular food-log entries** after clarifying the initial 75/100 wording.

## Behavior

- Photo and voice share ten successful scans for an anonymous backend account. Scan 10 is allowed; starting scan 11 requires Cave Cals+.
- Reaching 100 regular food-log entries also ends free scan eligibility, even with scans remaining. It affects the next scan; manual logging stays free.
- Every food entry counts once, including Quick Add, barcode, manual and saved-meal components. Direct photo/voice/link AI results do not count toward regular entries. Re-logging a saved food or meal is a new regular entry.
- Failed analyses do not consume the lifetime allowance. An in-flight request holds a slot for five minutes (longer than the function timeout); an abandoned request releases it. Operational attempt/rate quotas still apply to failures to limit abuse.
- Completed-upload retries return the stored result without recounting or paywalling, including scan 10. Stored results expire after the existing 24-hour upload window.
- Active Apple-verified subscriptions bypass these introductory limits. Website/recipe import remains a subscription feature. Free access is separate from an App Store subscription trial.

## Storage and enforcement

`ai_accounts.scans_used` and `regular_log_count` persist independently of expiring upload metadata. Account row locks serialize reservations/completions across serverless instances. Processing uploads carry expiring `scan_reserved_until` reservations; completions increment usage and save the result in one transaction.

The app remembers up to 100 regular entry UUIDs in local preferences. It seeds these from existing diary entries, deduplicates edits/iCloud deliveries, and retains the count after deletion or Undo. Only the aggregate count (capped at 100) is sent with signed status/upload/analyze requests; names, calories and entry UUIDs are not sent for this check. The server retains the greatest reported count. Purchases/restores preserve the highest counters when linking an installation to a purchase owner.

This is an anonymous-install allowance, not an identity-verified per-person trial. New App Attest registration after reinstall/key loss can create a new anonymous account. Historical entries deleted before this feature existed cannot be reconstructed. The app-reported regular-entry count is not independently audited by the server; App Attest protects the signed request. No signup or diary upload was introduced.

## Rollout

Migration: `drizzle/0001_abandoned_agent_zero.sql`. It adds three columns and preserves existing rows. The Drizzle config now uses Node's `createRequire` to load Next's environment loader reliably under the migration CLI.

1. Apply the migration to the intended database with `npm run db:migrate` (development), or `NODE_ENV=production npm run db:migrate` with the production direct URL configured privately.
2. Deploy the updated backend from the repository root to the **cavecals** Vercel project.
3. Build and distribute the updated native app. A backend deploy cannot update the App Store binary's paywall gate.

The owner chose to handle Vercel deployment. No new iOS archive/upload was performed for this change.

## Verification evidence

- The additive migration was applied successfully to the isolated development database and the configured production database. Vercel redeployment remains with the owner.
- Node 22.23.2: optimized Next.js production build and all 36 backend tests passed (24 unit, 12 development-database integration). The integration suite covers successful scans 1–10 across photo/audio, denial of scan 11, completed-result retries, the exact 100-entry threshold, lower/omitted claims, paid bypass, failure refunds, concurrent final-slot reservations and abandoned-worker expiry.
- All 44 native unit tests passed on iPad Air 11-inch (M3), iOS 26, including the new count persistence/deduplication and account contract tests. In-memory screenshot/UI-test stores do not write the real local allowance ledger.
- Existing `LoggingActionRouter` actor-isolation and app/widget build-number warnings are unrelated and remain. Physical App Attest, microphone/camera, StoreKit purchase/restore and real OpenAI billing paths have not been validated by these fixture/simulator tests.
- Final focused native tests passed on iPhone 17 Pro (count persistence, free-versus-paid account contract, photo/voice capture opening) and both capture-opening UI tests passed on iPad Air 11-inch (M3) in iPhone compatibility mode. Existing capture tests were updated from stale voice-screen/button labels to the current title and stable recording accessibility identifier.


### Backend production deployment follow-up

The owner completed Fixie setup and requested verification. Deployment `dpl_31vm8WLrxiSxhoQYaY8WNGzuQQUH` is now READY on `https://cavecals.vercel.app` and includes the prepared scan-allowance backend alongside Fixie search support. The database migration had already been applied. A native build/distribution remains necessary for the updated app-side paywall gate; no iOS archive or upload was performed in this deployment.
