# Code-check round 4 (#93)

Reviewer: subagent, 2026-09-29. The job of this round is to decide whether the loop can end.

**Scope.** `diff4_branch.patch` and `diff4_staged.patch`. Every script in `scripts/landcover_accuracy/` was read in full in its current state. They were checked against:

- drift 0.19.0 (installed): `dft_accuracy_sample`, `accuracy_draw`, `dft_accuracy_estimate`, `dft_accuracy_size`, and the `dft_stac_composite` cache key.
- the on-disk review project: `labels.gpkg` / `patches.gpkg` schema and CRS, read-only with `ogrinfo`.

**Runs.**

- `accuracy-check.R`: ALL PASS.
- `SYNTHETIC=1 accuracy_estimate.R necr` runs to a verdict ("1 of 4 evaluable"). Every stratum's `n_full` is 50 because drift's `n_min = 50` floor applies, not because of a defect.

**Probes.** All in `/private/tmp/claude-501/r4`, toy data only. Nothing in the repo or under `data/` was written.

## Findings

No defects. The round-3 fixes hold, and no fix reproduces the mechanism one axis over along any path the scripts themselves produce. There is one fragile guard and one scope note, and neither blocks ending the loop.

- **[severity: fragile] `fp_accuracy.R:193-195` — `fp_acc_design_check` treats an absent `cell` column as agreement.**
  - It requires `stratum` and `map_class`, and compares `cell` only when `x` happens to carry it.
  - `stratum` can never disagree for a matched id: drift writes `point_id = sprintf("%s_%05d", accuracy_key(code[h]), k)` (`dft_accuracy_sample.R:186`), so the stratum is the id's prefix.
  - Without `cell`, the check therefore reduces to `map_class`. That is constant within whole strata: Trees -> Rangeland is always 2011, Rangeland -> Trees 11002, stable Trees 2002.
  - Probed: a label frame with no `cell` column, against a redraw that moved every point in a constant-`map_class` stratum, returns `TRUE` (pass).
  - **Not reachable through the scripts as written.** `labels_export.R` writes `cell` (`fp_accuracy.R:233`), and `labels.gpkg` is built from `sample.gpkg`, which carries it. So the hole opens only for a `labels.csv` or working copy made some other way.
  - Fix, one line: require `"cell"` alongside `stratum`/`map_class` at `:194`. The one column that actually identifies a point should not be the optional one.
- **[note, no wrong number] `sample_draw-pilot.R:93-96` — the refusal does not see labels whose `point_id` the new draw no longer contains.** Examples: a smaller `N`, or a stratum that vanished.
  - `fp_acc_design_check` exempts unmatched ids by construction (`!is.na(m) &`, `:200`). The other three callers pre-refuse unknown ids:
    - `fp_accuracy.R:214` (`labels_frame`)
    - `:275` (estimate)
    - `review_build-qgis.R:190`

    `sample_draw` does not, so it overwrites `sample.gpkg` under those labels. Probed: labels from `n = 60` against a redraw at `n = 30` pass.
  - The outcome is still loud. `accuracy_estimate.R` refuses at `fp_accuracy.R:275`, and `labels_export.R` refuses at `:214`. `sample.gpkg` is git-tracked. The only thing wrong is the comment at `:92` ("anything else is refused").
  - Adding `setdiff(lab$point_id, pts$point_id)` to the refusal would make it true.

### The three questions asked

1. **Does `fp_acc_design_check` fold an absent value into agreement?**
   - **Missing design column:** yes for `cell` only (above). A missing `stratum` or `map_class` is refused.
   - **NA:** NA on one side is refused. NA on both sides agrees, which is correct: `map_class` is legitimately NA on both sides for round 3's row 5. `cell` is never NA.
   - **Type coercion:** Real, integer and character all become double. The largest NECR cell is 6288 × 8945 = 56.2M, which is exact in a double and through `write.csv`'s 15 significant digits. A non-numeric string on one side becomes NA and is refused.
   - **point_ids absent from `smp`:** exempt, but pre-refused by three of the four callers (above).
   - **Duplicate point_ids:** pass the check. drift then refuses them: probed, "`point_id` must be unique".
   - **A frame with no `point_id` column:** `bad` becomes `logical(0)` and the check passes, but every caller then fails loud (a row mismatch in `labels_frame`, `merge()` in estimate).
2. **Does reprojecting to EPSG:3005 break anything downstream?**
   - No. `labels_export.R` and `accuracy_estimate.R` drop geometry. `st_transform` does not touch attributes, so `cell` is intact.
   - `chip_build` reads `sample.gpkg` in 32610 and asks drift for 3005. drift transforms the AOI before keying the cache, and `target_crs` is in `stac_composite_cache_key`, so the timing run's 32610 chips cannot be served as 3005.
   - Probed, one residual: `st_write(append = TRUE)` of 3005 points into a **32610** layer is **silent**. It writes 3005 coordinates un-transformed.
     - That would bite only if a `labels.gpkg` survived from a run before the 3005 change. `review_build` writes `labels.gpkg` before `rfp_qgs_vector_add` refuses, so a failed pre-change run could leave one.
     - The one on disk is 3005 (checked). The damage would be display-only: points land around 9°N. Identity is `cell`, never geometry.
     - OK.
3. **Does `sample_draw`'s refusal pass growth (same seed, larger N)?**
   - Yes. Probed on drift 0.19.0: `n = 30` → `n = 60` keeps every pilot id on the same cell, and so does a tip into a census (`n = 1000`), because `accuracy_draw` pins `useHash = FALSE` (`dft_accuracy_sample.R:320`).
   - `fp_acc_design_check` returns `TRUE` on the grown draw.
   - The research note's "raise the stable strata first" (a per-stratum `n`) holds too, since each stratum has its own stream.

## Enumeration re-walk

Rows 1-53 are round 3's, re-checked against the current code (line numbers updated where they moved). Rows 54-75 are the sites the round-3 fixes introduced.

| # | file:line (current) | input that can be absent/NA/empty | becomes | verdict |
|---|---|---|---|---|
| 1 | fp_accuracy.R:17-18 | `primary_scenario`, `change_interval` absent | run_area.R defaults | OK |
| 2 | fp_accuracy.R:28 | raster with no EPSG | stop | OK |
| 3 | fp_accuracy.R:48 | endpoint year missing | stop | OK |
| 4 | fp_accuracy.R:55 | NA endpoint under a transition cell | disagreement | OK |
| 5 | fp_accuracy.R:55 / :154 | transition NA on a stable cell | map_class NA; drift refuses at estimate; design check agrees on NA/NA | OK-loud |
| 6 | fp_accuracy.R:63 | zero polygons | all-NA raster | OK |
| 7 | fp_accuracy.R:76-80 | NA from/to/trans/inpoly | excluded explicitly | OK |
| 8 | fp_accuracy.R:82-83 | denominator 0 | NA | OK |
| 9 | fp_accuracy.R:118-120 | trans NA, from != to | sieved | OK |
| 10 | fp_accuracy.R:131-147 | NA outside footprint | stratum NA | OK |
| 11 | fp_accuracy.R:165 | patch `in_<cause>` NA | not a cause (tagger writes FALSE) | OK |
| 12 | fp_accuracy.R:174-175 | fetch returns 0 rows | empty raster | OK |
| 13 | fp_accuracy.R:213-229 | dup/unknown ids, bad status, missing class, class on cannot_label | stop | OK |
| 14 | fp_accuracy.R:228-229 | confidence/imagery NA | allowed | OK |
| 15 | fp_accuracy.R:235, 237 | cannot_label ref_class; NA labelled_on | NA / "" | OK |
| 16 | fp_accuracy.R:217 + labels_export.R:32 | working-copy design columns disagree with sample.gpkg | **refused** (`fp_acc_design_check`; must-fail arms `accuracy-check.R:130-135`) | FIXED, OK (see 54) |
| 17 | fp_accuracy.R:214-216, :275 | label point not in the sample | stop | OK |
| 18 | fp_accuracy.R:284-286 | stratum < 2 labelled | stop | OK |
| 19 | fp_accuracy.R:280-287 | drawn points with no labels.csv row | dropped (random order within stratum, valid subsample) | OK (note) |
| 20 | fp_accuracy.R:293-296 | measure/class absent | NA | OK |
| 21 | fp_accuracy.R:301 | `in_<cause>_poly` absent | row-mismatch error | OK-loud |
| 22 | accuracy_estimate.R:188-194 | cause removed/renamed in the yml after the draw | causes from design.json; a differing yml is **refused** | FIXED, OK |
| 23 | fp_accuracy.R:305-315 | "target" in neither map nor ref | area 0, se 0 | OK |
| 24 | fp_accuracy.R:327 | unattributed area 0 | hw NA, criterion 2 NA | OK |
| 25 | fp_accuracy.R:267-270, :337 | FV PA NA at one endpoint | `fp_acc_crit1`: TRUE if any < 0.5, else NA if any NA, else FALSE | FIXED, OK |
| 26 | fp_accuracy.R:269 | both endpoints NA | NA | OK |
| 27 | fp_accuracy.R:339-342 | criterion NA | `n_na`, "undetermined" when it could tip | OK |
| 28 | fp_accuracy.R:347-348 | stratum SD NA | 0 (no target in that stratum's sample; SD truly 0) | OK |
| 29 | fp_accuracy.R:351-356 | all SDs 0 | note, not size | OK |
| 30 | fp_accuracy.R:245-248 | synthetic RNG state | restored | OK |
| 31 | accuracy_estimate.R:200 | labels.csv absent | stop | OK |
| 32 | accuracy_estimate.R:204-207 | omission CSV absent / blank | NA → criterion 4 NA | OK |
| 33 | accuracy_estimate.R:206 | harvest "all" row absent | row-mismatch error | OK-loud |
| 34 | fp_accuracy.R:276 | labels.csv stratum/cell/map_class disagree with sample.gpkg | **refused** (`accuracy-check.R:160-162`) | FIXED, OK |
| 35 | labels_export.R:31 | ref classes but blank status | not exported | OK |
| 36 | labels_export.R:35-51 | old csv empty / no overlap | nothing refused | OK |
| 37 | labels_export.R:40-50 | point dropped/relabelled vs committed | stop unless FORCE | OK |
| 38 | review_build-qgis.R:153-155; chip_build-composite.R:103-105 | project dir without .qgs | review_build stops with the cause; chips refuse before the project exists | FIXED, OK (on disk: `.qgs` present) |
| 39 | review_build-qgis.R:188-194 | missing label fields; id not in sample | stop | OK |
| 40 | review_build-qgis.R:195 | redraw, same ids, other cells | **refused** | FIXED, OK |
| 41 | review_build-qgis.R:222-229 | no chips | message | OK |
| 42 | chip_build-composite.R:121-126 | composite fails / empty | file NA, counted | OK |
| 43 | chip_build-composite.R:140-145 | window-year with 0 chips | no VRT | OK |
| 44 | chip_build-composite.R:110-113 | integer `months` column | strsplit error | OK-loud |
| 45 | chip_build-composite.R:83 | `n_points` non-numeric | NA → all | OK |
| 46 | window_count-clear.R:47-58 | NA cells in AOI | 0 | OK |
| 47 | window_count-clear.R:70-85 | skip warning + abort | "empty"; else "failed" | OK (accepted) |
| 48 | window_count-clear.R:91-95 | all-NA ok raster | unreachable (drift_empty_cube) | OK |
| 49 | window_count-clear.R:123-131 | empty vs failed | 0 vs NA; failed warns | OK |
| 50 | reference_omission-disturbance.R:57-63 | NA year | excluded by SQL window | OK |
| 51 | reference_omission-disturbance.R:69-73 | no qualifying harvest | NOT EVALUABLE | OK |
| 52 | reference_composition-wetland.R:44-46 | unknown class code | NA | OK |
| 53 | sample_draw-pilot.R:69-71 | strata don't partition | stop | OK |
| 54 | fp_accuracy.R:193-195 | **`cell` column absent from `x`** | not compared; the check reduces to `map_class` (stratum is the id prefix), which is constant within T→R, R→T and stable Trees; probed pass | **FRAGILE**: unreachable via the scripts (every writer carries `cell`); require it |
| 55 | fp_accuracy.R:196-200 via sample_draw-pilot.R:94-96 | labels.csv ids absent from the new draw (smaller N, stratum lost) | exempt; the redraw proceeds; probed pass | OK-loud: estimate `:275` and labels_frame `:214` refuse; sample.gpkg is git-tracked. The comment at `:92` overstates |
| 56 | fp_accuracy.R:199 | cell/stratum/map_class as Real, integer, character | double; exact (max cell 56.2M); non-numeric on one side refused | OK |
| 57 | fp_accuracy.R:200 | NA on both sides | agree (legitimate for row 5's map_class; cell never NA) | OK |
| 58 | fp_accuracy.R:197 | zero-row `x` | nothing to check, pass | OK |
| 59 | sample_draw-pilot.R:94 | labels only in labels.gpkg, not yet exported | no refusal at draw | OK-loud: review_build `:195` / labels_frame `:217` refuse next |
| 60 | sample_draw-pilot.R:94 | FORCE=1 | redraw, labels orphaned | OK-loud: estimate `:276` refuses |
| 61 | sample_draw-pilot.R:94-96 | growth, same seed, larger N (and a tip into a census) | pilot ids keep their cells; check passes (probed, drift `useHash = FALSE`) | OK |
| 62 | review_build-qgis.R:195 | a redraw before any labelling (all rows blank) | refused until labels.gpkg is moved aside | OK-loud (conservative) |
| 63 | accuracy_estimate.R:188-191 | one cause (auto_unbox scalar) / zero causes | identical() holds / zero causes refused upstream by `fp_acc_strata` | OK |
| 64 | accuracy_estimate.R:190 | yml read raw vs validated at draw | names identical either way | OK |
| 65 | fp_accuracy.R:269 | PA NaN | NA | OK |
| 66 | fp_accuracy.R:334 | criterion-1 `value` NA while `holds` TRUE | display only; `detail` shows both | OK |
| 67 | review_build-qgis.R:198 | append 3005 points into a pre-existing **32610** labels.gpkg | silent un-transformed write (probed) | OK: display only (points around 9°N); identity is `cell`; the on-disk copy is 3005 |
| 68 | chip_build-composite.R:118-123 | 32610 box, 3005 target | drift transforms the AOI; `target_crs` in the cache key | OK |
| 69 | chip_build-composite.R:103-105 | no .qgs | stop | OK |
| 70 | review_build-qgis.R:153-155 | stray project dir | stop | OK |
| 71 | fp_accuracy.R:233 | cell through write.csv/read.csv | 15 significant digits, exact | OK |
| 72 | fp_accuracy.R:196 | `x` without `point_id` column | `bad` = `logical(0)`, pass | OK-loud: every caller fails at the next step |
| 73 | fp_accuracy.R:275-277 | duplicate point_id in labels.csv | the check passes; drift refuses "`point_id` must be unique" (probed) | OK-loud |
| 74 | review_build-qgis.R:174-175 | smp reprojected before the check | attributes unchanged | OK |
| 75 | labels_export.R:28-29 | geometry of the working copy | dropped; never an identity | OK |

**Final count: 75 rows. Defects remaining: 0.** Rows 16, 22, 25, 34, 38 and 40 are fixed and verified. One row is FRAGILE (54), with a one-line fix. One row is a scope note (55) with no wrong number.

No row resolves an absent, failed or unevaluable input to a determinate number or class along a path the scripts produce. The loop can end, and row 54's one-line fix is advisable before labels exist.
