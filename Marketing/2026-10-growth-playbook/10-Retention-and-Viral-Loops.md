# Retention and viral loops: keep them, then let them bring friends

A subscriber who stays 2 years is worth about 2× one who stays 1. And every happy user can bring more. Calorie apps lose most users within a month, so keeping even a few more is worth more than any ad.

What Cave Cals already has for retention (and should say so in marketing): Quick Add that learns habits, learned morning log reminders, Home Screen widgets, Siri logging, Done eating, Weekly Recap, Apple Health sync, and iCloud sync. That's a strong base.

What's missing: **anything people share.** No share cards, no referrals, no milestones. Those are the proposals below. None are built.

---

## 1. Viral loops (product proposals, highest value first)

### A. "Cave Wrapped": year in review (ship by December 15)
Spotify Wrapped for food. A 9:16 shareable story sequence, generated locally from the diary:
- "You logged **247 days** this year. Cave strong."
- "Your #1 food: **Greek yogurt** (logged 183 times). Zog approves."
- "Most-logged breakfast time: **7:42 AM**"
- "Your protein best: **142 g** on March 3"
- "You tapped **Done eating** 96 times. Cave closed. 🔥"
- Final card: caveman art + "Cave Cals: me eat, app count" watermark + App Store QR

Design mock (sample numbers): [assets/concepts/cave-wrapped/](assets/concepts/cave-wrapped/).

Why it works: people post Wrapped-style cards in huge numbers every December, right before the January install spike. Every share is a free ad. **No weights shown by default** (privacy and body neutrality); make weight change opt-in.

### B. Weekly Recap share card
The PDF is great for coaches. Add a **"Share card"** option: a pretty 9:16 image with this week's average calories, protein days hit, days logged, and a caveman line ("Zog proud. 6 of 7 days."). Watermarked with the app name. **Don't include weight unless the user turns it on.**

### C. Milestones (with the rating prompt)
Zog celebrations with a `.success` haptic at 3, 7, 30, 100, and 365 days logged:
- Day 3: "Three days! Most cave people quit by now. Not you." → **rating prompt**
- Day 7: "One week. Zog make you honorary cave elder." → share card
- Day 30: "30 days. You are fire-maker now. 🔥" → share card
- Day 100: "100 days. Zog cry a little." → share card + "Give a friend a free month"

Count **days logged**, not consecutive streaks. Streak-breaking causes guilt and quitting, and Cave Cals' tone is "no shame."

### D. Give a month, get a month
See [02, Priority 4](02-Paywall-and-Onboarding.md#priority-4-referral-codes-and-offer-codes-the-trainer-channel-depends-on-this). Surface it in the milestone moments above and in Settings.

### E. "Send to my coach"
A one-tap weekly email/text of the Weekly Recap PDF to a saved contact every Sunday (a reminder notification that opens the share sheet prefilled). It keeps the trainer loop going and quietly advertises the app to every coach who receives one. The PDF footer could say "Made with Cave Cals" (small, tasteful).

---

## 2. Notification copy bank (caveman voice)

The app already sends at most one morning "Nothing logged yet" reminder (learned timing, stops after 3 idle days). Keep that restraint. These lines are alternates to rotate so it doesn't get stale, plus a few new proposed moments. **The accessibility text stays plain.**

**Morning log reminder** (the current copy is "Cave empty today. Log your breakfast?"; alternates to rotate):
- "Cave empty. Breakfast happen?"
- "Zog hungry for data. What you eat?"
- "Sun up. Fire lit. Log breakfast?"
- "Morning, cave friend. One tap to log breakfast."
- "Breakfast go in belly. Now go in app."

**Trial ending (proposed; required if the paywall promises a reminder)**
- "Heads up: your free trial ends in 2 days. Keep it or cancel anytime in Settings. No hard feelings. 🍖"

**Weekly recap ready (proposed, Sunday evening)**
- "Week done. Zog made you a recap. Look?"
- "Your week in one page. Protein days: 5 of 7."

**Scan allowance (in-app, not a push)**
- "3 free scans left. Use them wisely, cave friend."
- "Last free scan! Make it count."

**Win-back (App Store win-back offer; Apple surfaces these)**
- "Fire went out? Come back. First month on Zog."

**Never send:** weight-shaming, "you went over," late-night guilt pushes, or more than one push a day.

---

## 3. In-app moments to polish (small changes, big feel)

| Moment | Idea |
| --- | --- |
| First food ever logged | Full-screen Zog: "FIRST FOOD! Cave begin." Confetti made of tiny drumsticks |
| First Quick Add suggestion appears | Tooltip: "Zog learn your food. Tap + to log again." |
| First time over goal | A plain, kind message: "Over today. That's fine. Weekly average matters more." No red scolding. |
| Done eating, first time | "Day done. Cave closed." plus a one-time line: "Tomorrow, Zog remember what you like." |
| Empty Sunday | Friendly nudge on Home: "Weekend happens. Log what you remember. Close enough is fine." |

---

## 4. Retention metrics to watch

| Metric | Healthy target (health apps) | Where |
| --- | --- | --- |
| Day-1 return | 30%+ | App Store Connect → App Analytics → Retention |
| Day-7 return | 15%+ | Same |
| Day-30 return | 7%+ | Same |
| Trial → paid | 30%+ with a 7-day trial | RevenueCat |
| Yearly renewal | 30–40% | RevenueCat (first renewals start a year after launch) |
| Monthly churn | < 12% | RevenueCat |

App Store Connect's opt-in analytics only include users who share data with developers, so treat them as directional.
