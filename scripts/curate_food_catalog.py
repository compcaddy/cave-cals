#!/usr/bin/env python3
"""Select the catalog additions and append them to the reviewed manifest.

Selection only. Nutrition is never written here: build_common_foods.py
recalculates every value from the pinned USDA archives. Run once to (re)create
the additions; afterwards the manifest is the authoritative, frozen selection.

python3 scripts/curate_food_catalog.py /path/to/usda-downloads [--target 5000]

The directory must contain the pinned archives listed in SOURCES plus the NHANES
2021-2023 day-one individual foods file (DR1IFF_L.xpt), which is used only to
prioritise records people actually reported eating (unweighted counts, not
national consumption estimates). Standard library only.
"""
import argparse
import collections
import hashlib
import json
import math
import re
import statistics
import struct
import zipfile
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'Documentation/FoodCatalog/manifest.json'
REPORT = ROOT / 'Documentation/FoodCatalog/curation-report.json'

FNDDS_ZIP = 'FoodData_Central_survey_food_json_2024-10-31.zip'
SR_ZIP = 'FoodData_Central_sr_legacy_food_json_2018-04.zip'
SOURCES = {
    FNDDS_ZIP: 'dfb06ae7ddc397ccd570b91c14b75438ab2ba39f64f22d321f61d4a52a77f3eb',
    SR_ZIP: '0fe8ae486a2c8eb42cb96413f058deb51863a46c8fb8eeb4b1fb45006dd338ef',
}
NHANES = ('DR1IFF_L.xpt', '97177395e5fd1322ec8cb72d271a3f8d46e6a83b1105f89f6ef6f39f156037b3')
NUTRIENTS = {'kcal': 1008, 'protein': 1003, 'totalCarbs': 1005, 'fiber': 1079, 'fat': 1004}
MAX_CALORIES = 2500

# The ten original FDA poster fruits already cover these raw FNDDS records.
FDA_FRUIT_CODES = {'61119010', '63101000', '63107010', '63123000', '63126500',
                   '63135010', '63137010', '63141010', '63149010', '63223020'}


# ---------------------------------------------------------------- source data

def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_sources(folder):
    for name, digest in SOURCES.items():
        assert sha256(folder / name) == digest, f'{name} differs from the pinned release'
    assert sha256(folder / NHANES[0]) == NHANES[1], 'NHANES file differs from the pinned release'
    with zipfile.ZipFile(folder / FNDDS_ZIP) as z:
        fndds = json.loads(z.read('surveyDownload.json'))['SurveyFoods']
    with zipfile.ZipFile(folder / SR_ZIP) as z:
        sr = json.loads(z.read(z.namelist()[0]))['SRLegacyFoods']
    return fndds, sr


def ibm_float(raw):
    raw = raw.ljust(8, b'\0')
    if raw[1:] == b'\0' * 7 and raw[0] != 0:
        return None  # SAS missing value
    sign = -1 if raw[0] & 0x80 else 1
    return sign * int.from_bytes(raw[1:], 'big') / float(1 << 56) * 16 ** ((raw[0] & 0x7F) - 64)


def nhanes_intake(path):
    """Reliable day-one reports: people per food code and median grams per report."""
    data = path.read_bytes()
    head = data.index(b'HEADER RECORD*******NAMESTR HEADER RECORD')
    count = int(data[head + 54:head + 58])
    fields = {}
    for k in range(count):
        rec = data[head + 80 + k * 140: head + 80 + (k + 1) * 140]
        _, _, length, _ = struct.unpack('>hhhh', rec[:8])
        fields[rec[8:16].decode().strip()] = (struct.unpack('>i', rec[84:88])[0], length)
    start = data.index(b'HEADER RECORD*******OBS     HEADER RECORD') + 80
    width = sum(length for _, length in fields.values())
    people, grams = collections.defaultdict(set), collections.defaultdict(list)
    for offset in range(start, len(data) - width + 1, width):
        row = data[offset:offset + width]
        if not row.strip(b' '):
            break
        value = {name: ibm_float(row[pos:pos + length]) for name, (pos, length) in fields.items()
                 if name in ('SEQN', 'DR1DRSTZ', 'DR1IFDCD', 'DR1IGRMS')}
        if value['DR1DRSTZ'] != 1:
            continue
        code = str(int(value['DR1IFDCD']))
        people[code].add(value['SEQN'])
        if value['DR1IGRMS']:
            grams[code].append(value['DR1IGRMS'])
    return ({code: len(seqs) for code, seqs in people.items()},
            {code: statistics.median(values) for code, values in grams.items()})


def per100(food):
    values = {n['nutrient']['id']: n.get('amount') for n in food['foodNutrients'] if n.get('amount') is not None}
    units = {n['nutrient']['id']: n['nutrient']['unitName'] for n in food['foodNutrients']}
    result = {key: values.get(nid) for key, nid in NUTRIENTS.items()}
    if any(v is None or not math.isfinite(v) or v < 0 for v in result.values()):
        return None
    assert units[1008] == 'kcal' and all(units[NUTRIENTS[k]] == 'g' for k in result if k != 'kcal')
    return result


def app_norm(text):
    return ' '.join(re.findall(r'[0-9a-z]+', text.casefold()))


def close_nutrition(a, b):
    if abs(a['kcal'] - b['kcal']) > max(2.0, 0.03 * max(a['kcal'], b['kcal'])):
        return False
    for key in ('protein', 'totalCarbs', 'fat'):
        if abs(a[key] - b[key]) > max(0.5, 0.05 * max(a[key], b[key])):
            return False
    return abs(a['fiber'] - b['fiber']) <= 0.5


def similar_nutrition(a, b):
    """Looser than close_nutrition: same food after rounding/blending, but raw vs cooked still differs."""
    if abs(a['kcal'] - b['kcal']) > max(5.0, 0.10 * max(a['kcal'], b['kcal'])):
        return False
    return all(abs(a[k] - b[k]) <= max(1.0, 0.15 * max(a[k], b[k])) for k in ('protein', 'totalCarbs', 'fat', 'fiber'))


def sr_shares(fndds_food):
    parts = [(i['ingredientCode'], i.get('ingredientWeight') or 0) for i in fndds_food.get('inputFoods', [])]
    total = sum(w for _, w in parts)
    shares = collections.defaultdict(float)
    if total > 0:
        for code, weight in parts:
            if code < 1_000_000:  # 8-digit ingredient codes are nested survey foods, not SR records
                shares[code] += weight / total
    return shares


# ---------------------------------------------------------------- exclusions

ALLOWED_PARENS = {'2%', '1%', 'skim'}
FNDDS_BRANDS = re.compile(r'Nesquik|Hamburger Helper|Easy Mac|McDonald|Burger King|Whopper|Big Mac|Quarter Pounder|Spaghettio|\bSpam\b|Nutella')
INGREDIENT_ONLY = re.compile(r'as ingredient|for use with vegetables|for use on a sandwich|Industrial oil|Breading or batter')
VARIANT_QUALIFIERS = re.compile(
    r',\s*(?:from (?:fresh|frozen|canned|raw|pre-cooked|precooked|restaurant|fast food|school cafeteria|dry mix|ready-to-eat|concentrate)'
    r'|NS as to [^,]*|NFS)(?=,|$)', re.I)

SR_SKIP_GROUPS = {
    'Baby Foods': 'infant formula, baby or toddler food',
    'American Indian/Alaska Native Foods': 'regional traditional-food survey records (outside app scope)',
}
SR_BRAND_CAPS = re.compile(r"\b[A-Z][A-Z'&.\-]{2,}\b")
SR_CAPS_OK = {'USDA', 'NFS', 'UHT', 'NS', 'II', 'III', 'NLEA', 'RTF', 'RTE', 'NFDM'}
SR_BRANDS = re.compile(
    r"Glutino|Archway|Andrea's|Goya|Oscar Mayer|Pillsbury|Crunchmaster|Pepperidge|Rudi's|Nabisco|La Ricura|Udi's|Schar|"
    r"Ready Crust|La Moderna|Gamesa|Van's|Heinz|Weight Watcher|Wonder|Mary's Gone|Sage Valley|Natreon|Monster|Muscle Milk|"
    r"Hormel|Spam|Krusteaz|Continental Mills|Lean Pockets|Reddi Wip|Kraft|Oreo|\bPost\b|Propel|Powerade|Creamsicle|"
    r"America's Beef Roast|Interstate Brands")
SR_RULES = [
    (re.compile(r'For Reference Only|Milk, human', re.I), 'human milk reference record'),
    (re.compile(r'USDA Commodity|school lunch|Child Nutrition|\bCN\b|military|Food Distribution Program for Indian', re.I),
     'institutional or program-specific record'),
    (re.compile(r'infant|toddler|\bbaby\b', re.I), 'infant formula, baby or toddler food'),
    (re.compile(r'\bunprepared\b|dry mix|\bmix, dry\b|mix, powder|, powder$|powder, dry|\bundiluted\b|dehydrated|'
                r'as packaged|as purchased|boxed, uncooked|, condensed$|condensed, (?:as purchased|canned)|canned, condensed|, dry, mix|\bdough\b', re.I),
     'unprepared form (prepared or ready-to-eat form preferred)'),
    (re.compile(r'separable fat|\bfat, (?:raw|cooked)\b|variety meats and by-products|\bbrain|\bspleen|\blungs?\b|'
                r'\bpancreas|\bthymus|\bsuet|\bcaul fat|mechanically separated|skin only|\bgiblets|\btestes|\bfeet\b|\bears\b|'
                r'\btail\b|\bchitterlings|\bjowl|\bcracklings|\bleaf fat|\bbackfat|\bkidneys?\b|\bheart\b|\btongue\b', re.I),
     'by-product or non-consumer cut'),
    (re.compile(r'leavening agent|gelatins?, dry powder|yeast extract|protein isolate|bran, crude|germ, crude|'
                r'meal, defatted|meal, partially|flour, defatted|flour, low fat|lecithin|industrial|fully hydrogenated|protein concentrate|'
                r'confection fat|for baking and confections|special purpose|shortening frying|shortening, (?:household|multipurpose|confectionery|frying)|'
                r'\bcottonseed\b|\bpalm kernel\b|\bbabassu\b|\btallow\b|\blard\b|\bfish oil\b|\bcupu assu\b|\bucuhuba\b|\bshea\b|\bsheanut\b|\bmutton tallow\b', re.I),
     'industrial ingredient or fat'),
]
MEAT_GROUPS = {'Beef Products', 'Pork Products', 'Lamb, Veal, and Game Products', 'Poultry Products'}
SR_TIER1 = ['Fruits and Fruit Juices', 'Vegetables and Vegetable Products', 'Legumes and Legume Products',
            'Nut and Seed Products', 'Finfish and Shellfish Products', 'Dairy and Egg Products',
            'Cereal Grains and Pasta', 'Spices and Herbs']
SR_WEIGHTS = {
    'Vegetables and Vegetable Products': 5, 'Fruits and Fruit Juices': 4, 'Finfish and Shellfish Products': 3,
    'Dairy and Egg Products': 2.5, 'Legumes and Legume Products': 2, 'Beef Products': 2, 'Poultry Products': 1.5,
    'Pork Products': 1.5, 'Nut and Seed Products': 1.5, 'Cereal Grains and Pasta': 1.5, 'Spices and Herbs': 1,
    'Lamb, Veal, and Game Products': 1, 'Sausages and Luncheon Meats': 0.7, 'Beverages': 0.7,
    'Soups, Sauces, and Gravies': 0.7, 'Restaurant Foods': 0.7, 'Fats and Oils': 0.5, 'Sweets': 0.5, 'Snacks': 0.5,
    'Baked Products': 0.5, 'Breakfast Cereals': 0.4, 'Meals, Entrees, and Side Dishes': 0.4,
}
SR_TIER2 = ['Poultry Products', 'Beef Products', 'Pork Products', 'Sausages and Luncheon Meats', 'Restaurant Foods',
            'Beverages', 'Soups, Sauces, and Gravies', 'Fats and Oils', 'Lamb, Veal, and Game Products',
            'Breakfast Cereals', 'Snacks', 'Meals, Entrees, and Side Dishes', 'Sweets', 'Baked Products']


def fndds_branded(desc):
    return bool([p for p in re.findall(r'\(([^)]*)\)', desc) if p not in ALLOWED_PARENS] or FNDDS_BRANDS.search(desc))


def sr_branded(desc):
    return bool([w for w in SR_BRAND_CAPS.findall(desc) if w.strip(".'") not in SR_CAPS_OK] or SR_BRANDS.search(desc))


def fndds_candidates(fndds, existing_codes, reasons):
    """Returns (generic, branded) candidate lists."""
    pool, branded = [], []
    for food in fndds:
        code, desc = food['foodCode'], food['description']
        category = food['wweiaFoodCategory']['wweiaFoodCategoryDescription']
        if code in existing_codes:
            continue
        if per100(food) is None:
            reasons['FNDDS: missing required nutrient'] += 1
        elif re.match(r'^(Baby |Formula|Human milk)', category) or re.search(r'Toddler|Infant formula|Baby', desc):
            reasons['FNDDS: infant formula, baby or toddler food'] += 1
        elif INGREDIENT_ONLY.search(desc):
            reasons['FNDDS: recipe-ingredient-only record'] += 1
        elif code in FDA_FRUIT_CODES:
            reasons['FNDDS: duplicate of an original FDA fruit'] += 1
        else:
            (branded if fndds_branded(desc) else pool).append(food)
    return pool, branded


def sr_candidates(sr, reasons):
    """Returns (generic, branded) candidate lists."""
    descriptions = {f['description'] for f in sr}
    pool, branded = [], []
    for food in sr:
        group, desc = food['foodCategory']['description'], food['description']
        rule = next((why for rx, why in SR_RULES if rx.search(desc)), None)
        if group in SR_SKIP_GROUPS:
            reasons['SR: ' + SR_SKIP_GROUPS[group]] += 1
        elif per100(food) is None:
            reasons['SR: missing required nutrient (usually fiber not analysed)'] += 1
        elif rule:
            reasons['SR: ' + rule] += 1
        elif re.search(r', with salt\b', desc) and desc.replace('with salt', 'without salt') in descriptions:
            reasons['SR: salted twin of an unsalted record'] += 1
        elif group in MEAT_GROUPS and re.search(r'\braw\b', desc):
            reasons['SR: raw meat (cooked form preferred)'] += 1
        elif group == 'Finfish and Shellfish Products' and re.search(r'\braw\b', desc) and (
                re.sub(r'\braw\b', 'cooked, dry heat', desc) in descriptions or re.sub(r'\braw\b', 'cooked, moist heat', desc) in descriptions):
            reasons['SR: raw seafood with a cooked record'] += 1
        elif re.search(r'\b(select|prime|choice)\b', desc) and re.sub(r'\b(select|prime|choice)\b', 'all grades', desc) in descriptions:
            reasons['SR: grade-specific twin of an all-grades record'] += 1
        elif re.search(r'\bfrozen, cooked\b', desc) and desc.replace('frozen, cooked', 'cooked') in descriptions:
            reasons['SR: frozen-then-cooked twin of a fresh cooked record'] += 1
        elif (m := re.search(r',\s*(?:no salt added|low sodium|reduced sodium|without salt added)', desc)) and \
                desc.replace(m.group(0), '') in descriptions:
            reasons['SR: sodium-only variant of a regular record'] += 1
        elif sr_branded(desc):
            branded.append(food)
        elif group == 'Fast Foods':
            reasons['SR: unbranded fast-food record (covered by FNDDS fast-food generics)'] += 1
        else:
            pool.append(food)
    return pool, branded


# ---------------------------------------------------------------- portions

FRACTIONS = {0.25: '1/4', 0.5: '1/2', 0.75: '3/4', 1.5: '1 1/2', 1 / 3: '1/3', 2 / 3: '2/3'}
PLURALS = {
    'cup': 'cups', 'slice': 'slices', 'piece': 'pieces', 'link': 'links', 'egg': 'eggs', 'cookie': 'cookies',
    'nugget': 'nuggets', 'wing': 'wings', 'cracker': 'crackers', 'strip': 'strips', 'stick': 'sticks',
    'patty': 'patties', 'tender': 'tenders', 'meatball': 'meatballs', 'sausage': 'sausages', 'tortilla': 'tortillas',
    'roll': 'rolls', 'pancake': 'pancakes', 'waffle': 'waffles', 'crispbread': 'crispbreads', 'pretzel': 'pretzels',
    'olive': 'olives', 'date': 'dates', 'prune': 'prunes', 'fig': 'figs', 'wafer': 'wafers', 'rib': 'ribs',
    'drumstick': 'drumsticks', 'thigh': 'thighs', 'taco': 'tacos', 'taquito': 'taquitos', 'dumpling': 'dumplings',
    'ball': 'balls', 'bite': 'bites', 'shrimp': 'shrimp', 'scallop': 'scallops', 'oyster': 'oysters', 'clam': 'clams',
    'mussel': 'mussels', 'wonton': 'wontons', 'potsticker': 'potstickers', 'pierogi': 'pierogies', 'cake': 'cakes',
    'fajita': 'fajitas', 'drummette': 'drummettes', 'chip': 'chips', 'crisp': 'crisps', 'mushroom': 'mushrooms',
    'spear': 'spears', 'floweret': 'flowerets', 'floret': 'florets', 'leaf': 'leaves', 'clove': 'cloves',
    'fillet': 'fillets', 'pepper': 'peppers', 'plantain': 'plantains', 'hush puppy': 'hush puppies', 'bar': 'bars',
    'marshmallow': 'marshmallows', 'candy': 'candies', 'truffle': 'truffles', 'caramel': 'caramels', 'kiss': 'kisses',
    'sheet': 'sheets', 'square': 'squares', 'triangle': 'triangles', 'chunk': 'chunks', 'cube': 'cubes',
    'medallion': 'medallions', 'sardine': 'sardines', 'anchovy': 'anchovies', 'cherry': 'cherries', 'grape': 'grapes',
    'nut': 'nuts', 'almond': 'almonds', 'crouton': 'croutons', 'pod': 'pods', 'sprig': 'sprigs', 'stalk': 'stalks',
    'strawberry': 'strawberries', 'sandwich': 'sandwiches', 'burrito': 'burritos', 'wrap': 'wraps', 'sub': 'subs',
    'slider': 'sliders', 'hamburger': 'hamburgers', 'cheeseburger': 'cheeseburgers', 'biscuit': 'biscuits', 'muffin': 'muffins',
    'bagel': 'bagels', 'donut': 'donuts', 'doughnut': 'doughnuts', 'croissant': 'croissants', 'brownie': 'brownies', 'rings': 'rings', 'ring': 'rings', 'tablespoon': 'tablespoons', 'teaspoon': 'teaspoons',
}


def amount_text(value):
    for frac, text in FRACTIONS.items():
        if math.isclose(value, frac, abs_tol=1e-9):
            return text
    return f'{value:g}'


def grams_text(grams):
    text = str(Decimal(repr(grams)).quantize(Decimal('0.1'), rounding=ROUND_HALF_UP))
    return text[:-2] if text.endswith('.0') else text


def tidy_unit(text):
    text = re.sub(r'\btablespoons?\b', 'tbsp', text)
    text = re.sub(r'\bteaspoons?\b', 'tsp', text)
    text = re.sub(r',\s*NFS\b|\s*\(NFS\)', '', text)
    text = re.sub(r'^1 NLEA [Ss]erving\b', '1 serving', text)
    text = re.sub(r'\s*\(?\b1 NLEA [Ss]erving\)?', '', text)
    text = re.sub(r'\(\s+', '(', re.sub(r'\s+\)', ')', text))
    text = re.sub(r'^(\S+ (?:oz|fl oz|cup|tbsp|tsp)) \(\1\)', r'\1', text)
    return re.sub(r'\s+', ' ', text).strip()


def scale_text(unit_text, multiplier):
    """'1 cup, cooked' x 2 -> '2 cups, cooked'; returns None when pluralisation is unknown."""
    rest = unit_text[2:]
    if multiplier == 1:
        return unit_text
    if multiplier < 1 or not math.isclose(multiplier, round(multiplier)) or multiplier == 1.5:
        if re.match(r'(cup|tbsp|tsp|fl oz|oz|lb)\b', rest):
            return f'{amount_text(multiplier)} {rest}'
        if multiplier < 1:
            return f'{amount_text(multiplier)} {rest}'
        return None
    if re.match(r'(tbsp|tsp|fl oz|oz)\b', rest):
        return f'{amount_text(multiplier)} {rest}'
    words = rest.split(' ')
    limit = next((i for i, w in enumerate(words) if w.startswith('(')), len(words))
    for i in range(min(4, limit)):
        for n in (2, 1):
            key = ' '.join(words[i:i + n]).rstrip(',').casefold()
            if key in PLURALS and not key.endswith('s'):
                trail = ',' if ' '.join(words[i:i + n]).endswith(',') else ''
                words[i:i + n] = [PLURALS[key] + trail]
                return f'{amount_text(multiplier)} {" ".join(words)}'
    return None


BAD_PORTION = re.compile(r'Quantity not specified|^Guideline|cubic inch|surface inch|100 calorie|'
                         r'^1 chip\b|^1 nut\b|^[\d./]+ NLEA [Ss]erving$|^1 crumb|^1 grain|^1 kernel|^1 seed\b|^1 bean\b|'
                         r'^1 pea\b|^1 flake|^1 shred|^1 (?:dash|pinch)', re.I)
VAGUE_PORTION = re.compile(r'yields|^1 serving$|^1 serving\b(?! \()|NS as to|any size|, NFS', re.I)
MEAT_CATEGORY = re.compile(r'^(?:Chicken, whole pieces|Fish|Shellfish|Beef, excludes ground|Pork|Lamb, goat, game|'
                           r'Turkey, duck, other poultry|Liver and organ meats|Cold cuts and cured meats|Sausages|Bacon|'
                           r'Frankfurters|Ground beef|Sausages and Luncheon Meats|Finfish and Shellfish Products|Beef Products|'
                           r'Pork Products|Poultry Products|Lamb, Veal, and Game Products)$')


HANDHELD = re.compile(r'Cakes|pies|Cookies|brownies|breads|Rolls|Bagels|Pizza|sandwich|Burgers|Doughnuts|pastries|Biscuits|'
                      r'muffins|Pancakes|Turnovers|Baked Products|Crackers', re.I)
WHOLE_ITEM = re.compile(r'^1 pizza\b|^1/2 pie\b|^1 pie\b|\bloaf\b|\bpizza \(|\bwhole (?:cake|pie|pizza)|\b\d+" (?:cake|pie)|\bcake \(|\bpie \(\d|\bpackage\b|\bbox\b|\bbag \(\d+ oz|family|party', re.I)


def branded_portion(text):
    words = re.findall(r"[A-Za-z][A-Za-z'&]*", text)
    if text[:1].isalpha():
        words = words[1:]  # e.g. "Skin from 1 small"
    return any(w[0].isupper() and w not in ('NS', 'NFS') for w in words)
SIZE_WORDS = re.compile(r'miniature|bite|snack-size|fun/snack|child|kid|toddler|extra[- ]large|sharing|movie theater|family|party|jumbo', re.I)


def portion_options(portions, drink, category, branded=False):
    """Documented portions plus common household multiples of cups, spoons, fluid ounces, ounces and items."""
    options = []
    for p in portions:
        base = tidy_unit(p['text'])
        if p['grams'] <= 0 or BAD_PORTION.search(p['text']) or (branded_portion(base) and not branded):
            continue
        if not re.match(r'^1 ', base):
            options.append((p, 1, base))
            continue
        rest = base[2:]
        if rest.startswith('cup'):
            mults = [0.25, 0.5, 0.75, 1, 1.5, 2]
        elif rest.startswith(('tbsp', 'tsp')):
            mults = [1, 2]
        elif rest.startswith('fl oz'):
            if category in ('Liquor and cocktails',) or 'liquor' in category.lower():
                mults = [1, 1.5]
            elif category == 'Wine' or re.search(r'\bwine\b', category, re.I):
                mults = [5]
            elif drink:
                mults = [8, 12]
            else:
                mults = [1, 2]
        elif rest.startswith('oz'):
            mults = [1, 2, 3, 4]
        else:
            mults = [1, 2, 3, 4, 6] if p['grams'] < 40 else [1, 2]
        for m in mults:
            text = scale_text(base, m)
            if text:
                options.append((p, m, text))
    return options


def choose_portion(portions, target, drink, category, kcal100, branded=False, description=''):
    best = None
    skinless = bool(re.search(r'without skin|skin not eaten|meat only|skinless', description, re.I))
    portions = [p for p in portions if not (re.search(r'without skin|skin removed', p['text']) and not skinless)
                and not (re.search(r'\bwith skin', p['text']) and skinless)]
    for portion, mult, text in portion_options(portions, drink, category, branded):
        grams = round(portion['grams'] * mult, 3)
        if grams <= 0 or kcal100 * grams / 100 > MAX_CALORIES:
            continue
        score = abs(math.log(grams / target))
        score += 0 if mult == 1 else (0.3 if branded and mult > 1 else 0.05)
        score += 0.1 if mult in (0.75, 1.5) else 0
        score += 0.25 if SIZE_WORDS.search(text) else 0
        own_serving = (branded or category in ('Restaurant Foods', 'Fast Foods')) and re.match(r'^1 serving\b', portion['text'])
        score += 0.3 if VAGUE_PORTION.search(portion['text']) and not own_serving else 0
        score += 0.8 if MEAT_CATEGORY.match(category) and re.search(r'\bcups?\b', text) else 0
        score += 0.4 if HANDHELD.search(category) and re.search(r'\bcups?\b', text) else 0
        score += 0.5 if WHOLE_ITEM.search(text) else 0
        key = (round(score, 6), portion['seq'], mult)
        if best is None or key < best[0]:
            best = (key, portion, mult, text, grams)
    return best[1:] if best else None


def fndds_portions(food):
    return [{'id': p['id'], 'text': p['portionDescription'], 'grams': p['gramWeight'], 'seq': p.get('sequenceNumber', 0)}
            for p in food['foodPortions']]


def sr_portions(food):
    out = []
    for p in food.get('foodPortions', []):
        modifier = (p.get('modifier') or '').strip()
        unit = p.get('measureUnit', {}).get('name', 'undetermined')
        label = modifier if unit == 'undetermined' else f'{unit} {modifier}'.strip()
        amount = p.get('amount') or p.get('value') or 1
        out.append({'id': p['id'], 'text': f'{amount_text(amount)} {label}'.strip(), 'grams': p.get('gramWeight') or 0,
                    'seq': p.get('sequenceNumber', 0)})
    return out


SR_TARGETS = [
    (re.compile(r'\b(?:dry|dried|powder|powdered|flour|concentrate)\b(?!.*\b(?:cooked|prepared|reconstituted)\b)', re.I), 30),
    (re.compile(r'(?:prepared|cooked) with (?:water|milk)|, cooked\b.*\bcereal|cereal.*\bcooked', re.I), 240),
    (re.compile(r'juice|milk|drink|beverage|soymilk|nectar|soda|lemonade|punch|coffee|tea\b|wine|beer|smoothie|kefir|buttermilk|eggnog', re.I), 240),
    (re.compile(r'\bsoup\b|chowder|broth|stew', re.I), 245),
    (re.compile(r'\boil\b|butter\b|margarine|ghee|shortening|mayonnaise|dressing|spread', re.I), 14),
    (re.compile(r'\bcheese\b', re.I), 28),
    (re.compile(r'yogurt|pudding|cottage', re.I), 170),
    (re.compile(r'flour|meal\b|starch|bran\b|germ\b|, dry$|, uncooked|mature seeds, raw|dry roasted|\braw$', re.I), 45),
    (re.compile(r'\bnuts?\b|seeds?\b|almond|cashew|pecan|walnut|pistachio|peanut', re.I), 28),
    (re.compile(r'candies|candy|chocolate|syrup|jam|jelly|honey|sugar|frosting|topping|sauce|gravy|salsa|relish|catsup|ketchup', re.I), 30),
]
SR_GROUP_TARGETS = {
    'Fruits and Fruit Juices': 140, 'Vegetables and Vegetable Products': 90, 'Legumes and Legume Products': 170,
    'Nut and Seed Products': 28, 'Spices and Herbs': 3, 'Cereal Grains and Pasta': 160, 'Finfish and Shellfish Products': 85,
    'Dairy and Egg Products': 100, 'Poultry Products': 85, 'Beef Products': 85, 'Pork Products': 85,
    'Lamb, Veal, and Game Products': 85, 'Sausages and Luncheon Meats': 50, 'Fats and Oils': 14, 'Beverages': 240,
    'Soups, Sauces, and Gravies': 245, 'Sweets': 30, 'Snacks': 28, 'Baked Products': 50, 'Breakfast Cereals': 30,
    'Restaurant Foods': 250, 'Meals, Entrees, and Side Dishes': 250, 'Fast Foods': 250,
}
DRINK_CATEGORY = re.compile(r'drink|juice|milk|water|soda|soft drink|coffee|tea|beer|wine|liquor|cocktail|smoothie|shake|beverage', re.I)


# ---------------------------------------------------------------- names

SR_PREFIXES = re.compile(r'^(?:Beverages|Alcoholic [Bb]everages?|Snacks?|Candies|Spices|Mollusks|Crustaceans|Fish|Cereals ready-to-eat|Cereals|Nuts|Seeds),\s*')
ALIAS_SWAPS = [
    (r'\bSoft drink\b', 'Soda'), (r'\bFrankfurters?\b', 'Hot dog'), (r'\bGarbanzo beans?\b', 'Chickpeas'),
    (r'\bChickpeas\b', 'Garbanzo beans'), (r'\bCatsup\b', 'Ketchup'), (r'\bScallions?\b', 'Green onions'),
    (r'\bCilantro\b', 'Coriander leaves'), (r'\bEggplant\b', 'Aubergine'), (r'\bZucchini\b', 'Courgette'),
    (r'\bShrimp\b', 'Prawns'), (r'\bSquash, summer, zucchini\b', 'Zucchini'), (r'\bBeans, snap, green\b', 'Green beans'),
    (r'\bBeans, snap, yellow\b', 'Wax beans'), (r'\bPeppers, sweet, red\b', 'Red bell pepper'),
    (r'\bPeppers, sweet, green\b', 'Green bell pepper'), (r'\bPeppers, sweet, yellow\b', 'Yellow bell pepper'),
    (r'\bGame meat, deer\b', 'Venison'), (r'\bGame meat, bison\b', 'Bison'), (r'\bGame meat, elk\b', 'Elk'),
    (r'\bSoymilk\b', 'Soy milk'), (r'\bRutabagas?\b', 'Swede'),
    (r'\bArugula\b', 'Rocket'), (r'\bCantaloupe\b', 'Muskmelon'), (r'\bPotato, french fries\b', 'French fries'),
    (r'\bFrench fries\b', 'Fries'), (r'\bSeltzer\b', 'Sparkling water'),
    (r'\bOatmeal\b', 'Porridge'), (r'\bGrits\b', 'Hominy grits'), (r'\bPop\b', 'Soda'),
    (r'\bBeef, ground\b', 'Ground beef'), (r'\bPork, cured, bacon\b', 'Bacon'), (r'\bTurkey, ground\b', 'Ground turkey'),
    (r'\bChicken, ground\b', 'Ground chicken'), (r'\bBeans, kidney\b', 'Kidney beans'), (r'\bBeans, black\b', 'Black beans'),
    (r'\bBeans, pinto\b', 'Pinto beans'), (r'\bBeans, navy\b', 'Navy beans'), (r'\bBeans, great northern\b', 'Great northern beans'),
    (r'\bDoughnuts?\b', 'Donut'), (r'\bBarbecue\b', 'BBQ'), (r'\bCassava\b', 'Yuca'), (r'^Chard\b', 'Swiss chard'),
    (r'\bChard, swiss\b', 'Swiss chard'), (r'\bCabbage, chinese \(pak-choi\)', 'Bok choy'),
    (r'\bCabbage, Chinese\b', 'Bok choy'), (r'\bCabbage, chinese \(pe-tsai\)', 'Napa cabbage'),
    (r'\bGarbanzo\b', 'Chickpea'),
    (r'\bNuts, (\w+)', r'\1'), (r'\bSeeds, (\w+) seeds?\b', r'\1 seeds'),
]


def clean_fndds_name(desc):
    name = VARIANT_QUALIFIERS.sub(lambda m: '' if re.search(r'NS as to|NFS', m.group(0)) else m.group(0), desc)
    return re.sub(r'\s+', ' ', name).strip(' ,')


def clean_sr_name(desc):
    name = re.sub(r'\s*\((?:[^()]*\b(?:[Ii]ncludes?|may contain|USDA)\b[^()]*)\)', '', desc)
    name = SR_PREFIXES.sub('', name)
    name = re.sub(r',\s*without salt(?: added)?\b', '', name).rstrip('.')
    name = re.sub(r'^Restaurant, ([^,]+), (.+)$', r'\2 (\1 restaurant)', name)
    name = re.sub(r'\s+', ' ', name).strip(' ,')
    return name[:1].upper() + name[1:]


KEEP_UPPER = {'KFC', 'TGI', 'T.G.I.', 'USA', 'US', 'DQ', 'BBQ', 'M&M', "M&M's", 'IHOP', 'ARA', 'DHA', 'II', 'XL', 'KG', 'GmbH'}
SMALL_WORDS = {'Of', 'And', 'With', 'The', 'In', 'A', 'On', 'Or', 'For'}


def brand_case(word):
    if word.strip('.,') in KEEP_UPPER:
        return word
    if word.upper().startswith('MCDONALD'):
        return "McDonald's"
    return '-'.join(part[:1] + part[1:].lower() for part in word.split('-'))


def clean_branded_sr_name(desc):
    desc = re.sub(r"McDONALD'?S", "McDonald's", desc)
    desc = re.sub(r'MARS SNACKFOOD US,\s*|The COCA-COLA company,\s*|M&M MARS,\s*', '', desc)
    stripped = SR_PREFIXES.sub('', re.sub(r'^Restaurant,\s*', '', desc)).strip()
    first = stripped.split(',')[0]
    name = clean_sr_name(desc) if not desc.startswith('Restaurant,') else stripped
    name = SR_BRAND_CAPS.sub(lambda m: brand_case(m.group(0)), name)
    words = name.split(' ')
    name = ' '.join([words[0]] + [w.lower() if w in SMALL_WORDS else w for w in words[1:]])
    brand_first = all(w.isupper() or not w.isalpha() for w in re.findall(r"[A-Za-z]+", first)) or SR_BRANDS.match(first)
    if brand_first and ', ' in name:
        head, rest = name.split(', ', 1)
        name = f'{head} {rest}'
    name = re.sub(r'^(\w+) \1\b', r'\1', name, flags=re.I)
    name = re.sub(r'\b(OF|AND|THE|WITH|IN|N)\b', lambda m: m.group(0).lower(), name)
    for wrong, right in (("M&m's", "M&M's"), ('T.g.i.', 'T.G.I.'), ('5TH', '5th'), ('Mcdonald', 'McDonald')):
        name = name.replace(wrong, right)
    return re.sub(r'\s+', ' ', name).strip(' ,')


def brand_aliases(name):
    out = []
    m = re.match(r'^(.*?)\s*\(([^)]+)\)$', name)
    if m and m.group(2) not in ALLOWED_PARENS:
        product, brand = m.group(1), m.group(2).replace('McDonalds', "McDonald's")
        out.append(f'{brand} {product}')
    for text in [name] + out:
        if "'" in text:
            out.append(text.replace("'", ''))
        if 'McDonalds' in text:
            out.append(text.replace('McDonalds', "McDonald's"))
    return out


def aliases_for(name, description, taken_names, branded=False):
    raw = brand_aliases(name) if branded == 'fndds' else [name.replace("'", '')] if branded else []
    if app_norm(description) != app_norm(name):
        raw.append(re.sub(r'\s*\((?:[^()]*\b(?:[Ii]ncludes?|USDA)\b[^()]*)\)', '', description).strip())
    for pattern, repl in ([] if branded else ALIAS_SWAPS):
        swapped = re.sub(pattern, repl, name)
        if swapped != name:
            raw.append(swapped[:1].upper() + swapped[1:])
    seen, out = {app_norm(name)}, []
    for alias in raw:
        alias = re.sub(r'\s+', ' ', alias).strip()
        key = app_norm(alias)
        if key and key not in seen and key not in taken_names:
            seen.add(key)
            out.append(alias)
    return out


# ---------------------------------------------------------------- selection

def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('downloads', type=Path)
    parser.add_argument('--target', type=int, default=5000)
    args = parser.parse_args()

    fndds, sr = load_sources(args.downloads)
    people, median_grams = nhanes_intake(args.downloads / NHANES[0])
    manifest = json.loads(MANIFEST.read_text())
    original = manifest['foods'][:1000]  # the reviewed 1,000-food catalog always leads the manifest
    assert len(original) == 1000 and not any(f['id'].startswith('usda-sr-') for f in original)
    fndds_by_code = {f['foodCode']: f for f in fndds}
    existing_codes = {c['code'] for f in original for c in f.get('components', [])}
    primary_codes = {f['components'][0]['code'] for f in original if 'components' in f}
    taken = {app_norm(f['name']) for f in original} | {app_norm(a) for f in original for a in f['aliases']}
    reasons = collections.Counter()

    # FNDDS candidates, then drop variants whose nutrition matches a kept sibling.
    fpool, fbrands = fndds_candidates(fndds, primary_codes | {c for c in existing_codes}, reasons)
    fpool.sort(key=lambda f: (-people.get(f['foodCode'], 0), f['foodCode']))
    stems = collections.defaultdict(list)
    for code in primary_codes | FDA_FRUIT_CODES:
        f = fndds_by_code[code]
        stems[(f['wweiaFoodCategory']['wweiaFoodCategoryDescription'], app_norm(VARIANT_QUALIFIERS.sub('', f['description'])))].append(per100(f))
    kept_fndds, redundant = [], []
    for f in fpool:
        key = (f['wweiaFoodCategory']['wweiaFoodCategoryDescription'], app_norm(VARIANT_QUALIFIERS.sub('', f['description'])))
        nut = per100(f)
        if any(close_nutrition(nut, other) for other in stems[key]):
            reasons['FNDDS: nutritionally redundant source/NS variant of a kept food'] += 1
            redundant.append(f['description'])
            continue
        stems[key].append(nut)
        kept_fndds.append(f)

    # SR Legacy: drop foods an FNDDS food already represents.
    spool, sbrands = sr_candidates(sr, reasons)
    covered = {}
    fndds_final_codes = primary_codes | FDA_FRUIT_CODES | {f['foodCode'] for f in kept_fndds}
    for code in sorted(fndds_final_codes):
        for ndb, share in sr_shares(fndds_by_code[code]).items():
            covered.setdefault(ndb, []).append((share, code))
    popularity = collections.Counter()
    for code, food in fndds_by_code.items():
        for ndb, share in sr_shares(food).items():
            popularity[ndb] += people.get(code, 0) * share
    def name_tokens(text):
        return set(app_norm(text).split()) - {'raw', 'cooked', 'with', 'and', 'or', 'no', 'added', 'fat', 'without',
                                               'salt', 'the', 'of', 'in', 'nfs', 'ns', 'as', 'to'}
    fndds_profiles = [(name_tokens(clean_fndds_name(fndds_by_code[c]['description'])), per100(fndds_by_code[c]))
                      for c in sorted(primary_codes | {f['foodCode'] for f in kept_fndds if people.get(f['foodCode'], 0) > 0})]
    fndds_profiles += [(name_tokens(f['name']), per100(fndds_by_code[f['components'][0]['code']]))
                       for f in original if 'components' in f]

    def semantic_duplicate(food):
        t, p = name_tokens(clean_sr_name(food['description'])), per100(food)
        for u, q in fndds_profiles:
            if t and u and len(t & u) / len(t | u) >= 0.6 and abs(p['kcal'] - q['kcal']) <= max(3, 0.05 * q['kcal']) and \
                    all(abs(p[k] - q[k]) <= max(0.5, 0.1 * q[k]) for k in ('protein', 'totalCarbs', 'fat')):
                return True
        return False

    sr_kept, sr_seen = [], collections.defaultdict(list)
    tier = {g: i for i, g in enumerate(SR_TIER1 + SR_TIER2)}
    spool.sort(key=lambda f: (0 if popularity[f['ndbNumber']] > 0 else 1, -popularity[f['ndbNumber']],
                              tier[f['foodCategory']['description']], f['description'].count(','), f['fdcId']))
    ranked = [f for f in spool if popularity[f['ndbNumber']] > 0]
    by_group = collections.defaultdict(list)
    for f in spool:
        if popularity[f['ndbNumber']] == 0:
            by_group[f['foodCategory']['description']].append(f)
    queue = []
    for group, foods in by_group.items():
        foods.sort(key=lambda f: (f['description'].count(','), len(f['description']), f['fdcId']))
        queue += [((k + 1) / SR_WEIGHTS[group], tier[group], f['fdcId'], f) for k, f in enumerate(foods)]
    ranked += [item[-1] for item in sorted(queue, key=lambda item: item[:3])]
    for f in ranked:
        nut = per100(f)
        dup = None
        for share, code in covered.get(f['ndbNumber'], []):
            other = per100(fndds_by_code[code])
            if (share >= 0.85 and similar_nutrition(nut, other)) or (share >= 0.5 and close_nutrition(nut, other)):
                dup = code
                break
        if dup:
            reasons['SR: same food as a selected FNDDS record (via FNDDS ingredient link)'] += 1
            continue
        if semantic_duplicate(f):
            reasons['SR: same food as an FNDDS record (similar name and nutrition)'] += 1
            continue
        stem = app_norm(re.sub(r'trimmed to [^,]*|\b(all grades|choice|select|prime)\b|\([^)]*\)', '', f['description']))
        if any(close_nutrition(nut, other) for other in sr_seen[stem]):
            reasons['SR: nutritionally redundant trim/grade variant'] += 1
            continue
        sr_seen[stem].append(nut)
        sr_kept.append(f)

    # Portions, names and aliases.
    def build(food, dataset, branded=False):
        nut = per100(food)
        if dataset == 'fndds':
            code = food['foodCode']
            category = food['wweiaFoodCategory']['wweiaFoodCategoryDescription']
            cat_meds = category_medians.get(category, 100)
            target = median_grams[code] if people.get(code, 0) >= 10 else cat_meds
            target = min(target, 500 if DRINK_CATEGORY.search(category) else 400)
            portions = fndds_portions(food)
            name = clean_fndds_name(food['description'])
            drink = bool(DRINK_CATEGORY.search(category))
        else:
            category = food['foodCategory']['description']
            head = clean_sr_name(food['description']).split(',')[0]
            rules = SR_TARGETS[:2] if branded else SR_TARGETS
            target = next((t for i, (rx, t) in enumerate(rules) if rx.search(food['description'] if i < 2 else head)),
                          SR_GROUP_TARGETS[category])
            portions = sr_portions(food)
            name = (clean_branded_sr_name if branded else clean_sr_name)(food['description'])
            drink = category == 'Beverages' or bool(re.search(r'juice|milk|drink|nectar', food['description'], re.I))
        choice = choose_portion(portions, target, drink, category, nut['kcal'], branded, food['description'])
        if choice:
            portion, mult, text, grams = choice
            comp = {'portionId': portion['id'], 'multiplier': mult, 'grams': grams,
                    'basis': portion['text'] if mult == 1 else f"{portion['text']} × {mult:g}"}
            serving = f'{text} ({grams_text(grams)} g)'
        else:
            if nut['kcal'] > MAX_CALORIES:
                return None
            comp = {'grams': 100, 'basis': '100 g (no reliable household portion in source)'}
            serving = '100 g'
        return name, category, comp, serving

    category_medians = collections.defaultdict(list)
    for code, grams in median_grams.items():
        if code in fndds_by_code and people.get(code, 0) >= 3:
            category_medians[fndds_by_code[code]['wweiaFoodCategory']['wweiaFoodCategoryDescription']].append(grams)
    category_medians = {k: statistics.median(v) for k, v in category_medians.items()}

    needed = args.target - len(original)
    reported = [f for f in kept_fndds if people.get(f['foodCode'], 0) > 0]
    unreported = [f for f in kept_fndds if people.get(f['foodCode'], 0) == 0]
    ordered = [('fndds', f) for f in reported] + [('sr', f) for f in sr_kept] + [('fndds', f) for f in unreported]

    # Branded foods are appended after the generic target, labelled with their brand, never as generic substitutes.
    fbrands.sort(key=lambda f: (-people.get(f['foodCode'], 0), f['foodCode']))
    brand_rank = {'Fast Foods': 0, 'Restaurant Foods': 1}
    sbrands.sort(key=lambda f: (brand_rank.get(f['foodCategory']['description'], 2), f['description']))
    fndds_brand_keys = [set(app_norm(re.sub(r"'", '', f['description'])).split()) - {'sandwich', 'the'} for f in fbrands]
    brand_dupes = []
    kept_sbrands = []
    for f in sbrands:
        key = set(app_norm(re.sub(r"'", '', f['description'])).split()) - {'sandwich', 'the', 'fast', 'foods'}
        match = next((fb for fb, k in zip(fbrands, fndds_brand_keys) if k and k == key), None)
        if match:
            reasons['SR brand: same product as an FNDDS brand record'] += 1
            brand_dupes.append([f['description'], match['description']])
        else:
            kept_sbrands.append(f)
    ordered += [('fndds-brand', f) for f in fbrands] + [('sr-brand', f) for f in kept_sbrands]

    additions, names, collisions = [], set(taken), []
    brand_ids = set()
    for dataset, food in ordered:
        branded = dataset.endswith('-brand')
        dataset = dataset.replace('-brand', '')
        if len(additions) >= needed and not branded:
            reasons['below selection cutoff: FNDDS not reported in NHANES day one' if dataset == 'fndds'
                    else 'below selection cutoff: lower-priority SR Legacy record'] += 1
            continue
        built = build(food, dataset, branded)
        if built is None:
            reasons['no portion within calorie limit'] += 1
            continue
        name, category, comp, serving = built
        if app_norm(name) in names:
            fallback = re.sub(r'\s+', ' ', food['description']).strip()
            if dataset == 'sr':
                fallback = clean_sr_name(food['description'].replace('without salt', 'no salt'))
            if app_norm(fallback) in names:
                reasons['name collides with an existing food'] += 1
                collisions.append(food['description'])
                continue
            name = fallback
        names.add(app_norm(name))
        if branded:
            brand_ids.add(f"usda-{food['foodCode']}" if dataset == 'fndds' else f"usda-sr-{food['fdcId']}")
        if dataset == 'fndds':
            entry = {'id': f"usda-{food['foodCode']}", 'name': name, 'serving': serving, 'category': category,
                     'components': [{'code': food['foodCode'], **comp}]}
        else:
            entry = {'id': f"usda-sr-{food['fdcId']}", 'name': name, 'serving': serving, 'category': category,
                     'components': [{'dataset': 'sr_legacy', 'fdcId': food['fdcId'], **comp}]}
        entry['_description'] = food['description']
        entry['_branded'] = dataset if branded else False
        additions.append(entry)

    # Aliases last, so an alias never equals another food's name.
    all_names = {app_norm(f['name']) for f in original} | {app_norm(e['name']) for e in additions}
    for entry in additions:
        others = all_names - {app_norm(entry['name'])}
        entry['aliases'] = aliases_for(entry['name'], entry.pop('_description'), others, entry.pop('_branded'))
    original_aliases = {app_norm(a) for f in original for a in f['aliases']}
    alias_use = collections.Counter(app_norm(a) for e in additions for a in e['aliases'])
    for entry in additions:
        # An alias shared with another food would make it ambiguous in search matching; drop it.
        entry['aliases'] = [a for a in entry['aliases'] if alias_use[app_norm(a)] == 1 and app_norm(a) not in original_aliases]
        order = ['id', 'name', 'aliases', 'serving', 'category', 'components']
        entry_sorted = {k: entry[k] for k in order}
        entry.clear()
        entry.update(entry_sorted)

    generic = [e for e in additions if not brand_ids or e['id'] not in brand_ids]
    assert len(generic) == needed, f'Shortfall: {needed - len(generic)} generic foods'
    manifest['foods'] = original + additions
    manifest['additionalSources'] = [{
        'dataset': 'USDA SR Legacy (April 2018)',
        'url': 'https://fdc.nal.usda.gov/fdc-datasets/' + SR_ZIP,
        'sha256': SOURCES[SR_ZIP],
    }]
    manifest['expansionNote'] = (
        f'Foods {len(original) + 1}-{args.target} were appended by scripts/curate_food_catalog.py: FNDDS foods reported '
        'in reliable NHANES 2021-2023 day-one recalls (most-reported first), then SR Legacy foods not already represented '
        f'by an FNDDS food. Foods {args.target + 1}-{len(original) + len(additions)} are brand-name products and '
        'restaurant-chain items from the same two releases, named with their brand. Portions: the documented household '
        'portion (or common multiple) closest to the NHANES median amount per report, or a food-group default for foods '
        'without reports. Frozen after review; edit entries here.')
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    report = {
        'genericTarget': args.target, 'original': len(original), 'added': len(additions),
        'total': len(original) + len(additions), 'brandedAdded': len(brand_ids),
        'addedBySource': collections.Counter(('SR Legacy' if e['id'].startswith('usda-sr-') else 'FNDDS')
                                             + (' (brand)' if e['id'] in brand_ids else '') for e in additions),
        'brandedSrDuplicatesOfFndds': brand_dupes,
        'candidatePools': {'fnddsAfterExclusions': len(kept_fndds), 'fnddsReportedInNhanes': len(reported),
                           'fnddsUnreported': len(unreported), 'srAfterExclusionsAndDedup': len(sr_kept)},
        'exclusions': dict(sorted(reasons.items())),
        'redundantFnddsVariants': redundant,
        'nameCollisionsSkipped': collisions,
    }
    REPORT.write_text(json.dumps(report, indent=1) + '\n')
    print(json.dumps(report, indent=1))


if __name__ == '__main__':
    main()
