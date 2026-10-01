# Progress and Weekly Recap reports

Implemented locally September 27, 2026. Open **Progress** with the chart icon between the person and cog on Home. This feature is local source work, not evidence of a TestFlight upload.

## Page and navigation

The **Weekly Recap** comes first and defaults to the current calendar week, labeled **In progress**. It shows separate weight and calorie cards with mini weekly charts, bold prior-week changes, ranges labeled **Range:** (numbers only after the label), and coverage counts. Compact weekday labels and right-side value scales identify each chart; subtle axes and gridlines help read values. The plots leave extra space beside the metric details, with narrower calorie bars and a smooth monotone weight curve through the recorded points. Missing weigh-ins still break the line. Daily breakdown starts collapsed and resets when changing weeks. Do not display an incomplete-day count. The back arrow opens the previous week; forward navigation stops at the current week. A week’s average and range display whenever it has data, independently of whether a previous week is available for comparison.

Calories/macros and weight each have independent Week/Month/Year controls and period arrows. Week means seven calendar days, Month includes every day in that month, and Year contains weekly buckets clipped to January 1 and December 31. Week starts Monday by default; the local Week starts on preference applies to both charts, reviews, and reports. It does not change the existing Sunday–Saturday weigh-in editor.

Weight history and All weigh-ins moved from About You to Progress. Weight tracking, units, and today's weight entry remain in About You. Existing history editing and deletion use the same weight store and editor.

## Completeness and averages

- A past day with food entries is included when its calories are at least 60% of the average of previously completed days within the preceding **28 calendar days**. The day being evaluated is not part of its own reference.
- Classify chronologically. Previously incomplete days never lower a later day's reference. If no earlier completed days exist in the window, the first logged day is included as the starting reference.
- Less than the threshold means incomplete; exactly 60% is included. Missing logs are missing, never zero. Today is still in progress and excluded from completed calorie averages. Future entries are not counted.
- A day marked **Done eating for today** on Home (today only; the mark is local to the iPhone) counts as complete however low, including today, and joins later days' references. Logging more food that same day removes the mark; edits, deletes, and later backfills keep it.
- Daily charts still show logged amounts for incomplete/in-progress days with faded bars and a status label. Weekly/yearly averages and min/max exclude those days.
- Weight averages and min/max use recorded weigh-ins independently of food completeness. No missing weight is interpolated. Charts break lines across gaps.
- Show counts (for example, 5 of 7 completed days) so comparisons reveal uneven coverage. This is a logging heuristic, not a declaration that a day contains all meals or is nutritionally sufficient.
- Editing historical data recomputes results locally. No diary entries or recorded weights are changed by the calculations.

## Calorie and macro chart

Default stacks use three orange shades for protein, total carbohydrate, and fat, plus gray unknown. Approximate calorie shares use 4/4/9 calories per gram. Logged calories always determine total height. For each food, proportionally scale known shares down if their sum exceeds logged calories; otherwise unknown fills the remainder. This accommodates incomplete macros, rounding, fiber, and other energy sources without rewriting nutrition data.

The menu switches to Calories alone or Protein/Carbs/Fat in grams. Unknown macro values remain unknown. Year views average individual macro grams only over completed calorie days with known values; the detail shows the number of contributing days. Partial totals are labeled. Week totals are printed over columns; selecting a column in any period shows its value below the chart.

## Printing and sharing

The printer icon creates a **single US Letter page** titled **Weekly Recap**, with the selected week’s full weekday/month/ordinal-day dates. The top highlights average weight versus the prior week and average calories versus the current daily calorie goal (above/below/on goal; an unset goal is shown explicitly). It retains min/max and coverage. A horizontal rule separates a larger, dark **Six-Week Trends** section with two graphs and six weekly rows. Average weight/calorie columns include smaller signed changes versus the previous week, including the week before the first displayed row when recorded. The latest row stays tan. There are no calculation notes or footer text. Reports end with the selected week, including the current week. Current-week reports are labeled **In progress** and use the same available data as the recap; exporting never silently moves to the preceding week.

The PDF previews locally with Print (native AirPrint options) and Share (system PDF share sheet). Nothing is sent to a printer until the person chooses to print. A temporary, protected PDF supports sharing and is removed when the preview closes. No backend or subscription is involved.

## Verification and development

`Tests/ProgressTests.swift` covers calendar/DST boundaries, configurable week starts, the 60% boundary and chronological reference, 28-day expiration, missing/current/future data, independent weigh-ins, macro conservation and coverage, clipped weekly year buckets, prior-week comparisons, and one-page PDF output (populated and empty).

`UITests/ProgressUITests.swift` exercises navigation, chart period and macro filters, history access, week-start selection, large text, PDF preview, and native print options without submitting a job. Existing weight UI regressions verify logging/editing/deleting and refreshed graphs in their new location.

For a Debug simulator preview, launch with `--progress-preview --progress-open`. This uses synthetic in-memory diary/weight data, an in-memory Health ledger, and a separate week-start preference. `--progress-preview` alone opens Home so the new header icon can be tried. Release builds ignore this fixture flag.

Real AirPrint printer discovery, paper output, and sharing to third-party destinations require physical-device checks. See [release readiness](Release/Readiness.md) for dated simulator results.
