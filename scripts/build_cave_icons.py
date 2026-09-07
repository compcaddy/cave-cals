"""Trace the approved artwork into template vector PDFs and editable SVGs.
Requires ImageMagick and Potrace. No AI call or credentials required.
"""
from pathlib import Path
import subprocess,json,tempfile
root=Path(__file__).resolve().parent.parent
source=root/'Artwork/CaveIcons/approved-preview.png'
# Individual glyph bounds in the approved 1536 x 1024 concept sheet.
icons={'CaveBarcode':'200x178+230+245','CaveVoice':'205x182+548+245',
       'CaveMeal':'197x175+863+245','CaveSearch':'108x116+1159+279',
       'CavePlus':'98x111+1335+289','CaveSlash':'77x141+1265+265'}
catalog=root/'Shared/CaveIcons.xcassets';catalog.mkdir(exist_ok=True)
(catalog/'Contents.json').write_text(json.dumps({'info':{'author':'xcode','version':1}},indent=2))
with tempfile.TemporaryDirectory() as temp:
    for name,crop in icons.items():
        bitmap=Path(temp)/(name+'.pbm')
        subprocess.run(['magick',str(source),'-crop',crop,'+repage','-colorspace','Gray','-threshold','55%','-trim','+repage',str(bitmap)],check=True)
        asset=catalog/(name+'.imageset');asset.mkdir(exist_ok=True)
        # Keep the silhouette's hand-drawn edge while removing tiny isolated flecks.
        for kind,dest in [('svg',root/'Artwork/CaveIcons'/f'{name}.svg'),('pdf',asset/f'{name}.pdf')]:
            subprocess.run(['potrace',str(bitmap),'-b',kind,'--tight','-t','4','-O','0.3','-W','64pt','-o',str(dest)],check=True)
        (asset/'Contents.json').write_text(json.dumps({'images':[{'filename':name+'.pdf','idiom':'universal'}],'info':{'author':'xcode','version':1},'properties':{'preserves-vector-representation':True,'template-rendering-intent':'template'}},indent=2))
