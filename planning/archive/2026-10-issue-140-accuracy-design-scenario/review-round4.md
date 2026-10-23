# Code-check round 4 (#140): diff 66b6263...HEAD -- scripts CLAUDE.md

## Checklist read

- code-check-python.md: in full (7,237 bytes; nothing applies, the diff has no Python).
- code-check.md (330 KB): every H3 under `## Mechanisms`, prose only, `|` rows skipped. That is all 14: guard that fails toward pass, fixture that cannot reach, proxy, verification that reads its own output, a guard's scope, fix lands in one of two callers, restore the bug, shared working tree, wrapper's exit, zero-length/empty/unset, probe is broken, written data outlives the fix, serialization, one fact derived twice. Not read: the `## Rules that stand alone` and `## Security` sections and the spreadsheet/PDF section. None of their headings names a tool or shape this diff uses.
- code-check-r.md (177 KB): 11 headings read in full: Read-back shape; `$` partial-matches; yaml mixed int/float; `match()` NA; `[[` on atomic; CSV whitespace; `identical()` on reader results; `expect_false(identical())`; `tryCatch()` nests; `paste()` zero-length; `data.frame()` recycles. Not read: about 95 others (packaging, testthat, duckdb, arrow, ggplot and the like), which this diff does not touch.
- code-check-spatial.md (156 KB): 2 headings read in full: `terra::rast()` on a SpatRaster; `terra::project()` given only a CRS (its note on `compareGeom()`'s sub-metre tolerance, accepted). Not read: about 110 others.
- code-check-shell.md (124 KB): 0 headings read. The diff has no shell.

## Review of the round-3 fix (297d4d7)

The fix holds.
- `reference_omission-disturbance.R` gets `cfg` from `fp_acc_area()`, which resolves the design's scenario. It reads its rasters through `fp_acc_grid()`, so the grid guard runs before anything is written. It stamps `scenario = cfg$primary_scenario`.
- `fp_acc_omission_read()` refuses both cases: a file with no `scenario` column, and a file whose rows are not all on the estimate's scenario. It also refuses anything other than exactly one harvest/all row. A NA omission, when no harvest qualifies, still passes through as "not evaluable".
- Mutation check by reading: if the column-presence arm is dropped, the "no scenario" fixture gives `NULL == "ch_ff04"`. That is `logical(0)`, and `all()` of it is TRUE, so the file would be accepted and that test goes red. If the equality arm is dropped, the "another scenario" test goes red. Each arm has its own red test.
- I ran `accuracy-check.R` in a temp copy: rc 0, ALL PASS, including the three new omission assertions.
- The `year` column stays character because the "all" row is always present.
- `accuracy_estimate.R` gets `cfg$primary_scenario` from `fp_acc_area(area)` with no override, so it is always the design's scenario.

## Enumeration: every write in scripts/landcover_accuracy/*.R

For each output: whether a later stage reads it, and whether the scenario it was made on is checked.

| output | written by | read later by | scenario checked? |
|---|---|---|---|
| reference/sample.gpkg, strata.csv, design.json | sample_draw-pilot | every stage | defines the design (transition_layer) |
| data/accuracy/omission_disturbance.csv | reference_omission-disturbance | accuracy_estimate (criterion 4) | YES, stamped and refused (297d4d7) |
| data/accuracy/wetland_composition.csv | reference_composition-wetland | composition-check (5) | YES, stamped and compared like with like |
| **data/accuracy/windows_clear_obs.csv** | window_count-clear `run` | window_count-clear `derive` | **NO, see finding 1** |
| **reference/windows.csv** (committed) | window_count-clear `derive` | chip_build-composite, review_build-qgis, review_render-sheets | **NO, see finding 1** |
| data/accuracy/chips_manifest.csv | chip_build-composite | review_render-sheets, review_build-qgis | keyed by point_id; redraw-staleness is the pre-existing point_id issue, not scenario |
| reference/imagery.csv, wayback.csv; data/accuracy/wayback/built.csv | imagery_index-dated, wayback_index-capture, wayback_build-chips | review_build-qgis, review_render-sheets, imagery_build-dated | design-key checked (fp_acc_design_check) |
| review project: labels.gpkg, cells.gpkg, review_key.csv | review_build-qgis | labels_export, review_render-sheets | review_id/cell checked against the key and design |
| review project: patches.gpkg | review_build-qgis | QGIS only (display) | rebuilt whenever its attributes differ from the design's transition layer, so it heals itself |
| data/accuracy/model/* (sheet_map, batches, audit, sha) | review_render-sheets, labels_import-model | labels_import-model, accuracy_estimate | keyed to review_id and sample; no scenario dependence (not opened) |
| data/accuracy/drought_rank.csv | drought_rank-gauges | nothing | depends only on the interval |
| data/accuracy/wayback_coverage.csv | wayback_coverage-area | nothing (stdout summary names the scenario) | n/a |
| data/accuracy/estimate*.rds, criteria*.csv | accuracy_estimate | nothing programmatic | inputs are guarded; the verdict files themselves carry no scenario. Not a finding, because nothing reads them back |
| floodplain_lcc channel probe: data/channel/*.gpkg, logs csv/md | channel_probe-migration | nothing | the md header names the scenario; reads go through fp_acc_grid, and anchor 2 now compares against strata on the same scenario |

Round 3's list is complete except for `windows_clear_obs.csv`. It also covered `windows.csv` only by its current state ("committed pre-#125"), not on the FORCE path that this branch makes legal.

## Findings

- **[severity: fragile]** `scripts/landcover_accuracy/window_count-clear.R:160-203` (and :233). `windows_clear_obs.csv` records no scenario.
  - `run` counts clear days over `floodplain.gpkg` layer `cfg$primary_scenario` and writes the file unstamped.
  - `derive` reads it back with no check of which floodplain it was counted on.
  - Where 2017 needs widening, `derive` mixes those cached shares with *direct* counts over the current scenario's floodplain (lines 187-192).
  - It then writes the committed `reference/<area>/windows.csv`, also with no scenario. `chip_build-composite.R`, `review_build-qgis.R` and `review_render-sheets.R` read that file with no design or scenario check.

  This is the round-3 mechanism again: the scenario is an implicit key on a derived file.

  **Why it is not live today.** On disk, `windows_clear_obs.csv` was last modified 2026-09-30. NECR's `area.yml` moved to `all_ff04` in 760b8d9 on 2026-10-15. So the counts are on `ch_ff04`, the design's scenario.

  **When it breaks.** This branch makes `sample_draw-pilot.R <area> <scenario>` under `FORCE=1` the supported way to move a design to another scenario.
  - After such a redraw, `windows.csv` (made on the old floodplain) silently drives the chips for the new sample.
  - A re-derive without a fresh `run` would combine two floodplains in one committed file.

  The pre-registered rule is "clear everywhere over the floodplain", and `ch_ff04` and `all_ff04` differ in extent, so the windows can differ.

  **Fix.** It is the same shape as 297d4d7:
  - stamp `scenario` in `windows_clear_obs.csv` and refuse it in `derive` when the stamp differs from `cfg$primary_scenario`;
  - carry a `scenario` column into `windows.csv` and refuse a mismatch in `chip_build-composite.R` (its one consumer that fetches imagery).
