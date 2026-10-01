# Metrics, tracking, and what the money could look like

## Campaign links

App Store Connect → Apps → Cave Cals → Analytics → Acquisition → **Campaign links**. Each link looks like:

```
https://apps.apple.com/app/apple-store/id6809208501?pt=[PROVIDER_TOKEN]&ct=[campaign]&mt=8
```

`pt` is your provider token (shown in App Store Connect's link generator; it isn't in this repo, so none is filled in here). Make one `ct` per source, 40 characters max:

| Source | `ct` value |
| --- | --- |
| Brand TikTok bio | `tt_brand_bio` |
| Brand Instagram bio | `ig_brand_bio` |
| Trainer bio | `tt_trainer_bio` / `ig_trainer_bio` |
| Faceless account | `tt_faceless1_bio` |
| Gym flyer QR | `gym_[gymname]_flyer` |
| Each creator | `cr_[handle]` |
| Product Hunt | `producthunt` |
| Press article | `press_[outlet]` |
| Reddit | `reddit_[sub]` |
| Launch posts | `personal_launch` |

Apple only shows campaign rows above privacy thresholds, so small sources can be blank rather than zero. **Offer codes** are the more reliable way to attribute *paying* users per creator or trainer (RevenueCat shows which code a purchase used).

Use short link redirects for bios (for example, cavecals.vercel.app/tt → the campaign link) so you can change destinations without editing bios.

---

## Weekly scorecard

Fill this in every Monday. Keep a copy in [assets/weekly-scorecard.csv](assets/weekly-scorecard.csv).

| Metric | Source | This week | Last week | Target |
| --- | --- | --- | --- | --- |
| Product page views | ASC Analytics | | | ↑ |
| Page → install conversion | ASC | | | 30%+ |
| Installs (first-time downloads) | ASC | | | ↑ 20%/wk in month 1 |
| Installs by campaign link | ASC | | | – |
| Trials started | RevenueCat | | | – |
| Trial → paid | RevenueCat | | | 30%+ |
| New paid subscribers | RevenueCat | | | – |
| Revenue (net) | RevenueCat | | | – |
| Ratings (new / total / average) | ASC | | | 25/week, 4.7+ |
| Videos posted | You | | | 14+/wk |
| Total views (all accounts) | TikTok/IG | | | ↑ |
| Top video (views, saves) | TikTok/IG | | | – |
| Creator spend / attributed paid | You | | | RPM ≥ 2× CPM |
| Paid ad spend / cost per trial | Ads | | | Below target |

**Decision rule:** each Monday, pick **one** thing to double down on and **one** thing to stop.

---

## North-star metrics (in order)

1. **Revenue per install at day 35.** Combines conversion, price, and trial-to-paid. The one number that tells you whether paid acquisition can work.
2. **Weekly active loggers.** People who logged 3+ days this week. That's the habit, which drives renewals and word of mouth.
3. **Ratings count.** Drives search rank and page conversion.

---

## What the money could look like (planning scenarios, not forecasts)

Model assumptions: 65% of payers choose yearly; Apple's 15% small-business commission; monthly subscribers churn 15% a month; yearly renewals start in month 13, so they're excluded here. Real results will differ.

| Scenario | Installs / month | Install → paid | Prices | Month 1 net | Month 12 net | Year-1 net total |
| --- | --- | --- | --- | --- | --- | --- |
| **Starter** (organic only, current funnel) | 1,000 | 2% | $29.99 / $5.99 | ~$370 | ~$535 | **~$5.7k** |
| **Base** (daily content + trainer) | 5,000 | 3% | $29.99 / $5.99 | ~$2.8k | ~$4.0k | **~$43k** |
| **Base + pricing fix** (7-day trial, $39.99/yr) | 5,000 | 3.5% | $39.99 / $9.99 | ~$4.4k | ~$6.8k | **~$71k** |
| **Strong** (a few viral hits + creator retainers) | 20,000 | 4% | $39.99 / $9.99 | ~$20k | ~$31k | **~$325k** |
| **Cal AI-lite** (paid ads scaling) | 60,000 | 5% | $39.99 / $9.99 | ~$75k | ~$117k | **~$1.2M** |

**Takeaways:**
- **The pricing and trial fix is worth about +65% at the same traffic.** That makes it the highest-return work before any spending.
- Getting from Starter to Base is about *content volume*: 5,000 installs a month is roughly 1–2 videos a week reaching 100k+ views, plus steady App Store search.
- Beyond Base, it's creators and paid ads, which only work after the conversion fix.

Change the assumptions and rerun [assets/revenue_model.py](assets/revenue_model.py) (`python3 assets/revenue_model.py`). The formula is simple enough for a spreadsheet: each month, new yearly payers × net yearly price + active monthly payers × net monthly price, with monthly churn applied.

---

## Budget allocation (when there's money to spend)

| Monthly budget | Creators | Paid ads | Tools | Content production |
| --- | --- | --- | --- | --- |
| $0 | – | – | CapCut (free), Canva free | Your time + trainer |
| $500 | $300 (5 tests) | $150 Apple Search Ads | – | $50 costume/props/mic |
| $2,000 | $1,000 (3 retainers + tests) | $700 (Spark Ads + ASA) | $50 (Canva Pro, scheduler) | $250 trainer bonus/shoots |
| $5,000 | $2,500 | $2,000 | $100 | $400 |
| $10,000+ | 50% | 40% | 5% | 5%, plus a part-time creator manager on commission |

**Tools worth it:** RevenueCat (already in the app: paywall experiments, charts, integrations), CapCut (editing), Canva (slideshows), a scheduler (Later, Buffer, or Metricool; lets you batch a week in one sitting), and AppFigures or Astro for keyword ranking (~$10–30/month) once ASO matters.
