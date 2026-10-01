# Product growth specs: ready for a coding session

Short implementation specs for the in-app changes the marketing plan depends on, in priority order. **None are built.** Each follows the project rules in `AGENTS.md` (haptics on every new control, `--uitesting` guards, accessibility identifiers, update AGENTS.md when a UI decision changes). File references were checked on September 28, 2026.

Items marked **Owner decision** change a current product rule, so confirm before building.

---

## 1. App Store rating prompt (highest value, smallest change)

**Behavior**
- Ask via StoreKit's `requestReview` (SwiftUI `@Environment(\.requestReview)`). Apple decides whether it appears and caps it at 3 times a year.
- Trigger: the moment the Home calorie count-up **finishes** after an add, when all of these are true:
  - the person has logged on **3 or more different days** (same-day logs, the rule `LogReminders` already uses for its permission prompt)
  - at least **120 days** since the last ask (store the date locally)
  - no sheet is open; Home is visible; not `--uitesting` / `--screenshots`
- Alternative trigger to A/B later: first tap on **Done eating for today** (`finishDay`, `App/MainView.swift` around line 853).
- No custom pre-prompt screen in version 1. If you add one later, both answers must lead somewhere neutral (never route only happy people to the store).

**Where**
- Count-up completion: `SummaryFigures` / the count-up view in `App/MacroViews.swift` (~line 262–290). The "firm bump when the final number lands" haptic is the natural hook point.
- New small helper `App/ReviewPrompt.swift` with a testable `ReviewPromptPolicy` (days logged, last-ask date) → `shouldAsk(now:)`. Local key `reviewPromptLastAsked.v1`.

**Tests**: unit-test the policy (under 3 days, 3 days, within 120 days, UI-test flag). No UI test can see the system prompt.

**AGENTS.md**: add a bullet under UI decisions describing the trigger.

---

## 2. "Redeem a code" (Offer Codes) in Settings and About You

**Behavior**
- A row **Redeem a code** in the Cave Cals+ section (Settings and About You both show `AISubscriptionSection`, `App/MealsAndSettings.swift` lines ~91 and ~126).
- Opens Apple's offer-code sheet with StoreKit's `.offerCodeRedemption(isPresented:onCompletion:)` modifier. On completion, refresh subscription status the same way a purchase does (`App/AISubscriptions.swift`).
- Identifier `redeemOfferCode`. Haptic: `.tap` via `HapticButtonStyle` (inside a `HapticForm`/`HapticList`, per the haptics rules).

**Check before shipping**: an offer-code subscription is a normal App Store transaction with an offer type. Confirm the backend's Apple verification (server-verified paid AI access) accepts it the same as a regular purchase, with a sandbox offer code.

**Why**: makes trainer/creator codes redeemable inside the app instead of only via the redeem URL.

---

## 3. Yearly trial reminder notification (required if the paywall promises it)

**Behavior**
- When a yearly **free trial** starts, schedule one local notification **2 days before** it ends: "Heads up: your free trial ends in 2 days. Keep it or cancel anytime in Settings." Tap opens Settings → Cave Cals+.
- Cancel it if the subscription becomes paid-state or is cancelled (check on foreground).
- Reuse the notification authorization flow in `App/LogReminders.swift`; if notifications are denied, the paywall must not promise a reminder (show the timeline without "we'll remind you").

---

## 4. Onboarding plan-reveal paywall (**Owner decision**: reverses "no paywall during setup")

**Behavior**
- After the target step's **Let's go** (`App/OnboardingView.swift`, step 5, button text at ~line 252; `save()` at ~line 331), show one screen: a 6-second looping Meal Scan/Voice Log demo with "Want the lazy way?", then the RevenueCat paywall using a dedicated **`onboarding` offering** (so price/trial/copy tests run remotely).
- **Always skippable**, with a visible "Me keep logging by hand (free)" link. Skipping lands on Home exactly as today.
- Never shown to: existing users revisiting the plan (`isRevising`), Developer → Preview onboarding, `--uitesting`, or anyone already subscribed.
- Reuse `AIUpgradePaywall` (`App/AISubscriptions.swift` ~line 126), which already wraps RevenueCatUI's `PaywallView` with Schoolbell fonts.
- No permission prompts on this screen.

**Measure**: RevenueCat initial conversion by offering; day-7 logging retention for people who saw it vs. skipped (to be sure it doesn't hurt the habit).

**AGENTS.md**: replace "no paywall or permission requests during setup" with the new rule.

---

## 5. "Did someone send you?" code step (optional, pairs with #2 and #4)

- One optional onboarding question after the welcome: **"Got a code from a coach or friend?"** [Enter code] / [No code]. Enter opens the offer-code sheet (#2).
- Also a cheap attribution signal: store only a local boolean "entered a code" for your own analytics; never send it to ad platforms.

---

## 6. Scan-allowance nudges

- **Review Scan chip** after each free scan: "7 free scans left" (plain text, accessibility label plain). Uses the existing allowance state from `account/status` (see `Documentation/ScanAccess.md`).
- **Last free scan** message: "Last free scan! Keep the magic: try Cave Cals+." with a button to the paywall.
- **Barcode not found** → a secondary action "Snap the label instead" that opens Meal Scan.

---

## 7. Milestones and share cards

- Count **days logged** (not streaks). At 3, 7, 30, 100, and 365 days, show a one-time Zog card on Home with a `.success` haptic: "One week. Zog make you honorary cave elder."
- 7+ days: a **Share** button that renders a 1080×1920 card with SwiftUI `ImageRenderer` (days logged, protein days hit, a caveman line, small app name) and presents `ShareLink`. **Weight is off by default** on share cards.
- Local keys: `milestonesShown.v1`.

---

## 8. Cave Wrapped (target: ships by December 15)

- A December-only Progress entry: **Your year in the cave**. Five swipeable 9:16 cards computed locally: days logged, #1 food, usual breakfast time, best protein day, Done eating count. Last card has the app name and App Store QR.
- Each card shareable (same renderer as #7). No network calls; nothing leaves the phone unless the person shares an image.
- Needs a minimum of ~30 logged days to show, or it's a sad Wrapped.

---

## 9. Screenshot fixture with macros (for marketing captures)

- The `--screenshots` sample entries in `App/CaveCalsApp.swift` (~line 52–65) have calories only, so the Home hero shows "—" for protein/carbs/fat. Add realistic protein/carb/fat grams to those `EntryDraft`s so App Store captures show the macro row filled in. DEBUG + simulator only; no user-facing change.
- Also add a launch argument that opens add mode **with the keyboard dismissed** for a clean Quick Add capture.

---

## Suggested build order

1 (rating) → 9 (screenshots fixture) → 2 (redeem code) → 3 (trial reminder) → 4 (onboarding paywall, if approved) → 6 → 7 → 8 (by mid-December) → 5.
