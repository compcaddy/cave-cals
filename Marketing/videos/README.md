# Cave Cals videos

Every marketing and social video lives here: one [Remotion](https://www.remotion.dev) project (videos written as React code), one file per video, finished MP4s in `renders/`. **Add a catalog row for every new video**, and fill in where it was posted. Post performance goes in `../2026-10-growth-playbook/assets/content-tracker.csv`.

## Catalog

| Video id | Made | Length | Hook → what it shows | File | Posted |
|---|---|---|---|---|---|
| `snap-say-tap` | 2026-10-26 | 20 s, 1080×1920, silent | "Still counting calories on rocks?" → Meal Scan, Voice Log, Quick Add ("Snap it. Say it. Tap it. Done.") → end card. The "≈ 550 cals" scan card is illustrative. | [renders/snap-say-tap.mp4](renders/snap-say-tap.mp4) | not yet |

### Earlier videos (before this project)

Made with Python + headless Chrome + ffmpeg scripts kept beside them. They stay where they are because the playbook links to them.

| Made | Videos | Where |
|---|---|---|
| 2026-09-22 | Onboarding walkthrough screen recording (39 s) | `../2026-09-launch/video/onboarding-walkthrough.mp4` |
| 2026-10-01 | Slideshow promo (26 s); App Store previews, staged and real (25 s, 30 s) | `../2026-10-growth-playbook/assets/video/` |
| 2026-10-01 | Carousel videos: 5 ways no typing, app you don't hate, coach weekly recap, stopped doing, Zog's rules (15–20 s) | `../2026-10-growth-playbook/assets/video/carousels/` |
| 2026-10-01 | "Zog says" one-liners: barcode free, close enough, day done, me eat app count, protein first, same breakfast (6 s each) | `../2026-10-growth-playbook/assets/video/zog-says/` |
| 2026-10-01 | Real app demos: Done eating, pizza 300, Quick Add, full raw demo (7–43 s) | `../2026-10-growth-playbook/assets/video/real-demo/` |

## Making and changing videos

```bash
npm install
npm run studio                  # live preview with a timeline scrubber
npm run render -- snap-say-tap  # writes renders/snap-say-tap.mp4 (about 15 s)
```

New video: copy a file in `src/videos/`, give it a new kebab-case `id`, add it to the list in `src/Root.tsx`, render it, then add its catalog row above. Shared pieces are in `src/kit.tsx`: brand colors, cave-wall background with scene transitions, word-by-word Schoolbell headlines, mascot poses, a phone showing a real screenshot, cards, and the end card.

- **Art:** `public/brand` links to `../2026-10-growth-playbook/assets/brand` and `public/screens` to the 1.2 screenshots (`app-store-screenshots/raw-1.2`). Read `brand/characters/README.md` before picking poses. Body before-and-after poses are for organic posts only, never ads; the habit pair is fine anywhere.
- **Honesty:** show real features from real screenshots, and don't claim speeds the app doesn't have (see `../2026-10-growth-playbook/03-Video-Scripts.md`).
- **Sound:** renders are silent; add a trending sound in TikTok or Instagram when posting, or a licensed track for ads.
- **License:** Remotion is free for individuals and companies of up to 3 people; a bigger company needs a Remotion company license.
