# Review round 1 — staged diff for #106 (channel-migration probe)

Scope: `scripts/floodplain_lcc/fp_channel.R`, `channel_probe-migration.R`, `channel_probe-check.R`,
checked line by line against `research/channel_migration.md` "Pre-registered rule" v2.

## Verified correct (probed, not just read)

- Roles, class sets (erosion-from {2,4,5,8,11}, deposition-to {2,4,8,11}), `from*1000+to` split,
  the 2-column `classify()` is/becomes reclass (NA "becomes" works; probed).
- Candidate = AND of all five conditions; `channel_adjacent` = io AND fwa <= 50 AND not lake.
- Rule A/B/C/D denominators and thresholds match the text; width-matched set = `!cand & width >= 1.5`
  (includes "other"-role patches, which "fail any other condition" — correct).
- Pairs: opposite role, same blk, 300 m edge-to-edge (`st_is_within_distance`, GEOS, projected),
  station-interval overlap `|s_i - s_j| <= h_i + h_j` (correct interval test), i/j remap via `ci[]`,
  ero/dep assignment, exact-reverse = ero from-class == dep to-class, R over dep->ero unit vectors
  (row-wise division is correct for column-major recycling).
- Verdict table matches the outcomes table row for row.
- `raw()` (deepcopy + `set.cats(NULL)`) leaves the original factor intact (probed); `n_diff` is
  NA-safe in both directions.
- Anchor 1: step 3 sieves with `dft_rast_transition(patch_area_min = 10000)` (03 line 120), same call.
  Anchor 2: NECR strata.csv change + sieved sums to 5,779.45 ha; `chg_ha` uses the same footprint
  definition as `fp_acc_strata`.
- `terra::extract` on the cell-aligned polygons returns exactly one row per cell (centre rule, probed,
  multipart diagonal patches included); lines return a logical column and `%in% TRUE` is fine either
  way. `global(max)` on an all-NA patches raster is NA, so the empty-role guard works.
- Stream helpers on copies of the real NECR `streams_ch3` and BULK `streams_co3`: digitised-upstream
  share 1.0 on both; `drm + feature length` matches the next feature's `drm` to within 3 mm, so
  `station_m` is consistent.
- transition.tif's RAT carries the `transition` level column `dft_transition_artifact()` requires.
- Writes: only `data/<area>/channel/` and the logs dir. The publish layer copies named files only
  (`floodplain_landcover.gpkg`, `floodplain.gpkg`, `rasters/<scen>/`), so `channel/` never ships.
  Nothing writes to a published gpkg or raster.
- `channel_probe-check.R` runs green (all passed).

## Findings

- **[bug, low]** `scripts/floodplain_lcc/fp_channel.R:189-191` — `fp_ch_sustained()` reclassifies
  Snow/Ice (9) and Clouds (10) to NA only for years 2..n; the FIRST year `f` is used raw. The rule says
  9/10 years "count as missing", and the function's own contract says "NA where the first year is NA".
  A cell whose 2017 class is 9 or 10 (e.g. Snow/Ice -> Water, Clouds -> Water: "other" role) is
  therefore scored against a missing class: every later non-missing year is "away", nothing can ever
  be "back", so it scores sustained = 1 instead of NA. Those patches sit in B's width-matched
  comparison set, so the error inflates `sustained_wm` (B harder to pass — conservative). Magnitude is
  small (NECR's whole "Snow/Ice -> any" stratum is 3.39 ha), but it is a code/rule mismatch in a
  pre-registered measure. Fix: `f <- terra::classify(stack[[1]], rcl)` so a missing first year
  propagates NA.

- **[rule/code mismatch to resolve, low]** `scripts/floodplain_lcc/fp_channel.R:278,289` — `D_dir`
  (BULK direction) is `d_ok`, which requires `n_opp >= 10`. The rule's BULK clause lists only
  "R < 0.5"; the >= 10 minimum is stated inside criterion D, which is NECR's. Reading D's minimum into
  BULK is defensible, but it is an interpretation not written in the rule, and it decides the verdict
  ("separates" vs "NECR only") if BULK yields 1–9 opposite pairs with R < 0.5. State which reading is
  intended (in the rule's Results/notes, not by editing v2's thresholds) before the BULK number is read.

- **[fragile, low]** `scripts/floodplain_lcc/channel_probe-migration.R:106-110` — lakes are queried
  `WHERE watershed_group_code = <wsg>`. The rule restricts rivers to "in the WSG" but states
  `lake_margin` as "within 50 m of a fwa_lakes_poly polygon" with no WSG restriction. A floodplain
  patch near the group boundary (e.g. at the outlet) within 50 m of a lake assigned to the
  neighbouring group is not flagged as lake margin and can become a candidate. Likely rare; a bbox
  query (patch extent + 50 m) instead of the WSG filter would match the text.

No other issues found.
