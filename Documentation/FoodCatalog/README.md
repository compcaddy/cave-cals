# Common food catalog

The app bundles **5,904 foods** in `App/CommonFoods.json`: 5,000 generic foods
plus 904 brand-name products and restaurant-chain items. They work offline and
appear before remote search results. Every food includes protein, total
carbohydrates, dietary fiber, and fat in grams for its stated portion. Calories
and nutrients are approximate, not promises about every recipe or restaurant
serving.

| Foods | Contents | Source |
| --- | --- | --- |
| 1–1,000 | Original reviewed catalog (unchanged, byte-for-byte) | 990 FNDDS + 10 FDA fruits |
| 1,001–5,000 | 2,783 FNDDS foods + 1,217 SR Legacy foods | FNDDS, SR Legacy |
| 5,001–5,904 | 118 FNDDS + 786 SR Legacy brand-name/chain foods | FNDDS, SR Legacy |

## Source releases (pinned by SHA-256)

- **USDA FNDDS 2021–2023**, FoodData Central release of October 31, 2024 — primary.
  [FoodData_Central_survey_food_json_2024-10-31.zip](https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_survey_food_json_2024-10-31.zip),
  SHA-256 `dfb06ae7ddc397ccd570b91c14b75438ab2ba39f64f22d321f61d4a52a77f3eb`;
  [documentation](https://www.ars.usda.gov/ARSUserFiles/80400530/pdf/fndds/2021_2023_FNDDS_Doc.pdf).
  5,432 records; 5,431 have all five required nutrients.
- **USDA SR Legacy, April 2018** — supplemental, for foods FNDDS does not represent
  (raw produce varieties, specific meat cuts, seafood, cheeses, legumes, grains,
  and most brand/chain items).
  [FoodData_Central_sr_legacy_food_json_2018-04.zip](https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_json_2018-04.zip),
  SHA-256 `0fe8ae486a2c8eb42cb96413f058deb51863a46c8fb8eeb4b1fb45006dd338ef`.
  7,793 records; 7,231 have all five required nutrients.
- **FDA raw fruits poster** — the ten original fruits keep their frozen values and IDs
  ([source](https://www.fda.gov/food/nutrition-food-labeling-and-critical-foods/raw-fruits-poster-text-version-accessible-version)).
- **NHANES 2021–2023 day-one individual foods**
  ([DR1IFF_L.xpt](https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2021/DataFiles/DR1IFF_L.xpt),
  SHA-256 `97177395e5fd1322ec8cb72d271a3f8d46e6a83b1105f89f6ef6f39f156037b3`) —
  selection and portion aid only; never a nutrient source. Counts are unweighted
  reliable day-one reports (99,345 reports, 3,973 food codes), **not** national
  consumption estimates or measured search coverage.

USDA Foundation Foods was evaluated and not used: most of its records publish
Atwater energy (nutrients 2047/2048) instead of nutrient 1008, and many lack fiber.

## Selection (foods 1,001–5,904)

`scripts/curate_food_catalog.py` made the selection once; the manifest is now
the frozen, authoritative record. In order:

1. **FNDDS foods reported in NHANES** day-one recalls, most-reported first
   (2,783 generic foods). Unreported FNDDS records (1,292) were held in reserve
   and not needed.
2. **SR Legacy foods not already represented by an FNDDS food** (1,217): first
   records used as ingredients in NHANES-reported foods, then a weighted
   rotation across food groups favoring vegetables, fruits, seafood, dairy,
   legumes, meats, nuts and grains.
3. **Brand-name and restaurant-chain foods** from both releases (904),
   appended after the generic target. Names always carry the brand (e.g.
   `Big Mac (McDonalds)`, `Taco Bell Bean Burrito`, `Quaker Cap'n Crunch`), so a
   branded record is never presented as a generic substitute. Apostrophe-free
   aliases (e.g. `McDonalds Big Mac`, `Wendys …`) make them searchable, because
   the app's search normalizes `McDonald's` to `mcdonald s`. SR Legacy chain and
   product analyses date from 2018 or earlier and may not match current recipes.

Exclusions (counts in `curation-report.json` / `validation-report.json`):
infant formula, baby and toddler foods, human milk; records missing any
required nutrient (missing is never treated as zero — e.g. SR tempeh lacks
fiber and is excluded); FNDDS recipe-ingredient-only records; raw meat and raw
seafood that have a cooked record; unprepared forms (dry mixes, condensed soups,
doughs, frozen “as purchased”); by-products and industrial fats/ingredients;
salted, sodium-only and grade-only twins; unbranded SR fast-food records; FNDDS
source variants (from fresh/frozen/restaurant, NS/NFS) whose nutrition matches
a kept sibling; SR records that are the same food as an FNDDS record.

**Duplicate detection.** An SR record is dropped when an FNDDS food in the
catalog is built from it (≥ 85 % of the recipe weight with similar per-100 g
nutrition, or ≥ 50 % with near-identical nutrition), or when names overlap
strongly and nutrition matches. Raw and cooked forms are never merged because
their nutrition differs. Branded SR items identical to an FNDDS brand record
(e.g. Big Mac, Whopper with cheese) keep only the FNDDS record.

## Portions and nutrient math

Portions come only from a documented USDA `foodPortions` entry with a gram
weight, optionally multiplied by a common household amount (¼–2 cups, 1–2 tbsp,
8/12 fl oz, 1.5 fl oz liquor, 5 fl oz wine, 1–4 oz, or 2–6 small items). The
portion closest to the NHANES median grams per report is chosen (food-specific
when ≥ 10 people reported it, otherwise the category median; food-group defaults
for SR). Choices avoid whole pizzas/loaves, cups of meat or cake, brand-named
portions on generic foods, and vague “Quantity not specified”, guideline,
cubic-inch and single-crumb portions. Every serving shows its gram weight,
e.g. `1 cup (158 g)`. When USDA documents no usable portion the serving is an
honest `100 g` (65 foods). Cup weights are never invented and 1 mL is never
assumed to weigh 1 g.

Energy is USDA nutrient 1008 (kcal); protein 1003, total carbohydrate 1005,
fiber 1079 and fat 1004, all grams per 100 g (IDs and units are asserted at
build time). For each nutrient, serving amount = amount per 100 g × grams ÷ 100,
summed across recipe components before rounding. Calories are rounded once
(`floor(x + 0.5)`); grams are rounded once to two decimals. Published energy is
used — never a 4/4/9 recomputation. Total carbohydrates include fiber; the app
derives net carbs. Recipe assumptions of the original catalog (sandwich mayo,
lettuce and tomato; hot dog with bun; salads with dressing) are unchanged; no
new app recipes were added.

Additions use `usda-<foodCode>` IDs for FNDDS and `usda-sr-<fdcId>` for SR
Legacy. SR provenance records the real `fdcId` and `ndbNumber` and never a
manufactured food code.

## Rebuilding

Download the pinned archives (and, only for re-running selection, the NHANES
file) into one folder, then from the repository root:

```sh
D=/path/to/usda-downloads
python3 scripts/build_common_foods.py $D/FoodData_Central_survey_food_json_2024-10-31.zip \
  --sr-legacy $D/FoodData_Central_sr_legacy_food_json_2018-04.zip
python3 scripts/build_common_foods.py $D/FoodData_Central_survey_food_json_2024-10-31.zip \
  --sr-legacy $D/FoodData_Central_sr_legacy_food_json_2018-04.zip --check
python3 scripts/validate_food_catalog.py $D --baseline /path/to/original-1000/CommonFoods.json
```

The generator (standard library only) verifies both archive checksums,
resolves every portion ID and checks weight × multiplier, and validates exactly
5,904 foods with unique IDs and names, the runtime fields and types, integer
calories 0–2,500, complete non-negative nutrients with fiber ≤ carbs, the ten
original fruit IDs and the bun/mayo/cheese assumptions. `--check` requires the
bundled JSON to match byte-for-byte. The validator re-reads the archives
independently, recomputes all 4,904 additions, spot-checks at least 30, runs
the generator twice for determinism and writes `validation-report.json`.

`scripts/curate_food_catalog.py $D` re-creates the additions from the original
1,000 manifest entries; do not run it on the finished manifest unless you
intend to replace the reviewed selection. Edit `manifest.json` for future
changes and never change an existing ID. `curation.tsv` covers only the
original 1,000.

## Integration notes

- The Swift loader accepts any array length. `Tests/ECCTests.swift` now expects
  5,904 foods; `EXPECTED_FOODS` in the generator and `EXPECTED` in the validator
  must change together with any future count change.
- Always import `manifest.json` and the scripts together with the JSON, or a
  later regeneration will overwrite the expansion.
- The bundled JSON is about 6 MB (1 MB before) and is decoded lazily on first
  search. Personal defaults still override catalog values, catalog updates
  never rewrite past entries, and ambiguous aliases cannot select a default.

## Known limitations

- 22 servings exceed 1,000 kcal or 500 g (e.g. large restaurant platters, a
  Chinese-restaurant lemon chicken order, a double Whopper). They are the
  documented USDA portions and are listed in `validation-report.json` for review.
- About 4,000 foods have no aliases; most added FNDDS names are the USDA
  description itself, which the app's all-words search already matches.
- Not in either release: several major chains (e.g. Starbucks, Dunkin',
  Panera, Five Guys, Dairy Queen) and many current grocery products; tempeh and
  farro are absent or lack fiber. Packaged grocery brands exist only in USDA's
  separate Branded Foods label dataset, which is not used here.
