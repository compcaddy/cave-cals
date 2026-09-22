"""Build the owner's review packet. Run with the bundled Python/reportlab runtime."""
from pathlib import Path
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor, white
from reportlab.platypus import Paragraph
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.utils import ImageReader
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/pdf/cave-cals-onboarding-and-launch-review.pdf'
OUT.parent.mkdir(parents=True, exist_ok=True)
ASSETS = ROOT / 'Marketing/2026-09-launch'
FONT = ROOT / 'App/Fonts/Schoolbell-Regular.ttf'
if FONT.exists():
    pdfmetrics.registerFont(TTFont('Cave', str(FONT)))
else:
    FONT = None
HEAD = 'Cave' if FONT else 'Helvetica-Bold'
INK, BLUE, MUTED, CREAM = map(HexColor, ['#182026', '#008CFF', '#52616C', '#FFFBF0'])
W,H=612,792
c=canvas.Canvas(str(OUT), pagesize=(W,H))
c.setTitle('Cave Cals - Onboarding and Launch Review')
c.setAuthor('Cave Cals')
style=ParagraphStyle('body',fontName='Helvetica',fontSize=10.5,leading=15,textColor=INK)
small=ParagraphStyle('small',parent=style,fontSize=9,leading=13,textColor=MUTED)

def text(txt,x,y,width=516,sty=style):
    p=Paragraph(txt,sty); _,h=p.wrap(width,1000);p.drawOn(c,x,y-h);return y-h

def base(n,title,sub=''):
    c.setFillColor(CREAM);c.rect(0,0,W,H,fill=1,stroke=0)
    c.setFillColor(BLUE);c.setFont('Helvetica-Bold',9);c.drawString(48,750,'CAVE CALS / BUILD REVIEW')
    c.setFillColor(INK);c.setFont(HEAD,30);c.drawString(48,700,title)
    if sub:text(sub,48,681,sty=small)
    c.setStrokeColor(HexColor('#DDE4E8'));c.line(48,45,W-48,45)
    c.setFillColor(MUTED);c.setFont('Helvetica',8);c.drawString(48,29,'September 22, 2026 | Source changes and marketing drafts')
    c.drawRightString(W-48,29,str(n))

def image(path,x,y,width,height):
    im=ImageReader(str(path));iw,ih=im.getSize();scale=min(width/iw,height/ih)
    rw,rh=iw*scale,ih*scale;c.drawImage(im,x+(width-rw)/2,y+(height-rh)/2,rw,rh,mask='auto')

def heading(txt,y):
    c.setFillColor(INK);c.setFont('Helvetica-Bold',12);c.drawString(48,y,txt);return y-13

def bullet(txt,y):return text('&#8226; '+txt,52,y,508)-10

base(1,'A simpler start. A clearer launch.','Owner review packet - implementation, evidence, and ready-to-review creative.')
y=625
for title,body in [
 ('Built','A short optional onboarding flow estimates an editable daily calorie target. Existing users can build or update a plan from You.'),
 ('Kept simple','Five setup steps plus welcome. Manual and no-goal routes stay visible. No signup, paywall, or permission requests during setup.'),
 ('Prepared','A 30-day launch proposal, four video scripts, App Store and community drafts, three ad concepts with two variants, a recorded walkthrough, and a volunteer feedback guide.'),
 ('Pushed','Branch: codex/onboarding-and-launch. Baseline 35b5286 was pushed first. Core onboarding: 70cfa47. Latest app refinement: e2c8be8, including accessible layout and precise pace labels.')]:
    y=heading(title,y);y=text(body,48,y)-28
c.setFillColor(HexColor('#E5F2FF'));c.roundRect(48,128,516,116,16,fill=1,stroke=0)
text('<b>Review before release</b><br/>This is not a TestFlight or App Store upload. No advertisements, posts, outreach, or paid campaigns were launched. The proposed media budget is not a spending commitment.',66,224,480)
c.showPage()

base(2,'The new first run','Real iPhone simulator captures using synthetic test inputs.')
image(ASSETS/'screenshots/onboarding-welcome.png',54,228,236,422)
image(ASSETS/'screenshots/onboarding-target.png',322,228,236,422)
y=196
y=text('<b>Welcome -> About you -> Starting point -> Usual day -> Goal and pace -> Editable target</b>',48,y)-14
text('Users can choose metric or imperial units, opt out of weight tracking, or start without a calorie goal. Saving a plan never replaces an existing weigh-in for today. New steps open at the top; keyboard controls and scrolling keep the form usable.',48,y)
c.showPage()

base(3,'How the calorie target works','A starting estimate with explicit limits - not a promised weight-loss schedule.')
y=632
y=heading('Local, deterministic calculation',y)
y=text('Mifflin-St Jeor estimates resting energy from age, height, weight, and female/male reference values. A conservative activity multiplier estimates maintenance. The chosen pace sets a requested deficit; the app rounds the resulting target upward to the next 50 calories.',48,y)-20
for b in [
 'Automatic deficits are capped at 25% of maintenance or 750 calories/day, whichever is smaller.',
 'Automatic intake floors are 1,200 calories for the female reference and 1,500 for the male reference. These software limits do not guarantee a suitable diet for everyone.',
 'Ages outside 18-80, clinician-led needs, unspecified/other reference values, underweight current/goal values, and unsupported inputs take a manual route.',
 'Pregnancy, breastfeeding, eating-disorder history, and medical nutrition needs are named in the clinician-led option. That selection is not stored as a diagnosis.',
 'No deadline, automatic future calorie cuts, or exercise eat-back. The result is editable; progress and individual needs can differ.'
]:y=bullet(b,y)
y=heading('Privacy and storage',y-4)
y=text('Accepted calorie goals use the existing diary/iCloud path. Plan answers stay in the protected, backup-excluded local weight file. You can forget those answers without deleting your calorie goal or weigh-ins. Onboarding adds no CloudKit schema, backend endpoint, advertising SDK, or Health permission.',48,y)-18
text('Example test, not a recommendation: male reference, age 35, 180 cm, 90 kg, lightly active, requested 0.5 kg/week -> 2,050 calories. The test suite checks the exact equation and rounding.',48,y,sty=small)
c.showPage()

base(4,'What was checked','Focused checks plus the existing native unit suite.')
y=635
for h,b in [
 ('94 native unit tests passed','Includes nine calorie-plan tests: equation, floors/caps, unsupported inputs, maintenance, pace limiting, persistence, opt-out, legacy loading and forgetting details.'),
 ('Nine onboarding UI scenarios passed','Calculated target and weigh-in; manual/skip; minor/manual; units and unsafe goal; edited maintenance target and forgetting; back navigation; canceling revisions; both largest-text routes. Passed across focused runs.'),
 ('Small screens and older iOS passed','iPhone SE: calculated plan and largest text on iOS 26; calculated plan and minor/manual route on iOS 17.2. Visual review found and fixed large footer controls obscuring questions.'),
 ('iPad and existing behavior passed','Calculated and minor/manual flows pass in iPad compatibility mode. Existing manual-goal editing/cancel, skip-goal, and pending voice shortcut checks also pass.'),
 ('Visual and website checks','Screenshots and walkthrough reviewed; metric pace labels corrected. Website build and TypeScript pass. The missing download-button fallback is fixed and checked locally. Website/privacy changes remain undeployed.'),
 ('Release checks remain separate','No new archive/upload. Physical Health export, CloudKit production sync, camera and App Attest still need release verification. Earlier macro schema work remains. The existing Swift 6 isolation warning is unchanged.')]:
    y=heading(h,y);y=text(b,48,y)-22
c.showPage()

base(5,'Where the first users can come from','Recommendation: prove one clear message before spreading budget across channels.')
y=632
for h,b in [
 ('1. Founder demos first','Use real product footage: log a repeat breakfast, speak a meal and review it, or search for a restaurant. Start with the included scripts and captions.'),
 ('2. Make the App Store story obvious','Lead with easy daily logging, then Quick Add and optional scan/voice. Advertise the new onboarding only once it is in the public build.'),
 ('3. A small Apple search experiment','Proposed: search results, $15 average daily budget with an explicit 10-day end date ($150 media envelope). Individual days can exceed $15. The build sheet covers settings, keywords and costs; nothing is activated.'),
 ('4. Creators after message feedback','Collect concepts and quotes from practical food-prep/fitness creators. No outreach has been sent. Preserve honest opinions and disclose paid relationships.'),
 ('5. Measure without health-data targeting','Use App Store campaign links per source. Record spend, views, taps and downloads with their reporting windows. Do not send body details, foods or calorie targets to advertising platforms.')]:
    y=heading(h,y);y=text(b,48,y)-22
text('<b>Suggested sequence:</b> review and release (days 1-3); publish founder demos (4-7); learn from first-use feedback (8-10); capped search test if approved (11-20); improve one weak message (21-24); decide whether to repeat or pause (25-30).',48,y)
c.showPage()

for num,file,title,note in [
 (6,'food-simple.png','Food simple. Tracking simple.','Brand introduction. Pair with a real app demo or listing screenshot. Selected revision uses a plain text CTA and an unbranded phone.'),
 (7,'say-it-log-it.png','Say it. Log it.','Voice-logging angle. The copy calls the output an estimate and invites review. Do not imply unlimited free AI.'),
 (8,'small-steps.png','Small steps. Still count.','Routine and weigh-in angle. No promised transformation, target weight, deadline, or before/after imagery.'),
 (9,'say-it-log-it-story.png','A vertical voice concept','Story/Reels variant with extra space for placement controls. Preview actual overlays before publishing; 941 x 1672 is not an exact platform export preset.'),
 (10,'food-simple-cavewoman.png','Same message. Another character.','An alternate character edition of Food simple. Tracking simple. Keep message and placement consistent if comparing responses; performance has not been tested.')]:
    base(num,title,'AI-generated campaign concept; existing app artwork was not replaced.')
    image(ASSETS/'assets'/file,112,130,388,505)
    text(note,48,109,sty=small);c.showPage()

base(11,'Review map and sources','Detailed notes, prompts and scripts accompany the app source.')
y=632
for name,desc in [
 ('Documentation/Onboarding.md','Flow, algorithm choices, scope, persistence and primary sources.'),
 ('Documentation/Release/Onboarding-Review.md','Owner walkthrough, remaining release work, and privacy review.'),
 ('Marketing/2026-09-launch/Launch-plan.md','Channel priorities, budget proposal and 30-day sequence.'),
 ('Marketing/2026-09-launch/README.md','Asset index, video scripts, App Store copy, community drafts, ad build sheet and first-use feedback guide.'),
 ('Marketing/2026-09-launch/video/onboarding-walkthrough.mp4','39-second unedited automated simulator run with synthetic inputs; a review recording, not a finished ad.')]:
    y=text('<b>'+name+'</b><br/>'+desc,48,y)-15
refs=[
 ('Mifflin-St Jeor original equation','https://pubmed.ncbi.nlm.nih.gov/2305711/'),
 ('NIDDK Body Weight Planner','https://www.niddk.nih.gov/bwp'),
 ('Cal AI observed onboarding path (Lazyweb)','https://www.lazyweb.com/research/cal-ai-onboarding-personalization-before-signup'),
 ('Apple Ads search results','https://ads.apple.com/app-store/help/ad-placements/0082-search-results'),
 ('Apple Ads budget and end-date rules','https://ads.apple.com/app-store/help/bids-and-budget/0016-manage-budgets'),
 ('App Store campaign links','https://developer.apple.com/help/app-store-connect-analytics/acquisition/campaign-links'),
 ('TikTok weight-management policy','https://ads.tiktok.com/resources/help/article/tiktok-ads-policy-weight-management?lang=en')]
y=heading('Selected references',y-5)
for label,url in refs:y=text(f'<link href="{url}" color="#008CFF">{label}</link>',48,y,sty=small)-7
text('Cal AI research describes one captured path, not its conversion performance. Medical references inform the estimate; the app is not a medical assessment. Full sources and product assumptions are in Onboarding.md.',48,y-7,sty=small)
c.showPage();c.save();print(OUT)
