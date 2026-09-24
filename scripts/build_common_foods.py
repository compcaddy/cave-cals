#!/usr/bin/env python3
"""Rebuild the bundled food catalog from the pinned USDA archives (no API key).

From the repository root:

  python3 scripts/build_common_foods.py \\
      /path/to/FoodData_Central_survey_food_json_2024-10-31.zip \\
      --sr-legacy /path/to/FoodData_Central_sr_legacy_food_json_2018-04.zip
  python3 scripts/build_common_foods.py <same arguments> --check

The manifest fixes every food's name, aliases, source record, portion and
multiplier; nothing is ranked or randomly selected at build time. Every archive
must match the SHA-256 recorded in the manifest. --check rebuilds in memory and
fails unless App/CommonFoods.json is byte-for-byte identical. Standard library only.
"""
import argparse
import hashlib
import json
import math
import re
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'Documentation/FoodCatalog/manifest.json'
OUTPUT = ROOT / 'App/CommonFoods.json'
SOURCE_URL = 'https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_survey_food_json_2024-10-31.zip'
FNDDS_DATASET = 'USDA FNDDS 2021-2023'
SR_DATASET = 'USDA SR Legacy (April 2018)'
EXPECTED_FOODS = 5904  # 1,000 original + 4,000 generic additions + 904 brand-name/restaurant-chain foods
GENERIC_FOODS = 5000
ORIGINAL_FOODS = 1000

ENERGY = 1008
NUTRIENTS = {'protein': 1003, 'totalCarbs': 1005, 'fiber': 1079, 'fat': 1004}
NOTE = ('Approximate calories and nutrient grams per stated everyday serving. Total carbohydrates include fiber; net carbs '
        'are calculated in the app. Mixed dishes use the described recipe assumptions; actual recipes vary. Personal '
        'defaults override these values without changing past entries. Foods 1-1,000 are the original reviewed catalog; '
        'foods 1,001-5,000 add generic USDA FNDDS 2021-2023 foods and, where FNDDS has no equivalent, USDA SR Legacy '
        '(April 2018) foods listed in additionalSources. Foods 5,001 onward are brand-name products and restaurant-chain '
        'items named with their brand; their values reflect USDA analyses (SR Legacy items are 2018 or earlier) and may '
        'not match current formulations.')


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def amount(food, nutrient_id, unit):
    matches = [n for n in food['foodNutrients'] if n['nutrient']['id'] == nutrient_id and n.get('amount') is not None]
    assert len(matches) == 1, f"Nutrient {nutrient_id} missing or repeated for {food['description']}"
    assert matches[0]['nutrient']['unitName'] == unit, f"Unexpected unit for nutrient {nutrient_id}"
    value = matches[0]['amount']
    assert isinstance(value, (int, float)) and math.isfinite(value) and value >= 0, food['description']
    return value


def nutrients(food):
    return {key: amount(food, nutrient_id, 'g') for key, nutrient_id in NUTRIENTS.items()}


def energy(food):
    return amount(food, ENERGY, 'kcal')


def load_sources(fndds_path, sr_path, manifest):
    assert sha256(fndds_path) == manifest['sourceArchiveSHA256'], 'FNDDS archive differs from reviewed release'
    with zipfile.ZipFile(fndds_path) as z:
        fndds = {f['foodCode']: f for f in json.loads(z.read('surveyDownload.json'))['SurveyFoods']}
    sr = {}
    for extra in manifest.get('additionalSources', []):
        assert extra['dataset'] == SR_DATASET, f"Unknown supplemental dataset {extra['dataset']}"
        assert sr_path, '--sr-legacy is required: the manifest contains SR Legacy foods'
        assert sha256(sr_path) == extra['sha256'], 'SR Legacy archive differs from reviewed release'
        with zipfile.ZipFile(sr_path) as z:
            sr = {f['fdcId']: f for f in json.loads(z.read(z.namelist()[0]))['SRLegacyFoods']}
    return fndds, sr


def resolve(part, fndds, sr):
    """Return (source food, dataset, provenance identity) for one manifest component."""
    if part.get('dataset') == 'sr_legacy':
        food = sr[part['fdcId']]
        return food, SR_DATASET, {'fdcId': food['fdcId'], 'ndbNumber': food['ndbNumber']}
    food = fndds[part['code']]
    return food, FNDDS_DATASET, {'foodCode': food['foodCode'], 'fdcId': food['fdcId']}


def generate(fndds, sr, manifest, fndds_url=SOURCE_URL):
    foods = []
    for spec in manifest['foods']:
        food = {k: spec[k] for k in ('id', 'name', 'aliases', 'serving')}
        food['category'] = spec['category']
        if 'legacyCalories' in spec:
            food['calories'] = spec['legacyCalories']
            food['nutritionSource'] = spec['nutritionSource']
            food['macrosPerServing'] = spec['macrosPerServing']
            foods.append(food)
            continue
        components, datasets = [], set()
        raw_calories = 0
        raw_macros = {key: 0 for key in NUTRIENTS}
        for part in spec['components']:
            source, dataset, identity = resolve(part, fndds, sr)
            datasets.add(dataset)
            grams = part['grams']
            if 'portionId' in part:
                portion = next(p for p in source['foodPortions'] if p['id'] == part['portionId'])
                assert math.isclose(portion['gramWeight'] * part.get('multiplier', 1), grams, abs_tol=0.01), spec['id']
            else:
                # Only app recipe assumptions and honest 100 g servings may omit a USDA portion.
                assert part['basis'].startswith(('App recipe assumption', '100 g')), spec['id']
                assert not part['basis'].startswith('100 g') or grams == 100, spec['id']
            kcal = energy(source)
            per100g = nutrients(source)
            raw_calories += kcal * grams / 100
            for key, value in per100g.items():
                raw_macros[key] += value * grams / 100
            components.append({
                **identity, 'description': source['description'], 'grams': grams,
                'kcalPer100g': kcal, 'macrosPer100g': per100g, 'portionBasis': part['basis'],
                'url': f"https://fdc.nal.usda.gov/food-details/{source['fdcId']}/nutrients",
            })
        assert len(datasets) == 1, f"{spec['id']} mixes datasets"
        food['calories'] = int(math.floor(raw_calories + 0.5))
        food['macrosPerServing'] = {key: round(value, 2) for key, value in raw_macros.items()}
        food['nutritionSource'] = {
            'dataset': datasets.pop(),
            'method': 'recipe sum' if len(components) > 1 else 'USDA nutrients × portion weight',
            'components': components,
        }
        foods.append(food)
    catalog = {
        'version': 3,
        'source': fndds_url,
        'sourceArchiveSHA256': manifest['sourceArchiveSHA256'],
        'note': NOTE,
    }
    if manifest.get('additionalSources'):
        catalog['additionalSources'] = manifest['additionalSources']
    catalog['foods'] = foods
    return catalog


def normalized(name):
    return ' '.join(name.casefold().split())


def app_normalized(name):
    return ' '.join(re.findall(r'[0-9a-z]+', name.casefold()))


def validate(catalog):
    foods = catalog['foods']
    assert len(foods) == EXPECTED_FOODS, f'Expected {EXPECTED_FOODS:,} foods; got {len(foods):,}'
    assert len({f['id'] for f in foods}) == len(foods), 'Duplicate ID'
    assert len({normalized(f['name']) for f in foods}) == len(foods), 'Duplicate name'
    assert len({app_normalized(f['name']) for f in foods}) == len(foods), 'Duplicate name after app search normalization'
    for f in foods:
        assert all(isinstance(f[k], str) and f[k].strip() for k in ('id', 'name', 'serving', 'category')), f['id']
        assert isinstance(f['aliases'], list) and all(isinstance(a, str) and a.strip() for a in f['aliases']), f['id']
        assert len(set(f['aliases'])) == len(f['aliases']), f['id']
        assert isinstance(f['calories'], int) and not isinstance(f['calories'], bool), f['id']
        assert 0 <= f['calories'] <= 2500, f['id']
        assert f['nutritionSource'], f['id']
        macros = f['macrosPerServing']
        assert set(macros) == set(NUTRIENTS), f['id']
        assert all(isinstance(n, (int, float)) and not isinstance(n, bool) and math.isfinite(n) and 0 <= n <= 100_000
                   for n in macros.values()), f['id']
        assert macros['fiber'] <= macros['totalCarbs'], f['id']
    for f in foods[ORIGINAL_FOODS:]:
        source = f['nutritionSource']
        assert source['dataset'] in (FNDDS_DATASET, SR_DATASET), f['id']
        prefix = 'usda-sr-' if source['dataset'] == SR_DATASET else 'usda-'
        assert f['id'].startswith(prefix), f['id']
        grams = sum(c['grams'] for c in source['components'])
        assert f['serving'] == '100 g' or f['serving'].endswith(' g)'), f['id']
        assert f['serving'] != '100 g' or grams == 100, f['id']
    index = {f['id']: f for f in foods}
    for key in ('banana', 'apple', 'orange', 'pear', 'peach', 'grapes', 'strawberries', 'pineapple', 'watermelon', 'kiwi'):
        assert key in index, f'Legacy ID lost: {key}'
    assert index['turkey-and-cheese-sandwich']['calories'] > index['turkey-sandwich']['calories']
    assert 'mayo' in index['turkey-sandwich']['serving'].lower()
    assert 'bun' in index['hot-dog']['serving'].lower()


def render(catalog):
    return json.dumps(catalog, ensure_ascii=False, indent=2) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('archive', type=Path, help='FoodData_Central_survey_food_json_2024-10-31.zip')
    parser.add_argument('--sr-legacy', type=Path, help='FoodData_Central_sr_legacy_food_json_2018-04.zip')
    parser.add_argument('--check', action='store_true', help='verify the bundled JSON instead of writing it')
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text())
    fndds, sr = load_sources(args.archive, args.sr_legacy, manifest)
    catalog = generate(fndds, sr, manifest)
    validate(catalog)
    rendered = render(catalog)
    if args.check:
        assert OUTPUT.read_text() == rendered, 'Bundled catalog differs from manifest'
    else:
        OUTPUT.write_text(rendered)
    print(f"Validated {len(catalog['foods']):,} foods; {len(rendered.encode()) / 1024:.0f} KiB bundled JSON")


if __name__ == '__main__':
    main()
