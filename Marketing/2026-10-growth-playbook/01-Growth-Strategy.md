# Cave Cals growth strategy

Prepared September 28, 2026 for the release after 1.0.4. It builds on [the September launch packet](../2026-09-launch/README.md), which covered a first cautious test. This playbook is the "go make money" version: what the fastest-growing calorie apps actually did, which parts fit Cave Cals, and what to do each week.

Nothing here has been posted, purchased, sent, or changed in App Store Connect. The numbers below are planning assumptions until your own data replaces them.

---

## 1. What the winners did (and what to steal)

### Cal AI: $0 to about $30M a year in under two years, then acquired by MyFitnessPal

Public reporting and teardowns agree on four engines:

| Engine | What they did | Steal for Cave Cals? |
| --- | --- | --- |
| **Creators on retainer** | About 250 TikTok/Instagram creators paid a flat monthly fee for ~4 posts each. They tested a creator once, and if it worked they signed a long-term deal right away. Mid six figures a month at peak. Most spend went to *micro* creators with real audiences. | **Yes, small.** Test 5–10 micro creators at a low flat fee. Put anyone who converts on a monthly retainer. See [04-Creator-Program](04-Creator-Program.md). |
| **Many owned TikTok accounts** | About 12 accounts at once: faceless app demos, text-on-screen slideshows, and talking-head "myth-busting." TikTok ranks each video on its own, not by follower count, so more accounts means more lottery tickets. | **Yes, this is the $0 engine.** Start with 3 accounts (brand/caveman, trainer, slideshow). See [03-Video-Scripts](03-Video-Scripts.md). |
| **Long onboarding that builds a plan, then a paywall** | 32 screens: demo video, 20+ personalization questions, referral code entry, notification ask, **rating ask before the paywall**, animated "building your plan," then a paywall whose button says **"Try for $0.00."** The trial is explained in three steps ("No payment due now" → "We'll remind you before billing" → a timeline). | **Partly.** Cave Cals already has a plan builder. Add a skippable plan-reveal paywall with a trial timeline. Keep manual logging free. See [02-Paywall-and-Onboarding](02-Paywall-and-Onboarding.md). |
| **Relentless paywall testing** | 123 experiments across 46 trigger points in 10 months (about 5 a month). Trial-to-paid went up 31%, and revenue more than tripled. They never stopped testing against the current winner. | **Yes.** RevenueCat already serves the paywall remotely, so tests don't need app updates. |
| **Paid ads after organic saturated** | Once influencers plateaued around $2M/month, they scaled Meta/TikTok ads past $1M/month using the proven creator videos as ads. | **Later.** Only after organic proves which videos convert. |

Sources: [TechCrunch on the MyFitnessPal acquisition](https://techcrunch.com/2026/03/02/myfitnesspal-has-acquired-cal-ai-the-viral-calorie-app-built-by-teens/), [FunnelFox on Cal AI's influencer retainers](https://blog.funnelfox.com/cal-ai-influencer-marketing/), [Superwall's Cal AI case study](https://superwall.com/case-studies/cal-ai), [tasu 32-screen teardown](https://tasu.ai/library/cal-ai), [multi-account TikTok analysis](https://growwithplutus.com/blog/cal-ai-app-tiktok-strategy).

### Others worth copying

- **Duolingo:** a mascot with a fixed, slightly unhinged personality, posting like a creator rather than a brand. Reminders became jokes people share. Cave Cals has a ready-made character in the caveman ("You Eat. App Track. Weight Drop."), which most calorie apps can't match. [Contentgrip analysis](https://www.contentgrip.com/duolingo-viral-strategy/)
- **MacroFactor:** grew through one trusted fitness expert (Jeff Nippard / Stronger By Science) explaining *why* the app works. **Your trainer is this, at gym scale.**
- **Noom:** the quiz funnel. Personal questions make people feel the plan is theirs before they see a price.
- **MyFitnessPal:** won on its food database and SEO, then put barcode scanning behind Premium (2022). That still annoys people. **Cave Cals barcode scanning is free, which is a real comparison hook.**

### Benchmarks to plan against (RevenueCat, State of Subscription Apps 2026)

- Health & Fitness makes **68% of revenue from annual plans**, and 82% of trials start on download day. The first session is the sale.
- Onboarding paywalls with trials convert best: **~1.8% of installs pay** on average across categories.
- Median trial-to-paid is **25.5% for trials of 4 days or less** and **37.4% for 5–9 day trials**. The monthly plan's 3-day trial is on the weak end; a 7-day trial on the yearly plan is worth testing.

Sources: [RevenueCat 2026 report](https://www.revenuecat.com/state-of-subscription-apps), [RevenueCat trial length data](https://www.revenuecat.com/blog/growth/free-trial-length).

---

## 2. Positioning

### One line

**Cave Cals: the calorie tracker simple enough for a caveman.** Snap it, say it, or tap it. Most of it is free.

### The enemy

Calorie tracking is tedious, apps are cluttered, and the basics sit behind paywalls. People quit by week two. Cave Cals is the one you don't quit, because logging takes seconds and the app makes you smile.

### Why us, not them

| | Cave Cals | Cal AI | MyFitnessPal | Lose It! |
| --- | --- | --- | --- | --- |
| Manual logging & search | **Free** | Paywalled (hard paywall) | Free with ads | Free |
| Barcode scan | **Free** | Paid | Paid (Premium) | Free/limited |
| Photo & voice AI | Cave Cals+ (10 free tries) | Core paid feature | Premium | Premium |
| Account required | **No** | Yes | Yes | Yes |
| Learns your usual foods (Quick Add) | **Yes, ranked by time and habit** | Limited | Recent/frequent | Recent |
| Siri "Log food" without opening the app | **Yes** | – | – | – |
| Personality | **Caveman** | Clean/generic | Corporate | Friendly |
| Weekly recap PDF to share with a coach | **Yes** | – | – | – |

**Competitor prices (third-party reports, checked September 28, 2026; verify in each app before quoting):** Cal AI ~$29.99/year after a hard paywall (it A/B-tests other prices); MyFitnessPal Premium $79.99/year or $19.99/month, Premium+ $99.99/year; Lose It! Premium **$79.99/year, up from $39.99, with no monthly plan**. Cave Cals at $29.99/year is the cheapest paid tier in the group *and* gives away features the others charge for. That's why testing $39.99–49.99 is low-risk: it's still half of MyFitnessPal and Lose It. Sources: [eesel on Cal AI pricing](https://www.eesel.ai/blog/cal-ai-pricing), [FitBudd on MyFitnessPal](https://www.fitbudd.com/post/myfitnesspal-app-cost), [Nutrola on Lose It's increase](https://nutrola.app/en/blog/why-is-lose-it-so-expensive-now).

Check competitor columns before running any comparison ad. They change, and comparative claims must be true on the day they run. Never put competitor names in App Store keywords.

### Messaging pillars (every piece of content hits one)

1. **Caveman simple.** Log a meal in 3 seconds. Quick Add knows your usual breakfast. "Me eat. Me tap. Done."
2. **Free where it counts.** Search, barcode, manual logging, meals, weigh-ins, and progress are free. Pay only for photo and voice AI.
3. **Snap it. Say it.** Photo and voice estimates you can review. "Too lazy to type? Say it. Cave Cals listens."
4. **Real life, not a diet.** Same breakfast every day, restaurant lunches, "Done eating" at night, weekend misses. No shame, no streak-guilt.
5. **Coach-approved (via your trainer).** Protein goals, weekly recap PDF, Apple Health. The app a trainer can actually use with clients.

### Voice

Playful caveman talk on the surface, accurate underneath. Short words. Present tense. Drops articles. Never mean about bodies. Examples are in [11-Brand-Voice-Copy-Bank](11-Brand-Voice-Copy-Bank.md).

---

## 3. Who we're for (start with these, in this order)

| Persona | Pain | Hook that lands | Best channel | Feature to show |
| --- | --- | --- | --- | --- |
| **The Restarter** (25–45, tried MyFitnessPal/Lose It, quit) | "Logging was a second job." | "I quit every calorie app. Not this one." | TikTok/Reels slideshows, trainer videos | Quick Add, 3-second log, Siri |
| **The Gym Client** (clients of trainers, lifting 2–4x/week) | "My trainer says eat more protein. I have no idea how much I eat." | "My trainer made me track protein. Here's the lazy way." | **Your trainer**, gym flyers, IG | Macros, protein bar, weekly recap PDF |
| **The Routine Eater** (meal preppers, same 10 foods) | "Why am I typing 'Greek yogurt' for the 400th time?" | "Same breakfast? One tap." | TikTok demos, Pinterest | Quick Add pins, Meals |
| **The GLP-1 User** (fast-growing segment) | "I'm barely eating, and I'm told to protect muscle with protein." | "On a GLP-1? Track protein, not every crumb." | Organic content, trainer, Reddit (value-only) | Protein goals, voice log. **Organic only; see the ad rules in 07.** |
| **The Busy Parent** | "No time to weigh chicken." | "Say it while the kids scream." | Reels, Facebook | Voice Log (never show logging while driving) |

---

## 4. The money math (planning assumptions, replace with real data)

Current prices (BackendSetup.md): **$5.99/month with a 3-day trial**, **$29.99/year with no trial**.

Net after Apple (assuming the App Store Small Business Program at 15%; year one is 30% if not enrolled, so **enroll if you haven't**):

- Yearly: $29.99 → **~$25.49** per payer
- Monthly: $5.99 → **~$5.09**/month. At a typical 3–4 month life, about **~$18** per payer.
- Blended 12-month value per payer if 65% choose yearly: **≈ $23**

What that means per install:

| Install → paid | Revenue per install (12 mo) | Max you can pay per install at 1× ROAS |
| --- | --- | --- |
| 1% (freemium, weak paywall) | $0.23 | $0.23 |
| 2% (onboarding paywall + trial) | $0.46 | $0.46 |
| 4% (strong onboarding paywall, yearly trial) | $0.92 | $0.92 |
| 6% (Cal AI-grade funnel) | $1.38 | $1.38 |

US paid installs for health apps usually cost **$2–5**. **So at today's price and funnel, paid ads lose money.** Three things fix that, in order of leverage:

1. **Conversion first.** A skippable onboarding paywall with a yearly trial is the single biggest lever ([02](02-Paywall-and-Onboarding.md)).
2. **Price.** $29.99/yr is Cal AI's discounted price with none of its brand. Test **$39.99/yr with a 7-day trial** against the current $29.99 with no trial. Keep $5.99/mo or move it to $9.99 as an anchor that makes yearly look cheap.
3. **Free distribution.** Owned TikTok accounts, your trainer, gyms, and ASO cost time, not money. That's where the first 10,000 installs come from.

**Creator math:** if a creator video gets 10,000 views and 0.5% of viewers install, that's 50 installs. At 3% paying, that's 1.5 payers, about $35. Revenue per 1,000 views ≈ **$3.50**. Cal AI's rule was to earn at least 2× what you pay per 1,000 views, so **pay no more than ~$1.75 CPM until conversion improves**. That's a tight budget: favor micro creators, bonuses tied to views, and retainers only for proven converters.

---

## 5. Channel plan by budget

| Monthly budget | Where the money goes | Where the time goes |
| --- | --- | --- |
| **$0 (month 1)** | Nothing | 3 TikTok/IG accounts posting daily, trainer filming day, gym flyers, ASO, Product Hunt, build-in-public on X, Reddit value posts |
| **$300–500** | 5 micro creator tests ($50–100 each), $150 Apple Search Ads exact-match test | Same, plus creator ops |
| **$1,500–2,500** | Retain the 2–3 creators who converted; Spark Ads boosting the top 3 organic videos; Apple Search Ads on proven keywords | Weekly creative review |
| **$5,000+** | Only when revenue per 1,000 views ≥ 2× cost per 1,000 and trial-to-paid ≥ 30%. Scale retainers, then Meta Advantage+ app campaigns with proven UGC | Hire a part-time creator manager (commission on creator ROI) |

**Rule:** never increase spend on a channel until the paywall is converting. A leaky bucket gets more expensive with every dollar.

---

## 6. The seasonal calendar (the big one is January)

Diet and fitness apps get their biggest install spike of the year the first week of January. Everything in October–December is setting up for that.

| When | Moment | Play |
| --- | --- | --- |
| Oct (launch month) | New version ships | Launch sequence ([08](08-Launch-Calendar-30-Days.md)), build the content library |
| Late Oct | Halloween | "Cave Candy Count": how many calories in a fun-size bag, caveman costume skit |
| Late Nov | Thanksgiving | "Feast Mode": log the feast with voice, no guilt. "Done eating? Cave closed." |
| Black Friday – Cyber Monday | Deals | Yearly plan at 40% off via App Store promotional offer / Offer Codes for lapsed and free users. Deadline creates urgency. |
| Dec 26 – Jan 15 | **New Year** | Biggest push of the year. App Store In-App Event: "New Year Cave Hunt: 30 days of logging." Trainer 30-day challenge. Max creator posting. Heaviest Apple Search Ads budget. |
| Late Jan | Resolution quitters | "Still logging? Most quit by now. Cave people don't." Win-back offers. |
| March–May | Summer prep | "Beach cave season" (keep body-neutral) |
| September | Back to routine | "Fall back into routine" relaunch |

---

## 7. Guardrails (these protect the business, not just ethics)

- **No guaranteed results.** "Lose 10 lb in 2 weeks" gets ads rejected and invites FTC trouble. Say "track," "see," "stay consistent," and "hit your protein."
- **No before/after bodies in ads.** TikTok and Meta restrict them for weight loss. Organic trainer transformations need written consent, must be real, and need "results vary."
- **18+ only for weight-loss targeting.** TikTok requires it. Don't make content aimed at teens.
- **Paid posts must disclose** (#ad, platform "paid partnership" toggle). This includes your trainer if they get paid or free subscriptions.
- **No health data in ad pixels.** Never send weight, goals, foods, or gender to Meta/TikTok. Install and subscription events only.
- **Reviews:** asking for a rating is fine (Apple's `SKStoreReviewController`). Paying for, incentivizing, or gating reviews is not.
- **Eating-disorder safety:** avoid "earn your food," "burn off that cookie," or extremely low calorie numbers on screen. The app already refuses to auto-calculate for minors and clinician-led cases. Say so proudly.
