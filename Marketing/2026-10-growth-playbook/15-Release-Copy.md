# App Store copy for the upcoming release

Draft, September 28, 2026. Supersedes the description in [App-store-copy.md](../2026-09-launch/App-store-copy.md) for the next version, because the build now includes Progress, Weekly Recap PDF, Siri logging, Apple Health food sharing, Done eating, morning log reminders, Home Quick Start, haptics, and the new cream-and-orange look. **Trim anything that's already in the live version before pasting.** Nothing has been entered in App Store Connect.

Field limits (Apple): promotional text 170, description 4,000, What's New 4,000, subtitle 30, keywords 100 bytes. Lengths below were checked with a script.

---

## What's New (short version, recommended)

```
Big cave update! 🔥
• Progress: weekly averages, calorie & macro charts, weight trends
• Weekly Recap you can print or send to your coach
• "Hey Siri, log food with Cave Cals"
• Quick Start: your usual foods on Home each morning
• Done eating button: day done, cave closed
• Apple Health food sharing (optional)
• A fresh hand-drawn look, plus haptics everywhere
```

## What's New (longer version)

```
Me make app better. Here's what's new:

PROGRESS
Tap the chart icon for your week at a glance: average weight and calories, week-over-week changes, and calorie, protein, carb, and fat charts by week, month, or year.

WEEKLY RECAP
A one-page recap of your week with six-week trends. Print it or share it with your coach.

LOG WITHOUT OPENING THE APP
Say "Log food with Cave Cals" to Siri. Foods you've logged before are logged instantly.

QUICK START
New day? Your usual foods wait on Home. One tap each.

DONE EATING
Tap "Done eating for today" in the evening. Day done. Cave closed.

ALSO NEW
• Optional Apple Health sharing for calories and macros
• A gentle morning reminder if nothing's logged yet (you can turn it off)
• A new hand-drawn cave look
• Haptic taps throughout (turn off in Settings)
```

---

## Promotional text (170 max)

```
New: Progress charts, a printable Weekly Recap, and "Hey Siri, log food." Snap it, say it, or tap your usual foods once. Me eat. App count. 🍖
```

---

## Description

```
Me eat. App count.

Cave Cals is the calorie tracker so simple, a caveman uses it. Log a meal in seconds, see your day at a glance, and get on with life. No account needed.

LOG FOOD FAST
• Quick Add learns the foods you eat and when you eat them. Same breakfast? One tap.
• Search foods and restaurants, or scan a barcode. Both free.
• Type "pizza 300" and it's logged.
• Say "Log food with Cave Cals" to Siri without opening the app.
• Log from Home Screen widgets.
• Save meals and add them again in one tap.

SNAP IT OR SAY IT (CAVE CALS+)
• Meal Scan: snap your plate and get an editable calorie and macro estimate.
• Voice Log: say what you ate and review the foods before adding.
• Import a recipe from a link as a saved meal.
Try 10 photo or voice analyses free before deciding.

A PLAN THAT FITS YOU
A short, optional setup estimates a daily calorie target from your details, activity, and preferred pace. Adjust it anytime, set your own goal, or just start tracking. Track protein, carbs, and fat if you like.

SEE YOUR WEEK, NOT JUST TODAY
• Progress: weekly averages for weight and calories, with changes from last week.
• Calorie and macro charts by week, month, or year.
• Weight history with daily weigh-ins.
• Weekly Recap: a one-page summary with six-week trends to print or share with your coach.

LITTLE THINGS THAT HELP
• Done eating: close the kitchen for the night. Day done. Cave closed.
• A gentle morning reminder only if nothing's logged yet, timed to your routine.
• Optional Apple Health sharing for calories, macros, and weigh-ins.
• Private iCloud sync across your iPhones.

FREE VS CAVE CALS+
Food search, barcode scanning, manual logging, Quick Add, meals, calorie plans, macros, weigh-ins, progress, and Weekly Recap are free. Cave Cals+ adds Meal Scan, Voice Log, and recipe import, with up to 30 analyses per day and 300 per month.

Choose monthly or yearly. The monthly plan includes a 3-day free trial for eligible new subscribers. Prices are shown before purchase. Subscriptions renew automatically unless cancelled in your Apple Account settings at least 24 hours before the period ends.

GOOD TO KNOW
AI estimates can miss portions and hidden ingredients, so you review each result before saving. Calorie targets are estimates, not medical advice. Photos and recordings are sent for analysis only when you choose; your diary isn't.

Privacy: https://cavecals.vercel.app/privacy
Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/

Powered by fatsecret nutrition API (www.fatsecret.com)
```

**If you add the 7-day yearly trial** ([02](02-Paywall-and-Onboarding.md)), change the subscription paragraph to: "The yearly plan includes a 7-day free trial and the monthly plan a 3-day free trial for eligible new subscribers."

**Check before submitting:** the "Import a recipe" wording matches the shipped feature name; "up to 30 analyses per day and 300 per month" still matches the backend limits; Apple Health writes weigh-ins only when that switch is on.

---

## Reviewer notes addition

```
New in this version: Progress (chart icon on Home), a printable Weekly Recap (print icon in Progress; uses the standard iOS print/share sheet), Siri "Log food with Cave Cals" (App Intent; foods logged before are logged locally; new foods use one AI analysis and follow the same subscription rules as Voice Log), optional Apple Health food sharing (write-only; Settings → Apple Health), a "Done eating" card on Home in the evening, and an optional morning log reminder (the notification permission prompt appears only after the user has logged on 3 different days). No login is required.
```
