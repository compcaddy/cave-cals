#!/usr/bin/env python3
"""Rebuild the reviewed catalog from the official FNDDS archive (no API key).

python3 scripts/build_common_foods.py /path/to/FoodData_Central_survey_food_json_2024-10-31.zip
The manifest fixes names, source records and household portions; it never ranks or
randomly selects foods at build time. Run --check to compare without writing.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE_URL = 'https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_survey_food_json_2024-10-31.zip'

def energy(food):
    return next(n['amount'] for n in food['foodNutrients'] if n['nutrient']['id'] == 1008)

def generate(archive, manifest):
    with zipfile.ZipFile(archive) as z:
        source = {f['foodCode']: f for f in json.loads(z.read('surveyDownload.json'))['SurveyFoods']}
    foods = []
    for spec in manifest['foods']:
        food = {k: spec[k] for k in ('id', 'name', 'aliases', 'serving')}
        food['category'] = spec['category']
        if 'legacyCalories' in spec:
            food['calories'] = spec['legacyCalories']
            food['nutritionSource'] = spec['nutritionSource']
        else:
            components = []
            rawCalories = 0
            for part in spec['components']:
                f = source[part['code']]
                # The manifest stores an actual USDA portion and its multiplier.
                # Arbitrary app recipe weights are explicitly marked instead.
                grams = part['grams']
                if 'portionId' in part:
                    portion = next(p for p in f['foodPortions'] if p['id'] == part['portionId'])
                    assert math.isclose(portion['gramWeight'] * part.get('multiplier', 1), grams, abs_tol=0.01)
                kcal = energy(f)
                rawCalories += kcal * grams / 100
                components.append({
                    'foodCode': f['foodCode'], 'fdcId': f['fdcId'],
                    'description': f['description'], 'grams': grams,
                    'kcalPer100g': kcal,
                    'portionBasis': part['basis'],
                    'url': f"https://fdc.nal.usda.gov/food-details/{f['fdcId']}/nutrients"
                })
            food['calories'] = int(math.floor(rawCalories + 0.5))
            food['nutritionSource'] = {
                'dataset': 'USDA FNDDS 2021-2023',
                'method': 'recipe sum' if len(components) > 1 else 'USDA energy × portion weight',
                'components': components
            }
        foods.append(food)
    return {
        'version': 2,
        'source': SOURCE_URL,
        'sourceArchiveSHA256': hashlib.sha256(Path(archive).read_bytes()).hexdigest(),
        'note': 'Approximate calories per stated everyday serving. Mixed dishes use the described recipe assumptions; actual recipes vary. Personal defaults override these values without changing past entries.',
        'foods': foods
    }

def validate(catalog):
    foods = catalog['foods']
    assert len(foods) == 1000, f"Expected 1,000 foods; got {len(foods)}"
    assert len({f['id'] for f in foods}) == len(foods), 'Duplicate ID'
    assert len({f['name'].casefold() for f in foods}) == len(foods), 'Duplicate name'
    for f in foods:
        assert f['name'].strip() and f['serving'].strip() and f['category']
        assert isinstance(f['calories'], (int, float)) and math.isfinite(f['calories']) and 0 <= f['calories'] <= 2500, f
        assert all(a.strip() for a in f['aliases']) and len(set(f['aliases'])) == len(f['aliases'])
        assert f['nutritionSource']
    index = {f['id']: f for f in foods}
    for key in ('banana', 'apple', 'orange', 'pear', 'peach', 'grapes', 'strawberries', 'pineapple', 'watermelon', 'kiwi'):
        assert key in index, f'Legacy ID lost: {key}'
    assert index['turkey-and-cheese-sandwich']['calories'] > index['turkey-sandwich']['calories']
    assert 'mayo' in index['turkey-sandwich']['serving'].lower()
    assert 'bun' in index['hot-dog']['serving'].lower()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    manifest = json.loads((ROOT / 'Documentation/FoodCatalog/manifest.json').read_text())
    actual_hash = hashlib.sha256(args.archive.read_bytes()).hexdigest()
    assert actual_hash == manifest['sourceArchiveSHA256'], 'Source archive differs from reviewed release'
    catalog = generate(args.archive, manifest)
    validate(catalog)
    rendered = json.dumps(catalog, ensure_ascii=False, indent=2) + '\n'
    output = ROOT / 'App/CommonFoods.json'
    if args.check:
        assert output.read_text() == rendered, 'Bundled catalog differs from manifest'
    else:
        output.write_text(rendered)
    print(f"Validated {len(catalog['foods'])} foods; {len(rendered.encode()) / 1024:.0f} KiB bundled JSON")

if __name__ == '__main__':
    main()
