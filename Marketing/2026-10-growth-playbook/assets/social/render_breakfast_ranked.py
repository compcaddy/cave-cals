"""Render the "Calories in every fast-food breakfast (ranked)" slideshow.

Run from this folder: python3 render_breakfast_ranked.py   (needs Google Chrome)
Writes carousels/fast-food-breakfast-ranked/4x5/NN.png (Instagram, 1080 x 1350)
and .../9x16/NN.png (TikTok photo mode, 1080 x 1920).

Calories are each chain's published US numbers as of October 2026 (see SOURCES in POSTING.md).
No logos or food photos: chain names in text only.
"""
import pathlib
import subprocess

HERE = pathlib.Path(__file__).resolve().parent
BRAND = (HERE.parent / "brand").as_uri()
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
OUT = HERE / "carousels" / "fast-food-breakfast-ranked"
DAY = 2000  # reference day for the bar

# Lowest to highest, so the biggest lands last. (chain, item, calories, quip)
ITEMS = [
    ("Starbucks", "Double-Smoked Bacon, Cheddar &amp; Egg Sandwich", 500, "The “light” one.<br>Still a quarter of your day."),
    ("Sonic", "SuperSONIC Breakfast Burrito", 590, "Tater tots. Inside burrito."),
    ("Taco Bell", "Breakfast Crunchwrap (bacon)", 660, "Hash brown inside.<br>Crunch has a price."),
    ("Dunkin’", "Sausage, Egg &amp; Cheese on a Croissant", 700, "Croissant mostly butter.<br>Good butter. Still butter."),
    ("Wendy’s", "Breakfast Baconator", 730, "Burger. But morning."),
    ("Chick-fil-A", "Hash Brown Scramble Burrito (spicy chicken)", 740, "Two breakfasts.<br>One tortilla."),
    ("Burger King", "Egg-Normous Burrito", 800, "Name not lie."),
    ("Hardee’s", "Monster Biscuit", 820, "Bacon. Sausage. Ham.<br>Monster is accurate."),
    ("Jack in the Box", "Grande Sausage Breakfast Burrito", 1040, "Half your day.<br>Before 9 AM."),
    ("McDonald’s", "Big Breakfast with Hotcakes", 1340, "Two-thirds of your day.<br>And that’s before the coffee."),
]

SIZES = {"4x5": (1080, 1350), "9x16": (1080, 1920)}


def css(w, h):
    tall = h > 1500
    return f"""
@font-face {{ font-family: Schoolbell; src: url('{BRAND}/Schoolbell-Regular.ttf'); }}
* {{ box-sizing: border-box; margin: 0; }}
html, body {{ width: {w}px; height: {h}px; overflow: hidden; }}
body {{ font-family: 'Avenir Next', 'Helvetica Neue', sans-serif; display: flex; flex-direction: column;
  justify-content: center; align-items: center; text-align: center; padding: {200 if tall else 90}px 90px {260 if tall else 130}px; position: relative; }}
.cream {{ background: #F5ECDC; color: #2B211A; }}
.orange {{ background: #C4531B; color: #FFF8EF; }}
.hand {{ font-family: Schoolbell; font-weight: normal; }}
h1 {{ font-size: {118 if tall else 108}px; line-height: 1.04; }}
h1 em {{ font-style: normal; color: #C4531B; }}
.orange h1 em {{ color: #FFE2C4; }}
.lede {{ font-size: 44px; line-height: 1.35; margin-top: 34px; font-weight: 500; opacity: .85; }}
.rank {{ font-size: 64px; color: #C4531B; letter-spacing: .02em; }}
.orange .rank {{ color: #FFE2C4; }}
.chain {{ font-size: 40px; font-weight: 700; letter-spacing: .14em; text-transform: uppercase; margin-top: 10px; opacity: .7; }}
.item {{ font-size: 50px; font-weight: 600; line-height: 1.2; margin-top: 18px; max-width: 880px; }}
.cals {{ font-size: {250 if tall else 220}px; line-height: 1; margin-top: {60 if tall else 34}px; }}
.cals small {{ font-size: 64px; margin-left: 10px; }}
.bar {{ width: 820px; height: 34px; border-radius: 17px; border: 4px solid currentColor; margin-top: {50 if tall else 30}px; overflow: hidden; opacity: .95; }}
.bar i {{ display: block; height: 100%; background: #C4531B; border-radius: 0 12px 12px 0; }}
.orange .bar i {{ background: #FFF8EF; }}
.barlabel {{ font-size: 34px; font-weight: 600; margin-top: 16px; opacity: .7; }}
.quip {{ font-size: {72 if tall else 64}px; line-height: 1.15; margin-top: {80 if tall else 46}px; }}
.art {{ width: {380 if tall else 330}px; height: {380 if tall else 330}px; border-radius: 44px; margin-bottom: 50px; }}
.icon {{ width: 200px; height: 200px; margin-bottom: 40px; }}
.orange .icon {{ filter: brightness(0) invert(1); }}
.note {{ font-size: 28px; opacity: .6; margin-top: 40px; line-height: 1.4; }}
.foot {{ position: absolute; bottom: {120 if tall else 48}px; left: 0; right: 0; display: flex; justify-content: space-between; padding: 0 70px; font-size: 30px; opacity: .6; }}
"""


def bar(cals):
    pct = round(cals / DAY * 100)
    return (f'<div class="bar"><i style="width:{min(pct, 100)}%"></i></div>'
            f'<div class="barlabel">{pct}% of a {DAY:,}-calorie day</div>')


def slides():
    n = len(ITEMS)
    out = [("orange", f"""<img class="icon" src="{BRAND}/orange/CaveMeal.svg">
<h1 class="hand">Calories in every<br>fast-food breakfast<br><em>(ranked)</em></h1>
<p class="lede">The biggest breakfast at {n} chains.<br>Lowest to highest.</p>""")]
    for i, (chain, item, cals, quip) in enumerate(ITEMS):
        rank = n - i
        theme = "orange" if rank == 1 else "cream"
        out.append((theme, f"""<div class="rank hand">#{rank}</div>
<div class="chain">{chain}</div><div class="item">{item}</div>
<div class="cals hand">{cals:,}<small>cal</small></div>{bar(cals)}
<div class="quip hand">{quip}</div>"""))
    mcmuffin, biggest = 310, ITEMS[-1][2]
    out.append(("cream", f"""<div class="rank hand">Bonus: lightest pick</div>
<div class="chain">McDonald’s</div><div class="item">Egg McMuffin</div>
<div class="cals hand">{mcmuffin}<small>cal</small></div>{bar(mcmuffin)}
<div class="quip hand">{biggest / mcmuffin:.1f} Egg McMuffins<br>= one Big Breakfast<br>with Hotcakes.</div>"""))
    out.append(("orange", f"""<img class="art" src="{BRAND}/launch-art.png">
<h1 class="hand">Me eat.<br>App count.</h1>
<p class="lede">Log your usual breakfast in one tap.<br>Cave Cals: free on iPhone. Link in bio.</p>
<p class="note">Calories from each chain’s published US nutrition info, Oct. 2026.<br>Your order may vary.</p>"""))
    return out


def main():
    pages = slides()
    for label, (w, h) in SIZES.items():
        out = OUT / label
        out.mkdir(parents=True, exist_ok=True)
        for i, (theme, body) in enumerate(pages, 1):
            html = out / f".{i:02d}.html"
            html.write_text(f'<!doctype html><html><head><meta charset="utf-8"><style>{css(w, h)}</style></head>'
                            f'<body class="{theme}">{body}<div class="foot"><span>@cavecals</span>'
                            f'<span>{i}/{len(pages)}</span></div></body></html>')
            args = [CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                    "--allow-file-access-from-files", "--force-device-scale-factor=1",
                    f"--window-size={w},{h}", f"--screenshot={out / f'{i:02d}.png'}", html.as_uri()]
            for _ in range(3):  # headless Chrome occasionally exits early
                if subprocess.run(args, capture_output=True).returncode == 0:
                    break
            else:
                raise SystemExit(f"Chrome failed on {label} slide {i}")
            html.unlink()
        print("rendered", label, len(pages), "slides")


if __name__ == "__main__":
    main()
