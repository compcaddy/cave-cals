# Clans

Design draft, October 13, 2026. **Nothing is built yet.** This is on branch `clans` (worktree `../CaveCals-clans`), so `main` stays releasable for 1.1.x. The owner confirmed the design on October 13, 2026.

## The idea

A clan is a group of Cave Cals people who keep each other on track. It has two parts that work side by side:

- **Accountability:** an on/off view of how everyone's days went.
- **One challenge at a time:** a contest with a start date and a clear result.

Everything lives behind a new **campfire** icon in the Home header. The rest of the app stays the same. Logging stays local-first, and the diary never leaves the phone.

## Accounts and profiles

- **Sign in:** **Sign in with Apple** and **Sign in with Google**, side by side, asked for only when someone creates or joins a clan.
  - Google's sign-in provides the person's name and profile photo, which fill in their clan profile.
  - Apple provides the name only on the first sign-in, and no photo.
  - Google sign-in shows Google's normal page in the system sign-in window (`ASWebAuthenticationSession` with PKCE). Google's own SDK uses the same window, so leaving the SDK out changes nothing people see and keeps the app lighter.
  - Google needs an iOS OAuth client ID (no secret) and a Web client ID that the server uses to verify sign-ins. Both are free in Google Cloud Console.
- **Profile:**
  - Display name, defaulting to the first name from sign-in and editable.
  - Photo: picked from Photos or taken with the camera, then dragged and pinched inside a circle. Uploaded as 512 px, re-encoded so no location or other metadata remains (the same approach as Progress Photos), and stored in private Vercel Blob. Only clanmates can see it. A Google sign-in uses the Google photo until the person changes it; anyone without a photo shows initials.
  - Birth year: asked once, and needed for the 18+ check on weight challenges.
- **Agreeing to terms:** sign-up requires agreeing to the terms, including no objectionable content (Apple guideline 1.2).
- **Account deletion:** Settings → Clans → Delete clan account removes the person and all their clan data, and revokes the Apple sign-in, which Apple requires.
- Someone who signs in with Apple on one iPhone and Google on another ends up with two separate accounts. That's fine for v1.

## Clans

- **Creating:** anyone signed in can create a clan with a name (filtered for slurs) and an invite code. The creator is the owner and admin, and can add co-admins.
- **Cave Cals+:** a 2-person buddy clan is free, with everything included. A third member needs an admin with Cave Cals+, checked by the server against Apple-verified subscriptions.
  - If that membership lapses, running challenges finish and accountability keeps working, but no new members or challenges until an admin with Cave Cals+ takes over.
- **Size:** at most 50 members, never shown anywhere. A full clan says "This clan is full."
- **Joining:** through an invite link or by typing the code. A person can be in many clans.
- **Anonymous:** each member can join as **Cave person** with a generic image ("Cave person 2" when there are several). It can be changed anytime, and admins can't see through it.
- **Leaving:** allowed anytime. From that day the person isn't counted. They drop out of the challenge ranking (shown as "Left"), and a streak never breaks because someone left.
- **Removing:** admins can remove members, with the same effect as leaving. If the last admin leaves, the longest-standing member becomes admin.
- **Block:** a blocked person's name and photo are hidden from you, and they can't nudge or cheer you.
- **Report:** a member's name or photo, or a clan's name. Reports go to `/admin/reports` so the owner can act within 24 hours.

### Invite links

- The link is `CaveCals.com/join/<CODE>`. Add `JOIN` to `RESERVED_CODES`.
- **App installed:** it's a Universal Link that opens straight to the Join page for that clan. This needs the Associated Domains entitlement and `/.well-known/apple-app-site-association` on the backend.
- **Not installed:** the page shows the code, an App Store button, and "Installed? Tap this link again."
- **Never** offer "Join …?" on first launch, and never read the clipboard.
- Dev uses `cavecals-dev://join/<CODE>`.

## The daily report (what leaves the phone)

Whenever today's or yesterday's diary changes, the phone sends one small report per day. It's debounced, and also sent on open and on going to the background:

`{ date, timeZone, logged, fullDay, percentOfGoal (rounded whole %, null without a goal), goalOK (goal ≥ 1,200 women / 1,500 men, from CaloriePlan's minimums), doneEating }`

It never includes calories, the goal number, foods, or weight. The server computes every mark from this one report, so it covers all of a person's clans. Sending % of goal, rather than only ✓/✗, was confirmed by the owner on October 13: the ± view and on-target rules need it. The server stores it but shows it only where the clan's settings allow.

- **Locking:** a day locks at **9 AM the next morning**, the member's local time. After that, backfills don't change it.
- **Logged:** at least one food that day.
- **Full day:** the phone works this out with Progress's complete-day rule (`ProgressData.completeShare`):
  - With a goal: at least 70% of it logged.
  - Without a goal: 70% of their usual completed day.
- **On target:** a full day that's also inside the rule's range (`OnTargetRule`: at or under, within X%, or up to N over).
- **People without a goal:** they can earn logged and full-day marks, but not on-target ones.

## Accountability (clan setting, admins switch it)

- **Off:** members see the member list and the challenge board only.
- **Yes/no:**
  - Today shows whether each person has logged anything yet.
  - Once a day locks, it shows ✓ for a full day, a gray "partial" mark for a day with some food, and – for no log.
- **± mode:**
  - Today shows yes/no only, because the numbers mean little mid-day.
  - Once a day locks, or after Done eating, it shows the % versus that person's own goal ("−3%", "+12%").
  - Inside the clan's range: an orange ✓ with the number. Outside: the number in gray. Never red.
- **Layout:** a week grid with members down the side and the days across (following the Progress week start), plus a weekly line per person ("5 of 7 logged", average ±).
- **Turning it on:** everyone gets a heads-up, so they can switch to Cave person first.
- **The range:** set by the creator for the whole clan, or the creator lets each member pick their own.

## Challenges

There's **one active challenge per clan**. The database allows several, so that can change later.

- **Setting one up:** any admin picks the type, the rule, and the start date (today up to 30 days ahead). Members tap **Join** before the start, and the roster is fixed once it starts.
- **No rule changes.** To change something, end or delete the challenge and start a new one.
- **History:** past challenges and the clan's **best streak** are kept.

| Type | Scoring |
| --- | --- |
| Logging days | 1 point per full day. The admin can switch it to "any food counts" when setting up |
| On-target days | 1 point per on-target day |
| Team total | Everyone's points together toward a target (for example 100 days), using the logging or on-target rule |
| Survivor | Each miss costs a life (lives = saves). Out at zero. Fixed length (all survivors win) or open-ended (last one standing; same-day ties share) |
| Streak | Open-ended. A day counts when **Everyone**, or **X%** of the roster, made it (logging or on-target rule). It runs until it breaks. Shows "Record: 23 days" as the number to beat |
| Weight loss | % lost: the average of weigh-ins on days 1–3 versus the average on the last 3 days |

- **The logging rule** (used by logging days, team total, Survivor, and streak) means a full day, unless the admin picks "any food counts" when setting up the challenge.
- **Saves:** the creator sets a count and a period (per week, per month, or for the whole challenge). A miss uses a save automatically.
- **Ties** share the win.
- **Weight-loss rules:**
  - 2 to 12 weeks long.
  - Only people 18 or older can join, and not anyone with "Me follow doctor plan" on (the phone checks that).
  - Credit stops at **1% of body weight per week** of the challenge's length.
  - The phone computes the % from its own weigh-ins and sends only the %. Weigh-ins are local and never synced (WeightTracking.md), so the phone that has them reports.
  - Someone with no weigh-in in the first 3 days, or none in the last 3, isn't ranked. Reminders go out on day 1 and on each of the last 3 days.
- **Health guardrails:** always each person's own goal, never a fixed calorie number. A low or incomplete day never counts as "on target". Never "lowest calories".

## On Home

- **Campfire icon** to the right of the chart icon. Asset `CaveCampfire` (option A, below), identifier `clans`. Check that the header fits on an iPhone SE.
- **Badge:** a red circle on the campfire with the number of unread alerts (shows 9+ past nine). The app's home-screen icon gets no badge.
- **Status strip:** one line between the header and the calorie card, shown only while you're in an active challenge (`clanStatus`). Tapping it opens the clan.
  - Examples: "Fire lit 18 days · 4 of 6 in today", "Day 6 of 14 · You're 2nd", "7 left · You have 2 lives", "Week 3 · You're 1st (−2.4%)", "62 of 100 days".
  - With several challenges, it shows whichever one needs you today.
  - Hidden in add mode. Settings → Home → **Show clan status** (`showsClanStatus.v1`, on by default).

## Notifications (server push through APNs)

- **Asking permission:** iOS's prompt appears when someone first joins a clan.
- **Alerts:**
  - Fire going out: at 7 PM local, if you haven't logged and a streak or Survivor is at stake.
  - Nudges and cheers from clanmates: preset messages, one nudge per sender, person, and day.
  - Challenge starts, ends, and results.
  - Survivor: a life lost, and you're out.
  - Streak milestones (7, 30, 100) and new records.
  - Someone joined (admins only).
- **Controls:** each alert type can be turned off in Settings → Clans, and each clan can be muted.

## Backend (Neon + Vercel)

**Tables** (Drizzle migration `0005_clans.sql`; it adds tables only and changes nothing existing). Use `clan_` names, because `ai_challenges` already exists:

- `clan_people`: id, display_name, photo_path, birth_year, time_zone, created_at
- `clan_identities`: (provider, subject) primary key, person_id, apple_refresh_token (encrypted, needed to revoke at deletion)
- `clan_sessions`: token_hash, person_id, ai_account_id (for the Cave Cals+ check), last_used_at, expires_at
- `clan_push_tokens`: person_id, token, environment (sandbox/production), updated_at
- `clans`: id, name, invite_code (unique), accountability (off/logged/percent), rule (jsonb OnTargetRule), rule_choice (clan/member), best_streak, created_by, created_at
- `clan_members`: id, clan_id, person_id, role (owner/admin/member), anonymous, anon_number, rule (when members choose), joined_at, left_at, removed_by
- `clan_days`: (person_id, date) primary key, logged, full_day, percent_of_goal, goal_ok, done_eating, reported_at
- `clan_challenges`: id, clan_id, kind, rule (jsonb), saves_count, saves_period, starts_on, ends_on (null when open-ended), status (upcoming/active/ended/canceled), result (jsonb), created_by. Allow several per clan, and enforce one active in code.
- `clan_entrants`: (challenge_id, person_id) primary key, status (in/out/left), points, lives_left, saves_used (jsonb by period), weight_change_pct, weight_start_ok, weight_end_ok, final_rank
- `clan_marks`: (challenge_id, person_id, date) → made/missed/saved/none. A cache for grids and history.
- `clan_alerts`: id, person_id, clan_id, kind, payload, created_at, read_at. Drives the badge.
- `clan_nudges` (from, to, clan, date, kind; unique per day), `clan_blocks`, `clan_reports`

**API** (`/api/v1/…`, App Attest–signed like today plus a person session token; Dev uses test access):

- **Sign-in and account:** `auth/apple`, `auth/google`, `auth/signout`, `clans/account/delete`
- **Profile and push:** `me`, `me/photo`, `push/register`
- **Clans:** `clans/list`, `clans/create`, `clans/get`, `clans/update`, `clans/join`, `clans/leave`, `clans/members/remove`, `clans/members/role`, `clans/code/reset`, `clans/delete`
- **Daily reports:** `days/report` (a batch)
- **Challenges:** `challenges/create`, `challenges/join`, `challenges/leave`, `challenges/end`, `challenges/weight`
- **Social and safety:** `nudges/send`, `alerts/list`, `alerts/read`, `blocks/add`, `blocks/remove`, `reports/create`

**Web pages:** `/join/[code]`, `/.well-known/apple-app-site-association`, `/admin/reports`.

**Jobs:** `/api/cron/clans` runs every 15 minutes (`*/15 * * * *` in `vercel.json`, protected by the existing `CRON_SECRET`). It locks days whose 9 AM has passed, scores challenges, ends finished ones, and sends the 7 PM alerts. It runs every 15 minutes, not hourly, so 9 AM and 7 PM land on time in half-hour and 45-minute time zones (India, Newfoundland, Nepal). The owner's Vercel plan is Pro ($20/month), which allows cron jobs as often as once a minute; Hobby allows only once a day. Each run only handles what's due, so a late or repeated run does no harm. The owner's own timer server could call the same URL as a backup if Vercel cron ever misbehaves.

**Push:** HTTP/2 to APNs (`node:http2`) with a .p8 key (`APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_KEY`).

**Database branches:** the old `backend-dev` Neon branch is gone (October 13 check: only `production` remains). Create a new dev branch for clans work. Production is migrated only at release.

## In the app

- **New files:** `App/Clans.swift` (models, `ClanStore`), `App/ClanViews.swift`, `App/ClanChallenges.swift`, `App/ClanAccount.swift` (sign-in), `App/ClanDayReport.swift` (unit-tested report and weight-% logic), and `App/AvatarCropper.swift`.
- **Screens:** Clans list, Sign in, Profile, Create clan, Invite/share, Join, Clan page (members, accountability grid, challenge card, history), New challenge, Challenge board, Clan settings, and Report/Block.
- **House rules:** `HapticForm`/`HapticList`, haptics on every tap, `.tapOutsideClosesKeyboard()`, usage stats (`clan.created`, `clan.joined`, `challenge.started` {kind}, `nudge.sent`; error area `clans`; usage stats stay separate from accounts), and plain accessibility labels with caveman copy.
- **Tests:** a DEBUG `--clans-fixture` stands in for the backend in UI tests.

## Setup checklist (owner)

1. Apple Developer: add Sign in with Apple and Associated Domains to `com.philstarkovich.cavecals`, create a Sign in with Apple key (for token revocation), and an APNs key. Decide whether the Dev app ID gets its own sign-in and push capabilities so Dev can test.
2. Google Cloud Console: set up the OAuth consent screen, then create an iOS client ID and a Web client ID.
3. Vercel: the current Pro plan already covers the 15-minute cron. Add the new environment variables (APNs key, Sign in with Apple key, Google client IDs).
4. Neon: create a dev branch.
5. App Store Connect: update the age rating questionnaire (user-generated content) and the privacy details (name, photo, user ID, email from sign-in, and the fitness data linked to an account). Claude will update the privacy policy and terms.

## App Review checklist

- Report, block, the name filter, and terms agreement are in place (guideline 1.2), with contact info.
- Account deletion is in the app, and it revokes Apple tokens (guideline 5.1.1(v)).
- No HealthKit data leaves the phone: reports come from the diary and the app's own weigh-ins.
- The review notes explain clans and give a demo account with a seeded clan.

## Campfire icon (option A)

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" fill="none" stroke="#000" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round">
  <path d="M16 19.8c-3.9 0-6.4-2.5-6.3-5.9.1-3.7 3.3-5.8 4.6-10.4 1.6 1.6 2.4 3.8 2.1 6.2 1.3-.6 2.6-1.6 3.4-3.1 2 2.2 3.1 4.8 3 7.6-.1 3.4-2.7 5.6-6.8 5.6z"/>
  <path d="M4.5 22.6c7.6 1.7 15.2 3.4 23 5"/>
  <path d="M4.8 27.6c7.5-1.6 15-3.3 22.6-5.1"/>
</svg>
```

## Later

Chat (with moderation), public clans, coach dashboards, several challenges at once, referrals ("Give a Friend a Premium Pass"), and a clan widget.
