# Short onboarding and calorie plans

Implemented September 22, 2026 on `codex/onboarding-and-launch`, starting from fully pushed `35b5286`.

## Product flow

Welcome -> About you -> Starting point -> Usual day -> Goal and pace -> Editable target.

- The welcome preserves Cave Cals' supplied artwork, Schoolbell typography, and “You Eat. / App Track. / Weight Drop.” headline.
- Build my plan starts five short steps. Set my own goal and Just start tracking remain available immediately. There is no account, subscription, notification, tracking, camera, or Health permission prompt in onboarding.
- Gender/reference category and age inform the equation; height and current weight support metric or imperial input. Activity choices include work and walking, not only gym sessions.
- Lose weight supports a goal weight and three requested rates (0.25, 0.5, 0.75 kg/week; converted for pounds). Maintain weight skips deficit and goal-weight entry. We do not promise a deadline or a fixed weight-loss outcome.
- The target is editable before saving. Optional Track my weight adds the initial weight only if today has no record, and never replaces an existing weigh-in. Existing Health sharing is respected; onboarding does not turn it on.
- Existing profiles enter the app normally. You -> Build/Update calorie plan offers the same flow later. Changing a plan updates the normal calorie goal while preserving historical daily goals.
- Questions are not analytics events and their answers are not sent to an AI, food provider, or advertising platform.

## Research and what we chose

[Cal AI's official site](https://www.calai.app/) emphasizes quick photo, barcode, and descriptive logging. [Lazyweb's August 2026 observed onboarding capture](https://www.lazyweb.com/research/cal-ai-onboarding-personalization-before-signup) documents profile/activity/goal questions, motivational/preferences screens, integrations, an editable plan, and then signup/subscription. Its 45 frames include repeated states, not 45 different questions. It is evidence of one captured path, not conversion evidence or a promise that every current user sees the same sequence.

Cave Cals borrows the clear link between essential answers and an immediately visible editable plan. It omits discovery-source surveys, referral codes, testimonial screens, simulated plan-generation delays, signup and upsell. No Cal AI assets or proprietary implementation are copied.

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
- There are no automated reductions over time, exercise calorie “eat-back,” target dates, or aggressive catch-up deficits. Revisit targets based on observed progress and qualified advice.

### Primary health references

1. [Mifflin et al., 1990 original study](https://pubmed.ncbi.nlm.nih.gov/2305711/) - reference equation and its estimation basis.
2. [2013 AHA/ACC/TOS guideline](https://pmc.ncbi.nlm.nih.gov/articles/PMC5819889/) - individualized calorie reduction and common 1,200–1,500 / 1,500–1,800 ranges. The software's 25%/750 caps are additional product decisions.
3. [NIDDK Body Weight Planner](https://www.niddk.nih.gov/bwp) - adult scope, pregnancy/breastfeeding exclusions and warnings about unsuitable goals. Cave Cals does not implement or claim equivalence to NIDDK's dynamic model.
4. [CDC Steps for Losing Weight](https://www.cdc.gov/healthy-weight-growth/losing-weight/index.html) - gradual progress and realistic goals.

## Persistence and release

Saved plan inputs, selected calorie target, and creation time are an optional field in the existing protected, backup-excluded weight file. Older weight files decode without it. No SwiftData/CloudKit schema change is needed for onboarding. Only the accepted daily calorie goal follows the existing private iCloud diary path. Gender, age, height and goal weight do not join the CloudKit profile or backend database.

Unfinished answers live only in view state and are discarded when the app exits. The saved plan can be revisited in You. Apple Health export retains its existing explicit opt-in. If a file write fails the user stays in setup; the app does not pretend the plan was saved. A diary write failure also leaves setup open for retry.

You -> Forget plan details removes saved inputs and the saved plan snapshot after confirmation. It preserves the active daily goal, weigh-ins, unit, tracking preference, and Health-sharing setting. Editing the target shows a concise supported-range message if it cannot be saved. Revising users can cancel from any step, and a manual-only result returns directly to the question that led there.

This work is a source change, not an App Store/TestFlight submission. Prior macro CloudKit release requirements still apply. The website privacy source now describes local plan/weight storage and optional Health exports; it still needs to be deployed alongside the release. App Store disclosures should be checked against this on-device processing before the next release.
