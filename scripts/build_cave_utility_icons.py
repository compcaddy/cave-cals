"""Build hand-drawn utility vectors to complement the approved cave icon set.
Requires the workspace Sharp dependency, ImageMagick, and Potrace.
"""
from pathlib import Path
import json, subprocess, tempfile
root = Path(__file__).resolve().parent.parent
# Deliberately uneven contours and broad strokes remain legible at toolbar sizes.
paths = {
'Pencil': 'M12 44 L17 31 L42 7 Q46 5 50 10 L55 16 Q57 19 53 23 L29 47 L12 52 Z M18 32 L29 44 M39 11 L50 23 M13 49 L20 47',
'ChevronLeft': 'M41 10 L22 30 Q20 32 23 35 L41 53',
'ChevronRight': 'M22 10 L41 30 Q44 32 41 35 L22 53',
'ArrowRight': 'M9 33 L52 31 M36 13 L53 31 L37 51',
'ArrowUpLeft': 'M48 50 L15 16 M15 38 L14 14 L39 15',
'Camera': 'M8 21 L19 20 L24 12 L40 13 L45 21 L56 22 L55 51 L9 50 Z M41 35 Q43 46 32 46 Q20 45 22 34 Q23 24 33 25 Q41 26 41 35',
'Circle': 'M32 7 C49 6 57 19 56 33 C56 49 44 58 29 56 C14 56 6 46 7 30 C7 15 17 6 32 7 Z',
'Check': 'M32 7 C49 6 57 19 56 33 C56 49 44 58 29 56 C14 56 6 46 7 30 C7 15 17 6 32 7 Z M19 32 L28 42 L46 23',
'Stop': 'M32 7 C49 6 57 19 56 33 C56 49 44 58 29 56 C14 56 6 46 7 30 C7 15 17 6 32 7 Z M24 24 L41 23 L40 41 L23 40 Z',
'Cloud': 'M17 49 Q5 48 7 36 Q8 28 18 28 Q16 11 32 12 Q45 11 47 27 Q58 27 57 39 Q57 50 45 49 Z',
'Phone': 'M21 7 L45 8 Q49 8 48 13 L47 53 Q47 57 42 57 L20 56 Q16 56 17 50 L17 12 Q17 7 21 7 Z M28 15 L37 15 M30 48 L35 48',
'Warning': 'M30 9 Q32 5 35 10 L58 51 Q60 56 54 56 L9 55 Q4 55 7 50 Z M32 23 L33 37 M33 46 L33 47',
'Gear': 'M26 7 L38 8 L40 16 L46 19 L54 17 L59 28 L52 33 L51 40 L56 47 L47 55 L40 50 L33 52 L29 59 L18 54 L19 46 L14 41 L6 40 L6 28 L14 25 L18 19 L17 11 Z M40 31 Q42 41 32 43 Q22 43 22 33 Q21 23 31 23 Q40 22 40 31 Z',
}
with tempfile.TemporaryDirectory() as temp:
    for key, path in paths.items():
        name = 'Cave' + key
        svg = root / 'Artwork/CaveIcons' / (name + '.svg')
        stroke_width = 4.8 if key == 'Pencil' else 5.5
        svg.write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64"><path d="{path}" fill="none" stroke="black" stroke-width="{stroke_width}" stroke-linecap="round" stroke-linejoin="round"/></svg>\n')
        pbm = Path(temp) / (name + '.pbm')
        png = Path(temp) / (name + '.png')
        # Sharp uses librsvg; ImageMagick's SVG delegate can silently output blank images.
        subprocess.run(['node', '-e',
            "require('sharp')(process.argv[1], {density:576}).flatten({background:'#ffffff'}).png().toFile(process.argv[2]).catch(e=>{console.error(e);process.exit(1)})",
            str(svg), str(png)], cwd=root, check=True)
        subprocess.run(['magick',str(png),'-threshold','55%',str(pbm)],check=True)
        ink_mean = float(subprocess.check_output(['magick',str(pbm),'-format','%[fx:mean]','info:'], text=True))
        if not 0.05 < ink_mean < 0.95:
            raise RuntimeError(f'{name}: blank or invalid artwork (mean={ink_mean})')
        asset = root / 'Shared/CaveIcons.xcassets' / (name + '.imageset')
        asset.mkdir(exist_ok=True)
        subprocess.run(['potrace',str(pbm),'-b','pdf','-W','64pt','-o',str(asset/(name+'.pdf'))],check=True)
        (asset/'Contents.json').write_text(json.dumps({'images':[{'filename':name+'.pdf','idiom':'universal'}],'info':{'author':'xcode','version':1},'properties':{'preserves-vector-representation':True,'template-rendering-intent':'template'}},indent=2))
