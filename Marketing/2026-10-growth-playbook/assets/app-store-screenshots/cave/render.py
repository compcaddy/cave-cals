"""Render the cave-wall store screenshots for the App Store (iPhone 6.9" and 6.5") and Google Play (phone).

Every slide uses the same background, headline and phone size, so the set reads as one; phones tilt or zoom per slide for variety.
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

# (file, headline, raw capture, mascot, phone tilt in degrees, phone zoom)
# A clockwise tilt swings the phone's bottom left, so its mascot moves to the right.
SLIDES = [
    ("01-lose-weight", "Lose weight\nnot time", "welcome.png", "zena/zena-salad.png", -4, 1),
    ("02-snap-it", "Snap it", "meal-scan.png", "zog/zog-scan-food.png", 5, 1.08),
    ("03-say-it", "Say it", "voice-log.png", "zena/zena-voice-log.png", -3, 1),
    ("04-track-it", "Track it", "home.png", "zog/zog-thumbs-up.png", 3, 1),
    ("05-find-it", "Find it", "search.png", "zena/zena-phone-heart.png", 0, 1.16),
    ("06-lose-it", "Lose it", "progress.png", "zog/zog-streak-torch.png", -4, 1),
    ("07-team-up", "Team up", "clans.png", "together/together-high-five.png", 4, 1),
]


def page(w, h, screen, head, shot, mascot, tilt, zoom):
    # Everything is sized from the canvas width so iPhone and Android match; the phone is as large as fits
    # between the headline and the bottom edge.
    u = w / 1320
    top = 470 * u
    phone_w = min(1000 * u, (h - top - 70 * u - 40 * u) / screen + 40 * u)
    # A two-line headline is set smaller and pushes the same-size phone down (its bottom runs off the edge).
    lines = head.split("\n")
    size = 230 if len(lines) == 1 else 150
    top += (size * len(lines) - 230) * u
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>
@font-face {{ font-family: Marker; src: url('{(BRAND / "PermanentMarker-Regular.ttf").as_uri()}'); }}
* {{ box-sizing: border-box; margin: 0; }}
html, body {{ width: {w}px; height: {h}px; overflow: hidden; }}
body {{ background: url('{(BRAND / "cave-wall-bg.png").as_uri()}') center / cover; position: relative; }}
h1 {{ font-family: Marker; font-weight: normal; text-transform: uppercase; color: #B84718; text-align: center;
     font-size: {size * u}px; line-height: 1; letter-spacing: {4 * u}px; margin-top: {150 * u}px;
     text-shadow: 0 {3 * u}px 0 rgba(120, 50, 15, .18); }}
.phone {{ position: absolute; left: 50%; top: {top}px; width: {phone_w}px; transform-origin: 50% 0;
         transform: translateX(-50%) rotate({tilt}deg) scale({zoom});
         background: #17120F; border-radius: {120 * u}px; padding: {20 * u}px;
         box-shadow: 0 {50 * u}px {110 * u}px rgba(70, 35, 10, .35), inset 0 0 0 {4 * u}px #3A2F28; }}
.phone img {{ width: 100%; display: block; border-radius: {100 * u}px; }}
.mascot {{ position: absolute; {"right" if tilt > 0 else "left"}: {20 * u}px; bottom: {30 * u}px; height: {460 * u}px;
          filter: drop-shadow(0 {16 * u}px {24 * u}px rgba(70, 35, 10, .3)); }}
</style></head><body><h1>{"<br>".join(lines)}</h1>
<div class="phone"><img src="{shot.as_uri()}"></div>
<img class="mascot" src="{(CHAR / mascot).as_uri()}"></body></html>"""


def render(name):
    cfg = PLATFORMS[name]
    w, h = cfg["size"]
    cfg["out"].mkdir(parents=True, exist_ok=True)
    for old in cfg["out"].glob("*.png"):
        old.unlink()
    for file, head, raw, mascot, tilt, zoom in SLIDES:
        shot = cfg["raw"] / raw
        if not shot.exists():
            print("skip", name, file, "(no", raw + ")")
            continue
        html = HERE / f".{name}-{file}.html"
        html.write_text(page(w, h, cfg["screen"], head, shot, mascot, tilt, zoom))
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                        "--allow-file-access-from-files", "--force-device-scale-factor=1",
                        f"--window-size={w},{h}", f"--screenshot={cfg['out'] / (file + '.png')}",
                        html.as_uri()], check=True, capture_output=True)
        html.unlink()
        print("rendered", name, file)


if __name__ == "__main__":
    for n in sys.argv[1:] or PLATFORMS:
        render(n)
