# Setup checklist: everything to switch on before and after launch

Step-by-step, in order. Each item says where to click. Menus move around; if a path has changed, search the App Store Connect help for the feature name. **Nothing here has been done yet.**

---

## Day 0: accounts and money (1–2 hours)

- [ ] **App Store Small Business Program.** developer.apple.com → Account → Small Business Program → Enroll. This cuts Apple's commission from 30% to 15% on all sales (under $1M/year). Takes effect at the start of the next fiscal month after approval. **Skip only if already enrolled.** Every sale before enrolling costs 15% more.
- [ ] **Check storefronts.** App Store Connect → Cave Cals → Pricing and Availability. English-speaking markets (UK, Canada, Australia, New Zealand, Ireland) need no translation and have similar diet-app demand. The app shows kilograms and pounds already. FatSecret results can be US-centric, so spot-check a few UK/AU searches.
- [ ] **Claim handles:** @cavecals on TikTok, Instagram, YouTube, X, Threads, Pinterest, Facebook page, and Reddit (u/cavecals). Same profile photo (launch art) and bio ([11](11-Brand-Voice-Copy-Bank.md#bios)).
- [ ] **TikTok Business account** for @cavecals (free; enables link in bio sooner, analytics, and Spark Ads later).
- [ ] **Instagram professional account** linked to a Facebook page (needed for ads and Collab posts).

## Day 1: App Store Connect (2 hours)

### Campaign links
- [ ] App Store Connect → Apps → Cave Cals → **Analytics → Acquisition → Campaign links** (or App Analytics → Sources → "Generate a campaign link"). Create one per source from the table in [12](12-Metrics-and-Budget.md#campaign-links).
- [ ] Paste them into [assets/content-tracker.csv](assets/content-tracker.csv) and the creator pipeline as you use them.
- [ ] Re-make the flyer QR with the gym campaign link: `pip install qrcode`, then `python3 assets/make_qr.py "<campaign link>"`, then re-render the flyer (open `assets/gym-flyer.html` in Chrome → Print → Save as PDF).

### Offer Codes (free months for trainers, creators, and win-back)
- [ ] App Store Connect → Cave Cals → **Subscriptions** → the Cave Cals+ group → the Yearly and Monthly subscriptions → **Offer Codes** → Create.
  - Offer: **Free, 1 month** (for new subscribers) → customer eligibility: new
  - Code type: **custom codes** (e.g. `CAVETRAINER`, `ZOGLAUNCH`, `CAVE[CREATOR]`), with a redemption limit per code
  - Second offer for win-back: **Pay up front, first year at $19.99** → eligibility: expired subscribers
- [ ] Redemption link to share: `https://apps.apple.com/redeem?ctx=offercodes&id=6809208501&code=CODE` (works without an app update).
- [ ] Test a code with a sandbox account before sharing it widely.

### Introductory offer on the yearly plan
- [ ] Subscriptions → Yearly → **Subscription Prices → Introductory Offers** → Free trial, **1 week**, all territories. (Needed for the trial and pricing tests in [02](02-Paywall-and-Onboarding.md#priority-2-put-a-trial-on-the-yearly-plan-and-show-it-at-the-plan-reveal).)
- [ ] Update the App Store description's subscription paragraph if trial terms change (the current draft describes only the monthly trial).

### Win-back offers (iOS 18+)
- [ ] Subscriptions → a subscription → **Win-back Offers** → Create: e.g. 1 month free for people lapsed 30–180 days. Apple can show these on the App Store product page and in the Apps tab.

### Custom product pages
- [ ] App Store Connect → Cave Cals → **Custom Product Pages** → Create: "Trainers & gyms," "Snap it," "Caveman" ([06 §4](06-App-Store-Optimization.md#4-custom-product-pages-one-listing-per-audience)). Each gets its own screenshots, promo text, and URL. They need review, which is quicker than an app update.

### In-app events
- [ ] App Store Connect → Cave Cals → **In-App Events** → Create "Cave Candy Count" (Oct 24 – Nov 1). Apple asks for submission at least ~2 weeks ahead for featuring consideration. Event card image 1920×1080 (use the launch art on the orange background).

### Product page optimization
- [ ] After the new screenshots have been live 2 weeks: **Product Page Optimization** → new test → screenshot 1 caveman hero vs plain UI hero ([06 §6](06-App-Store-Optimization.md#6-product-page-ab-tests-product-page-optimization)).

### Featuring nomination
- [ ] App Store Connect → Cave Cals → **Featuring Nominations** (or developer.apple.com → Promote your app). Nominate the launch for "New Year" and "Apps we love." Mention App Intents/Siri logging, widgets, and Apple Health.

## Day 1: RevenueCat (1 hour)

- [ ] Confirm the Yearly product's new introductory offer shows up in the offering.
- [ ] **Experiments** → create test 1: yearly trial vs no trial (two offerings). Metric: realized LTV / revenue per customer, 35-day window.
- [ ] **Integrations**: connect Apple Search Ads attribution (AdServices). Later, TikTok and Meta. Send only purchase and trial events; never health data.
- [ ] **Charts to bookmark:** Trial conversion, Revenue, Active subscriptions, Churn, Initial conversion.

## Day 2: link in bio

- [ ] Simple short links on the backend domain, e.g. `cavecals.vercel.app/tt` → TikTok campaign link, `/ig`, `/gym`. Lets you change destinations without touching bios. (A draft landing page is in [assets/landing-page/](assets/landing-page/index.html).)
- [ ] Or use a free link-in-bio tool with the campaign link as the main button.

## Before each creator or trainer goes live

- [ ] Offer code created and tested
- [ ] Campaign link created
- [ ] Row added to [creator-pipeline.csv](assets/creator-pipeline.csv)
- [ ] Brief sent ([04](04-Creator-Program.md#the-one-page-creator-brief))
- [ ] Agreement signed, including disclosure

## Weekly (Mondays)

- [ ] [Weekly scorecard](assets/weekly-scorecard.csv)
- [ ] Reply to new App Store reviews
- [ ] Rotate promo text if a seasonal moment is coming ([06 §2](06-App-Store-Optimization.md#promotional-text-170-characters-changeable-without-review))
- [ ] Check RevenueCat experiment status
