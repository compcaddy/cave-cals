# Where the money is made: onboarding, paywall, ratings, referrals

Every marketing dollar lands here. Cal AI's biggest lever wasn't TikTok. It was the funnel TikTok traffic landed in, improved by about five experiments a month. This file lists product changes worth considering **in the app**, most important first. None have been built. Several change current product rules in `AGENTS.md`, so each is marked **Owner decision**.

What the app does today (checked in code, September 28, 2026):

- Onboarding: welcome → about you → measurements → activity → goal/pace → editable target. **No paywall and no permission requests during setup** (a deliberate rule).
- The paywall appears when someone opens Meal Scan / Voice Log after their 10 free scans, or taps Cave Cals+ in You/Settings. It's served remotely by RevenueCat.
- Prices: $5.99/month with a 3-day trial; $29.99/year with **no trial**.
- **No App Store rating prompt anywhere** (`requestReview` isn't called).
- **No referral codes or Offer Code redemption.**

---

## Priority 1: Ask for ratings (cheap, big)

Ratings drive App Store conversion and search ranking. A new app with 3 ratings looks abandoned; one with 150 ratings at 4.8 looks safe.

**Recommendation:** call `requestReview` (StoreKit) at a happy moment, never after an error. Apple shows it at most 3 times a year per user and decides whether it actually appears.

| Trigger (pick one to start) | Why |
| --- | --- |
| **The moment the calorie count-up finishes after the 3rd day with a log** | Proven habit + dopamine moment. Best default. |
| After tapping **Done eating for today** the first time | "Day done. Cave closed." is a proud moment |
| After the Weekly Recap shows a weight drop | Only if weight tracking is on; avoid when weight went up |
| Cal AI-style: during onboarding, right after the plan reveal | Highest volume, but the user hasn't used the app yet. Test it after the in-app version. |

Optional pre-prompt screen in caveman voice (Apple allows your own screen before the system prompt, as long as you don't only forward happy people or offer rewards):

> **Cave Cals help you?**
> Rocks and stars help other cave people find app.
> [ Give stars ] [ Not now ]

Rule: never offer anything in exchange for a rating, and don't block the app on it.

**Target:** 100 ratings in the first 30 days, 500 by New Year's.

---

## Priority 2: Put a trial on the yearly plan and show it at the plan reveal

**Owner decision:** this reverses "no paywall during setup." It's the single largest revenue lever in this category (RevenueCat: onboarding paywalls with trials convert best, and 68% of Health & Fitness revenue is annual).

**Keep what makes Cave Cals different:** the paywall is **skippable**, and manual logging stays free. Cal AI blocks the whole app; Cave Cals says "Try the magic free, or keep logging by hand, free forever." That's a better story and a marketing hook in itself.

### Proposed flow (adds 2 screens to the end of onboarding)

Visual concept of the paywall screen, using test arm C prices: [assets/concepts/onboarding-paywall/paywall-concept.png](assets/concepts/onboarding-paywall/paywall-concept.png). In practice, build it as a RevenueCat paywall template so copy and prices stay remote.

1. **Plan reveal** (existing target screen), with a gentle upgrade: animate the calorie number building up (reuse the count-up), plus a line like *"Plan ready. 2,100 cals a day. Me proud of you."*
2. **New: "Want the lazy way?"** A 6-second looping demo of Meal Scan and Voice Log, with the fire lit.
3. **New: paywall** (RevenueCat, remote):
   - Headline: **Log food 3× faster. Snap it. Say it. Done.**
   - Three-step trial timeline (the Cal AI pattern that reduced fear):
     - **Today:** Unlock photo & voice logging. **$0.00 due today.**
     - **Day 5:** We send a reminder before billing.
     - **Day 7:** Trial ends. $39.99/year (just $3.33/month). Cancel anytime before.
   - Button: **Try for $0.00**
   - Secondary plan: Monthly $9.99 (or $5.99 today)
   - Skip link (always visible, not tiny): **"Me keep logging by hand (free)"**
4. **Transaction-abandon offer** (only if someone starts checkout and cancels): *"Wait! Cave people share. First year $24.99."* Superwall reports up to 17% more revenue from this. Only show it once, only to people who canceled checkout.

The "we'll remind you before billing" promise **must be real**: schedule a local notification on day 5 of the trial. The app's reminder system (`LogReminders.swift`) already handles notification permission, and an honest reminder cuts refund requests and angry reviews.

### Pricing test (RevenueCat Experiments, no app update needed)

| Arm | Yearly | Yearly trial | Monthly | Hypothesis |
| --- | --- | --- | --- | --- |
| A (control) | $29.99 | none | $5.99 + 3-day | – |
| B | $29.99 | **7-day** | $5.99 + 3-day | Trial alone lifts yearly starts |
| C | **$39.99** | 7-day | **$9.99** | Higher anchor, same take rate, more revenue per install |
| D | $49.99 | 7-day | $9.99 | Ceiling check |

Measure **revenue per install at day 35** (trial ended plus refund window), not trial starts. Run until each arm has ~50 conversions, or at least 3 weeks. Don't call a winner from 12 purchases.

App Store Connect needs a yearly introductory offer (free trial) configured before arms B–D can run.

---

## Priority 3: Better upgrade moments inside the app (no onboarding change needed)

Today the paywall mostly appears once scans run out. Add softer, well-timed nudges:

| Moment | Nudge copy | Notes |
| --- | --- | --- |
| After the **3rd manual search log in one day** | "Tired of typing? Snap it instead. 10 free tries." | Sells the trial of AI, not the subscription |
| Scan counter after each free scan | "7 free scans left" chip on Review Scan | Scarcity people can see |
| **Last free scan** | "Last free scan! Keep the magic: try Cave Cals+ free for 7 days." | The single highest-intent moment |
| Barcode not found | "Not in the database? Snap the label instead." | Converts a failure into a demo |
| Weekly Recap | "Coach-ready recap. Send it to your trainer." | Free feature, drives sharing (see referrals) |

---

## Priority 4: Referral codes and Offer Codes (the trainer channel depends on this)

Cal AI had a referral code field in onboarding. For Cave Cals it pays twice: attribution for your trainer and creators, and a reason for users to share.

### Phase 1: no code changes

- **App Store Offer Codes** (App Store Connect → Subscriptions → Offer Codes). Create **custom codes** like `CAVETRAINER`, `ZOG30`, or `[CREATOR]` with, for example, one free month or the first year at 50% off. Users redeem them at `apps.apple.com/redeem?ctx=offercodes&id=6809208501&code=CODE`, which works without an app update.
- One code per creator or trainer gives clean attribution of **paying** users, which is what matters.
- **App Store campaign links** (`?pt=…&ct=trainer_[name]`) for install attribution. See [12-Metrics](12-Metrics-and-Budget.md).

### Phase 2: small app change

- Settings / You → **"Have a code?"** row that calls `presentCodeRedemptionSheet()` (StoreKit's offer-code sheet). One line of UI.
- Optional onboarding question, Cal AI style: *"Did someone send you? Enter code."* It's also a great question for learning which channels work.

### Phase 3: give-a-month, get-a-month

- Every subscriber gets a personal link: *"Give a friend 1 free month of Cave Cals+."* When a friend subscribes, the referrer gets a free month (App Store promotional offer, signed server-side; the backend already verifies subscriptions).
- Share sheet text: *"Me use Cave Cals. Log food with a photo. Try it free: [link] 🍖"*

---

## Priority 5: Onboarding additions that lift conversion without feeling salesy

All optional; each adds personalization, the thing that made Noom and Cal AI feel "made for me."

1. **"What do you want to track?"** already exists. Keep it.
2. **"What made you quit before?"** (Too slow to log / Forgot / Hated weighing food / Apps too complicated / First time). Show a response screen: *"Too slow? Cave Cals log in 3 seconds. Watch."* This remembers the pain and sells the fix.
3. **Projected timeline graph** after the goal step: a simple curve from today's weight to the goal at the chosen pace, with the date it would reach the goal *if the pace holds*. **It must say "estimate"**, never "you will lose." Cal AI and Noom both use this, and it's the emotional peak.
4. **Commitment tap**: *"Me promise log food 7 days."* Hold-to-commit button with a haptic `.success`. The app's haptic system makes this easy.
5. **Notification ask** tied to the plan: *"Want a nudge if you forget breakfast?"*. Cave Cals already learns reminder timing. Asking at the plan moment gets more yeses than a cold prompt.

---

## Priority 6: Win-back and retention offers

| Who | When | Offer |
| --- | --- | --- |
| Cancelled trial | Day 1 after cancel | "Fire went out? Come back: first year $19.99." (App Store win-back offer) |
| Lapsed subscriber | 30 days after expiry | Win-back offer in App Store Connect (Apple shows these in the App Store, too) |
| Free user, 14+ days of logs, never trialed | Black Friday | 40% off yearly, 5 days only |
| Stopped logging 3 days | Already handled: log reminders stop after 3 days without logging, which is correct. Don't spam. | – |

---

## Priority 7 (later): web checkout for US users

Since May 2025, US App Store apps may link to a web checkout (Stripe, Paddle) with **no Apple commission** for now. Apple has proposed 15% (5% for small businesses) on linked purchases, and the Supreme Court agreed on July 2, 2026 to hear Apple's appeal, so the rules may change. [MacRumors](https://www.macrumors.com/2026/08/13/app-store-fees-apple-link-outs/), [TechCrunch](https://techcrunch.com/2026/08/14/apple-proposes-to-take-a-15-cut-of-purchases-made-outside-the-app-store/)

Why it's interesting: creator and trainer traffic could go to a **web quiz → plan → Stripe checkout → download app** funnel, the way Noom and many fitness apps work. You keep more of each sale, get better attribution than App Store campaign links, and can run discounts freely.

Why it's later: the backend grants AI access only from **Apple-verified** subscriptions, so web purchases would need a second entitlement path (RevenueCat Web Billing, or Stripe webhooks writing an entitlement the backend trusts), plus restore and cancel flows. Only worth building once monthly revenue justifies it (roughly $5k+/month), and after checking the legal status that day.

---

## Experiment backlog (run one at a time, about 5 a month once traffic allows)

| # | Test | Metric | Needs app update? |
| --- | --- | --- | --- |
| 1 | Yearly 7-day trial vs no trial | Revenue per install at day 35 | No (ASC + RevenueCat) |
| 2 | $39.99 vs $29.99 yearly | Revenue per install | No |
| 3 | Paywall headline: "3× faster" vs "Snap it. Say it." vs "Lazy cave logging" | Trial start rate | No |
| 4 | Trial timeline vs plain features list | Trial start rate | No (RevenueCat paywall template) |
| 5 | Caveman mascot on paywall vs screenshot demo | Trial start rate | No |
| 6 | Onboarding paywall on/off | Revenue per install; day-7 retention (make sure it doesn't hurt habits) | **Yes** |
| 7 | Review prompt: day-3 count-up vs Done eating | Ratings per 1,000 users | Yes |
| 8 | Free scans: 10 vs 5 vs 3 | Paid conversion vs AI-habit formation | Backend config |
| 9 | Transaction-abandon offer on/off | Revenue per paywall view | Yes |
| 10 | "What made you quit before?" question | Onboarding completion, day-7 retention | Yes |

Log every test in the [experiment log](assets/experiment-tracker.csv) with start date, arms, sample size, result, and decision.

---

## Appendix: paywall copy variants (for RevenueCat tests)

Keep prices, renewal terms, Restore, and legal links exactly as the paywall template requires. Only the marketing copy changes.

| Variant | Headline | Bullets | Button | Skip link |
| --- | --- | --- | --- | --- |
| **A: Speed** | Log food 3× faster | Snap your plate · Say what you ate · Import any recipe | Try for $0.00 | Keep logging by hand |
| **B: Caveman** | Want fire? | Zog look at food, Zog count · Zog listen, Zog log · No more typing | Light the fire (free trial) | Me keep rubbing sticks |
| **C: Lazy** | The laziest way to track | Photo in, calories out · Talk instead of type · Review before it's logged | Start free trial | Maybe later |
| **D: Coach** | Hit protein without the homework | Photo and voice logging with macros · Recipes to meals in one tap · Weekly recap for your coach (always free) | Try it free | Not now |
| **E: Honest** | Try the magic. Keep the free stuff. | Photo & voice logging · Everything else stays free · Cancel anytime in Settings | Try for $0.00 | No thanks |

Trial timeline copy (used under any headline):
- **Today:** Photo and voice logging unlocked. $0.00 due today.
- **Day 5:** We remind you before your trial ends.
- **Day 7:** Your yearly plan starts. Cancel anytime before.

(Only promise the reminder if the trial reminder notification from [14 §3](14-Product-Growth-Specs.md#3-yearly-trial-reminder-notification-required-if-the-paywall-promises-it) is built and notifications are allowed.)
