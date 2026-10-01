Expand the bundled food catalog for my calorie-tracking app, Cave Cals, from 1,000 to 5,000 total foods. Produce actual downloadable files, not a sample or 5,000 entries pasted into chat.

Use code to download, parse, transform, and validate authoritative nutrition data. AI may help curate readable food names and aliases, but must not invent nutrient amounts, serving weights, source IDs, or source links.

INPUTS
I am attaching:
- App/CommonFoods.json — the current 1,000-food catalog and exact runtime format.
- Documentation/FoodCatalog/manifest.json — the authoritative source/portion selections.
- scripts/build_common_foods.py — the current reproducible generator.
- Documentation/FoodCatalog/README.md — sources and recipe assumptions.
- App/FoodHistory.swift and App/Macros.swift — reference-only decoder and nutrient model.

If these files are missing, ask for them before building a replacement. Do not claim to preserve the existing catalog without reading it.

TARGET AND PRESERVATION
Produce 5,000 TOTAL foods: retain the original 1,000 and add 4,000 genuinely distinct foods. Preserve all existing food objects, IDs, names, aliases, serving descriptions, calories, nutrition values, and recipe assumptions. Append the additions in a deterministic order. Do not duplicate existing foods under different names, IDs, or serving sizes.

SOURCES
Primary source: USDA Food and Nutrient Database for Dietary Studies (FNDDS), 2021–2023, released in FoodData Central on October 31, 2024.
Download:
https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_survey_food_json_2024-10-31.zip
Documentation:
https://www.ars.usda.gov/ARSUserFiles/80400530/pdf/fndds/2021_2023_FNDDS_Doc.pdf
Official download index:
https://fdc.nal.usda.gov/download-datasets/

The primary archive SHA-256 used by the current catalog is:
dfb06ae7ddc397ccd570b91c14b75438ab2ba39f64f22d321f61d4a52a77f3eb

Verify that checksum before using this release. Inside the ZIP, read surveyDownload.json and its SurveyFoods array. This archive was inspected and contains 5,432 records; 5,431 have the required nutrient amounts and portions before curation. Independently verify the counts. Do not assume all records are appropriate consumer-facing foods.

The existing ten FDA fruit entries come from:
https://www.fda.gov/food/nutrition-food-labeling-and-critical-foods/raw-fruits-poster-text-version-accessible-version
Keep their existing values and serving sizes exactly.

If filtering and deduplication leave too few suitable FNDDS foods, supplement from official USDA SR Legacy or Foundation Foods downloads listed on the official download index. Pin the exact supplemental release and record its URL and SHA-256. Prefer FNDDS for ready-to-eat foods; use supplemental datasets for genuinely missing ingredients or foods. Do not use a branded product as an unlabeled generic substitute.

Do not scrape proprietary calorie-tracking apps or generate missing nutrition using an LLM. If authoritative sources still cannot support 5,000 suitable complete records, deliver the verified partial expansion with the exact shortfall and explanation; never pad the count.

SELECTION AND SEARCH QUALITY
- Prioritize recognizable foods, everyday ingredients, common prepared dishes, and useful international foods.
- Include fruits, vegetables, grains, breads, cereals, beans, nuts, seeds, dairy, alternatives, eggs, meats, seafood, drinks, snacks, sauces, and meals.
- Preserve meaningful distinctions: raw versus cooked, drained versus undrained, sweetened versus unsweetened, fat percentage, cooking method, and materially different recipes.
- Exclude infant formula, supplements, non-food records, brand-specific products, vague catch-all records, and redundant survey variants unless there is a clear consumer use.
- Never strip a preparation qualifier that materially changes nutrition.
- Prefer concise consumer-facing names and helpful aliases. Do not claim a ranking represents national popularity without an appropriate weighted analysis.
- Review duplicate foods across datasets semantically, not just by ID. Do not create separate foods merely for different portions. Alias collisions should be reported; aliases must not misleadingly equate different preparations.

PORTIONS AND NUTRIENT MATH
Use a practical portion: one item, slice, cup, tablespoon, bowl, or an appropriate weight serving. Prefer a documented source foodPortions entry with a known gramWeight. The serving description must include the corresponding gram weight, such as "1 cup (158 g)".

If no reliable household portion exists, an honestly labeled "100 g" serving is acceptable. Do not invent cup weights or assume 1 mL = 1 g. Never use microscopic units such as rice grains.

USDA nutrient IDs:
- 1008: energy, kcal
- 1003: protein, grams
- 1005: total carbohydrates, grams
- 1079: dietary fiber, grams
- 1004: total fat, grams

Verify the nutrient IDs, units, and per-100-gram basis in each source dataset. For each nutrient:
    amount for the selected serving = source amount per 100 g × serving grams / 100

For an existing composite recipe, sum its documented component amounts before rounding. Do not add new speculative recipes just to increase the count; prefer documented USDA composite foods. Preserve the existing sandwich/bun/dressing assumptions.

Round calories once to the nearest whole kcal using floor(value + 0.5). Round nutrient grams once to two decimal places, matching the current Python generator. Do not round intermediate component calculations. Use published energy; do not recompute calories with a 4/4/9 formula.

Store TOTAL carbohydrates INCLUDING fiber. Store fiber separately. Do not subtract fiber before storing totalCarbs. Do not write a netCarbs field; the app computes totalCarbs minus fiber. No sugar-alcohol subtraction.

All added foods must have sourced numeric protein, totalCarbs, fiber, and fat values. A verified zero is valid. Missing values are not zero: exclude/report incomplete candidates rather than guessing.

REQUIRED OUTPUT FORMAT
Output a UTF-8 JSON object, not a bare array, using exactly these runtime field names and types. This is one real existing record illustrating the format; the final foods array must contain the full catalog:

{
  "version": 3,
  "source": "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_survey_food_json_2024-10-31.zip",
  "sourceArchiveSHA256": "dfb06ae7ddc397ccd570b91c14b75438ab2ba39f64f22d321f61d4a52a77f3eb",
  "note": "Approximate calories and nutrient grams per stated everyday serving. Total carbohydrates include fiber; net carbs are calculated in the app.",
  "foods": [
    {
      "id": "usda-92101000",
      "name": "Coffee",
      "aliases": ["black coffee", "brewed coffee", "regular coffee", "coffee, brewed"],
      "serving": "1 cup (8 fl oz) (240 g)",
      "category": "Coffee",
      "calories": 2,
      "macrosPerServing": {
        "protein": 0.29,
        "totalCarbs": 0.0,
        "fiber": 0.0,
        "fat": 0.05
      },
      "nutritionSource": {
        "dataset": "USDA FNDDS 2021-2023",
        "method": "USDA nutrients × portion weight",
        "components": [
          {
            "foodCode": "92101000",
            "fdcId": 2710375,
            "description": "Coffee, brewed",
            "grams": 240,
            "kcalPer100g": 1.0,
            "macrosPer100g": {
              "protein": 0.12,
              "totalCarbs": 0.0,
              "fiber": 0.0,
              "fat": 0.02
            },
            "portionBasis": "1 cup (8 fl oz)",
            "url": "https://fdc.nal.usda.gov/food-details/2710375/nutrients"
          }
        ]
      }
    }
  ]
}

Preserve the original catalog note, extending it if necessary to accurately describe supplemental sources. Keep version 3 because the runtime schema is unchanged. If supplemental datasets are used, keep the primary source/hash fields and add an additionalSources array of objects with dataset, url, and sha256. Make each added food's nutritionSource identify its actual dataset.

For new FNDDS foods use "usda-<foodCode>" IDs unless that ID already exists. For supplemental foods use stable namespaced IDs such as "usda-sr-<fdcId>" or "usda-foundation-<fdcId>". Do not manufacture a foodCode for a dataset that has none; omit that provenance field and retain the real fdcId. Existing FDA entries keep their existing provenance format.

Numbers must be JSON numbers, never strings. Do not emit comments, NaN, Infinity, placeholder values, truncated arrays, or markdown inside the JSON file.

REPRODUCIBLE DELIVERABLES
Return a ZIP containing:
1. App/CommonFoods.json — the complete importable catalog.
2. Documentation/FoodCatalog/manifest.json — the expanded authoritative selection, preserving existing entries and recording each new source record, chosen portion ID/weight, and any multiplier. Extend it explicitly for supplemental sources when necessary.
3. scripts/build_common_foods.py — an updated generator with clear invocation instructions, source checksum checks, deterministic output, and a working --check mode. It must validate the new target count rather than the old 1,000 limit.
4. Documentation/FoodCatalog/README.md — exact source releases, download URLs, portion/rounding rules, rebuild commands, exclusions, and integration notes.
5. validation-report.json — actual validation results, counts by category and source, original/additional counts, excluded-record counts and reasons, duplicate/alias findings, file size, and representative spot checks.

The new JSON must be regenerated from the expanded manifest and pinned source files, not hand-authored separately from the generator. Do not modify Swift app code, backend code, app versions, or release/deployment settings.

VALIDATION — RUN IT, DO NOT JUST DESCRIBE IT
- Parse the final JSON from disk.
- Confirm 5,000 foods, with all 1,000 original food objects deeply equal to their inputs and 4,000 new entries.
- Check unique IDs and unique normalized names (case-folded and trimmed, with repeated whitespace collapsed).
- Check every alias is a nonempty string; no duplicate aliases within a food.
- Verify every required runtime field and type.
- Verify finite nonnegative calories and nutrients; calories must be an integer between 0 and 2,500 per selected serving, matching the current validator. Flag oversized portions for review; do not artificially shrink them just to pass.
- Verify all four nutrient fields exist and fiber <= totalCarbs.
- Recalculate added entries from their source records and serving weights; compare with final rounded values.
- Verify source identities, units, portion IDs, gram weights, and checksums.
- Check common raw/cooked distinctions and duplicates across sources.
- Spot-check at least 30 additions across categories, including high-fiber foods, zero-carb foods, drinks, mixed dishes, and any supplemental datasets.
- Run the generator twice and confirm deterministic output. Run --check successfully against the delivered JSON.
- Report any unresolved quality problem honestly. Do not claim completion until the files exist and validation has run.

INTEGRATION NOTE
The Swift loader accepts an array of any length; it does not impose a 1,000-food limit. The existing generator and Tests/ECCTests.swift currently assert 1,000. Document that these catalog-count checks need to become 5,000 when the expanded catalog is imported. The expanded manifest and generator must be imported with the JSON, or a later regeneration could overwrite the expansion.

Finish with the downloadable ZIP, the actual food count, source breakdown, validation summary, and any unresolved issues.
