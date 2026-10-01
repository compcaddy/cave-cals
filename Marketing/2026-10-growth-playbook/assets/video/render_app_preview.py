"""Build an App Store app preview (886 x 1920, 30 fps, ~25 s) from real app captures.

Run from this folder: python3 render_app_preview.py   (needs Google Chrome and ffmpeg)
Apple's rules for app previews: show the app itself (screen captures), text overlays are fine, no device frames,
no people holding phones, 15-30 seconds. The first seconds autoplay muted in search results, so the caption carries it.
Upload in App Store Connect under the 6.9-inch iPhone size (886 x 1920 portrait). Apple also needs a silent or licensed
audio track; this file has a silent AAC track so it uploads cleanly.
"""
import pathlib
import subprocess

HERE = pathlib.Path(__file__).resolve().parent
BRAND = (HERE.parent / "brand").as_uri()
RAW = (HERE.parent / "app-store-screenshots" / "raw").as_uri()
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
W, H = 886, 1920
SECONDS, FADE, FPS = 3.4, 0.35, 30

SCENES = [
    ("home.png", "Me eat. App count."),
    ("quick-add.png", "Your usuals. One tap."),
    ("meal-scan-marketing.png", "Snap it. Done."),
    ("voice-log.png", "Say it. Done."),
    ("type-pizza-300.png", "Type it. Done."),
    ("progress-weight-chart.png", "See your week."),
    ("day-done.png", "Day done. Cave closed."),
    ("01-welcome.png", "Plan in one minute. Free."),
]

CSS = f"""
@font-face {{ font-family: Schoolbell; src: url('{BRAND}/Schoolbell-Regular.ttf'); }}
* {{ box-sizing: border-box; margin: 0; }}
html, body {{ width: {W}px; height: {H}px; overflow: hidden; background: #F5ECDC; }}
img {{ position: absolute; inset: 0; width: {W}px; height: {H}px; object-fit: cover; }}
.cap {{ position: absolute; left: 40px; right: 40px; top: 120px; background: #C4531B; color: #FFF8EF; border-radius: 40px;
        padding: 26px 30px; text-align: center; font-family: Schoolbell, cursive; font-size: 74px; line-height: 1.05;
        box-shadow: 0 20px 50px rgba(40,20,5,.3); }}
"""


def run(args):
    for _ in range(3):  # headless Chrome occasionally exits early
        if subprocess.run(args, capture_output=True).returncode == 0:
            return
    raise SystemExit("failed: " + str(args[-1]))


def main():
    tmp = HERE / ".preview-frames"
    tmp.mkdir(exist_ok=True)
    stills = []
    for i, (raw, caption) in enumerate(SCENES):
        page = tmp / f"s{i}.html"
        page.write_text(f'<!doctype html><html><head><meta charset="utf-8"><style>{CSS}</style></head><body>'
                        f'<img src="{RAW}/{raw}"><div class="cap">{caption}</div></body></html>')
        png = tmp / f"s{i}.png"
        run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--allow-file-access-from-files",
             "--force-device-scale-factor=1", f"--window-size={W},{H}", f"--screenshot={png}", page.as_uri()])
        page.unlink()
        stills.append(png)
    n = int(SECONDS * FPS)
    inputs, filters = [], []
    for i, png in enumerate(stills):
        inputs += ["-i", str(png)]
        filters.append(f"[{i}:v]scale={W * 3 // 2}:{H * 3 // 2},zoompan=z='min(zoom+0.0006,1.05)':d={n}:"
                       f"x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s={W}x{H}:fps={FPS},setsar=1[v{i}]")
    last = "v0"
    for i in range(1, len(stills)):
        filters.append(f"[{last}][v{i}]xfade=transition=fade:duration={FADE}:offset={round(i * (SECONDS - FADE), 3)}[x{i}]")
        last = f"x{i}"
    out = HERE / "app-store-preview-886x1920.mp4"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *inputs, "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo",
                    "-filter_complex", ";".join(filters), "-map", f"[{last}]", "-map", f"{len(stills)}:a", "-shortest",
                    "-c:v", "libx264", "-profile:v", "high", "-pix_fmt", "yuv420p", "-r", str(FPS), "-crf", "18",
                    "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", str(out)], check=True)
    for png in stills:
        png.unlink()
    tmp.rmdir()
    print("wrote", out)


if __name__ == "__main__":
    main()
