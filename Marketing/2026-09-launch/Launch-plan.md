# Cave Cals: first users, then repeatable growth

Prepared September 22, 2026. This is a proposal and draft asset pack. No campaigns, posts, messages, purchases, or App Store changes have been made.

## Positioning

**Calorie tracking with less fuss.** A memorable caveman personality and a short path from food to a useful daily total.

Lead with the easy job: “Log lunch. Get on with your day.” Follow with proof: manual calories, useful Quick Add, restaurant search, optional macros, and photo/voice estimates that can be reviewed. The new onboarding adds an editable starting calorie target without making the app a long coaching program.

Primary audience hypothesis: adults who have tried calorie tracking but dislike complicated setup and busy screens. Secondary hypothesis: people who repeatedly eat similar meals and appreciate Quick Add. These are hypotheses to test, not proven segments or targeting based on private health information.

Use **Cave Cals** consistently (the App Store/app brand), not “CaveCal.” Keep weight loss as a user goal, not a guaranteed outcome. Avoid “AI knows exactly what you ate,” “effortless weight loss,” before/after bodies, fixed pounds lost, or comparisons that imply the app is medically superior to competitors.

## Where I would start

| Priority | Channel | Concrete next move | Why this fits | Initial spending |
| --- | --- | --- | --- | --- |
| 1 | Owned short video | Record three 15–25 second demos: repeat breakfast, say a meal, restaurant search | Shows the product doing something real; can reuse in multiple placements | $0 media; founder time |
| 2 | App Store listing | Lead first screenshots with simple logging, then Quick Add, then optional scan/voice; show the new target only after release | Visitors need to understand the app before installing | $0 media |
| 3 | Apple Ads search results | A small exact-match discovery test for calorie-tracker intent | People are already searching for an app | Proposed $150 total cap, subject to owner approval |
| 4 | Small creators | Ask a few adult food-prep / practical fitness creators for a simple demo concept and quote | Everyday food content is a closer fit than dramatic transformations | No commitment; collect quotes first |
| 5 | Organic communities | Helpful, nonpromotional participation; only use expressly permitted app/showcase threads | Learn vocabulary and friction without spamming weight-loss communities | $0 media |
| Later | Paid Reels / TikTok / Meta | Promote the strongest demonstrated creative after organic feedback | Creative iteration is easier after one message resonates | Separate approval and budget |

Apple documents search-result placement as reaching users while searching for apps. Advanced gives keyword/placement control; Basic trades that control for automated promotion. For learning which searches fit Cave Cals, my recommendation is a small **Advanced search-results-only** experiment rather than several placements at once. This is an inference from the available controls, not a guarantee of cheap installs. Sources: [search results](https://ads.apple.com/app-store/help/ad-placements/0082-search-results), [Basic vs Advanced](https://ads.apple.com/app-store/help/apple-ads-basic/0001-compare-apple-ads-solutions).

## First paid experiment (proposal, not activated)

- US iPhone, English, adults; start only once the advertised features are in the public build.
- One search-results campaign, small groups for “calorie tracker,” “simple calorie counter,” and relevant close variants. Begin with exact matching; separately label any discovery/Search Match group. Inspect actual terms before expanding.
- Suggested learning envelope: $15 average daily budget with an explicit 10-day end date, planned media total $150. Daily spend can exceed $15. Confirm the account's date calculation and any separate billing charges before activation. See [the build sheet](Apple-search-test.md) and [Apple's budget rules](https://ads.apple.com/app-store/help/bids-and-budget/0016-manage-budgets). This is not a CPC/CPI forecast or authority to spend.
- Avoid spreading this budget over many audiences, ad groups, or creative variants. Start with the main listing and a clear first screenshot.
- Record spend, taps, downloads, product-page views, subscriptions/proceeds where available, and feedback on first use. Do not infer retention or profitability from downloads alone.
- Stop early for broken landing links, crashes, irrelevant terms, or feature mismatch. Do not repeatedly raise bids just to exhaust the budget.
- After the cap, decide whether the best signal is search intent, listing clarity, or product activation. It is acceptable for the first conclusion to be “not enough evidence.”

## A 30-day sequence

| Days | Work | Deliverable / decision |
| --- | --- | --- |
| 1–3 | Review onboarding and ad drafts; ship a verified native build; check listing claims | One approved message and live feature parity |
| 4–7 | Publish founder demos on owned channels; use separate App Store campaign links | Three clips + a simple per-link results log |
| 8–10 | Ask a small opt-in group to try setup and log a meal; note where they hesitate | Fix the largest observed activation problem |
| 11–20 | If approved, run the capped Apple search test; review terms and landing page | An actual spend/download baseline |
| 21–24 | Rewrite or replace the weakest first screenshot/hook based on observed confusion | One focused creative revision |
| 25–30 | Repeat the strongest demo; assess creator quotes and next budget | Continue, change approach, or pause |

This is a suggested order; the calendar starts after review and release, not automatically today. No timers or campaigns have been scheduled.

## Measurement without sending health data to ad platforms

Generate separate campaign links in App Store Connect for founder Instagram, founder TikTok, each creator, and each experiment. Apple supports campaign-specific reporting with privacy thresholds; missing rows are not necessarily zero activity. [Campaign links documentation](https://developer.apple.com/help/app-store-connect-analytics/acquisition/campaign-links)

Use a lightweight spreadsheet or the included CSV template. Keep platform-reported downloads separate from unique people and retain the source/date window. Ask volunteers about first-meal success directly until a deliberate product analytics design is approved. Do not send gender, age, height, weight, goal weight, calorie targets, meals, photos, voice content, or Health data as ad events, audiences, URL parameters, or pixel metadata.

Suggested product milestones to measure if analytics are later added: welcome viewed, setup completed/skipped, first food logged, return on day 2 and day 7. Use event-only booleans, no answers or food content. These events are a design proposal; no tracking SDK or event collection was added.

Apple also supports product-page optimization and custom pages. Start with a single clear listing; add a custom page only when a meaningful traffic source needs a different promise. Avoid calling a low-volume variant a winner from a handful of installs. [Product page optimization](https://developer.apple.com/help/app-store-connect/create-product-page-optimization-tests/overview-of-product-page-optimization), [custom product pages](https://developer.apple.com/app-store/custom-product-pages/).

## Creative directions in this folder

1. **Food simple. Tracking simple.** Brand introduction. Use the caveman as a memorable guide, paired with a real product demo or listing screenshot.
2. **Say it. Log it.** Voice logging. The copy explicitly calls the output an estimate and asks users to review it.
3. **Small steps. Still count.** Consistent logging and weigh-ins, without a transformation promise.

Draft images are concepts, not evidence of performance or approved platform ads. Use the original app artwork untouched. Any depicted phone is illustrative; detailed product UI should come from a real released build. The selected files in assets/ use plain text CTAs and unbranded phones. An earlier draft with hand-drawn Apple branding is in archive/ for provenance; do not publish it or treat it as an official badge.

For weight-management advertising, TikTok requires adult targeting and healthy-lifestyle framing and restricts negative body-image messaging. Eligibility varies by market and category; check the current policy when setting up the actual campaign. [TikTok's current policy](https://ads.tiktok.com/resources/help/article/tiktok-ads-policy-weight-management?lang=en)

Do not treat r/loseit as an app-acquisition channel: its moderation enforces no self-promotion. Check each community's rules before posting anywhere; offer useful discussion without product links unless the relevant thread explicitly permits them. No community posts or creator outreach have been sent.
