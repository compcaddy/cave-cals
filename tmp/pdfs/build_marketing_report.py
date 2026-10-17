from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, PageBreak, Table, TableStyle, Image
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib import colors
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from pathlib import Path
from xml.sax.saxutils import escape

ROOT=Path('/Users/phil/Documents/GIT/ECC2')
OUT=ROOT/'output/pdf/Cave-Cals-Marketing-Research-2026-10-17.pdf'
ASSETS=ROOT/'Marketing/2026-10-growth-playbook/assets'
pdfmetrics.registerFont(TTFont('Schoolbell',str(ASSETS/'brand/Schoolbell-Regular.ttf')))
orange=colors.HexColor('#C4531B'); ink=colors.HexColor('#302820'); cream=colors.HexColor('#F6EEDC')
styles=getSampleStyleSheet()
styles.add(ParagraphStyle(name='TitleC',fontName='Schoolbell',fontSize=37,leading=42,textColor=ink,spaceAfter=18))
styles.add(ParagraphStyle(name='HeadC',fontName='Helvetica-Bold',fontSize=23,leading=28,textColor=ink,spaceAfter=17))
styles.add(ParagraphStyle(name='SubC',fontName='Helvetica-Bold',fontSize=12,leading=16,textColor=orange,spaceBefore=11,spaceAfter=6))
styles.add(ParagraphStyle(name='BodyC',fontName='Helvetica',fontSize=10.1,leading=14.4,textColor=ink,spaceAfter=9))
styles.add(ParagraphStyle(name='SmallC',fontName='Helvetica',fontSize=8.2,leading=11,textColor=ink,spaceAfter=7))
story=[]
def p(t,style='BodyC'): story.append(Paragraph(t,styles[style]))
def h(t): p(t,'SubC')
def page(n,title,sub=None):
    if story: story.append(PageBreak())
    p(f'FIELD NOTES / {n:02d} / OCTOBER 17, 2026','SmallC');p(title,'HeadC')
    if sub:p(sub)
def bullets(items):
    for a,b in items:p(f'<b>{a}</b> {b}')
def table(rows,widths=None):
    data=[[Paragraph(str(x),styles['SmallC']) for x in row] for row in rows]
    t=Table(data,colWidths=widths, hAlign='LEFT')
    t.setStyle(TableStyle([('BACKGROUND',(0,0),(-1,0),cream),('VALIGN',(0,0),(-1,-1),'TOP'),('LEFTPADDING',(0,0),(-1,-1),8),('RIGHTPADDING',(0,0),(-1,-1),8),('TOPPADDING',(0,0),(-1,-1),7),('BOTTOMPADDING',(0,0),(-1,-1),6),('LINEBELOW',(0,0),(-1,0),1,orange),('LINEBELOW',(0,1),(-1,-1),.3,colors.HexColor('#DDD4C4'))]))
    story.append(t);story.append(Spacer(1,10))

page(1,'Cave Cals\nMarketing field guide')
story.append(Image(str(ASSETS/'brand/app-icon.png'),width=88,height=88,hAlign='LEFT'))
story.append(Spacer(1,15))
p('Less food admin.<br/>More life.','TitleC')
p('<b>Recommended positioning:</b> The friendly iPhone calorie tracker for people who want logging to feel easier. Start with useful free logging; sell the convenience of Cave Cals+ after people experience it.')
h('The first five decisions')
bullets([('Audience:','Start with adults who have tried tracking before and disliked the effort. Secondary: people who repeat meals and busy home cooks.'),('Creative:','Show one real meal being logged. Make the cave character a memorable guide, with the actual app doing the convincing.'),('Money:','Use a small, finite Apple Ads search test plus a few reusable creator demos. Keep Google App campaigns for a later, better-funded stage.'),('Conversion:','Sell less repetitive work, editable estimates, and recipe convenience. Measure paid users and contribution after costs.'),('Launch:','Confirm the public build, paid offers and purchase flow before sending traffic to promises about them.')])
p('Prepared from current public sources, repository release evidence, and existing marketing assets. Recommendations are hypotheses unless labeled otherwise. No ads launched, money spent, accounts connected, messages sent, or app changes made. Existing imagery is reproduced for review, not newly generated.','SmallC')

page(2,'What sells calorie apps?','People buy a useful outcome in a believable demonstration. A long feature list rarely explains why this app deserves another subscription.')
table([['Buyer job','Message to test','Proof to show'],['Make logging less tedious','Your usual breakfast. A few taps.','Repeat a real breakfast from history.'],['Log when life is busy','Say lunch. Review it. Get on with your day.','Voice input, result, correction, save.'],['Understand the day','See your calories and macros at a glance.','Home summary with a realistic diary.'],['Handle home cooking','One recipe. Easy servings.','Import, check yield, log one serving.'],['Feel comfortable returning','A friendlier place to keep track.','A calm ordinary day, including edits and Undo.']],[112,178,214])
h('Evidence and its limits')
p('MyFitnessPal sells faster logging and customizable goals. Cronometer emphasizes nutrition depth and paid convenience. MacroFactor sells adaptive coaching and a premium experience. Cal AI leads with photo logging and prominent creator examples. These are observed sales messages, not proof that each claim caused growth. [1-5]')
p('Two sampled CICO discussions describe manual logging effort, uncertainty about restaurant meals, and frustration with paywalled barcode scanning. This is qualitative language research from a small, self-selected sample; it does not establish how common each problem is. [6,7]')
h('The useful distinction')
p('<b>Downloads:</b> a clear demonstration, recognizable benefit and appealing price. <b>Payment:</b> repeated convenience worth the charge. <b>Renewal:</b> the app stays useful after the novelty wears off. Optimize all three separately.')
p('For Cave Cals, repeat-food suggestions are a strong acquisition story, but they are free. Pair them with a paid use case for meals that are not already in history. Otherwise a successful free-feature campaign may produce few subscribers.')

page(3,'The competitive opening')
table([['App','Observed pitch / paid value','Implication for Cave Cals'],['MyFitnessPal','Faster logging, macro controls; official legacy Premium page lists $79.99/year. [1,2]','Convenience sells, but camera and voice alone are not unique.'],['Cronometer','Nutrition detail; free barcode scanning; Gold adds photo, voice, recipes and more. [3]','Do not claim Cave Cals is the only free barcode option.'],['MacroFactor','Adaptive nutrition coaching; $71.99/year or $11.99/month for one app. [4]','People may pay more for an ongoing decision aid. Cave Cals should not imply equivalent adaptive coaching.'],['Cal AI','Photo-first presentation with creator endorsements. [5]','The demo is easy to understand. Its reach and accuracy claims are vendor claims.'],['Lose It!','Basic calorie tracking; Premium includes barcode, photo/voice and additional goals. [8]','Keep comparisons current. Avoid old free/paid feature matrices.']],[90,213,201])
h('Recommended territory')
p('<b>Friendly, low-friction daily logging.</b> Own a small, concrete promise: less effort putting ordinary food into a diary. The recognizable cream-and-orange identity can help people remember which app delivered that feeling.')
h('Who to pursue first')
bullets([('1. Returning trackers','They already understand calories; demonstrate why this routine feels easier. Recruit through practical demos and search intent.'),('2. Repeat-meal eaters','Show coffee, breakfast and usual snacks. Their routine fits Quick Add; test whether occasional scans create paid demand.'),('3. Busy home cooks','Recipe import and servings can support a clearer subscription reason. Only advertise features in the released build.')])
p('Do not open with elite bodybuilding, clinical nutrition or guaranteed weight loss. Those promises invite expectations outside the strongest documented product fit. Prices vary by storefront, channel and eligibility; competitor figures above are checked web offers, not in-app purchase quotes.','SmallC')

page(4,'What actually works: evidence')
bullets([('High-intent search: plausible first channel.','Apple publishes a YAZIO case study reporting stronger conversion and lifetime value from Apple Ads than other channels. It is a selected vendor case study, not a forecast for a new indie app. Copy the intent matching and keyword analysis, not its growth percentages. [9]'),('Paywall testing: useful once there is traffic.','Superwall reports 123 Cal AI experiments and a 31% improvement in trial-to-paid conversion over ten months. Revenue grew alongside that work; the public case does not isolate every cause. Copy the test discipline, not the volume or long onboarding funnel. [10]'),('Subscriptions: a hard business.','RevenueCat reports median iOS Health & Fitness download-to-paid conversion of 3.5% by day 35. Its Health & Fitness trial-to-paid median is 37.7%; that is a different denominator and a free-trial cohort. Neither is a target guaranteed for Cave Cals. [11]'),('AI: attention is not retention.','RevenueCat reports higher revenue per payer but weaker retention among AI apps. That supports testing ongoing usefulness instead of making AI the entire brand. The comparison is observational and spans more than calorie apps. [11]')])
h('What we do not know yet')
p('Cave Cals has no measured acquisition cost, ad-to-paid conversion, mature renewal cohort, or demonstrated winning creative in the evidence reviewed. Public creator appearances do not reveal profitable creator economics. The existing playbook does not establish these results either.')
h('A practical proof ladder')
p('Watch five people try the product. Then obtain 20-30 unaided first-use sessions. Next run one finite acquisition test and follow its cohort for 35 days. Only then decide whether conversion economics justify more spend. These sample sizes are operational starting points, not statistical guarantees.')
p('At low volume, learn why people stop. One or two purchases are encouraging but insufficient to declare a winner. Avoid splitting a few hundred visitors across five paywall variants.')

page(5,'Brand: warm, simple, recognizable')
h('A usable brand platform')
bullets([('Name:','Use <b>Cave Cals</b> consistently, matching the app. Cave Cals+ is the paid tier. Do not scatter CaveCal, CaveCal AI and Cave Cals across campaigns.'),('Promise:','Less effort logging the food you actually eat.'),('Personality:','Warm, practical, lightly funny. The caveman is a helpful companion, never someone shaming bodies, food or missed days.'),('Voice:','Use normal language for explanations and pricing. Short cave-style lines can be the signature: "Food logged. Carry on." Avoid making every sentence a joke.'),('Visual system:','Keep the supplied icon and mascot. Use the existing light-mode orange (#C4531B), cream surfaces and dark brown text. Schoolbell for brief headlines; a highly legible sans serif for details.'),('Brand misunderstanding to test:','Ask people what they think the app does before explaining it. The name can suggest paleo or carnivore diets. Add "Calorie & macro tracker" where the category is not obvious.')])
h('Copy bank: starting options')
table([['Role','Draft'],['Primary headline','Less food admin. More life.'],['Product descriptor','A friendlier calorie tracker for iPhone.'],['Repeat-food hook','Same breakfast? Start with your usuals.'],['Voice hook','Say lunch. Review it. Log it.'],['Paid value','Make the meals you do not want to type easier to log.'],['Brand sign-off','Food logged. Carry on.'],['CTA','Start logging free. Explore Cave Cals+ for more convenience.']],[112,392])
p('These lines are original test concepts, not validated taglines. Avoid "weight drop," "effortless weight loss," "perfectly accurate," and unmeasured time-saving numbers. Use "estimate" for AI output and show the review step.')

page(6,'Imagery: reuse the good foundation','Two existing assets illustrate useful directions. They are draft references, not launch-approved ads.')
imgs=[Image(str(ASSETS/'ads/ad-03-same-breakfast.png'),width=238,height=297.5),Image(str(ASSETS/'ads/ad-04-snap-say.png'),width=238,height=297.5)]
story.append(Table([imgs],colWidths=[252,252]));story.append(Spacer(1,10))
table([['Repeat-food direction','Photo / voice direction'],['Good: concrete task, clear type and actual UI. Fix: breakfast headline sits above rice and chicken; recapture with a plausible breakfast. The Today pill is outdated relative to current local decisions.','Good: real food, legible benefit, estimate/review wording. Fix: "Free on iPhone" can imply unlimited free AI. State limited introductory access and optional subscription clearly.']],[252,252])
h('Three new production briefs')
p('<b>Kitchen-counter demo:</b> coffee, toast, phone, one tap in real time. Headline: "Start with your usuals." <b>Lunch on a busy day:</b> creator speaks a meal, checks the result, adjusts one amount. Headline: "Say it. Check it. Log it." <b>Home-cook demo:</b> a recipe and serving count next to a real plate. Headline: "Cook once. Log your serving."')
p('Use real capture from the public build and fictional diary data. For social production, prepare portrait 4:5 and 9:16 versions with safe space for platform overlays. Keep one benefit per asset. No invented testimonials, fake screens, or body transformations. These briefs are new; no new image files were generated in this pass.','SmallC')

page(7,'How to earn the subscription')
h('Keep the free product trustworthy')
p('Manual logging, history and basic use should continue delivering the promise that brought someone in. Cave Cals+ should save additional effort, especially on varied meals and recipes. Free users may recommend the app even if they never subscribe.')
h('A proposed value sequence')
bullets([('First session:','Help someone log their own first food. Show the result and a useful next action. Measure completion and time, rather than adding onboarding questions for their own sake.'),('First successful AI use:','Let them inspect and correct an estimate. An honest review flow builds a more credible reason to pay than pretending a photo knows exact ingredients.'),('After repeated value:','Test a skippable explanation of what Plus adds, with one relevant example. Do not interrupt the first add just to maximize paywall views.'),('At the access limit:','Explain the paid option and the available free path. Current documentation says up to ten successful shared photo/voice scans, ending sooner at 100 regular entries. Do not market this as an unconditional ten-scan promise or a subscription free trial.'),('Before renewal:','Make the product useful enough to return to: favorite meals, quick logging and progress review. Do not rely on people forgetting to cancel.')])
h('Pricing copy must match the offer')
p('Repository evidence schedules U.S. offers from October 15: <b>$0.99 for the first month, then $4.99/month</b>; <b>$19.99 for the first year, then $39.99/year</b>. Eligibility and storefront affect display. Confirm these in the actual purchase flow before publication. The older "Try for $0.00" copy is inappropriate for paid intro offers.')
p('Explain the full annual charge prominently; do not present $1.67/month as if it were monthly billing. Test annual-first versus neutral presentation while keeping monthly visible. Keep price, benefit and timing experiments separate.')
h('Do not sell the wrong benefit')
p('Macro auto-fill is documented as free and not part of scan budgets. Do not imply Plus is required to unlock it. Clans is documented as unreleased; treat social accountability as a later campaign until release and signed-device checks are confirmed.')

page(8,'The economics that decide the budget','Illustrative planning model, not a revenue forecast. Replace every assumption with measured proceeds, refunds and service costs.')
p('<b>First-year contribution per annual buyer</b> = introductory price x (1 - store commission) - refunds/taxes not already netted - variable service/support cost. <b>Break-even cost per install</b> = contribution per buyer x install-to-paid conversion. Fixed overhead and founder time are additional.')
table([['Annual first-year scenario','$19.99 intro','Meaning'],['Proceeds at assumed 15% commission','$16.99','Only if applicable; enrollment/status not verified. [12]'],['Illustrative annual service-cost reserve','$4.00','Assumption; AI usage and support may cost more.'],['Available before acquisition','$12.99','Before unmodeled refunds, taxes and fixed costs.'],['Break-even CPI at 2% paid','$0.26','2 buyers per 100 installs.'],['Break-even CPI at 3.5% paid','$0.45','Benchmark-shaped scenario, not forecast.'],['Break-even CPI at 5% paid','$0.65','Still little room for expensive installs.'],['Same model at 30% commission','$9.99 contribution','$0.35 CPI at 3.5% paid.']],[220,100,184])
p('<b>Example:</b> $300 buys 200 installs at $1.50 each. At 3.5% conversion, seven annual buyers contribute about $91 before acquisition under the 15%/$4-cost scenario. The test loses about $209 on that basis. That can be deliberate research spend; it is not profitable scaling.')
h('Monthly offers need their own model')
p('The first $0.99 charge yields roughly $0.84 at an assumed 15% commission, before service costs. Count subsequent $4.99 renewals only when observed or explicitly modeled with retention. Never value an introductory monthly payer as twelve guaranteed months.')
h('Proposed initial acquisition target')
p('For the annual scenario, use a provisional paid-customer CAC ceiling of $8, leaving some room below the $12.99 contribution assumption. At 3.5% install-to-paid, that implies $0.28 CPI. If market bids cannot achieve it, improve conversion, economics or channel mix; do not hide the gap with hypothetical year-two renewals.')

page(9,'Where to spend the first dollars')
table([['Total test envelope','Allocation','Purpose'],['$300','$150 Apple Ads; $100 capture/editing; $50 reserve','One search test and owner-made demos. No paid software subscription required.'],['$750 - recommended','$300 Apple Ads; $250 creator content; $100 editing; $100 reserve','Buy learning and reusable assets. Creator prices are spending caps to negotiate, not market quotes.'],['$1,500','$500 Apple Ads; $500 creator content; $200 production; $300 held back','Release the reserve only after an initial review. No need to spend the whole envelope.']],[115,221,168])
h('Priority order')
bullets([('1. Store page and demonstrations','Every acquired visitor needs an understandable destination. Use current screenshots and a visible distinction between free features and Plus.'),('2. Apple Ads search results','Test people actively looking for a tracker. Start with one geography and a small number of closely related keyword themes. Low-volume words may not spend.'),('3. Small creator production tests','Pay for a clear demonstration and reusable footage, with distribution optional. A creator with a useful audience is preferable to an impressive follower count.'),('4. Meta or TikTok later','Take an organic demo that produces qualified visits and test it in one network. Recheck account-specific health-category and event restrictions first.'),('5. Google App campaigns later','Google recommends daily budgets around 50x target CPI or 10x target CPA. At a hypothetical $2 CPI, that is $100/day. A tiny budget spread across networks is unlikely to teach much. [13]')])
p('Do not start with an agency retainer, a large influencer package, broad awareness placements, or several attribution subscriptions. If you cannot afford to lose the test amount, start with organic demos and interviews. These are planning options; no spending is authorized or scheduled by this document.')

page(10,'A concrete Apple Ads pilot')
h('Draft configuration: $300 over 15 days')
p('One U.S. campaign for search results, $20 average daily budget, explicit start/end dates, with no automatic budget increases. This is a proposed configuration, not a created campaign. Apple says daily spend may exceed the daily average; with an end date its stated ceiling is days x daily budget. Recheck the schedule, account timezone and budget in the live setup. [14]')
table([['Ad group','Initial terms / treatment','Why'],['Simple tracking','simple calorie counter; food diary; calorie tracker','Core intent. Start exact-match; volume and bids unknown.'],['Convenient logging','voice food log; photo calorie counter','Compare demand for the paid convenience story.'],['Discovery - later','Search Match or broader exploration','Add only after core data; keep separately identifiable.'],['Brand - separate if needed','Cave Cals and obvious variants','Do not mix existing brand demand into generic acquisition results.']],[112,230,162])
h('How to decide')
bullets([('Before launch','Verify install destination, public-build features, offer eligibility, purchase/restore and revenue reporting. Record the baseline organic week.'),('First days','Look for irrelevant queries, broken destinations and obvious overspend. Fix technical problems immediately. Do not judge day-35 payer conversion on day two.'),('At the end date','Pause the pilot and preserve the unspent reserve. Review spend, installs, first-use quality and acquisition mix. Follow the cohort through day 35.'),('After cohort maturity','Compare contribution per install against CPI, including creator/editing costs in a fully loaded view. Continue only if economics or a specific learnable failure justify another finite test.')])
p('Avoid a rule such as "pause after $8 with no sale" on a channel expected to convert only a few percent. Zero sales from a tiny sample is unsurprising. A budget stop is a spending decision, not proof the ad is ineffective. Long-tail keyword bids may simply be too expensive for the current intro economics.')

page(11,'Can this be connected and automated?')
table([['Route','Verified capability','Remaining setup'],['Apple Ads API','Official API manages campaigns, ad groups, keywords and reports; OAuth and designated API-user roles. [15]','Your account, billing and authorized access; implement and test integration. No connected Apple Ads tool found in this session.'],['Google Ads API','Official programmatic account/campaign management and reporting. Google also documents scripts and automated rules. [16]','Authorized account, OAuth and applicable API access. Integration has not been tested here.'],['Windsor.ai plugin','Directory listing advertises reporting across Google, Meta and others, plus selected write actions with confirmation.','Not installed. Confirm exact account and action support and any subscription cost. Listing is not proof of a working connection.'],['ChatGPT Ads Manager','Directory lists an ads-management plugin.','Its listing did not establish Apple/Google network coverage. Do not assume it controls either.']],[105,215,184])
h('Useful automation in stages')
p('<b>Stage 1:</b> read-only daily spend and weekly cohort summary. <b>Stage 2:</b> recommend pauses or keyword exclusions with reasons. <b>Stage 3:</b> once authorized, bounded changes only within a defined campaign, spend envelope and end date. No autonomous expansion into new countries or networks.')
p('Use platform-enforced budgets and end dates as primary controls. Monitoring can lag and cannot guarantee a hard ceiling. Google uses average daily budgets with spending-limit rules; ordinary daily limits can reach twice the average. Do not equate a $10 daily setting with an exact $10 daily charge. [17]')
p('A future specification should include: account/campaign IDs, total budget, currency, timezone, dates, allowed actions, reporting lag, a safety margin, alerts, a kill switch and a change log. If reporting becomes stale or credentials fail, notify the owner; do not silently increase bids or pretend the monitor is still protecting spend.')
p('No recurring automation was installed. Your request asks what is possible; setting up live ad control needs an actual account and chosen spending envelope. More connectors may exist in the plugin directory.','SmallC')

page(12,'Measure customers, not just clicks')
table([['Metric','Definition / use'],['Store conversion','First-time downloads divided by the corresponding eligible product-page views; keep Apple metric definitions consistent.'],['Activation','Proposed: a new install logs a first food within 24 hours. Separate test/dev use.'],['Habit','Proposed: at least three distinct logging days in the first seven days.'],['D35 paid conversion','New installs with a verified paid subscription by day 35 / eligible new-install cohort. Separate intro monthly and annual.'],['Contribution per install','Realized proceeds minus refunds and variable costs, divided by installs in the same acquisition cohort.'],['CAC','Acquisition spend / attributed new paid customers; report media-only and fully loaded versions.'],['Renewal','Track subscription renewals by original start cohort and plan; cancellation is not always immediate expiry.']],[145,359])
h('Practical attribution')
p('Create separate App Store campaign links for each creator and campaign family. Apple now documents campaign-level downloads, sales and subscription metrics, but privacy thresholds and reporting delays apply. A missing small-cohort metric is not zero. Use the existing optional "Where did you hear about us?" response as supporting evidence, not exact attribution. [18]')
p('Do not assume an App Store campaign link automatically supplies user-level attribution inside RevenueCat. Confirm available aggregate reports and any explicit integration before promising a joined funnel. Do not add counts across platforms as if every conversion were unique.')
h('One-page weekly decision')
p('Record spend, qualified visits, installs, first logs, retained loggers, paid starts by plan, net proceeds, refunds, AI costs and top reasons for stopping. Include denominators and cohort ages. End with one decision: keep, change one variable, pause, or wait for the cohort.')
p('Keep food names, calories, weight, photos and health details out of advertising payloads. Verify platform rules before any event integration. Meta documentation could not be fully inspected without login, so this report does not assert which conversion events that account will allow.')

page(13,'A lean creator and organic program')
h('Start with one account and three repeatable formats')
bullets([('The 15-second demo','Open on the task, show the actual tap or voice entry, include the reviewed result, end with one CTA.'),('The honest founder','Explain the small frustration you built around. Show a real limitation and how to correct it. Credibility is a useful contrast to exaggerated scan claims.'),('The practical guide','Teach one logging shortcut in context: repeat breakfast, saved meal, a recipe serving or numeric quick add. Keep it about using the app, not prescribing a diet.')])
h('Creator selection rubric')
p('Shortlist adult-audience creators who already discuss everyday food routines, meal preparation or practical iPhone tools. Inspect their last ten relevant posts for clear explanations, meaningful comments and audience location. Ask for audience evidence and a quote. Followers alone do not show purchase intent.')
p('For an initial small commission, request one 15-30 second demonstration, raw footage, one opening-hook alternative, captions and explicit usage rights. Clarify whether the price includes posting, revisions, ad reuse and the duration of that permission. No outreach has been sent.')
h('Four original scripts to film')
bullets([('Repeat breakfast','"I eat roughly the same breakfast. Logging it should not be the hard part." Show the foods already in history, tap adds, reveal summary. CTA: "Try Cave Cals on iPhone."'),('Voice lunch','"Here is how I log lunch when I do not want to type it." Speak a meal, show the estimate, correct an amount, save. CTA: "Try the introductory scan allowance."'),('Known calories','"Already know the calories?" Enter "pizza 300," select the add row, show the diary. CTA: "Start logging free." Verify this exact interaction in the public build.'),('Recipe serving','"This makes four servings. I am logging one." Import a recipe, check ingredients and yield, log a serving. CTA: "Explore recipe logging with Cave Cals+." Release-dependent.')])
p('A workable starting rhythm is three solid posts per week, one weekly review and one filming session every two weeks. Do not adopt the old three-account/100-post plan before finding a repeatable format. Paid or gifted creator relationships need clear disclosure; do not ask for positive ratings in exchange.','SmallC')

page(14,'Thirty additional ideas to test','Original opportunity bank. Order reflects judgment about product fit, not measured performance.')
table([['Acquisition / creative','Conversion / retention','Partnership / distribution'],['1. Breakfast in real time','11. First-food guided demo','21. Trainer logs their own lunch'],['2. Coffee-plus-snack routine','12. Feature-specific Plus explanation','22. Gym QR with a unique link'],['3. Barcode without an account','13. Clear remaining scan allowance','23. Seven-day logging workshop'],['4. One food, three ways to log','14. Annual vs neutral plan emphasis','24. Coach recap handoff demo'],['5. Fixing a photo estimate','15. Recipe import value demonstration','25. Meal-prep creator partnership'],['6. A week of ordinary meals','16. Returning-user first action','26. iPhone productivity newsletter'],['7. Why I made Cave Cals','17. Two-minute first-use interview','27. Indie app founder interview'],['8. No-perfect-diary demo','18. Canceled-subscriber feedback','28. Food blogger recipe workflow'],['9. Pocket guide to servings','19. First-week habit walkthrough','29. Permission-based community AMA'],['10. Day done, cave closed','20. User-controlled recap sharing','30. Later: verified Clans invite loop']],[168,168,168])
h('Ten more specific campaign hooks')
p('31. "Your coffee deserves fewer taps." 32. "A food diary for real weekdays." 33. "Three ways to log the same sandwich." 34. "What a meal photo can miss." 35. "Your usual foods, ready when you are." 36. "A small app with a big orange plus." 37. "Lunch logged before the meeting." 38. "One recipe, the right serving." 39. "The app I built because I kept restarting." 40. "Less typing at the dinner table."')
h('Five retention experiments worth more than another slogan')
p('41. Compare first-week behavior by initial logging method. 42. Interview people who scanned once but never twice. 43. Find whether saved-meal users renew more often, without claiming causation. 44. Check whether people understand that canceling Plus preserves free logging. 45. Measure how many first-time users correct an AI result and still save it.')
p('Treat recap sharing, changed onboarding, allowance displays and any new reactivation flow as proposed product work unless already verified. Avoid building a referral reward system before ordinary sharing produces meaningful use. Clans and recent local-only UI changes are not launch claims.')

page(15,'Tests worth running first')
table([['Priority / hypothesis','Design','Decision measure'],['1. People understand the brand','Show five adults the icon, name and first screenshot without explanation. Ask what it does and who it is for.','If paleo/carnivore dominates, strengthen the calorie-tracker descriptor.'],['2. Ease beats AI as the lead','Same audience and format: repeat-meal demo vs photo demo. Hold CTA and destination stable.','Qualified installs and D35 contribution, with early first-log feedback.'],['3. First use is too hard','Observe 5-8 people logging their own food unaided.','Repeated points of confusion; fix those before buying more traffic.'],['4. Paid value is unclear','Show one Plus example after successful use vs current explanation.','Paid starts and retained logging, not paywall clicks alone.'],['5. Home cooks are better buyers','Recipe-focused creative/page vs general tracker creative.','Contribution per acquired install and AI/service costs.'],['6. A creator can transfer trust','Two or three small content commissions, each with a distinct link and reusable footage.','Cost per qualified install; payer cohort when mature; content reuse value separately.']],[143,226,135])
h('A stopping rule that respects uncertainty')
p('Predeclare the test envelope and end date. Stop immediately for broken purchase flows, inaccurate claims or uncontrolled spend. Otherwise complete the finite test and wait for the selected conversion window. Keep a promising angle only if its economics or qualitative learning justify the next budget. Report small samples as inconclusive.')
h('What not to test simultaneously')
p('Do not change price, trial type, screenshot message, audience and onboarding together. Do not compare organic fans with cold paid traffic and attribute the difference to copy. Do not optimize a $0.99 start while ignoring the first full-price renewal.')
p('Once volume supports it, use App Store product-page optimization or custom pages to match messages to audiences. Apple supports measuring these surfaces; account eligibility and page approval still need checking. [19]')

page(16,'A practical first 30 days')
table([['When','Work','Deliverable / gate'],['Days 1-3','Confirm released version, purchase flow and offer text; inventory current screenshots and analytics.','One accurate promise sheet. No traffic to unreleased benefits.'],['Days 4-7','Watch first-use sessions; record three demos; update the first screenshots.','Three usable videos and a clear store page.'],['Days 8-10','Post demos; shortlist creators; make campaign links; choose a loss-tolerant test envelope.','One audience, one geography, one test plan.'],['Days 11-25','Run the finite Apple Ads pilot if setup is ready; publish three posts weekly; commission a small amount of creator content.','Spend monitored; new cohorts and reasons for friction recorded.'],['Days 26-30','Pause and review acquisition; follow older cohorts; fix the biggest observed friction.','A written keep/change/pause decision.'],['After day 35 per cohort','Assess mature payer conversion and contribution.','Decide whether a second test is justified.']],[90,235,179])
h('Before January')
p('Use October and November to learn which message produces useful first sessions and genuine payment. In December, prepare proven demonstrations for January rather than buying traffic because the category is seasonal. Do not assume January acquisition costs or demand from generic fitness seasonality; inspect your own data and bids.')
h('What to spend time on this week')
p('First: verify the real subscription flow on a signed iPhone and iPad compatibility mode. Second: record repeat breakfast, voice lunch and a reviewed photo estimate. Third: show them to five adults who have used trackers. Fourth: choose the first budget envelope only after hearing what they understood and would pay for.')
p('The most important missing facts are your affordable monthly test budget, available weekly marketing time, currently released app version, actual proceeds/AI costs, and whether a trainer or creator partner is already committed. This report makes working assumptions instead of claiming those are known.')

page(17,'What to keep from the old playbook')
table([['Keep / adapt','Correct / retire'],['Cream/orange brand, supplied icon and mascot, real-demo approach, founder voice, creator briefs.','Free-trial headlines and "Try for $0.00" where the offer now charges an introductory price.'],['Existing scripts, trainer cue cards and footage as a production starting point.','The claim that a pricing change is "worth +65%" as if measured. It was an assumption-driven scenario.'],['Separate campaign links, weekly review, App Store screenshots and honest AI review.','Assuming creator/offer codes automatically identify paying users. Removed in-app discount codes must not return in copy.'],['Small Apple search pilot and later reuse of effective creative.','Three accounts and 100 videos as a default solo-founder workload. Quality and learning come first.'],['Coach recap concept and recipe convenience.','Claims that ratings are absent, old competitor feature comparisons, and unreleased Clans promotion.']],[252,252])
h('Asset locations already in the repository')
p('Marketing/2026-10-growth-playbook/assets/ads/: six static ad drafts.<br/>assets/video/real-demo/: recorded demonstrations listed by the existing README.<br/>assets/app-store-screenshots/: older captures and rendering materials.<br/>assets/brand/: supplied icon, launch art, Schoolbell font and cave icons.<br/>assets/social/carousels/: themed carousel sets.<br/>Marketing/2026-09-launch/: earlier launch drafts.','SmallC')
h('What this research added')
p('Current competitor positioning; primary-source advertising capabilities; a refreshed brand recommendation; a review of two existing visual directions; three production briefs; four filming scripts; 45 additional ideas; six prioritized tests; three budget envelopes; conservative intro-price economics; measurement definitions; an automation specification; and a 30-day sequence.')
p('The public App Store page was not readable through the research tool, and repository release notes are dated evidence rather than live release status. Nothing here certifies that the latest local features are downloadable. No new raster imagery or campaign implementation was produced; imagery work here is an audit and production brief.')

sources=[
('1','MyFitnessPal: Premium features','https://support.myfitnesspal.com/hc/en-us/articles/360032625951-MyFitnessPal-Premium-features'),
('2','MyFitnessPal: legacy Premium offer','https://www.myfitnesspal.com/premium?legacy=true'),
('3','Cronometer: Gold and free feature comparison','https://cronometer.com/gold/'),
('4','MacroFactor: subscription pricing','https://help.macrofactorapp.com/en/articles/393-how-macrofactor-subscriptions-and-bundles-work'),
('5','Cal AI: product positioning and creator examples','https://www.calai.app/'),
('6','CICO discussion: logging frustration (qualitative only)','https://www.reddit.com/r/CICO/comments/1ho5bzc/is_calorie_tracking_this_frustrating_for_everyone/'),
('7','CICO discussion: getting started (qualitative only)','https://www.reddit.com/r/CICO/comments/1hady0b/'),
('8','Lose It!: membership tiers','https://loseit.zendesk.com/hc/en-us/articles/51906561286804-Lose-It-Membership-Tiers-Pricing'),
('9','Apple Ads: YAZIO case study (vendor-selected)','https://ads.apple.com/app-store/success-stories/yazio'),
('10','Superwall: Cal AI case study (vendor-reported)','https://superwall.com/case-studies/cal-ai'),
('11','RevenueCat: State of Subscription Apps 2026','https://www.revenuecat.com/state-of-subscription-apps'),
('12','Apple: Small Business Program','https://developer.apple.com/app-store/small-business-program/'),
('13','Google Ads: App campaign budget recommendations','https://support.google.com/google-ads/answer/9176652?hl=en'),
('14','Apple Ads: budget behavior and end dates','https://ads.apple.com/app-store/help/bids-and-budget/0016-manage-budgets'),
('15','Apple Ads: API access and capabilities','https://ads.apple.com/app-store/help/campaigns/0022-use-the-apple-ads-platform-api'),
('16','Google Ads API: capabilities and automation alternatives','https://developers.google.com/google-ads/api/docs/get-started/introduction'),
('17','Google Ads: spending limits','https://support.google.com/google-ads/answer/10486637/about-spending-limits?hl=en-GB'),
('18','Apple: campaign links and reporting thresholds','https://developer.apple.com/help/app-store-connect-analytics/acquisition/campaign-links'),
('19','Apple: App Store analytics and page measurement','https://developer.apple.com/app-store-connect/analytics/'),
]
page(18,'Sources and confidence','Public pages checked October 17, 2026. Numbers and offers can change. Click a title to open its source.')
for num,title,url in sources[:11]:p(f'[{num}] <a href="{escape(url)}" color="#C4531B">{escape(title)}</a>','BodyC')
h('How the evidence was used')
p('Official product pages establish current advertised features and web offers. They do not independently establish accuracy, user outcomes or profitable acquisition. Advertising case studies are selected examples. RevenueCat benchmarks describe its observed subscription-app population, not all apps or a randomized experiment. Reddit provides language and questions, not representative demand data.')
p('All proposed budgets, creator caps, conversion scenarios, copy, personas and experiment priorities are recommendations or illustrative assumptions. There is no claimed Cave Cals campaign result in this report.')
page(19,'Sources and working record')
for num,title,url in sources[11:]:p(f'[{num}] <a href="{escape(url)}" color="#C4531B">{escape(title)}</a>','BodyC')
h('Internal evidence reviewed')
p('README.md; Documentation/Release/Readiness.md (especially October 13 build/offer notes); Documentation/BackendSetup.md; Documentation/ScanAccess.md; supplied AGENTS.md guidance; and the existing Marketing/2026-10-growth-playbook strategy, budget, paid-ads and asset inventory. Current local instructions identify several October 17 features as local-only. These are not proof of a live App Store release.','SmallC')
h('Connection research')
p('Plugin-directory results on October 17 listed Windsor.ai and ChatGPT Ads Manager as available but not installed. Windsor advertised multi-network reporting and selected writes requiring confirmation. No account access, network coverage beyond that listing, cost, or working write path was independently tested. Meta health-event documentation was login-blocked.','SmallC')
h('Quota and delivery')
p('The account reported 3% weekly quota used / 97% remaining at the start and at interim checks. That reading did not visibly move during research. The PDF was prepared early rather than attempting to consume quota until a particular percentage. Usage can update with delay; an exact eventual remaining percentage is not promised.','SmallC')

def footer(c,doc):
    c.setFillColor(cream);c.rect(0,0,612,20,fill=1,stroke=0)
    c.setStrokeColor(orange);c.line(54,748,558,748)
    c.setFont('Helvetica',8);c.setFillColor(ink)
    c.drawString(54,31,'CAVE CALS / MARKETING RESEARCH / DRAFT FOR DECISIONS')
    c.drawRightString(558,31,str(doc.page))
doc=SimpleDocTemplate(str(OUT),pagesize=(612,792),rightMargin=54,leftMargin=54,topMargin=57,bottomMargin=53,title='Cave Cals Marketing Field Guide',author='Cave Cals / Research prepared with Codex')
doc.build(story,onFirstPage=footer,onLaterPages=footer)
print(OUT)
