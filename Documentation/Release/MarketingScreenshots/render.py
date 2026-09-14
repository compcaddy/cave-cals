from PIL import Image, ImageDraw, ImageFont, ImageFilter
from pathlib import Path
import json, math
ROOT=Path(__file__).resolve().parent
W,H=1320,2868
BLUE=(0,122,255)
FONT='/System/Library/Fonts/Avenir Next.ttc'
def font(size,bold=False): return ImageFont.truetype(FONT,size,index=0 if bold else 5)
def center(d,text,y,size,color,bold=False):
 f=font(size,bold); b=d.textbbox((0,0),text,font=f); d.text(((W-(b[2]-b[0]))/2,y-b[1]),text,font=f,fill=color)
def rounded_mask(size,r):
 m=Image.new('L',size); ImageDraw.Draw(m).rounded_rectangle((0,0,size[0]-1,size[1]-1),r,fill=255); return m
slides=[
 dict(file='01-hero.png',raw='01-zog.png',lines=['Calorie tracking.','Caveman simple.'],sub='Meet Zog. Your everyday calorie companion.',top=(0,122,255),bottom=(0,78,214),ink='white',muted=(215,233,255),tag='MEET CAVE CALS'),
 dict(file='02-daily-diary.png',raw='02-diary.png',lines=['Your day.','At a glance.'],sub='Calories logged. Calories left. All right here.',top=(249,252,255),bottom=(216,235,255),ink=(14,31,55),muted=(71,95,122),tag='YOUR DAILY DIARY'),
 dict(file='03-meal-scan.png',raw='03-meal-scan.png',lines=['Snap a meal.','Skip the typing.'],sub='AI calorie estimates you can review and log.',top=(248,251,255),bottom=(221,239,255),ink=(14,31,55),muted=(71,95,122),tag='AI MEAL SCAN • PAID FEATURE'),
 dict(file='04-quick-log.png',raw='04-quick-log.png',lines=['Your usuals.','Logged faster.'],sub='Tap a suggestion. Get on with your day.',top=(15,31,54),bottom=(3,15,34),ink='white',muted=(180,204,232),tag='QUICK LOGGING • FREE')]
for i,s in enumerate(slides):
 im=Image.new('RGB',(W,H)); pix=im.load()
 for y in range(H):
  t=y/(H-1); c=tuple(round(s['top'][k]*(1-t)+s['bottom'][k]*t) for k in range(3))
  ImageDraw.Draw(im).line((0,y,W,y),fill=c)
 # Large quiet circular geometry, used consistently through the series.
 glow=Image.new('RGBA',(W,H)); gd=ImageDraw.Draw(glow)
 gd.ellipse((-430,1060,1750,3240),outline=(255,255,255,20 if i in [0,3] else 110),width=4)
 gd.ellipse((-240,1250,1560,3050),outline=(255,255,255,18 if i in [0,3] else 100),width=3)
 im=Image.alpha_composite(im.convert('RGBA'),glow)
 d=ImageDraw.Draw(im)
 center(d,'CAVE CALS',115,34,s['muted'],True)
 for j,line in enumerate(s['lines']): center(d,line,244+j*143,112,s['ink'],True)
 center(d,s['sub'],569,39,s['muted'])
 # Actual, unchanged app capture inside a restrained device frame.
 capture=Image.open(ROOT/'raw'/s['raw']).convert('RGB')
 sw=876; sh=round(sw*capture.height/capture.width)
 x=(W-sw)//2; y=790
 shadow=Image.new('RGBA',(W,H)); sd=ImageDraw.Draw(shadow)
 sd.rounded_rectangle((x-22,y+24,x+sw+22,y+sh+48),radius=116,fill=(0,13,40,105))
 im=Image.alpha_composite(im,shadow.filter(ImageFilter.GaussianBlur(35)))
 d=ImageDraw.Draw(im)
 d.rounded_rectangle((x-23,y-23,x+sw+23,y+sh+23),radius=115,fill=(30,36,44),outline=(115,130,149),width=3)
 d.rounded_rectangle((x-14,y-14,x+sw+14,y+sh+14),radius=108,fill=(5,7,11))
 capture=capture.resize((sw,sh),Image.Resampling.LANCZOS)
 im.paste(capture,(x,y),rounded_mask((sw,sh),98))
 d=ImageDraw.Draw(im)
 # Discreet device controls; no UI content is redrawn.
 d.rounded_rectangle((x-28,y+315,x-22,y+412),radius=3,fill=(70,80,94))
 d.rounded_rectangle((x+sw+23,y+359,x+sw+29,y+502),radius=3,fill=(70,80,94))
 center(d,s['tag'],708,26,s['muted'],True)
 for j in range(4):
  cx=W//2+(j-1.5)*30; cy=2796
  d.ellipse((cx-4,cy-4,cx+4,cy+4),fill=s['ink'] if i==j else s['muted'])
 im.convert('RGB').save(ROOT/s['file'],optimize=True)
# Compact visual QA contact sheet.
thumbs=[]
for s in slides:
 im=Image.open(ROOT/s['file']); im.thumbnail((330,717)); thumbs.append(im)
cs=Image.new('RGB',(1320,717),'white')
for i,im in enumerate(thumbs):cs.paste(im,(i*330,0))
cs.save(ROOT/'contact-sheet.jpg',quality=94)
(ROOT/'manifest.json').write_text(json.dumps({'dimensions':[W,H],'source':'Actual iPhone 15 Pro simulator captures; sample diary stored in memory via existing --screenshots mode. Meal photo selected through the real Photos picker.','slides':slides},indent=2))
