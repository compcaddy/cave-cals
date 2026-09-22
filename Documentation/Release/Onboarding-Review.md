# Onboarding release review

Prepared September 22, 2026. This document accompanies source work; no new archive, TestFlight upload, or App Store submission is implied.

## Owner walkthrough

1. On a fresh install, tap Build my plan. Try metric and imperial units. Use your usual activity, then a goal and pace. Review and edit the starting target.
2. Confirm the daily goal is applied and the initial weigh-in appears only if Track my weight was enabled and today was empty.
3. In You, open Update calorie plan, change an answer, then Cancel. The accepted goal should stay unchanged.
4. Try Forget plan details. Cancel once, then confirm. The active calorie goal and weight history should remain; opening the planner should ask for fresh answers.
5. On another fresh setup, use Set my own goal or Just start tracking. Confirm both reach manual logging without a subscription.
6. Try a minor age, an unspecified gender/reference option, or the clinician-led choice. These should offer manual/no-goal routes without calculating a target.

## Release work still separate

- Select a version/build only when preparing the release; keep app/widget versions aligned. Do not reuse or overwrite the dated 1.0.3 evidence as proof of this feature.
- Apply and verify the earlier additive macro CloudKit schema changes, then test sync on physical devices. Onboarding itself adds no new CloudKit field.
- Verify Health exports, corrections, and deletions on a physical device with both allowed and denied permissions. The onboarding tests do not establish Trainerize delivery.
- Deploy the updated website source with the release. Privacy describes local plan/weight storage, forgetting details, and optional Health exports. The home-page fix uses the verified App Store listing when `APP_STORE_URL` is missing or invalid; the public site still displayed “Coming to the App Store” when checked September 22.
- Review current App Store privacy answers against actual off-device flows, including existing AI media, purchase validation, and operational records. Don't label the whole app “no data collected” merely because onboarding is local.
- Use current released screenshots in advertisements. The ad concepts and store-copy drafts are not a published campaign.

## Privacy review basis

Apple says information processed only on-device is not collected for the privacy questionnaire; derived information sent off-device is considered separately. The new plan answers remain local. The accepted calorie target follows the existing private iCloud diary path, and optional Health copies remain subject to the user's Apple permissions. Existing backend/AI/purchase processing still needs its own disclosure assessment. [Apple's app-privacy details](https://developer.apple.com/app-store/app-privacy-details/)

This is an implementation inventory for review, not a claim that an App Store label has been changed or approved.
