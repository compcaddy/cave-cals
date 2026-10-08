# Progress and Weekly Recap reports

Implemented locally September 27, 2026. Open **Progress** with the chart icon between the person and cog on Home. This feature is local source work, not evidence of a TestFlight upload.

## Page and navigation

The **Weekly Recap** comes first and defaults to the current calendar week, labeled **In progress**. It shows separate weight and calorie cards with mini weekly charts, bold prior-week changes, ranges labeled **Range:** (numbers only after the label), and coverage counts. Compact weekday labels and right-side value scales identify each chart; subtle axes and gridlines help read values. The plots leave extra space beside the metric details, with narrower calorie bars and a smooth monotone weight curve through the recorded points. Missing weigh-ins still break the line. Daily breakdown starts collapsed and resets when changing weeks. Do not display an incomplete-day count. The back arrow opens the previous week; forward navigation stops at the current week. A week’s average and range display whenever it has data, independently of whether a previous week is available for comparison.

Calories/macros and weight each have independent Week/Month/Year controls and period arrows. Week means seven calendar days, Month includes every day in that month, and Year contains weekly buckets clipped to January 1 and December 31. Week starts Monday by default; the local **Weekday Start** row at the bottom of the page (label on the left, the day on the right; October 6, 2026) applies to both charts, reviews, reports, and the progress-photo week strip. It does not change the existing Sunday–Saturday weigh-in editor. The “How averages work” explainer under it is hidden for now; its text stays in `ProgressScreen.averagesExplanation` for when it returns.

Weight history and All weigh-ins moved from About You to Progress. Weight tracking, units, and today's weight entry remain in About You. Existing history editing and deletion use the same weight store and editor.

## Progress Photos

Added locally October 6, 2026, below Weight history.

- **Card:** the latest photo day's thumbnails (tap to open that day), **Take Photo** and **From Library** for today, **All photos**, and **Compare** once any angle has two photos. With no photos it says “No cave paintings yet.”
- **All photos:** a week strip like the weigh-in editor's (following the Weekday Start; each day shows its photo count; future days are disabled), the selected day's photos in a grid with that day's weigh-in, Take Photo / From Library for the selected day, and a **Photo days** list to jump to any day. A footnote says photos stay on this iPhone, are never uploaded, and are included in the iPhone backup.
- **Angles:** Front, Back, Left Side, Right Side, and **Other…** for a typed label (up to 24 characters). Labels match regardless of case, typed labels are offered again once used, and a day's photos sort in that order.
- **Camera:** full screen with angle pills (checked once taken that day), a 3:4 viewfinder, and the fixed red Cancel. The **Ghost** overlays the latest photo at the selected angle, preferring one from the same camera, with an opacity slider (0–80%, 35% to start). The **10-second timer** (on to start) shows a large countdown with a tick each second (system sounds follow the ringer switch); tapping the shutter again stops it. Front-camera photos are saved mirrored, exactly as previewed, so a front-camera ghost lines up. After a shot: Retake or **Use Photo**. Cave Cals+ members stay in the camera, moved on to the next angle not yet taken that day, and finish with **Done**; otherwise the camera closes after the day's photo. Timer, ghost opacity, and camera choice are remembered on this iPhone.
- **Library:** opens **Add Photo** with the picture, angle chips, and the day, preset to when the photo was taken (from its metadata) or else the selected day.
- **Viewing:** swipe through a day's photos; Edit changes the angle or day, Share hands over the saved JPEG, and Delete removes it from the iPhone after confirmation.
- **Compare:** angle chips, **Side by Side** or **Slider** (drag the divider; VoiceOver adjusts it in 10% steps), Before and After strips (oldest and newest to start), and a line such as “8 weeks apart · ↓ 2.6 lb” using the weigh-in that day or the closest within three days (shown with ≈ when not the same day). The share button renders both photos with their dates and that line.
- **Free limit:** one photo a day is free. A second photo on a day (camera, library, or moving a photo onto a day that has one) shows the Cave Cals+ paywall (trigger `progressPhotos`); joining continues to the camera. Membership comes from the backend, falling back to StoreKit's on-device entitlement offline; only a membership is remembered (for 10 minutes). Photos already saved stay viewable, comparable, and deletable whatever the membership.
- **Storage and privacy:** `Application Support/ProgressPhotos/` holds `photos-v1.json` and, per photo, a 2048-px JPEG and a 480-px thumbnail. Photos are re-encoded, so no location or other metadata is kept. Images use complete file protection and the index is protected until first unlock. Nothing is uploaded or synced. Unlike weigh-ins, the folder is included in iPhone backups so a new iPhone restored from backup keeps the photos. An unreadable index is never overwritten, and images left behind by an interrupted save are removed when the index loads.

## Completeness and averages

- Since October 8, 2026 (owner request), a past day with food entries is included when its calories are at least **70% of that day's calorie goal** (a 2,000 goal needs 1,400). Until then it was 60% of the reference below.
- A day without a goal uses the earlier reference: 70% of the average of previously completed days within the preceding **28 calendar days**, classified chronologically (previously incomplete days never lower a later day's reference; with no earlier completed days, the first logged day is included). The day being evaluated is not part of its own reference.
- Less than the threshold means incomplete; exactly 70% is included. Missing logs are missing, never zero. Today is still in progress and excluded from completed calorie averages. Future entries are not counted.
- A day marked **Done eating for today** on Home (today only; the mark is local to the iPhone) counts as complete however low, including today, and joins later days' references. Logging more food that same day removes the mark; edits, deletes, and later backfills keep it.
- Daily charts still show logged amounts for incomplete/in-progress days with faded bars and a status label. Weekly/yearly averages and min/max exclude those days.
- Weight averages and min/max use recorded weigh-ins independently of food completeness. No missing weight is interpolated. Charts break lines across gaps.
- Show counts (for example, 5 of 7 completed days) so comparisons reveal uneven coverage. This is a logging heuristic, not a declaration that a day contains all meals or is nutritionally sufficient.
- Editing historical data recomputes results locally. No diary entries or recorded weights are changed by the calculations.

## Calorie and macro chart

Default stacks use three orange shades for protein, total carbohydrate, and fat, plus gray unknown. Approximate calorie shares use 4/4/9 calories per gram. Logged calories always determine total height. For each food, proportionally scale known shares down if their sum exceeds logged calories; otherwise unknown fills the remainder. This accommodates incomplete macros, rounding, fiber, and other energy sources without rewriting nutrition data.

The menu switches to Calories alone or Protein/Carbs/Fat in grams. Unknown macro values remain unknown. Year views average individual macro grams only over completed calorie days with known values; the detail shows the number of contributing days. Partial totals are labeled. Week totals are printed over columns; selecting a column in any period shows its value below the chart.

## Printing and sharing

The printer icon creates a **single US Letter page** titled **Weekly Recap**, with the selected week’s full weekday/month/ordinal-day dates. The top highlights average weight versus the prior week and average calories versus the current daily calorie goal (above/below/on goal; an unset goal is shown explicitly). The goal itself follows in parentheses (“↓ 85 cals below goal (2,100)”). It retains min/max and coverage, then shows the week’s days as two small charts labeled with each date: a smooth weight curve that breaks at missing weigh-ins, and calorie bars (faded for incomplete or in-progress days). A horizontal rule separates a larger, dark **Five-Week Trends** section, its date range right-aligned on the title line, with two graphs and five weekly rows. Average weight/calorie columns include smaller signed changes versus the previous week, including the week before the first displayed row when recorded. The latest row stays tan. There are no calculation notes or footer text. Reports end with the selected week, including the current week. Current-week reports are labeled **In progress** and use the same available data as the recap; exporting never silently moves to the preceding week.

The PDF previews locally with Print (native AirPrint options) and Share (system PDF share sheet). Nothing is sent to a printer until the person chooses to print. A temporary, protected PDF supports sharing and is removed when the preview closes. No backend or subscription is involved.

## Verification and development

`Tests/ProgressTests.swift` covers calendar/DST boundaries, configurable week starts, the 70% boundaries (of the goal, and of the reference without one) and chronological reference, 28-day expiration, missing/current/future data, independent weigh-ins, macro conservation and coverage, clipped weekly year buckets, prior-week comparisons, and one-page PDF output (populated and empty).

`Tests/ProgressPhotoTests.swift` covers angle labels, ordering and the next-angle step, the one-a-day rule, nearby weigh-ins and comparison wording, resizing and metadata removal, capture dates, saving/reloading/editing/deleting with files, backup inclusion, ghost choice, an unreadable index, and stray-file cleanup.

`UITests/ProgressUITests.swift` exercises navigation, chart period and macro filters, history access, the Weekday Start row, large text, PDF preview, and native print options without submitting a job. `testProgressPhotosCameraTimerGhostCompareAndEdit` and `testSecondPhotoOfADayAsksForCaveCalsPlusWhenFree` cover the simulator camera stand-in, timer, ghost, staying in the camera for members, Compare, the viewer, editing an angle, and the free limit (DEBUG `--photos-free`). Existing weight UI regressions verify logging/editing/deleting and refreshed graphs in their new location.

For a Debug simulator preview, launch with `--progress-preview --progress-open`. This uses synthetic in-memory diary/weight data, eight weeks of in-memory sample progress photos (stand-in figures), an in-memory Health ledger, and separate week-start and camera preferences. `--progress-preview` alone opens Home so the new header icon can be tried. Release builds ignore this fixture flag.

Real AirPrint printer discovery, paper output, and sharing to third-party destinations require physical-device checks, as do the real camera (front/back, mirroring, the timer's sounds), the RevenueCat paywall for a second photo, and restoring photos from an iPhone backup. See [release readiness](Release/Readiness.md) for dated simulator results.

## Trends

Below Weekday Start, **Trends** has one range toggle (Last 30 days, Last 90 days, All time; each ends yesterday, since today is in progress) for two charts:

- **By day of the week**: the average calories of complete days falling on each weekday, in the Progress week-start order. Complete days follow the same rule as every Progress average (at least 70% of that day's goal; days marked done eating always count).
- **By time of day**: 24 hourly columns. **Calories** shows the average calories eaten in that hour per counted day (the columns add up to a typical day); **% of day** shows the hour's share of all counted calories (they add up to 100%). Only food logged on the day it belongs to counts: food added on a later day carries the clock time it was entered, not when it was eaten. A day counts here when at least one of its foods was logged that day.

Tapping a bar shows its value; each chart's caption gives the number of days it's based on. The calculation is `ProgressTrends` in `App/ProgressData.swift`.

## On-Target vs. Over Days

The last card on Progress (named "Good Days vs. Over Days" until October 8, 2026) compares **on-target days** with **over days**, over its own range toggle (Last 30 days, Last 90 days, All time; 90 by default). Days without a goal aren't compared, and comparisons need at least 3 of each.

What counts as on target is the person's choice (**Change** under the title opens three options, the numbers editable in place, orange and underlined): **At or under my goal** (default), **Within 5% of my goal** (either way; any percentage from 1 to 50), or **Up to 100 over is fine** (10 to 2,000 calories). Within a percentage, complete days below the range aren't compared, only counted. The choice is synced with the other Progress settings. `HabitInsights` in `App/ProgressHabits.swift` does the work on the iPhone:

- **Summary**: good and over day counts with average calories, and the current streak of good days ending yesterday.
- **What's different**: plain-language findings, strongest first, each shown only past a real gap: when eating starts and ends (30+ minutes apart), the eating window (1+ hour), the part of the day where over days' extra calories land (150+), a bigger morning on good days (100+ before 11 AM), protein share of calories higher on good days (3+ points) or fat/carb share higher on over days (4+), more foods logged on over days (1.5+), the food that leans most to each side, and the weekday that goes over most (60%+ of at least 3 days).
- **Calories by time of day**: average calories per day before 11 AM, 11 AM–4 PM, 4–8 PM, and after 8 PM, good vs over.
- **A typical day**: median first and last food, eating window, foods logged, and average macros.
- **Foods**: foods on at least 3 compared days that are 15+ points more common on one side.

Times and time-of-day calories use only food logged on the day it belongs to (backfilled food carries the time it was entered). A macro counts for a day only when every food that day has it.

**Cave Coach** (Cave Cals+) sends the comparison, never diary entries, to the backend's `insights/coach`, which asks the AI for exactly 3 tips for healthier eating habits (each an action title plus one or two sentences), turning the patterns into actions instead of restating them. The app introduces them with “Based on your last 30 days, here are 3 tips…”. **Get new tips** replaces them, sending the shown tips along so the new ones differ. Its instructions treat food names as data, forbid shaming, skipping meals, fasting, extreme restriction, exercise compensation, and medical advice, and ask it to call patterns early when there are few days. Up to 3 write-ups a day (`COACH_DAILY_LIMIT`). The last write-up is kept on the iPhone.

## Synced settings

Since October 8, 2026, Progress settings live on the profile (`UserProfile.progressSettingsData`, a `ProgressSettings` JSON), so they sync over iCloud with the diary to every iPhone and iPad on the account: the week start, the on-target rule, and the Trends and On-Target vs. Over Days ranges. Until something changes, an iPhone keeps showing the week start it stored locally before (`progressWeekStart.v1`). Progress photos and their camera settings stay on each iPhone by design. The new CloudKit field must be deployed to production before release, with the meal-type fields (see [Meal types](MealTypes.md)).

