"""Build a 9:16 promo video (cave-cals-promo-9x16.mp4) from real app captures.

Run from this folder: python3 render_promo.py
Needs Google Chrome and ffmpeg. The video is silent on purpose: add a trending sound inside
TikTok / Instagram when posting (licensed there), or a royalty-free track for ads.
"""
import pathlib
import subprocess

HERE = pathlib.Path(__file__).resolve().parent
BRAND = (HERE.parent / "brand").as_uri()
RAW = (HERE.parent / "app-store-screenshots" / "raw").as_uri()
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
W, H = 1080, 1920
SECONDS = 3.6   # per scene
FADE = 0.4

# (theme, headline, subline, image)
SCENES = [
    ("orange", "Me eat.<br>App count.", "The calorie tracker so simple, a caveman uses it.", "art"),
    ("cream", "Your day.<br>At a glance.", "Calories, macros &amp; what you ate.", "home.png"),
    ("orange", "Your usual foods.<br>One tap.", "Quick Add learns what you eat.", "quick-add.png"),
    ("cream", "Snap it. Done.", "Photo to a calorie estimate you review.", "meal-scan-marketing.png"),
    ("orange", "Say it. Done.", "Tell it what you ate. Review, then log.", "voice-log.png"),
    ("cream", "Type it. Done.", "“pizza 300” logs in one tap.", "type-pizza-300.png"),
    ("orange", "See your week.", "Protein, calories &amp; weight trends.", "progress-weight-chart.png"),
    ("cream", "Cave Cals", "Free on iPhone.<br>Barcode scan, search &amp; logging: free.", "end"),
]

CSS = f"""
@font-face {{ font-family: Schoolbell; src: url('{BRAND}/Schoolbell-Regular.ttf'); }}
* {{ box-sizing: border-box; margin: 0; }}
html, body {{ width: {W}px; height: {H}px; overflow: hidden; }}
body {{ font-family: 'Avenir Next', 'Helvetica Neue', sans-serif; display: flex; flex-direction: column; align-items: center; text-align: center; position: relative; }}
.cream {{ background: linear-gradient(#F7EFE2, #EFE3CF); color: #2B211A; }}
.orange {{ background: linear-gradient(#CC5A20, #B24A16); color: #FFF8EF; }}
h1 {{ font-family: Schoolbell; font-weight: normal; font-size: 118px; line-height: 1.04; margin-top: 190px; }}
p {{ font-size: 42px; line-height: 1.3; margin-top: 26px; max-width: 900px; opacity: .85; font-weight: 500; }}
.phone {{ position: absolute; top: 640px; left: 50%; transform: translateX(-50%); width: 780px; border-radius: 116px; background: #1D1814; padding: 20px; box-shadow: 0 40px 90px rgba(60,30,10,.35); }}
.phone img {{ width: 100%; display: block; border-radius: 98px; }}
.art {{ width: 620px; height: 620px; border-radius: 60px; margin-top: 150px; box-shadow: 0 30px 70px rgba(60,30,10,.25); }}
.end h1 {{ margin-top: 70px; font-size: 150px; }}
.badge {{ margin-top: 70px; font-size: 44px; font-weight: 600; padding: 26px 56px; border-radius: 999px; background: #C4531B; color: #FFF8EF; }}
"""


def html_for(theme, head, sub, image):
    if image == "art":
        body = f'<h1>{head}</h1><p>{sub}</p><img class="art" style="margin-top:110px" src="{BRAND}/launch-art.png">'
    elif image == "end":
        body = (f'<img class="art" src="{BRAND}/launch-art.png"><h1>{head}</h1><p>{sub}</p>'
                '<div class="badge">Search “Cave Cals” on the App Store</div>')
        theme += " end"
    else:
        body = f'<h1>{head}</h1><p>{sub}</p><div class="phone"><img src="{RAW}/{image}"></div>'
    return f'<!doctype html><html><head><meta charset="utf-8"><style>{CSS}</style></head><body class="{theme}">{body}</body></html>'


def run(args):
    for _ in range(3):  # headless Chrome occasionally exits early
        if subprocess.run(args, capture_output=True).returncode == 0:
            return
    raise SystemExit("failed: " + " ".join(map(str, args[:3])))


def main():
    frames = HERE / "frames"
    frames.mkdir(exist_ok=True)
    stills = []
    for i, scene in enumerate(SCENES):
        page = frames / f".scene{i}.html"
        page.write_text(html_for(*scene))
        png = frames / f"scene{i}.png"
        run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--allow-file-access-from-files",
             "--force-device-scale-factor=1", f"--window-size={W},{H}", f"--screenshot={png}", page.as_uri()])
        page.unlink()
        stills.append(png)

    # Slow push-in on each still, then crossfade scenes together.
    fps = 30
    n = int(SECONDS * fps)
    inputs, filters = [], []
    for i, png in enumerate(stills):
        inputs += ["-i", str(png)]  # one frame in; zoompan emits n frames
        filters.append(f"[{i}:v]scale={W*3//2}:{H*3//2},zoompan=z='min(zoom+0.0009,1.08)':d={n}:"
                       f"x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s={W}x{H}:fps={fps},setsar=1[v{i}]")
    last = "v0"
    for i in range(1, len(stills)):
        offset = round(i * (SECONDS - FADE), 3)
        filters.append(f"[{last}][v{i}]xfade=transition=fade:duration={FADE}:offset={offset}[x{i}]")
        last = f"x{i}"
    out = HERE / "cave-cals-promo-9x16.mp4"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *inputs, "-filter_complex", ";".join(filters),
                    "-map", f"[{last}]", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "20",
                    "-movflags", "+faststart", str(out)], check=True)
    print("wrote", out)


if __name__ == "__main__":
    main()
