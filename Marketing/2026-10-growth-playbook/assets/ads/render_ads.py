"""Render static 4:5 feed ads (1080 x 1350) for Instagram / Facebook / TikTok image ads into this folder.

Run from this folder: python3 render_ads.py   (needs Google Chrome)
Copy follows the ad-policy guardrails in 07-Paid-Ads.md: no weight-loss promises, no body images, no competitor names.
Each ad uses a real app capture from ../app-store-screenshots/raw.
"""
import pathlib
import subprocess

HERE = pathlib.Path(__file__).resolve().parent
BRAND = (HERE.parent / "brand").as_uri()
RAW = (HERE.parent / "app-store-screenshots" / "raw").as_uri()
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
W, H = 1080, 1350

# (file, theme, headline, subline, image, crop-% of width to shift the capture up)
ADS = [
    ("ad-01-barcode-free", "orange", "Why are you paying<br>to scan a barcode?", "Barcode scan, food search &amp; logging: free.", "icon:CaveBarcode", 0),
    ("ad-02-me-eat", "cream", "Me eat.<br>App count.", "Calorie tracking, caveman simple.", "art", 0),
    ("ad-03-same-breakfast", "cream", "Same breakfast?<br>One tap.", "Cave Cals learns the foods you actually eat.", "quick-add.png", 8),
    ("ad-04-snap-say", "orange", "Snap it. Say it.<br>Done.", "Photo or voice to a calorie estimate you review.", "meal-scan-marketing.png", 12),
    ("ad-05-protein", "cream", "Stop guessing<br>your protein.", "Set a goal. Watch one bar.", "home.png", 12),
    ("ad-06-day-done", "orange", "Day done.<br>Cave closed.", "Tap Done eating. Kitchen closed for the night.", "day-done.png", 94),
]

CSS = f"""
@font-face {{ font-family: Schoolbell; src: url('{BRAND}/Schoolbell-Regular.ttf'); }}
* {{ box-sizing: border-box; margin: 0; }}
html, body {{ width: {W}px; height: {H}px; overflow: hidden; }}
body {{ font-family: 'Avenir Next', 'Helvetica Neue', sans-serif; display: flex; flex-direction: column; align-items: center; text-align: center; padding: 80px 70px 0; position: relative; }}
.cream {{ background: #F5ECDC; color: #2B211A; }} .orange {{ background: #C4531B; color: #FFF8EF; }}
h1 {{ font-family: Schoolbell; font-weight: 400; font-size: 100px; line-height: 1.02; }}
p {{ font-size: 40px; line-height: 1.3; margin-top: 22px; font-weight: 500; opacity: .88; }}
.shot {{ width: 700px; height: 820px; border-radius: 52px 52px 0 0; overflow: hidden; border: 16px solid #1D1814; border-bottom: 0; box-shadow: 0 30px 60px rgba(40,20,5,.28); position: absolute; bottom: 0; left: 190px; }}
.shot img {{ width: 100%; display: block; }}
.art {{ width: 600px; height: 600px; border-radius: 60px; margin-top: 70px; }}
.icon {{ width: 460px; height: 460px; margin-top: 120px; }}
.orange .icon {{ filter: brightness(0) invert(1); }}
.cta {{ position: absolute; top: 24px; right: 28px; font-size: 26px; font-weight: 700; padding: 10px 20px; border-radius: 999px; }}
.cream .cta {{ background: #C4531B; color: #FFF8EF; }} .orange .cta {{ background: #FFF8EF; color: #C4531B; }}
.brand {{ position: absolute; top: 30px; left: 34px; font-family: Schoolbell; font-size: 32px; opacity: .8; }}
"""


def main():
    for name, theme, head, sub, image, crop in ADS:
        if image == "art":
            visual = f'<img class="art" src="{BRAND}/launch-art.png">'
        elif image.startswith("icon:"):
            visual = f'<img class="icon" src="{BRAND}/orange/{image[5:]}.svg">'
        else:
            visual = f'<div class="shot"><img style="margin-top:-{crop}%" src="{RAW}/{image}"></div>'
        page = HERE / f".{name}.html"
        page.write_text(f'<!doctype html><html><head><meta charset="utf-8"><style>{CSS}</style></head><body class="{theme}">'
                        f'<div class="brand">Cave Cals</div><div class="cta">Free on iPhone</div>'
                        f'<h1>{head}</h1><p>{sub}</p>{visual}</body></html>')
        args = [CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--allow-file-access-from-files",
                "--force-device-scale-factor=1", f"--window-size={W},{H}", f"--screenshot={HERE / (name + '.png')}", page.as_uri()]
        for _ in range(3):  # headless Chrome occasionally exits early
            if subprocess.run(args, capture_output=True).returncode == 0:
                break
        page.unlink()
        print("rendered", name)


if __name__ == "__main__":
    main()
