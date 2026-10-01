# Apple search test: build sheet

Draft, September 22, 2026. No account settings, bids, budgets, or campaigns have been changed. This makes the proposed $150 experiment concrete for later approval.

## Proposed configuration

| Setting | Draft value |
| --- | --- |
| Internal campaign name | `CaveCals_US_Search_FirstTest` |
| Placement / bidding | Search results / Manage Bids |
| Storefront / device | United States / iPhone |
| Audience | Adults 18+, all genders; inspect actual eligibility settings before launch |
| Initial structure | One small category ad group; Search Match off |
| Daily budget | $15 average, not a hard daily ceiling |
| Duration | Explicit start and end covering 10 campaign days; confirm account timezone and inclusive dates |
| Planned media envelope | $150; confirm any applicable taxes or billing charges separately |
| Landing page | Current default App Store page, with screenshots matching the released build |
| Initial status | Paused until owner approval and review of final settings |

Apple's daily budget can be exceeded on an individual day. Its documented end-date limit is the campaign's number of days multiplied by its daily budget. An undated $15 campaign can continue into future months. Lifetime budgets were retired in June 2026. The proposal therefore requires a verified end date; do not look for an old lifetime-budget setting. [Budget rules](https://ads.apple.com/app-store/help/bids-and-budget/0016-manage-budgets)

Choosing an age refinement excludes users with Personalized Ads off. That is a reach tradeoff for the adult-only proposal. Do not compensate by using private body/food information or uploading audiences. [Audience settings](https://ads.apple.com/app-store/help/ad-groups/0021-modify-audience-settings)

Manage Bids provides explicit keyword bids; Search Match is on by default in that campaign type, so turn it off for this narrowly scoped first test. Exact match can include close variants, so review the search-term report. [Search Match](https://ads.apple.com/app-store/help/campaigns/0006-understand-search-match), [match types](https://ads.apple.com/app-store/help/keywords/0059-understand-keyword-match-types)

## Candidate keywords

These are relevance hypotheses, not verified volume, competition, or cost data. Begin with the first four; add a second angle only if the first produces useful evidence.

| Keyword | Match | Reason / landing-page proof |
| --- | --- | --- |
| calorie tracker | Exact | Main daily calorie container and log |
| calorie counter | Exact | Manual calories and searchable foods |
| food diary | Exact | A clear list of logged meals |
| simple calorie counter | Exact | One home screen and Quick Add |
| macro tracker | Exact, later | Optional protein/net-carb/fat totals visible in the released build |
| voice food tracker | Exact, later | Speak Food and estimate review shown clearly |

No search volume has been fabricated. Generic “fitness,” “diet,” and “weight loss” are too broad for this small first experiment. Competitor terms and medical-condition terms are not included. Don't automatically exclude “free”: manual logging is free, while the listing should explain optional paid AI access.

If irrelevant queries appear, add narrowly chosen negatives after inspecting them. Exact negatives do not automatically cover every close variant. [Negative keywords](https://ads.apple.com/app-store/help/keywords/0060-use-negative-keywords)

## Decide the bid from a tolerable learning cost

Keep the first test framed as paid learning. Before activation, approve an initial max cost per tap using the live suggested bid and an amount you're willing to lose while learning. There is no recommended dollar bid here because we have no observed auction or conversion data. Apple describes its suggestion as guidance, not guaranteed delivery or results. [Bid controls](https://ads.apple.com/app-store/help/bids-and-budget/0062-set-and-adjust-bids)

For later scaling, use observed contribution rather than download counts:

`contribution per acquired install = net receipts per acquired install - variable service costs per acquired install`

`break-even cost per tap = contribution per acquired install × tap-to-install rate`

Net receipts should reflect App Store deductions, refunds, the chosen reporting period, and actual renewals. Service costs must include free users as well as paid users: AI estimates, search-provider/proxy usage, and other usage-based hosting. A subscription price alone is not lifetime value. If the result is unknown or negative, there is no evidence-based profitable bid yet.

## Review routine

- At launch: inspect the end date, average daily budget, storefront, Search Match state, keyword list, actual listing, and final bid. Keep a screenshot of approved settings.
- During the test: review spend, search terms, taps, and first-time downloads. Separate tap-through from view-through reporting and redownloads from new downloads.
- Pause for broken flows, misleading feature claims, or irrelevant traffic. Do not raise the budget merely because impressions are low.
- At the end: reconcile reporting windows, fill experiment-log.csv, and write one sentence about what was learned. Renewing the test requires another decision; it is not automatic.

Apple exposes separate tap-through/view-through and new-download/redownload metrics. Avoid adding overlapping totals together. [Campaign metrics](https://ads.apple.com/app-store/help/reporting/0024-view-campaigns-dashboard-metrics)
