"""Render Instagram / TikTok photo-mode carousels (1080 x 1350) into carousels/<set>/NN.png.

Run from this folder: python3 render.py
Edit SETS to change copy. Images come from ../brand and ../app-store-screenshots/raw (real app captures).
"""
import pathlib
import subprocess

HERE = pathlib.Path(__file__).resolve().parent
BRAND = (HERE.parent / "brand").as_uri()
RAW = (HERE.parent / "app-store-screenshots" / "raw").as_uri()
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
W, H = 1080, 1350

# Each slide: (theme, title, body, image). image: None, "art", "icon:<name>", or "shot:<file>:<crop-top-%>".
SETS = {
    "5-ways-no-typing": [
        ("orange", "5 ways to log food<br>without typing", "(save this for your next cut)", "art"),
        ("cream", "1. Tap your usuals", "Quick Add learns what you eat and when. Same breakfast? One tap.", "shot:quick-add.png:0"),
        ("cream", "2. Snap your plate", "Photo to a calorie &amp; macro estimate. Review it, then log.", "shot:meal-scan-marketing.png:6"),
        ("cream", "3. Just say it", "“Two eggs, toast, big coffee.” Voice Log turns it into a food list you can check.", "icon:CaveVoice"),
        ("cream", "4. Scan the barcode", "Packaged food? Scan it. Free, no premium needed.", "icon:CaveBarcode"),
        ("cream", "5. “Hey Siri, log food”", "Log without opening the app. Foods you've logged before are instant.", "icon:CaveCheck"),
        ("orange", "Me eat.<br>App count.", "Cave Cals: free on iPhone. Link in bio.", "art"),
    ],
    "stopped-doing": [
        ("orange", "Things I stopped doing that made calorie tracking stick", "", None),
        ("cream", "Weighing every gram", "Close enough beats not tracking at all.", None),
        ("cream", "Logging at night from memory", "Log as you eat. It takes seconds.", None),
        ("cream", "Starting over every Monday", "One off day is just one day. Look at the week.", None),
        ("cream", "Panicking at daily weigh-ins", "Water and salt move the scale. Watch the weekly average.", None),
        ("cream", "Typing the same foods 400 times", "Let the app remember your usual breakfast.", None),
        ("cream", "Paying to scan barcodes", "Some apps charge for it. It should be free.", None),
        ("orange", "What I do now", "Log as I go. One-tap usuals. Check the week on Sunday.<br><br>(I use Cave Cals. It has a caveman.)", "art"),
    ],
    "zogs-rules": [
        ("orange", "Zog's rules of calorie tracking", "Cave man simple. Cave man strong.", "art"),
        ("cream", "Close enough good.", "Perfect bad. Perfect make you quit.<br><small>Zog rule #1</small>", None),
        ("cream", "Week matter.<br>Day not.", "Look at the weekly average, not today's scale.<br><small>Zog rule #2</small>", None),
        ("cream", "Protein first.", "Drumstick good.<br><small>Zog rule #3</small>", "icon:CaveMeal"),
        ("cream", "Log when eat.", "Not at night. Night brain forget.<br><small>Zog rule #4</small>", None),
        ("cream", "Same breakfast?<br>One tap.", "Zog not type.<br><small>Zog rule #5</small>", "icon:CaveLightning"),
        ("cream", "Weekend count too.", "Sorry.<br><small>Zog rule #6</small>", None),
        ("orange", "Day done.<br>Cave closed. 🔥", "Tap the button. Kitchen close.<br><small>Zog rule #7</small>", "icon:CaveCheck"),
    ],
    "app-you-dont-hate": [
        ("orange", "POV: you found a calorie app you don't hate", "", "art"),
        ("cream", "It remembers your breakfast", "Tap + and it's logged.", "shot:quick-add.png:0"),
        ("cream", "It has a caveman", "“You Eat. App Track. Weight Drop.”", "shot:01-welcome.png:40"),
        ("cream", "It shows your week", "Protein, calories, and weight trends. Not just today.", "shot:progress-weight-chart.png:12"),
        ("cream", "The basics are free", "Search, barcode scanning, manual logging. Photo and voice logging are extra.", "icon:CaveBarcode"),
        ("orange", "Cave Cals", "Free on iPhone. Link in bio.", "art"),
    ],
    "coach-weekly-recap": [
        ("orange", "How my clients send me their week", "(and why I stopped asking for screenshots)", "icon:CaveCheck"),
        ("cream", "Sunday: one page", "Averages, not daily noise.", "shot:weekly-recap-six-week-pdf.png:55"),
        ("cream", "Six weeks at a glance", "Weight trend and average calories, week by week.", "shot:weekly-recap-six-week-pdf.png:95"),
        ("cream", "Protein days, not perfect days", "We look at how many days hit protein.", "shot:progress-weight-chart.png:12"),
        ("cream", "Logging takes seconds", "Their usual foods are one tap, so they actually do it.", "shot:quick-add.png:0"),
        ("orange", "Coach code in bio", "Clients get a free month of Cave Cals+.", "icon:CaveCheck"),
    ],
}

CSS = f"""
@font-face {{ font-family: Schoolbell; src: url('{BRAND}/Schoolbell-Regular.ttf'); }}
* {{ box-sizing: border-box; margin: 0; }}
html, body {{ width: {W}px; height: {H}px; overflow: hidden; }}
body {{ font-family: 'Avenir Next', 'Helvetica Neue', sans-serif; display: flex; flex-direction: column; justify-content: center; align-items: center; padding: 90px 90px 120px; text-align: center; position: relative; }}
.cream {{ background: #F5ECDC; color: #2B211A; }}
.orange {{ background: #C4531B; color: #FFF8EF; }}
h1 {{ font-family: Schoolbell; font-weight: normal; font-size: 104px; line-height: 1.05; }}
p {{ font-size: 44px; line-height: 1.35; margin-top: 34px; font-weight: 500; opacity: .85; }}
.art {{ width: 360px; height: 360px; border-radius: 40px; margin-bottom: 50px; }}
.icon {{ width: 190px; height: 190px; object-fit: contain; margin-bottom: 50px; }}
.orange .icon {{ filter: brightness(0) invert(1); }}
.shot {{ width: 620px; height: 620px; border-radius: 42px; overflow: hidden; margin-top: 50px; border: 14px solid #1D1814; box-shadow: 0 30px 60px rgba(60,30,10,.25); }}
.shot img {{ width: 100%; display: block; }}
small {{ display: block; font-size: 32px; margin-top: 28px; opacity: .7; letter-spacing: .04em; }}
.foot {{ position: absolute; bottom: 48px; left: 0; right: 0; display: flex; justify-content: space-between; padding: 0 70px; font-size: 30px; opacity: .6; }}
"""


def slide(theme, title, body, image, index, total):
    top, bottom = "", ""
    if image == "art":
        top = f'<img class="art" src="{BRAND}/launch-art.png">'
    elif image and image.startswith("icon:"):
        top = f'<img class="icon" src="{BRAND}/orange/{image[5:]}.svg">'
    elif image and image.startswith("shot:"):
        _, name, crop = image.split(":")
        bottom = f'<div class="shot"><img style="margin-top:-{crop}%" src="{RAW}/{name}"></div>'
    body_html = f"<p>{body}</p>" if body else ""
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>{CSS}</style></head>
<body class="{theme}">{top}<h1>{title}</h1>{body_html}{bottom}
<div class="foot"><span>@cavecals</span><span>{index}/{total}</span></div></body></html>"""


def main():
    for name, slides in SETS.items():
        out = HERE / "carousels" / name
        out.mkdir(parents=True, exist_ok=True)
        for i, s in enumerate(slides, 1):
            html = out / f".{i:02d}.html"
            html.write_text(slide(*s, i, len(slides)))
            args = [CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                    "--allow-file-access-from-files", "--force-device-scale-factor=1",
                    f"--window-size={W},{H}", f"--screenshot={out / f'{i:02d}.png'}", html.as_uri()]
            for attempt in range(3):  # headless Chrome occasionally exits early
                if subprocess.run(args, capture_output=True).returncode == 0:
                    break
            else:
                raise SystemExit(f"Chrome failed on {name} slide {i}")
            html.unlink()
        print("rendered", name, len(slides), "slides")


if __name__ == "__main__":
    main()
