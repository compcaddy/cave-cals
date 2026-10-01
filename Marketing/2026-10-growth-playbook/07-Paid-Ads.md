# Paid ads: when, where, and exactly what to run

**Rule zero:** don't scale paid ads until the funnel converts. At today's $29.99/year with no yearly trial, a paid install is worth roughly $0.25–0.50, while US health-app installs usually cost $2–5 (see [01, §4](01-Growth-Strategy.md#4-the-money-math-planning-assumptions-replace-with-real-data)). Paid ads are for **learning** now and **scaling** after the paywall work in [02](02-Paywall-and-Onboarding.md).

The capped Apple test in [the September plan](../2026-09-launch/Apple-search-test.md) is still the right first step. This file covers what comes after.

---

## Stage 1: learn (≈$300 total, weeks 2–5 after launch)

| Channel | Budget | Setup | What you learn |
| --- | --- | --- | --- |
| **Apple Search Ads, Advanced** | $150 over 10 days | Exact match: `calorie tracker`, `calorie counter`, `food tracker`, `macro tracker`, `protein tracker`, `ai calorie`, `calorie counter free`, `barcode calorie`. One separate Search Match (discovery) group at a low bid | Which searches convert; real cost per install and per trial |
| **TikTok Spark Ads** | $20/day × 5 days = $100 | Boost your **best organic video** (top 10% by saves/shares). Objective: App Installs (or Traffic to the App Store link while there's no SDK) | Whether a proven organic video can buy installs cheaply |
| **Meta (Instagram Reels)** | $50 | Boost the best Reel, Advantage+ audience, 18+ US | Baseline comparison |

**Competitor keywords on Apple Search Ads** (`cal ai`, `myfitnesspal`, `lose it`) are allowed as *bid keywords* (not in your metadata). They're often expensive with low conversion. Test at a low bid in a separate ad group only after the generic terms.

## Stage 2: scale what works (only when these are true)

- Trial-to-paid ≥ 30% and revenue per install ≥ your cost per install × 0.7 at day 35 (the rest comes from renewals)
- At least 3 creatives with a cost per trial you can afford
- RevenueCat → ad platform conversion events are connected so the platforms optimize for **trials/purchases**, not installs

Then:
- **Apple Search Ads:** raise budget on winning exact keywords by 20% every 3 days while cost per trial holds. Point groups at matching custom product pages.
- **TikTok:** Smart+ app campaigns fed 10–20 creator/organic videos. Refresh 3–5 new creatives a week; TikTok creatives fatigue in 7–14 days.
- **Meta:** Advantage+ app campaigns with the same UGC. Meta often has better trial-to-paid quality for 30+ audiences.

## Attribution without leaking health data

- Use **RevenueCat's integrations** (TikTok, Meta, Apple Search Ads attribution) to send only `trial_started`, `purchase`, and `renewal` events.
- Apple Search Ads attribution works through the AdServices framework without user tracking.
- **Never** send weight, goals, calorie targets, foods, photos, gender, or Health data to any ad platform, and never build audiences from them. That's a privacy promise in the App Store listing, and health data in ad pixels is a legal minefield (FTC Health Breach Notification Rule actions against health apps).
- Don't add an App Tracking Transparency prompt just for ads. Aggregated platform reporting is enough at this scale.

---

## Ad policy guardrails for weight-loss apps

| Platform | Rules that bite |
| --- | --- |
| **TikTok** | Weight-management ads must target **18+**; no before/after images; no negative body image; no unrealistic results; healthy-lifestyle framing. [Policy](https://ads.tiktok.com/resources/help/article/tiktok-ads-policy-weight-management?lang=en) |
| **Meta** | Weight-loss ads must target 18+; no before/after; no **"personal attributes"** copy ("Are you overweight?" or "You need to lose weight" gets rejected; "Track your meals" is fine); no zoomed-in body parts |
| **Apple Search Ads** | Ads use your product page; metadata must be accurate |
| **Everywhere** | No prescription drug names (Ozempic, Wegovy, Zepbound) in ads; keep GLP-1 content organic only. No "guaranteed," "lose X lb in Y days," or "doctor recommended" without substantiation |

---

## 20 ad scripts and copy variants

Each is a 15–25s vertical video built from the [03 library](03-Video-Scripts.md) footage. Primary text is for Meta; TikTok uses the first line as the caption.

### Angle 1: Speed / laziness (broadest)
1. **Hook:** "Logging my whole day took 20 seconds." · **Text:** Calorie tracking for people who hate calorie tracking. One-tap Quick Add learns your usual foods. · **CTA:** Download free
2. **Hook:** "Type 'pizza 300.' Done." · **Text:** No menus, no serving math. Just the calories. Cave Cals is free on iPhone.
3. **Hook:** "This app learned my breakfast." · **Text:** Cave Cals remembers the foods you actually eat, so the next log is one tap.

### Angle 2: AI magic (Cal AI's angle; show the review step)
4. **Hook:** "Snap. Done." · **Text:** Snap your plate for a calorie and macro estimate. Review it, tweak it, log it. Try 10 free scans.
5. **Hook:** "I told my phone what I ate." · **Text:** Voice Log turns "two eggs and toast" into a food log. Review and tap Add.
6. **Hook:** "Hey Siri, log food." · **Text:** Log without even opening the app.

### Angle 3: Free where it counts (vs paywalled competitors, without naming them)
7. **Hook:** "Why are you paying to scan a barcode?" · **Text:** Barcode scanning, food search, and manual logging are free in Cave Cals.
8. **Hook:** "No account. No ads. No barcode paywall." · **Text:** A calorie tracker that just lets you track. (Check the no-ads claim stays true.)
9. **Hook:** "Free calorie tracker that doesn't hide the basics." · **Text:** Upgrade only if you want photo and voice logging.

### Angle 4: Caveman personality (stand out in the feed)
10. **Hook:** Zog: "Me eat. App count." · **Text:** Calorie tracking, caveman simple. 🍖
11. **Hook:** Zog squinting at a mammoth leg's calories · **Text:** Cave man discover portion size. You can too.
12. **Hook:** "Day done. Cave closed." · **Text:** Tap Done eating and close the kitchen for the night. Tiny ritual, big difference.

### Angle 5: Trainer authority
13. **Hook:** "Personal trainer here: tracking is the difference." · **Text:** The app my clients actually keep using. Protein goals, weekly recaps, one-tap logging.
14. **Hook:** "Stop guessing your protein." · **Text:** Set a protein goal and watch one bar. That's it.
15. **Hook:** "Look at your week, not your scale." · **Text:** Weekly averages and a one-page recap you can send your coach.

### Angle 6: Restart / quitters
16. **Hook:** "I quit calorie tracking 4 times." · **Text:** The 5th time I used an app that doesn't feel like homework.
17. **Hook:** "Starting over Monday? Start tonight." · **Text:** One-minute setup. No signup.
18. **Hook:** "You don't need willpower. You need less typing."

### Angle 6b: Price refugees (organic first; check claims the day you post)
- **Hook:** "My calorie app doubled its price. So I switched." · **Text:** Cave Cals: search, barcode, and logging free. Photo and voice for less than half what the big apps charge. (Don't name the competitor in paid ads; organic posts can, if the price is verified that day.)
- **Hook:** "$80 a year to count calories? No." · **Text:** The basics should be free. In Cave Cals, they are.

### Angle 7: Seasonal
19. **Thanksgiving:** "Log the feast. Enjoy the feast." · **Text:** Say what you ate. Cave Cals does the math.
20. **New Year:** "30-Day Cave Challenge." · **Text:** Log 5 days a week for 30 days. That's the whole challenge.

---

Ready-made static versions of angles 1–5 (speed, AI, free basics, caveman, protein) are in [assets/ads/](assets/ads/) at 1080×1350. Static images are cheap to test on Meta next to the videos.

## Creative testing framework (3 × 3)

Each week, test **3 hooks × 3 bodies** from the footage library (9 ads), $10/day each for 3 days. Keep the winner's body and try 3 new hooks the next week. The first 2 seconds decide ~80% of performance, so test hooks the most.

**Kill rules** (after about $30 spend per ad):
- Thumb-stop rate (3-second views ÷ impressions) under 25% → kill
- Click-through under 0.6% → kill
- Cost per trial more than 2× target → kill

**Scale rule:** under target cost per trial for 3 days → raise budget 20% and make 3 variants of the hook.

---

## Budget ladder

| Month | Monthly paid budget | Gate to move up |
| --- | --- | --- |
| 1 (launch) | $0–150 | Apple test only |
| 2 | $300 | Paywall trial live; 100+ ratings |
| 3 | $1,000 | Revenue per install ≥ 70% of cost per install at day 35 |
| 4+ | +50%/month | Payback within 6 months on yearly cohort |
| Dec 26 – Jan 31 | **2–3× normal** | January installs are cheaper and higher-intent. Pre-build 30 creatives in December. |
