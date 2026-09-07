# Common food catalog

The app bundles **1,000 non-branded food defaults** in `App/CommonFoods.json`.
They work offline and appear before remote search results. Calories are approximate
for the stated portion, not promises about every recipe or restaurant serving.

## Sources and selection

- **990 entries:** USDA Food and Nutrient Database for Dietary Studies (FNDDS),
  2021–2023, FoodData Central release dated October 31, 2024.
  [Download archive](https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_survey_food_json_2024-10-31.zip)
  and [dataset documentation](https://www.ars.usda.gov/ARSUserFiles/80400530/pdf/fndds/2021_2023_FNDDS_Doc.pdf).
- **10 original fruits:** existing values and stable IDs retained from the
  [FDA raw fruits table](https://www.fda.gov/food/nutrition-food-labeling-and-critical-foods/raw-fruits-poster-text-version-accessible-version).
- Initial selection priority used unweighted frequencies among reliable day-one
  reports in [NHANES 2021–2023 dietary intake](https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2021/DataFiles/DR1IFF_L.htm).
  These are a curation aid, **not nationally weighted consumption estimates**.
  Common international dishes and everyday staples were explicitly included;
  branded names, vague records and narrow duplicates were filtered out.

There is no measured claim that this catalog covers 75% of user searches.
Coverage depends on the audience and should be assessed using real search misses.

## Portions and recipe assumptions

The reviewed manifest fixes each source food, household portion, multiplier,
display name and aliases. Calories are calculated as USDA kcal per 100 g × grams
÷ 100, summed for recipes and rounded once to the nearest whole calorie.

Defaults favor an item, slice, cup, tablespoon or other practical portion rather
than 100 g. Examples include a slice of pizza, a sandwich, a cup of cooked rice,
two tablespoons of dressing and a small handful of nuts. Portion descriptions
retain gram weights so users can compare or adjust them.

- The default hot dog includes a bun, without extra toppings.
- Deli turkey, ham and roast-beef sandwich defaults add mayonnaise, lettuce and
  tomato to USDA's bread-and-meat base. Cheese versions use a separate USDA base
  containing cheese; cheese is not counted twice.
- Garden and Caesar salad defaults include the dressing described in the portion.
- Other prepared dishes use the USDA composite recipe, with its original food
  description retained in provenance. Actual recipes and portions vary.

Every USDA entry contains the source food code, FoodData Central ID/link, energy
density, gram weight and portion basis. Added recipe ingredients are explicitly
marked as app assumptions; these are not represented as USDA-published recipes.

## Maintaining and rebuilding

`manifest.json` is the authoritative, frozen selection. `curation.tsv` records
explicit everyday names and aliases used during selection; changing that TSV
alone does not regenerate the manifest. Edit the manifest for future updates.
Do not change existing IDs when changing a name or calorie value.

Download the archive above, then from the repository root:

```sh
python3 scripts/build_common_foods.py /path/to/FoodData_Central_survey_food_json_2024-10-31.zip
python3 scripts/build_common_foods.py /path/to/FoodData_Central_survey_food_json_2024-10-31.zip --check
```

The generator uses only Python's standard library. It validates the archive's
SHA-256 against the manifest, resolves USDA portions, verifies portion weights,
checks exactly 1,000 unique IDs/names, checks finite calorie values, retains the
original fruit IDs and checks the bun/mayo/cheese assumptions. `--check` also
requires an exact match between the generated and bundled JSON.

The source archive is not bundled with the app. The JSON is approximately 720 KiB.
Personal defaults remain in their existing separate store and override catalog
values; catalog updates do not rewrite previous log entries. Exact canonical
names win over aliases, and ambiguous aliases cannot choose a default to update.
