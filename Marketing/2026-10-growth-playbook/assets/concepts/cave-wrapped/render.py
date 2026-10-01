"""Design mock of the proposed December "Cave Wrapped" cards (1080 x 1920). SAMPLE numbers only.

Run from this folder: python3 render.py   (needs Google Chrome)
See 10-Retention-and-Viral-Loops.md §1A and 14-Product-Growth-Specs.md §8.
"""
import pathlib, subprocess

HERE = pathlib.Path(__file__).resolve().parent
BRAND = (HERE.parents[1] / "brand").as_uri()
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
CARDS = [
    ("orange", "Your year<br>in the cave", "2026", "art"),
    ("cream", "247", "days logged. Cave strong.", "CaveCheck"),
    ("orange", "Greek yogurt", "Your #1 food. Logged 183 times. Zog approves.", "CaveMeal"),
    ("cream", "7:42 AM", "Breakfast o'clock. Every. Single. Day.", "CaveLightning"),
    ("orange", "142 g", "Best protein day: March 3. Drumstick legend.", "CaveMeal"),
    ("cream", "96×", "Done eating. Cave closed. 🔥", "CaveCheck"),
]
CSS = f"""
@font-face {{ font-family: Schoolbell; src: url('{BRAND}/Schoolbell-Regular.ttf'); }}
* {{ box-sizing: border-box; margin: 0; }}
html, body {{ width: 1080px; height: 1920px; overflow: hidden; }}
body {{ display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 50px; text-align: center; padding: 0 90px; font-family: Schoolbell, cursive; position: relative; }}
.cream {{ background: #F5ECDC; color: #2B211A; }} .orange {{ background: #C4531B; color: #FFF8EF; }}
h1 {{ font-weight: 400; font-size: 190px; line-height: 1; }}
p {{ font-size: 70px; line-height: 1.15; opacity: .92; }}
.art {{ width: 560px; height: 560px; border-radius: 60px; }}
.icon {{ width: 220px; height: 220px; }} .orange .icon {{ filter: brightness(0) invert(1); }}
.top, .foot {{ position: absolute; left: 0; right: 0; font-family: 'Avenir Next', sans-serif; font-size: 34px; opacity: .7; }}
.top {{ top: 90px; letter-spacing: .2em; text-transform: uppercase; font-weight: 700; }}
.foot {{ bottom: 90px; }}
.sample {{ position: absolute; top: 150px; font-family: 'Avenir Next', sans-serif; font-size: 26px; padding: 6px 16px; border-radius: 999px; border: 2px solid currentColor; opacity: .6; }}
"""
for i, (theme, big, small, img) in enumerate(CARDS, 1):
    pic = f'<img class="art" src="{BRAND}/launch-art.png">' if img == "art" else f'<img class="icon" src="{BRAND}/orange/{img}.svg">'
    html = HERE / f".card{i}.html"
    html.write_text(f'<!doctype html><html><head><meta charset="utf-8"><style>{CSS}</style></head><body class="{theme}">'
                    f'<div class="top">Cave Wrapped 2026</div><div class="sample">sample data</div>{pic}<h1>{big}</h1><p>{small}</p>'
                    f'<div class="foot">Cave Cals · free on iPhone</div></body></html>')
    args = [CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--allow-file-access-from-files",
            "--force-device-scale-factor=1", "--window-size=1080,1920", f"--screenshot={HERE / f'{i:02d}.png'}", html.as_uri()]
    for _ in range(3):
        if subprocess.run(args, capture_output=True).returncode == 0:
            break
    html.unlink()
    print("card", i)
