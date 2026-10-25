"""Render the cave-wall store screenshots for the App Store (iPhone 6.9" and 6.5") and Google Play (phone).

Every slide uses the same background, headline spot, phone size and mascot spot, so the set reads as one.
Run from anywhere: python3 render.py [ios|android]   (both by default)
Needs Google Chrome. Raw captures: ../raw-1.2/ (iOS) and CaveCalsAndroid/docs/play-store/raw-2026-10/ (Android).
"""
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
BRAND = HERE.parent.parent / "brand"
CHAR = BRAND / "characters"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

PLATFORMS = {
    "ios": dict(size=(1320, 2868), screen=2868 / 1320, raw=HERE.parent / "raw-1.2", out=HERE / "ios"),
    "ios65": dict(size=(1284, 2778), screen=2868 / 1320, raw=HERE.parent / "raw-1.2", out=HERE / "ios-6.5"),
    "android": dict(size=(1080, 2160), screen=2400 / 1080, out=HERE / "android",
                    raw=pathlib.Path("/Users/phil/Documents/GIT/CaveCalsAndroid/docs/play-store/raw-2026-10")),
}

# (file, headline, raw capture, mascot)
SLIDES = [
    ("01-track-it", "Track it", "home.png", "zog/zog-thumbs-up.png"),
    ("02-snap-it", "Snap it", "meal-scan.png", "zog/zog-scan-food.png"),
    ("03-say-it", "Say it", "voice-log.png", "zena/zena-voice-log.png"),
    ("04-find-it", "Find it", "search.png", "zena/zena-phone-heart.png"),
    ("05-see-it", "See it", "progress.png", "zog/zog-streak-torch.png"),
    ("06-team-up", "Team up", "clans.png", "together/together-high-five.png"),
]


def page(w, h, screen, head, shot, mascot):
    # Everything is sized from the canvas width so iPhone and Android match; the phone is as large as fits
    # between the headline and the bottom edge.
    u = w / 1320
    top = 470 * u
    phone_w = min(1000 * u, (h - top - 70 * u - 40 * u) / screen + 40 * u)
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>
@font-face {{ font-family: Marker; src: url('{(BRAND / "PermanentMarker-Regular.ttf").as_uri()}'); }}
* {{ box-sizing: border-box; margin: 0; }}
html, body {{ width: {w}px; height: {h}px; overflow: hidden; }}
body {{ background: url('{(BRAND / "cave-wall-bg.png").as_uri()}') center / cover; position: relative; }}
h1 {{ font-family: Marker; font-weight: normal; text-transform: uppercase; color: #B84718; text-align: center;
     font-size: {230 * u}px; line-height: 1; letter-spacing: {4 * u}px; margin-top: {150 * u}px;
     text-shadow: 0 {3 * u}px 0 rgba(120, 50, 15, .18); }}
.phone {{ position: absolute; left: 50%; top: {top}px; transform: translateX(-50%); width: {phone_w}px;
         background: #17120F; border-radius: {120 * u}px; padding: {20 * u}px;
         box-shadow: 0 {50 * u}px {110 * u}px rgba(70, 35, 10, .35), inset 0 0 0 {4 * u}px #3A2F28; }}
.phone img {{ width: 100%; display: block; border-radius: {100 * u}px; }}
.mascot {{ position: absolute; left: {20 * u}px; bottom: {30 * u}px; height: {460 * u}px;
          filter: drop-shadow(0 {16 * u}px {24 * u}px rgba(70, 35, 10, .3)); }}
</style></head><body><h1>{head}</h1>
<div class="phone"><img src="{shot.as_uri()}"></div>
<img class="mascot" src="{(CHAR / mascot).as_uri()}"></body></html>"""


def render(name):
    cfg = PLATFORMS[name]
    w, h = cfg["size"]
    cfg["out"].mkdir(parents=True, exist_ok=True)
    for file, head, raw, mascot in SLIDES:
        shot = cfg["raw"] / raw
        if not shot.exists():
            print("skip", name, file, "(no", raw + ")")
            continue
        html = HERE / f".{name}-{file}.html"
        html.write_text(page(w, h, cfg["screen"], head, shot, mascot))
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                        "--allow-file-access-from-files", "--force-device-scale-factor=1",
                        f"--window-size={w},{h}", f"--screenshot={cfg['out'] / (file + '.png')}",
                        html.as_uri()], check=True, capture_output=True)
        html.unlink()
        print("rendered", name, file)


if __name__ == "__main__":
    for n in sys.argv[1:] or PLATFORMS:
        render(n)
