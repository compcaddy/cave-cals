#!/usr/bin/env python3
"""Independently validate App/CommonFoods.json and write validation-report.json.

python3 scripts/validate_food_catalog.py /path/to/usda-downloads --baseline /path/to/original/CommonFoods.json

The downloads directory must contain the pinned FNDDS and SR Legacy archives.
--baseline is the 1,000-food catalog before the expansion; its first 1,000 foods
must be deeply equal to the expanded catalog's first 1,000. The script re-reads
the source archives with its own code path (it does not import the generator),
recomputes every added food, runs the generator twice to prove deterministic
output, and runs the generator's --check mode. Standard library only.
"""
import argparse
import collections
import hashlib
import json
import math
import re
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / 'App/CommonFoods.json'
MANIFEST = ROOT / 'Documentation/FoodCatalog/manifest.json'
CURATION = ROOT / 'Documentation/FoodCatalog/curation-report.json'
REPORT = ROOT / 'Documentation/FoodCatalog/validation-report.json'
FNDDS_ZIP = 'FoodData_Central_survey_food_json_2024-10-31.zip'
SR_ZIP = 'FoodData_Central_sr_legacy_food_json_2018-04.zip'
IDS = {'kcal': 1008, 'protein': 1003, 'totalCarbs': 1005, 'fiber': 1079, 'fat': 1004}
UNITS = {'kcal': 'kcal', 'protein': 'g', 'totalCarbs': 'g', 'fiber': 'g', 'fat': 'g'}
EXPECTED = {'total': 5904, 'original': 1000, 'generic': 5000}


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def norm(text):
    return ' '.join(text.casefold().split())


def app_norm(text):
    return ' '.join(re.findall(r'[0-9a-z]+', text.casefold()))


def source_values(food):
    out = {}
    for key, nid in IDS.items():
        hits = [n for n in food['foodNutrients'] if n['nutrient']['id'] == nid and n.get('amount') is not None]
        assert len(hits) == 1 and hits[0]['nutrient']['unitName'] == UNITS[key], (food['description'], key)
        out[key] = hits[0]['amount']
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('downloads', type=Path)
    parser.add_argument('--baseline', type=Path, required=True)
    args = parser.parse_args()
    failures, warnings = [], []

    def check(condition, message):
        if not condition:
            failures.append(message)
        return condition

    raw = CATALOG.read_text(encoding='utf-8')
    catalog = json.loads(raw, parse_constant=lambda c: failures.append(f'Non-JSON constant {c}'))
    manifest = json.loads(MANIFEST.read_text())
    baseline = json.loads(args.baseline.read_text())
    foods = catalog['foods']
    original, added = foods[:EXPECTED['original']], foods[EXPECTED['original']:]
    brand_ids = {f['id'] for f in foods[EXPECTED['generic']:]}

    # Archives and checksums.
    archives = {
        'FNDDS 2021-2023': (args.downloads / FNDDS_ZIP, manifest['sourceArchiveSHA256']),
        'SR Legacy 2018-04': (args.downloads / SR_ZIP, manifest['additionalSources'][0]['sha256']),
    }
    checksum_results = {}
    for label, (path, expected) in archives.items():
        actual = digest(path)
        checksum_results[label] = {'file': path.name, 'expected': expected, 'actual': actual, 'match': actual == expected}
        check(actual == expected, f'{label} checksum mismatch')
    check(catalog['sourceArchiveSHA256'] == manifest['sourceArchiveSHA256'], 'Catalog source hash differs from manifest')
    check(catalog.get('additionalSources') == manifest['additionalSources'], 'additionalSources differ from manifest')
    with zipfile.ZipFile(archives['FNDDS 2021-2023'][0]) as z:
        fndds_list = json.loads(z.read('surveyDownload.json'))['SurveyFoods']
    with zipfile.ZipFile(archives['SR Legacy 2018-04'][0]) as z:
        sr_list = json.loads(z.read(z.namelist()[0]))['SRLegacyFoods']
    fndds = {f['foodCode']: f for f in fndds_list}
    sr = {f['fdcId']: f for f in sr_list}
    source_counts = {
        'fnddsRecords': len(fndds_list),
        'fnddsWithAllFiveNutrients': sum(1 for f in fndds_list if all(
            any(n['nutrient']['id'] == i and n.get('amount') is not None for n in f['foodNutrients']) for i in IDS.values())),
        'srLegacyRecords': len(sr_list),
        'srLegacyWithAllFiveNutrients': sum(1 for f in sr_list if all(
            any(n['nutrient']['id'] == i and n.get('amount') is not None for n in f['foodNutrients']) for i in IDS.values())),
    }

    # Counts, preservation and uniqueness.
    check(len(foods) == EXPECTED['total'], f"Expected {EXPECTED['total']} foods, found {len(foods)}")
    check(original == baseline['foods'], 'Original 1,000 foods are not deeply equal to the baseline')
    check(len(baseline['foods']) == EXPECTED['original'], 'Baseline does not contain 1,000 foods')
    ids = collections.Counter(f['id'] for f in foods)
    names = collections.Counter(norm(f['name']) for f in foods)
    app_names = collections.Counter(app_norm(f['name']) for f in foods)
    check(all(n == 1 for n in ids.values()), 'Duplicate IDs')
    check(all(n == 1 for n in names.values()), 'Duplicate normalized names')
    check(all(n == 1 for n in app_names.values()), 'Duplicate names under app search normalization')

    # Runtime schema and nutrient sanity.
    oversized = []
    for f in foods:
        ok = (isinstance(f.get('id'), str) and isinstance(f.get('name'), str) and f['name'].strip()
              and isinstance(f.get('serving'), str) and f['serving'].strip() and isinstance(f.get('category'), str)
              and isinstance(f.get('aliases'), list) and isinstance(f.get('nutritionSource'), dict))
        check(ok, f"{f.get('id')}: missing or mistyped runtime field")
        check(all(isinstance(a, str) and a.strip() for a in f['aliases']), f"{f['id']}: empty alias")
        check(len(set(f['aliases'])) == len(f['aliases']), f"{f['id']}: duplicate alias")
        cal = f['calories']
        check(isinstance(cal, int) and not isinstance(cal, bool) and 0 <= cal <= 2500, f"{f['id']}: calories {cal}")
        m = f['macrosPerServing']
        check(set(m) == {'protein', 'totalCarbs', 'fiber', 'fat'}, f"{f['id']}: macro keys {sorted(m)}")
        check(all(isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v) and v >= 0 for v in m.values()),
              f"{f['id']}: invalid macro value")
        check(m['fiber'] <= m['totalCarbs'], f"{f['id']}: fiber exceeds total carbs")
        check('netCarbs' not in m, f"{f['id']}: stores netCarbs")
        grams = sum(c.get('grams', 0) for c in f['nutritionSource'].get('components', []))
        if cal > 1000 or grams > 500:
            oversized.append({'id': f['id'], 'name': f['name'], 'serving': f['serving'], 'calories': cal})

    # Recompute every addition from the raw source and its manifest portion.
    manifest_by_id = {f['id']: f for f in manifest['foods']}
    recomputed = mismatches = 0
    datasets = collections.Counter()
    for f in added:
        spec = manifest_by_id[f['id']]
        (part,) = spec['components']
        comp = f['nutritionSource']['components'][0]
        if part.get('dataset') == 'sr_legacy':
            src, label = sr.get(part['fdcId']), 'USDA SR Legacy (April 2018)'
            check(src is not None and f['id'] == f"usda-sr-{part['fdcId']}", f"{f['id']}: SR identity")
            check('foodCode' not in comp and comp['ndbNumber'] == src['ndbNumber'], f"{f['id']}: SR provenance fields")
        else:
            src, label = fndds.get(part['code']), 'USDA FNDDS 2021-2023'
            check(src is not None and f['id'] == f"usda-{part['code']}", f"{f['id']}: FNDDS identity")
            check(comp['foodCode'] == src['foodCode'], f"{f['id']}: foodCode")
        datasets[label] += 1
        check(f['nutritionSource']['dataset'] == label, f"{f['id']}: dataset label")
        check(comp['fdcId'] == src['fdcId'] and comp['description'] == src['description'], f"{f['id']}: provenance")
        check(comp['url'] == f"https://fdc.nal.usda.gov/food-details/{src['fdcId']}/nutrients", f"{f['id']}: URL")
        if 'portionId' in part:
            portion = [p for p in src['foodPortions'] if p['id'] == part['portionId']]
            check(len(portion) == 1, f"{f['id']}: portion {part['portionId']} not in source")
            check(portion and abs(portion[0]['gramWeight'] * part['multiplier'] - part['grams']) <= 0.01,
                  f"{f['id']}: portion weight × multiplier ≠ grams")
            shown = re.search(r'\(([\d.]+) g\)$', f['serving'])
            check(shown and abs(float(shown.group(1)) - part['grams']) <= 0.0501, f"{f['id']}: serving text grams")
        else:
            check(part['grams'] == 100 and f['serving'] == '100 g', f"{f['id']}: 100 g fallback")
        values = source_values(src)
        grams = part['grams']
        kcal = math.floor(values['kcal'] * grams / 100 + 0.5)
        macros = {k: round(values[k] * grams / 100, 2) for k in ('protein', 'totalCarbs', 'fiber', 'fat')}
        recomputed += 1
        if kcal != f['calories'] or any(abs(macros[k] - f['macrosPerServing'][k]) > 1e-9 for k in macros):
            mismatches += 1
            failures.append(f"{f['id']}: recomputed values differ")
        check(comp['kcalPer100g'] == values['kcal'], f"{f['id']}: kcalPer100g")

    # Aliases: collisions across foods and aliases that equal another food's name.
    alias_owner = collections.defaultdict(set)
    for f in foods:
        for a in f['aliases']:
            alias_owner[app_norm(a)].add(f['id'])
    name_owner = {app_norm(f['name']): f['id'] for f in foods}
    shared_aliases = {a: sorted(o) for a, o in alias_owner.items() if len(o) > 1}
    alias_equals_other_name = [{'alias': a, 'aliasOf': sorted(o), 'nameOf': name_owner[a]} for a, o in alias_owner.items()
                               if a in name_owner and name_owner[a] not in o]
    new_alias_problems = [x for x in alias_equals_other_name if any(i not in {f['id'] for f in original} for i in x['aliasOf'])]
    check(not new_alias_problems, 'An added alias equals another food name')
    prep_conflicts = []
    for f in added:
        name_state = 'raw' if re.search(r'\braw\b', f['name'], re.I) else 'cooked' if re.search(r'\bcooked|baked|fried|boiled|roasted|grilled|broiled\b', f['name'], re.I) else None
        for a in f['aliases']:
            if name_state == 'cooked' and re.search(r'\braw\b', a, re.I) or name_state == 'raw' and re.search(r'\bcooked\b', a, re.I):
                prep_conflicts.append({'id': f['id'], 'name': f['name'], 'alias': a})
    check(not prep_conflicts, 'An alias equates raw and cooked preparations')

    # Raw vs cooked pairs keep distinct values; semantic cross-source duplicates for review.
    by_stem = collections.defaultdict(list)
    for f in foods:
        stem = app_norm(re.sub(r'\b(raw|cooked[^,]*|boiled|drained|baked|roasted)\b', '', f['name']))
        by_stem[stem].append(f)
    raw_cooked_pairs = []
    for stem, group in by_stem.items():
        raws = [g for g in group if re.search(r'\braw\b', g['name'], re.I)]
        cooked = [g for g in group if re.search(r'\bcooked|boiled\b', g['name'], re.I)]
        for r_ in raws:
            for c_ in cooked:
                per_r = r_['calories'] / max(1e-9, sum(x['grams'] for x in r_['nutritionSource'].get('components', [{'grams': 1}])))
                per_c = c_['calories'] / max(1e-9, sum(x['grams'] for x in c_['nutritionSource'].get('components', [{'grams': 1}])))
                raw_cooked_pairs.append({'raw': r_['name'], 'cooked': c_['name'],
                                         'kcalPerGramRaw': round(per_r, 3), 'kcalPerGramCooked': round(per_c, 3)})
    raw_cooked_same_density = [p for p in raw_cooked_pairs if p['kcalPerGramRaw'] == p['kcalPerGramCooked']]

    def per100(f):
        comps = f['nutritionSource'].get('components') or []
        if len(comps) != 1:
            return None
        return {'kcal': comps[0]['kcalPer100g'], **comps[0]['macrosPer100g']}

    def tokens(name):
        return set(app_norm(name).split()) - {'raw', 'cooked', 'with', 'and', 'or', 'no', 'added', 'fat', 'without', 'salt', 'the', 'of', 'in', 'nfs'}

    review_dupes = []
    fndds_foods = [(f, per100(f), tokens(f['name'])) for f in foods if f['nutritionSource'].get('dataset') == 'USDA FNDDS 2021-2023' and per100(f)]
    for f in added:
        if not f['id'].startswith('usda-sr-') or f['id'] in brand_ids:
            continue
        p, t = per100(f), tokens(f['name'])
        for g, q, u in fndds_foods:
            if not t or not u:
                continue
            overlap = len(t & u) / len(t | u)
            if overlap >= 0.6 and abs(p['kcal'] - q['kcal']) <= max(3, 0.05 * q['kcal']) and \
                    all(abs(p[k] - q[k]) <= max(0.5, 0.1 * q[k]) for k in ('protein', 'totalCarbs', 'fat')):
                review_dupes.append({'sr': f['name'], 'fndds': g['name'], 'nameOverlap': round(overlap, 2)})

    # Determinism and the generator's --check mode.
    gen = [sys.executable, str(ROOT / 'scripts/build_common_foods.py'), str(archives['FNDDS 2021-2023'][0]),
           '--sr-legacy', str(archives['SR Legacy 2018-04'][0])]
    before = digest(CATALOG)
    hashes = []
    for _ in range(2):
        run = subprocess.run(gen, capture_output=True, text=True)
        check(run.returncode == 0, f'Generator failed: {run.stderr[-500:]}')
        hashes.append(digest(CATALOG))
    check_run = subprocess.run(gen + ['--check'], capture_output=True, text=True)
    check(hashes[0] == hashes[1] == before, 'Generator output is not deterministic or differs from the delivered file')
    check(check_run.returncode == 0, f'--check failed: {check_run.stderr[-500:]}')

    # Spot checks: >= 30 additions across required kinds, recomputed from raw source.
    def pick(pred, n):
        return [f for f in added if pred(f)][:n]
    kinds = {
        'highFiber': pick(lambda f: f['macrosPerServing']['fiber'] >= 8 and f['id'] not in brand_ids, 4),
        'zeroCarb': pick(lambda f: f['macrosPerServing']['totalCarbs'] == 0 and f['calories'] > 50, 4),
        'drinks': pick(lambda f: re.search(r'drink|juice|milk|coffee|tea|soda|beer|wine', f['category'], re.I) and f['id'] not in brand_ids, 4),
        'mixedDishes': pick(lambda f: re.search(r'mixed dishes|Burritos|Pizza|Soups', f['category']) and f['id'] not in brand_ids, 4),
        'fruitsAndVegetables': pick(lambda f: f['id'].startswith('usda-sr-') and re.search(r'Fruits|Vegetables', f['category']), 5),
        'srLegacyOther': pick(lambda f: f['id'].startswith('usda-sr-') and re.search(r'Finfish|Beef|Legumes|Nut', f['category']) and f['id'] not in brand_ids, 4),
        'hundredGram': pick(lambda f: f['serving'] == '100 g', 2),
        'branded': [f for f in added if f['id'] in brand_ids][::150][:6],
    }
    spot = []
    for kind, items in kinds.items():
        for f in items:
            spec = manifest_by_id[f['id']]['components'][0]
            src = sr[spec['fdcId']] if spec.get('dataset') == 'sr_legacy' else fndds[spec['code']]
            v = source_values(src)
            spot.append({
                'kind': kind, 'id': f['id'], 'name': f['name'], 'serving': f['serving'],
                'sourceDescription': src['description'], 'sourcePer100g': v,
                'expected': {'calories': math.floor(v['kcal'] * spec['grams'] / 100 + 0.5),
                             **{k: round(v[k] * spec['grams'] / 100, 2) for k in ('protein', 'totalCarbs', 'fiber', 'fat')}},
                'catalog': {'calories': f['calories'], **f['macrosPerServing']},
            })
    for s in spot:
        check(s['expected'] == s['catalog'], f"Spot check failed for {s['id']}")
    check(len(spot) >= 30, 'Fewer than 30 spot checks')

    curation = json.loads(CURATION.read_text())
    if oversized:
        warnings.append(f'{len(oversized)} servings exceed 1,000 kcal or 500 g; kept as documented USDA portions for review')
    if review_dupes:
        warnings.append(f'{len(review_dupes)} SR/FNDDS pairs have similar names and nutrition; listed for human review')
    report = {
        'result': 'PASS' if not failures else 'FAIL',
        'failures': failures[:200],
        'warnings': warnings,
        'counts': {
            'total': len(foods), 'original': len(original), 'added': len(added),
            'addedGeneric': len(added) - len(brand_ids), 'addedBranded': len(brand_ids),
            'bySource': dict(collections.Counter(f['nutritionSource']['dataset'] for f in foods)),
            'addedBySource': dict(datasets),
            'byCategory': dict(sorted(collections.Counter(f['category'] for f in foods).items(), key=lambda x: (-x[1], x[0]))),
            'servingsOf100g': sum(1 for f in added if f['serving'] == '100 g'),
            'foodsWithoutAliases': sum(1 for f in foods if not f['aliases']),
        },
        'sourceRecordCounts': source_counts,
        'checksums': checksum_results,
        'file': {'path': 'App/CommonFoods.json', 'bytes': len(raw.encode()), 'sha256': digest(CATALOG)},
        'preservation': {'original1000DeepEqual': original == baseline['foods'], 'baselineSha256': digest(args.baseline)},
        'recalculation': {'additionsRecomputed': recomputed, 'mismatches': mismatches},
        'determinism': {'run1Sha256': hashes[0], 'run2Sha256': hashes[1], 'identical': hashes[0] == hashes[1] == before},
        'generatorCheckMode': {'returncode': check_run.returncode, 'output': check_run.stdout.strip()},
        'exclusions': curation['exclusions'],
        'brandedSrDuplicatesOfFnddsSkipped': curation.get('brandedSrDuplicatesOfFndds', []),
        'nameCollisionsSkipped': curation.get('nameCollisionsSkipped', []),
        'aliases': {
            'sharedAcrossFoods': len(shared_aliases), 'sharedExamples': dict(list(shared_aliases.items())[:25]),
            'aliasEqualsAnotherFoodName': alias_equals_other_name,
            'rawCookedConflicts': prep_conflicts,
        },
        'rawVsCooked': {'pairsChecked': len(raw_cooked_pairs), 'pairsWithIdenticalEnergyDensity': raw_cooked_same_density,
                        'examples': raw_cooked_pairs[:15]},
        'crossSourceReviewCandidates': review_dupes,
        'oversizedServings': oversized,
        'spotChecks': spot,
    }
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=1) + '\n')
    print(f"{report['result']}: {len(foods)} foods, {len(failures)} failures, {len(warnings)} warnings, "
          f"{len(spot)} spot checks, {recomputed} additions recomputed")
    sys.exit(0 if not failures else 1)


if __name__ == '__main__':
    main()
