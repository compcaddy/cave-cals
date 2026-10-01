"""Render short 9:16 "Zog says" brand clips (about 6 seconds each) into zog-says/.

Run from this folder: python3 render_zog_says.py
Needs Google Chrome and ffmpeg. Each clip builds up in three beats: the caveman, line one, line two.
Silent on purpose; add a sound in TikTok / Instagram when posting.
"""
import pathlib
import subprocess

HERE = pathlib.Path(__file__).resolve().parent
BRAND = (HERE.parent / "brand").as_uri()
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
W, H = 1080, 1920

CLIPS = {
    "me-eat-app-count": ("orange", "Me eat.", "App count."),
    "same-breakfast": ("cream", "Same breakfast?", "One tap. Zog not type."),
    "barcode-free": ("orange", "Barcode scan.", "Free. Like fire. 🔥"),
    "day-done": ("cream", "Day done.", "Cave closed."),
    "close-enough": ("orange", "Close enough good.", "Perfect make you quit."),
    "protein-first": ("cream", "Protein first.", "Drumstick good. 🍗"),
}

CSS = f"""
@font-face {{ font-family: Schoolbell; src: url('{BRAND}/Schoolbell-Regular.ttf'); }}
* {{ box-sizing: border-box; margin: 0; }}
html, body {{ width: {W}px; height: {H}px; overflow: hidden; }}
body {{ display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 60px; text-align: center; font-family: Schoolbell, cursive; padding: 0 70px; }}
.cream {{ background: #F5ECDC; color: #2B211A; }}
.orange {{ background: #C4531B; color: #FFF8EF; }}
img {{ width: 640px; height: 640px; border-radius: 64px; box-shadow: 0 30px 80px rgba(40,20,5,.25); }}
.lines {{ min-height: 420px; display: flex; flex-direction: column; gap: 18px; }}
h1 {{ font-weight: 400; font-size: 136px; line-height: 1.02; }}
h2 {{ font-weight: 400; font-size: 92px; line-height: 1.05; opacity: .92; }}
.hide {{ visibility: hidden; }}
.handle {{ position: absolute; bottom: 110px; font-family: 'Avenir Next', sans-serif; font-size: 38px; opacity: .65; }}
"""


def frame(theme, one, two, beat):
    return (f'<!doctype html><html><head><meta charset="utf-8"><style>{CSS}</style></head><body class="{theme}">'
            f'<img src="{BRAND}/launch-art.png"><div class="lines">'
            f'<h1 class="{"" if beat >= 1 else "hide"}">{one}</h1><h2 class="{"" if beat >= 2 else "hide"}">{two}</h2>'
            f'</div><div class="handle">@cavecals · free on iPhone</div></body></html>')


def shoot(html_path, png_path):
    args = [CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--allow-file-access-from-files",
            "--force-device-scale-factor=1", f"--window-size={W},{H}", f"--screenshot={png_path}", html_path.as_uri()]
    for _ in range(3):  # headless Chrome occasionally exits early
        if subprocess.run(args, capture_output=True).returncode == 0:
            return
    raise SystemExit(f"Chrome failed on {html_path.name}")


def main():
    out = HERE / "zog-says"
    tmp = out / ".frames"
    tmp.mkdir(parents=True, exist_ok=True)
    durations = [1.2, 1.6, 3.2]  # caveman, line one, line two (holds)
    for name, (theme, one, two) in CLIPS.items():
        pngs = []
        for beat in range(3):
            page = tmp / f"{name}-{beat}.html"
            page.write_text(frame(theme, one, two, beat))
            png = tmp / f"{name}-{beat}.png"
            shoot(page, png)
            page.unlink()
            pngs.append(png)
        inputs, filters, offset = [], [], 0.0
        for i, (png, d) in enumerate(zip(pngs, durations)):
            inputs += ["-loop", "1", "-t", str(d + 0.25), "-framerate", "30", "-i", str(png)]
            filters.append(f"[{i}:v]format=yuv420p,setsar=1[v{i}]")
        filters.append(f"[v0][v1]xfade=transition=fade:duration=0.25:offset={durations[0]}[x1]")
        filters.append(f"[x1][v2]xfade=transition=fade:duration=0.25:offset={durations[0] + durations[1]}[x2]")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *inputs, "-filter_complex", ";".join(filters),
                        "-map", "[x2]", "-c:v", "libx264", "-crf", "20", "-pix_fmt", "yuv420p",
                        "-movflags", "+faststart", str(out / f"{name}.mp4")], check=True)
        for png in pngs:
            png.unlink()
        print("wrote", name)
    tmp.rmdir()


if __name__ == "__main__":
    main()
