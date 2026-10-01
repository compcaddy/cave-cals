# PR, launch sites, and communities

Existing drafts: [Community-launch-drafts.md](../2026-09-launch/Community-launch-drafts.md) (Product Hunt fields, App Shelf). This file adds press pitches, story angles, and a directory list.

**Nothing has been sent or posted.**

---

## Story angles journalists actually want

Nobody writes about "a new calorie app." They write about stories:

1. **"Solo developer vs. the $50M app."** Cal AI (built by teens, sold to MyFitnessPal) proved photo calorie counting is huge. Cave Cals is a one-person answer that keeps the basics free and adds a caveman. *Pitch to indie/tech outlets and newsletters.*
2. **"The calorie app that won't let you under-eat."** The plan builder won't auto-calculate for minors or clinician-led plans, never suggests below 1,200 (female) / 1,500 (male) calories a day, and caps the daily deficit at 750 calories or 25% of maintenance, whichever is smaller (`CaloriePlan.swift`, checked September 28, 2026). Compare that with viral "800 calories a day" content. *Pitch to health/wellness writers covering diet-app safety.*
3. **"Local developer and personal trainer team up."** A community story. *Pitch to local TV, newspaper, and city magazines.* Local news loves this, and a TV segment of the trainer in the gym with the app is gold for content.
4. **"No account, no ads: the privacy-first calorie tracker."** The diary stays on the phone; AI only sees what you choose to send. *Pitch to privacy-focused tech writers.*
5. **"Why this app has a caveman."** Brand and design story: hand-drawn icons, Schoolbell font, caveman copy. *Pitch to design newsletters (Sidebar, UX Collective) and Dribbble/Behance.*

---

## Press pitch (short; reporters skim)

> **Subject:** Solo dev's answer to Cal AI: a calorie tracker with a caveman
>
> Hi [name],
>
> Cal AI showed that people want calorie tracking to be effortless: snap a photo, done. It grew to $30M a year and was bought by MyFitnessPal.
>
> I'm a solo iPhone developer, and I built **Cave Cals** as the scrappy alternative: food search, barcode scanning, and manual logging stay free (no account needed), photo and voice logging are optional, and the whole app talks like a caveman ("You Eat. App Track. Weight Drop.").
>
> A couple of details you might find interesting:
> - It learns your usual foods from when and how often you eat them, so breakfast is one tap
> - "Hey Siri, log food" works without opening the app
> - The plan builder won't auto-calculate targets for minors or medically supervised plans
>
> Happy to send a TestFlight build, screenshots, or connect you with the personal trainer who uses it with clients.
>
> Phil Starkovich · [App Store link] · [press kit link]

**Follow up once**, 4–5 days later, with one new detail (a user number, a funny review, a new feature). Then stop.

### Who to pitch (verify each outlet's current contact and focus)

| Tier | Targets | Angle |
| --- | --- | --- |
| Apple/iOS press | 9to5Mac, MacStories, iMore, AppleInsider, Cult of Mac, MacRumors | Siri logging, widgets, Apple Health, indie dev |
| Indie app newsletters | Indie App Santa (December!), iOS Dev Weekly (dev angle), App Shelf, "Built with SwiftUI" features | Indie story |
| Health/fitness | Well+Good, Verywell Fit "best calorie apps," Healthline app roundups, Garage Gym Reviews | Ask to be considered for their next "best calorie tracker" update |
| Local | Local TV morning shows, city newspaper business section, local podcasts | Developer + trainer story |
| Podcasts | Indie dev podcasts (Launched, Under the Radar listener mail), fitness podcasts for the trainer | Founder story / trainer tips |

**Indie App Santa** features one paid indie app a day in December with a discount. It's a perfect fit for the Black Friday → New Year window. Apply early (usually October–November).

---

## Launch sites and directories

| Where | When | Notes |
| --- | --- | --- |
| **Product Hunt** | L+7, Tuesday–Thursday, 12:01am PT | Gallery: the new screenshots + a 30s video. First comment: the founder story. Ask friends to *visit and comment*, not upvote-beg. |
| **r/iOSapps, r/apple (App Saturday), r/AppHookup** | Saturdays; AppHookup only for a discount | Follow each sub's exact format |
| **r/SideProject, r/indiehackers, r/SwiftUI** | Launch week | Share the build story and screenshots of the SwiftUI details |
| **Hacker News "Show HN"** | Only with a technical angle (local-first SwiftData + CloudKit, App Attest-protected AI backend) | HN hates marketing, and loves real engineering tradeoffs |
| **Indie Hackers** | Monthly revenue update posts | Build-in-public |
| **AlternativeTo** | Launch week | List as an alternative to MyFitnessPal, Lose It!, Cal AI |
| **App directories** | Launch week | AppAdvice, Appvizer, SaaSHub, Uneed, and others; each takes 5 minutes |
| **Apple "Tell us about your app"** | 6–8 weeks before a big moment | developer.apple.com → App Store → Promote your app (featuring nominations). Submit for **New Year** featuring now. Apple features apps with great design and new-OS features (widgets, Siri/App Intents, which Cave Cals has). |

---

## Communities: give value first

Most weight-loss communities ban self-promotion (r/loseit strictly). **Don't post links there.** Instead:

- **Be helpful as yourself.** Answer tracking questions in r/CICO, r/1200isplenty, r/Fitness daily threads, and r/loseit. Mention the app only if someone asks for app recommendations *and* the sub allows it, and always disclose "I made this."
- **The trainer answers questions** in fitness subreddits and Facebook groups with genuine expertise. People check profiles.
- **Start a Discord or Facebook group: "The Cave."** A home for challenge participants and power users. Weekly "log your wins" thread, Zog memes, beta testers for new features. Your 100 biggest fans become your QA team and word-of-mouth engine.

### Value-first post drafts (disclose you made the app if you mention it at all)

**r/CICO or r/loseit (no link, no app name unless someone asks):**
> **What finally made logging stick for me: stop logging at night**
> I quit tracking three times because I'd try to remember everything at 10pm and give up. What worked: log each thing right after eating, even if it's rough ("pasta ~600"), and only look at the weekly average on Sunday. Weighing everything was also killing me, so I weigh only the calorie-dense stuff (oils, nut butters, cereal) and eyeball the rest. Anyone else find the *timing* of logging mattered more than the accuracy?

**r/Fitness daily thread or r/xxfitness (trainer posts, as themselves):**
> Personal trainer here. The clients who hit their goals aren't the ones who log perfectly; they're the ones who log *something* 5+ days a week. I've stopped asking for perfect food scales and just ask for a weekly average. Happy to answer questions about protein targets or tracking without obsessing.

**r/SideProject / r/iOSapps (self-promotion allowed; follow each sub's format):**
> **I built a calorie tracker where a caveman does the math**
> Solo iOS dev here. Cave Cals learns the foods you actually eat (by time of day and habit) so logging breakfast is one tap. Barcode scanning, search, and manual logging are free; photo and voice logging are the paid part. Built with SwiftUI + SwiftData, no account needed. I'd love brutal feedback on the first-run experience. [App Store link]

---

## Press kit (put at cavecals.vercel.app/press, or a shared folder)

- App icon (1024px), launch art, caveman logo (from `App/Assets.xcassets`)
- 6–8 current screenshots (from [assets/app-store-screenshots](assets/app-store-screenshots/))
- 30s demo video
- Fact sheet: name, price (free; Cave Cals+ $5.99/mo or $29.99/yr, or the tested prices), platforms (iPhone, iOS 17+), launch date, developer, contact
- 3-sentence description + 1-paragraph founder bio + photo
- Trainer quote (with their written approval)
