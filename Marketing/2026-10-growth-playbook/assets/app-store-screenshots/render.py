"""Render 1320 x 2868 App Store screenshots (6.9-inch) from real captures in raw/.

Run from this folder: python3 render.py
Needs Google Chrome. Each panel is an HTML page screenshotted headlessly.
"""
import pathlib
import subprocess

HERE = pathlib.Path(__file__).resolve().parent
BRAND = (HERE.parent / "brand").as_uri()
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
W, H = 1320, 2868

PANELS = [
    dict(file="01-hero", raw="home.png", theme="cream", art=True,
         head="Me eat.<br>App count.", sub="Calorie tracking, caveman simple."),
    dict(file="02-quick-add", raw="quick-add.png", theme="orange",
         head="Your usual foods.<br>One tap.", sub="Quick Add learns what you eat."),
    dict(file="03-snap-it", raw="meal-scan-marketing.png", theme="cream",
         head="Snap it. Done.", sub="Photo to calories &amp; macros. Review, then log."),
    dict(file="04-say-it", raw="voice-log.png", theme="orange",
         head="Say it. Done.", sub="Tell it what you ate. Review, then log."),
    dict(file="05-type-it", raw="type-pizza-300.png", theme="cream",
         head="Type it. Done.", sub="“pizza 300” logs in one tap."),
    dict(file="06-plan", raw="01-welcome.png", theme="cream",
         head="A plan in<br>one minute.", sub="Pick what to track. Get a starting target."),
    dict(file="07-progress", raw="progress-weight-chart.png", theme="orange",
         head="See your week.", sub="Calories, protein, carbs, fat &amp; weight."),
    dict(file="08-done-eating", raw="day-done.png", theme="cream",
         head="Day done.<br>Cave closed.", sub="Tap Done eating. Kitchen closed for the night.", width=780),
    dict(file="09-recap", raw="weekly-recap-six-week-pdf.png", theme="cream",
         head="One-page recap.", sub="Print it or send it to your coach."),
]

CSS = f"""
@font-face {{ font-family: Schoolbell; src: url('{BRAND}/Schoolbell-Regular.ttf'); }}
* {{ box-sizing: border-box; margin: 0; }}
html, body {{ width: {W}px; height: {H}px; overflow: hidden; }}
body {{ font-family: 'Avenir Next', 'Helvetica Neue', sans-serif; display: flex; flex-direction: column; align-items: center; position: relative; }}
body.cream {{ background: linear-gradient(#F7EFE2, #EFE3CF); color: #2B211A; }}
body.orange {{ background: linear-gradient(#CC5A20, #B24A16); color: #FFF8EF; }}
.brand {{ font-family: Schoolbell; font-size: 46px; letter-spacing: .04em; margin-top: 150px; opacity: .75; }}
h1 {{ font-family: Schoolbell; font-weight: normal; font-size: 150px; line-height: 1.02; text-align: center; margin-top: 40px; }}
p {{ font-size: 52px; line-height: 1.3; text-align: center; margin-top: 34px; max-width: 1100px; opacity: .8; font-weight: 500; }}
.phone {{ position: absolute; left: 50%; transform: translateX(-50%); width: 1010px; border-radius: 150px; background: #1D1814; padding: 26px; box-shadow: 0 60px 120px rgba(60,30,10,.35); }}
.phone img {{ width: 100%; display: block; border-radius: 126px; }}
.art {{ width: 470px; height: 470px; border-radius: 48px; margin-top: 110px; box-shadow: 0 24px 60px rgba(60,30,10,.18); }}
.fade {{ position: absolute; left: 0; right: 0; bottom: 0; height: 900px; }}
body.orange .fade {{ background: linear-gradient(rgba(178,74,22,0), #B24A16 38%); }}
"""


def page(p):
    top = 820 if "<br>" in p["head"] else 700
    header = f'<div class="brand">CAVE CALS</div>'
    if p.get("art"):
        header = f'<img class="art" src="{BRAND}/launch-art.png">'
        top += 230
    fade = '<div class="fade"></div>' if p.get("fade") else ""
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>{CSS}</style></head>
<body class="{p['theme']}">{header}<h1>{p['head']}</h1><p>{p['sub']}</p>
<div class="phone" style="top:{top + 260}px;width:{p.get('width', 1010)}px"><img src="{(HERE / 'raw' / p['raw']).as_uri()}"></div>{fade}</body></html>"""


def main():
    out = HERE / "store"
    out.mkdir(exist_ok=True)
    for p in PANELS:
        html = HERE / f".{p['file']}.html"
        html.write_text(page(p))
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                        "--allow-file-access-from-files", "--force-device-scale-factor=1",
                        f"--window-size={W},{H}", f"--screenshot={out / (p['file'] + '.png')}",
                        html.as_uri()], check=True, capture_output=True)
        html.unlink()
        print("rendered", p["file"])


if __name__ == "__main__":
    main()
