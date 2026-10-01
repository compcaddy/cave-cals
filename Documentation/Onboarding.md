# Short onboarding and calorie plans

Implemented September 22, 2026 on `codex/onboarding-and-launch`, starting from fully pushed `35b5286`.

## Product flow

Welcome -> About you -> Starting point -> Usual day -> Goal and pace -> What do you want to track? -> Editable target -> Optional Cave Cals+ offer -> Home.

Skipping: Welcome -> **Just start tracking** -> **Skip plan?** confirmation -> What do you want to track? -> Optional Cave Cals+ offer -> Home.

- The welcome preserves Cave Cals' Schoolbell typography and “You Eat. / App Track. / Weight Drop.” headline, now with the Cave Cals logo above it instead of the app icon. A one-time intro (September 30, 2026) drops the logo in from the top, slides the lines in from alternating sides, and then raises the buttons; Reduce Motion fades instead. Once “Weight Drop.” slides in, the caveman scans his drumstick on a loop (phone up, brackets and rays, a label filling to “SCAN COMPLETE”, phone down, then a 2-second rest); Reduce Motion shows the still logo.
- **Build Plan** starts six short steps; **Just start tracking** skips the calorie-plan questions without a goal after a **Skip plan?** confirmation (“Cave Cals help pick ideal daily calorie target to reach goal. Take under one minute.”). **No, me build plan** starts the plan; **Yes, skip plan** continues to the tracking step. Both routes ask **What do you want to track?** on its own step near the end (moved off the welcome screen September 29, 2026): **Track my weight** and **Track macros**, both on by default, with no per-switch explanations. Users can turn either off before continuing or change them later in About You. In the plan route the step sits just before the target; manual-only results (minors, clinician-led, older saved No Say plans, out-of-range) also pass through it and go back through it. In the skip route it has no progress bar, its button reads **Let’s go**, and back returns to the welcome. Plan revisions from About You skip it. The welcome-screen manual-goal shortcut was removed September 26, 2026; a manual target remains on the result step when the calculator can't estimate, and in About You. There is no account, subscription, notification, tracking, camera, or Health permission prompt in onboarding.
- Gender/reference category and age inform the equation; height and current weight support metric or imperial input. **Tell About You** (formerly **Me Info**) asks **Me** with two picture cards, Man and Woman (supplied art, raw stored values unchanged); the No Say card is hidden since September 30, 2026 because the equation needs one of the two, and saved No Say plans still load and **Age** with a swipeable, free-flicking number dial defaulting to 40 (13–100) under a top-center caret. **You start** keeps imperial height honest: feet 3–7 (one digit, then focus jumps to inches), inches 0–11 (focus jumps to weight once the value can't grow; a lone 1 waits for 10/11). Weight typing is not restricted beyond the existing valid range for Continue. **Measurements** (formerly the starting-point step) keeps weights to one decimal place with a “0.0” placeholder. **Usual Week** lists activity levels without a subheader. **Set Goal** puts **Lose** / **Maintain** on the title row, shows the entered current weight (“Current: 190.0 lb”) beside the goal-weight label, and heads the pace options with **Rate**. **Your target** shows the grouped number (“2,050”); tapping anywhere on its card selects the whole number for retyping. Activity choices include work and walking, not only gym sessions.
- Lose weight supports a goal weight and three requested rates (0.25, 0.5, 0.75 kg/week; converted for pounds). Maintain weight skips deficit and goal-weight entry. We do not promise a deadline or a fixed weight-loss outcome.
- The target is editable before saving. When Track my weight is on, a calculated plan adds the initial weight only if today has no record, and never replaces an existing weigh-in. Existing Health sharing is respected; onboarding does not turn it on.
- The choices are saved on every completion route, including manual targets and no-goal setup. No-goal/manual setup enables weigh-ins without inventing a starting weight. Existing profiles enter the app normally, retaining their current tracking preferences. You -> Build/Update calorie plan offers the same flow later. Changing a plan updates the normal calorie goal while preserving historical daily goals.
- Questions are not analytics events and their answers are not sent to an AI, food provider, or advertising platform.

## Optional offer after setup (September 29, 2026)

Every first-run completion route saves the profile and tracking choices before showing `OnboardingUpgradeView`. The app fetches the existing RevenueCat offering and uses the same server-verified purchase/restore handlers as other paywall entry points. A fixed **Skip for now** button is available even during loading or a service failure. Closing, skipping, or successfully purchasing/restoring enters Home. A confirmed active member bypasses the offer. Existing profiles, plan revisions, and developer previews do not trigger it; a relaunch with a saved profile does not repeat it.

The yearly App Store subscription now offers a one-week free trial for eligible subscribers, starting September 29 in its 175 enabled territories. Its price remains unchanged (U.S. $29.99/year). Monthly retains its existing 3-day trial. The published RevenueCat introductory rule uses `Try for {{ product.offer_price_with_zero }}` (localized **Try for $0.00** with SDK 5.90.0), and shows the offer duration followed by the full renewal price. The default rule keeps **Continue** and standard pricing for ineligible customers. StoreKit determines eligibility; there is only one introductory offer per subscription group.

UI tests isolate onboarding from live App Attest/StoreKit and exercise the unavailable-offer branch, skip/close, saved choices, existing profiles, and preview isolation. A signed-device sandbox purchase remains a separate release check.

## Developer preview

Settings → Developer settings → **Preview onboarding** opens the actual new-user screens with blank answers and both tracking switches on. Each opening creates new in-memory diary and weight stores; it never replaces the live `Persistence.shared` store. Preview saves do not write food history, weigh-ins, calorie/macro settings, plan answers, widgets, iCloud, or Health data. **Close Preview** exits from any onboarding step. Completing the calculated, manual-target, or no-goal route returns to Developer settings and discards the temporary session. The entry follows the existing Developer settings availability (Debug and TestFlight).

## Research and what we chose

[Cal AI's official site](https://www.calai.app/) emphasizes quick photo, barcode, and descriptive logging. [Lazyweb's August 2026 observed onboarding capture](https://www.lazyweb.com/research/cal-ai-onboarding-personalization-before-signup) documents profile/activity/goal questions, motivational/preferences screens, integrations, an editable plan, and then signup/subscription. Its 45 frames include repeated states, not 45 different questions. It is evidence of one captured path, not conversion evidence or a promise that every current user sees the same sequence.

Cave Cals borrows the clear link between essential answers and an immediately visible editable plan. It omits discovery-source surveys, referral codes, testimonial screens, simulated plan-generation delays, signup, and upsells during the questions. A skippable offer follows completed setup as of September 29, 2026. No Cal AI assets or proprietary implementation are copied.

## Calculation and boundaries

`CaloriePlanner` is pure and local. Mifflin–St Jeor resting-energy equation:

- 10 x kg + 6.25 x cm - 5 x age, plus 5 for the male reference or minus 161 for the female reference.
- Activity multipliers: 1.2 / 1.375 / 1.55 / 1.725. These are starting heuristics, not measured energy expenditure or a claim of clinical validation.
- Requested daily deficit = selected kg/week x 7,700 / 7. This is a rough starting conversion, not a dynamic weight-loss forecast.
- Actual automatic deficit is limited to the lowest of requested deficit, 750 calories, 25% of estimated maintenance, and the distance to the intake floor.
- Intake floors: 1,200 for the female reference and 1,500 for the male reference. These are conservative software boundaries, not a guarantee of nutritional adequacy for every person.
- Round the final recommendation upward to the next 50 calories so rounding never creates an excessive deficit. Show a gentler-pace explanation when the requested rate is materially constrained.
- No automatic estimate for ages outside 18–80, unspecified/other reference values, selected clinician-led support, underweight current or target BMI (<18.5), invalid inputs, or maintenance outside the supported range. Users can still log or use a target from their clinician.
- The clinician-led option explicitly includes pregnancy, breastfeeding, eating-disorder history and medical nutrition needs. It is temporary UI state, not a stored diagnosis.
- Height support for automated estimates: 120–230 cm. Weight support: 35–300 kg. The UI accepts a wider input range so it can explain the manual route rather than forcing a different personal value.
- No inferred gender coefficient for nonbinary or undisclosed users. The short explanation names the sex-based reference limitation and retains manual setup.
- There are no automated reductions over time, exercise calorie “eat-back,” or aggressive catch-up deficits. Since September 30, 2026 (owner request) the result step shows an estimated goal date: “Based on your current weight and pace, you could weigh 80 kg by March 3rd, 2027” (date orange and underlined). It divides the weight left to lose (7,700 kcal/kg) by the typed target’s daily deficit below today’s maintenance, updates as the target is edited, and is hidden for Maintain, a target at or above maintenance, an invalid target, or a date more than three years out. It is a straight-line estimate (real loss usually slows as weight drops), so the copy says “could”, not “will”. Revisit targets based on observed progress and qualified advice.

### Primary health references

1. [Mifflin et al., 1990 original study](https://pubmed.ncbi.nlm.nih.gov/2305711/) - reference equation and its estimation basis.
2. [2013 AHA/ACC/TOS guideline](https://pmc.ncbi.nlm.nih.gov/articles/PMC5819889/) - individualized calorie reduction and common 1,200–1,500 / 1,500–1,800 ranges. The software's 25%/750 caps are additional product decisions.
3. [NIDDK Body Weight Planner](https://www.niddk.nih.gov/bwp) - adult scope, pregnancy/breastfeeding exclusions and warnings about unsuitable goals. Cave Cals does not implement or claim equivalence to NIDDK's dynamic model.
4. [CDC Steps for Losing Weight](https://www.cdc.gov/healthy-weight-growth/losing-weight/index.html) - gradual progress and realistic goals.

## Persistence and release

Saved plan inputs, selected calorie target, and creation time are an optional field in the existing protected, backup-excluded weight file. Older weight files decode without it. No SwiftData/CloudKit schema change is needed for onboarding. Only the accepted daily calorie goal follows the existing private iCloud diary path. Gender, age, height and goal weight do not join the CloudKit profile or backend database.

Unfinished answers live only in view state and are discarded when the app exits. The saved plan can be revisited in You. Apple Health export retains its existing explicit opt-in. If a file write fails the user stays in setup; the app does not pretend the plan was saved. A diary write failure also leaves setup open for retry.

The calculator's first screen offers **Clear my saved answers** when answers are saved; it removes saved inputs and the saved plan snapshot after confirmation and blanks the form. It preserves the active daily goal, weigh-ins, unit, tracking preference, and Health-sharing setting. Editing the target shows a concise supported-range message if it cannot be saved. Revising users can cancel from any step, and a manual-only result returns directly to the question that led there.

This work is a source change, not an App Store/TestFlight submission. Prior macro CloudKit release requirements still apply. The website privacy source now describes local plan/weight storage and optional Health exports; it still needs to be deployed alongside the release. App Store disclosures should be checked against this on-device processing before the next release.
