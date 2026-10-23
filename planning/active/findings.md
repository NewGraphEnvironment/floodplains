# Findings — #140

## Issue context

**If we fix it:** the accuracy module reads the population its reference sample was drawn from, whatever an area's config says today.
**If we never do:** every NECR accuracy stage reads `all_ff04`, a different grid and population from the `ch_ff04` sample in `reference/necr/`, and nothing checks that the two match.

Found by #125's acceptance checks (2026-10-17). `composition-check.R necr all_ff04` fails check (5):

```
FAIL  footprint in_wetland matches the accuracy module's FWA-wetland count (to 0.1 ha)  (12809.04 vs 6436.64 ha)
```

## Cause

- `fp_acc_area()` (`scripts/landcover_accuracy/fp_accuracy.R:18-20`) takes the scenario from `config/<area>/area.yml`'s `primary_scenario`. #125 moved NECR's to `all_ff04`.
- NECR's design is on `ch_ff04`. `reference/necr/sample.gpkg` has `scenario = ch_ff04`. `design.json` has `transition_layer = transition_ch_ff04_2017_2023`, dims 6,288 x 8,945. The `all_ff04` transition grid is 6,832 x 9,423.
- **`design.json`'s `transition_layer` is written by `sample_draw-pilot.R:136` and compared nowhere.**
- `data/necr/accuracy/wetland_composition.csv` (written by `reference_composition-wetland.R`) carries no scenario. Its 6,436.64 ha matches the earlier species composition exactly (`scripts/floodplain_lcc/logs/20261002_composition_build-rollout_necr-bulk.md:51`). `composition-check.R:238` binds it to whatever `area.yml` names now.

The species rasters are still on disk under `data/necr/rasters/ch_ff04/`, so nothing is lost. They stay until #131 prunes them, which would make the design unreproducible.

## Work

- The accuracy module takes its scenario from `design.json` (`transition_layer`), not from `area.yml`. Every stage refuses a cfg whose scenario differs from the design's.
- `wetland_composition.csv` records its scenario, and `composition-check.R` (5) compares only a reference of the same scenario.
- #131 must not prune a species output a committed design names.

Relates #93, #125, #131.


## Exploration (2026-10-23)

- ch_ff04 transition.tif: 8945 x 6288, origin 381677.13 / 6008953.56 = design.json dims/extent exactly. all_ff04: 9423 x 6832, origin 378182.41 / 6011001.70.
- transition layers: ch_ff04 5,692 features; all_ff04 11,469.
- review projects' patches.gpkg: necr_lulc_review (10-06) 5,692; necr_lulc_review_pre103 (09-29) 5,692; necr_lulc_review_b (2026-10-23 06:08) 11,469 -- built on all_ff04.
- composition_ch_ff04_2017_2023 and composition_all_ff04_2017_2023 both in floodplain_landcover.gpkg.
- #131 body already says never prune a species output a committed design names.

## Errors Encountered

| Error | Resolution |
|-------|------------|
