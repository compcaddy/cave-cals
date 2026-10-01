# App Store optimization (ASO)

The App Store is the free channel you control completely. Every video, creator, and flyer sends people to one product page. If it doesn't convert, everything else costs more.

Existing drafts: [App-store-copy.md](../2026-09-launch/App-store-copy.md) (description, What's New, reviewer notes). This file adds the conversion and search playbook on top. **Nothing has been changed in App Store Connect.**

---

## 1. Urgent: the screenshots still show the old blue theme

The live screenshots (`Screenshots/2026-09-17-v2/store/`) show the September 17 blue UI. The app is now cream-and-burnt-orange with Schoolbell handwriting and cave doodles, which is far more distinctive. **A visitor who installs from a blue screenshot and opens an orange app feels misled, and a distinctive look is a reason to stop scrolling.** Replace them with the new build.

New screenshot draft set: [assets/app-store-screenshots/](assets/app-store-screenshots/). These are made from real captures of the current build. Check them against the final release build, and re-capture if anything changed.

### Screenshot story (the first 3 do 90% of the work, because most people never scroll)

| # | Headline (caveman voice, big) | Subline | Screen (rendered in `assets/app-store-screenshots/store/`) |
| --- | --- | --- | --- |
| 1 | **Me eat. App count.** | Calorie tracking, caveman simple. | Home with macros filled in, plus the caveman art |
| 2 | **Your usual foods. One tap.** | Quick Add learns what you eat. | Quick Add list |
| 3 | **Snap it. Done.** | Photo to calories & macros. Review, then log. | Meal Scan with a plate photo |
| 4 | **Say it. Done.** | Tell it what you ate. Review, then log. | Voice Log ("You Talk App Listen.") |
| 5 | **Type it. Done.** | "pizza 300" logs in one tap. | Search with the one-tap `Add "pizza" · 300 calories` row |
| 6 | **A plan in one minute.** | Pick what to track. Get a starting target. | Setup welcome ("You Eat. App Track. Weight Drop.") |
| 7 | **See your week.** | Calories, protein, carbs, fat & weight. | Progress protein chart + weight history |
| 8 | **Day done. Cave closed.** | Tap Done eating. Kitchen closed for the night. | Home after Done eating |
| 9 | **One-page recap.** | Print it or send it to your coach. | Weekly Recap PDF preview |

Not yet captured (need a device): Barcode Scan ("Barcode scan. Free."), "Hey Siri, log food," and the widget.

Rules: headline ≤ 5 words, readable at thumbnail size. Show the real UI large. Screenshot 1 carries the caveman art so the brand is instantly different from the 40 other "Cals" apps. No fake ratings, awards, or weight-loss claims.

### App preview video (15–30s, autoplays muted in search results)
Autoplaying previews are a big conversion lever in search results. The first 3 seconds must work **with no sound**.

1. 0–2s: big text "Me eat. App count." over the caveman art → cut to the Home screen
2. 2–7s: Quick Add: tap, tap, tap; the count-up animation rolls
3. 7–13s: Meal Scan: photo → Review Scan → Add All
4. 13–18s: search `pizza 300` → one-tap add
5. 18–23s: Progress / Weekly Recap
6. 23–25s: end card with the caveman and "Cave Cals"

Record with the simulator (`xcrun simctl io booted recordVideo`) or a device screen recording. Apple requires previews to show actual app footage. Ready to upload: [assets/video/app-store-preview-real-886x1920.mp4](assets/video/app-store-preview-real-886x1920.mp4) is **real screen footage** (29.7 seconds: Quick Add taps, the count-up, then "pizza 300" logged) with a silent audio track. A captioned stills version is [app-store-preview-886x1920.mp4](assets/video/app-store-preview-886x1920.mp4). Apple lets you set the poster frame; pick the moment the count-up lands.

---

## 2. Name, subtitle, keywords

Apple indexes **title (30) + subtitle (30) + keyword field (100)**. Words used in one don't need repeating in another. Plurals and "and/the" are handled automatically.

**The app name is the strongest ranking field.** The listing URL suggests the current name is "Cave Cals: AI Calorie Tracker" (verify in App Store Connect).

### Title options (30 characters max)

| Option | Chars | Notes |
| --- | --- | --- |
| **Cave Cals: AI Calorie Tracker** | 29 | Current (probably). Strong "calorie tracker" + "AI" |
| Cave Cals: Calorie Counter AI | 29 | Tests "counter" vs "tracker" |
| Cave Cals - Food & Calorie Log | 30 | Broader, loses "AI" |

**Recommendation:** keep "Cave Cals: AI Calorie Tracker." Don't churn the title often; ranking resets take time.

### Subtitle options (30 characters max)

| Option | Chars | Keywords it adds |
| --- | --- | --- |
| **Snap, Say & Log Food. Macros** | 28 | snap, say, log, food, macros |
| Photo Food Log & Macro Counter | 30 | photo, food, log, macro, counter |
| Protein, Macros & Weight Loss | 29 | protein, macros, weight, loss |
| Simple food & calorie tracker | 29 | Existing draft; "calorie tracker" is wasted, since it repeats the title |

**Recommendation:** test "Photo Food Log & Macro Counter" (high-intent AI and macro words) first. The existing draft repeats title words, so it adds no new ranking terms.

### Keyword field (100 bytes, comma-separated, no spaces)

Assuming title "Cave Cals: AI Calorie Tracker" and subtitle "Photo Food Log & Macro Counter":

```
protein,diet,weight,loss,scan,barcode,nutrition,meal,diary,fitness,fasting,carb,keto,voice,snap,cal
```

That's 99 bytes (checked). Every word describes a shipped feature except "keto" and "fasting," which are borderline: people on those diets can use it, but there are no keto or fasting features. Swap them for "journal" and "counter" if you'd rather stay literal. Don't add "planner"; meal planning is out of scope. **Never use competitor names** (Cal AI, MyFitnessPal); Apple rejects them.

### Promotional text (170 characters, changeable without review)

Rotate monthly; it's your free billboard:

- **Launch:** "New: build a calorie plan in a minute, track protein, and see your week at a glance. Snap it, say it, or tap it. Me eat. App count. 🍖" (133 characters)
- **Halloween:** "Fun-size? Still counts. Log candy in one tap and keep your week on track. Cave Cals: calorie tracking, caveman simple. 🎃" (120 characters)
- **Thanksgiving:** "Log the feast, enjoy the feast. Say what you ate and Cave Cals does the math. Then tap Done eating: Day done. Cave closed. 🦃" (124 characters)
- **New Year:** "New year, same you, better cave. Start the 30-Day Cave Challenge: log 5 days a week, one tap at a time. Free barcode scan & search." (131 characters)

---

## 3. Ratings: the ranking multiplier

See [02, Priority 1](02-Paywall-and-Onboarding.md#priority-1-ask-for-ratings-cheap-big). Without a rating prompt, only angry people write reviews. **Also reply to every review** in App Store Connect, in a friendly caveman voice for positive ones and plain helpful English for problems:

- 5★: "Zog thank you! Cave strong because of you. 🍖"
- Bug: "Sorry about that! Fixed in version X. If it still happens, email [support] and I'll look personally. — Phil"

---

## 4. Custom product pages (one listing per audience)

Apple allows up to 35 custom product pages (App Store Connect → Custom Product Pages), each with its own screenshots and promo text and its own URL. Send each channel to the page that matches its promise; that consistency lifts conversion.

| Page | Used for | Screenshot 1 headline |
| --- | --- | --- |
| **Trainers & gyms** | Trainer videos, gym flyer QR, coach outreach | "Your trainer wants you to track protein. Easy." |
| **Snap it** | AI/photo videos, Cal AI-style creators | "Snap your plate. Calories done." |
| **Free & simple** | "Other apps charge for barcodes" angle | "Barcode scan. Free." |
| **Caveman** | Zog skits | "Me eat. App count." with the caveman big |
| **New Year** (Dec–Jan) | Seasonal ads | "30-Day Cave Challenge starts now" |

Apple Search Ads can also point keyword groups at matching custom pages ("protein tracker" → Trainers page).

---

## 5. In-app events (free visibility in search and the Today tab)

In-app events get their own cards in App Store search and can be featured. They need a real, time-bound thing happening in the app. Ideas that need **no code** (each is a challenge framed around existing features):

| Event | Dates | Badge | Card copy |
| --- | --- | --- | --- |
| **Cave Candy Count** | Oct 24 – Nov 1 | Challenge | "Log every piece of Halloween candy for a week. Fun-size counts!" |
| **Feast Mode** | Nov 23 – Nov 30 | Challenge | "Log Thanksgiving the easy way: say it, snap it, done." |
| **30-Day Cave Challenge** | Jan 1 – Jan 31 | Challenge | "Log food 5 days a week for 30 days. Consistency beats perfect." |
| **Protein Hunt** | Feb | Challenge | "Hit your protein goal 20 days this month." |
| **Summer Cave Prep** | May | Challenge | "8 weeks of simple tracking before summer." |

Apple reviews events; they must describe something users can do in the app during those dates. Pair each event with the same-named social campaign.

---

## 6. Product page A/B tests (Product Page Optimization)

Run one test at a time, ~90% confidence, 2–4 weeks each:

1. **Screenshot 1:** caveman hero vs plain UI hero
2. **Headline voice:** caveman ("Me eat. App count.") vs plain ("Calorie tracking made simple")
3. **Icon:** current drumstick-scan vs caveman face (only if you're willing to change the icon; check brand consistency)
4. **Order:** AI first (Snap it) vs Quick Add first

---

## 7. Search outside the App Store

The web search for "Cave Cals" doesn't return the app's App Store page yet, while a dozen "Cals" apps show up. Fix that:

- A simple site at **cavecals.com** (or cavecals.vercel.app for now) with the app name, screenshots, App Store badge, press kit, and a privacy link. Currently only /privacy exists.
- Utility pages that rank: "calories in [common food]" pages generated from the app's built-in food catalog (`Documentation/FoodCatalog`). Each page ends with "Log it in one tap with Cave Cals." Programmatic SEO took MyFitnessPal a long way.
- Claim @cavecals on TikTok, Instagram, YouTube, X, Threads, and Pinterest today, even if unused.
- Submit to "best calorie app" roundups and app directories (see [09-Launch-PR-Community](09-Launch-PR-Community.md)).
