# Findings — Composite windows name their scenario; NECR's accuracy sample moves to all_ff04 (#148)

## Issue context

**If we fix it:** the composite windows the review chips are built from carry the floodplain they were measured on, and a stage refuses windows from another one. NECR's accuracy sample is redrawn on the floodplain that is actually published, `all_ff04`, under that guard.
**If we never do:** after a `FORCE=1` redraw onto a new scenario (legal since #140), `chip_build-composite.R` builds the new sample's chips from windows measured on the old floodplain, with no message. And NECR's accuracy work keeps measuring land cover on `ch_ff04`, a floodplain the catalogue retired on 2026-10-15.

Found by #140's `/code-check branch` round 4, which walked every write in `scripts/landcover_accuracy/`. It is the one output whose scenario is still implicit.

## Why NECR is redrawn here (decided 2026-10-23)

NECR's design (`reference/necr/design.json`) is on `ch_ff04`; stac_floodplains_bc v2.0.0 retired the species items on 2026-10-15, so the published NECR floodplain is `all_ff04` (75,909 ha footprint against `ch_ff04`'s 41,838 ha). Nobody has labelled in either QGIS project, so the redraw costs regeneration only. The one thing lost is the model labeller's labels for the first draw (hash committed in 4072a24): nobody has seen them and labeller B has none, so no result informs the redraw. They are discarded unread and the model labeller re-runs on the new draw. The redraw is exactly the case the window guard exists for, so the guard lands first.

## Where it breaks

- `window_count-clear.R run` counts clear days over the `floodplain.gpkg` layer `cfg$primary_scenario` and writes `windows_clear_obs.csv` with no scenario.
- `derive` reads it back unchecked. Where 2017 needs widening it mixes those cached shares with direct counts over the current scenario's floodplain, then writes the committed `windows.csv`.
- `chip_build-composite.R`, `review_build-qgis.R` and `review_render-sheets.R` read `windows.csv` with no scenario check.

## Work

- `run` stamps `scenario` in `windows_clear_obs.csv`; `derive` refuses a missing or different one.
- `derive` writes `scenario` into `windows.csv`; its readers refuse a mismatch with `fp_acc_area()`'s scenario (`fp_acc_windows_read()`, the shape of `fp_acc_omission_read()`, #140). A file with no column is refused, not passed.
- Offline arms in `accuracy-check.R`, each with a must-fail form.
- Redraw NECR: `FORCE=1 sample_draw-pilot.R necr all_ff04` (seed 930093, 30 per stratum, whole footprint), after removing the first draw's `review_key.csv` and `labels_model.sha256` and moving the old review projects and `model/` aside unread.
- Regenerate on the new draw: windows (`validate`/`run`/`derive`, logs grepped per drift#87), the wetland and omission references (criterion 4), `imagery.csv`, `wayback.csv`, the dated, Wayback and S2 chips, both review projects (B: 75 points), and the model labeller's sheets and labels (hash only committed).
- Rewrite the research file's "Reference sample (NECR pilot)".

Relates #140, #93, #145, #131.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `window_count-clear.R run`: 2022-08 and 2022-09 FAILED, `HTTP content type response 'text/plain' not defined for this operation` (Planetary Computer STAC); derive refused "2 month-year(s) failed or unmeasured" | Transient: `run` re-run (47 months cached, the 2 re-counted, 0 failed); derive then hit the same error on the 2017 Aug-Sep direct count and passed on a re-run. 0 `repoprted` in all five logs |

## Plan review (2026-10-23)

`review-plan.md` holds the findings and their disposition. Three blockers: a sheet-title regex that knew only NECR's first windows (fixed), a `derive` refusal with no branch (now a stop-and-ask gate), and the model-labeller subsection needing a dated amendment for the second hash (Phase 5).

## The first redraw (2026-10-23T20:47Z)

`FORCE=1 sample_draw-pilot.R necr all_ff04`: 7.0 min. Strata partition the footprint, 8,078,287 cells (80,782.9 ha, the touches ring; 75,909 ha by cell centre in the floodplain). 16 strata, 3 of them stable, 30 points each = 480. So B's subset is 3 x 16 + 9 x 3 = 75, and the model labeller runs 12 batches of 40, as before.

## Accepted residual risk: the windows guard compares names

A re-run of step 2 or 3 under the same scenario name (`all_ff04`) between `run` and `derive`, or before the chips, passes the guard. Same class as #140's design guard, which the grid comparison closes there; for windows it is accepted, because the windows are re-measured whenever the sample is redrawn.

## Criterion 4 moves with the population (recorded 2026-10-23, before the all_ff04 value is computed)

Criterion 4 (free reference: IO's omission of qualifying harvest) was scored on `ch_ff04`: omission_io **0.2549** over 92.0 ha, so it did not hold. The sample moves to `all_ff04` for a catalogue reason (the species items were retired 2026-10-15; the published NECR floodplain is `all_ff04`), decided by the user before any `all_ff04` accuracy number existed. The **`all_ff04` value is the one that counts** for the verdict, whatever it is, and the `ch_ff04` value stays stated beside it in the research file, so a move across the threshold cannot read as choosing the population for the result.

## Phase 2-3 results (2026-10-23)

- Redraw byte-identical twice (`sample.gpkg`, `strata.csv`, `design.json` cmp-equal). `fp_acc_area("necr")` gives all_ff04 / all / 2 / design, no NOTE. `fp_acc_grid()` refuses the ch_ff04 grid.
- Windows (validate 2021-07 floodplain-wide 2.3 min; run ~70 min; derive): August in every year but 2017, 2017 widened to Aug-Sep (direct count 0.999). The same windows as on ch_ff04, now stamped `all_ff04`.
- Wetland reference: FWA wetland cells 12,809.04 ha of the 80,782.9 ha footprint; `composition-check.R necr` (5) PASS at 12,809.04 vs 12,809.04, ALL PASS. Outside the group polygon: 190.1 ha of change, 1,014.8 ha of floodplain.
- Criterion 4 on all_ff04: omission_io **0.1475** (0.148; the script's 3 dp print read 0.147) over 481.46 ha (223 qualifying cutblocks); does not hold. ch_ff04 was 0.2549 over 92.0 ha. Same verdict.
- imagery.csv: themed epochs unchanged in kind, air photo 2012 (480 of 480) and orthophoto 2021 (136 of 480, 28.3%; was 204, 42.5%).
- wayback.csv: 960 rows; 160 of 480 points have the same capture at both endpoints (was 115).
- Review project A built (480 cells, patches from transition_all_ff04, 24 columns); review_key.csv 480 rows, 75 in B's subset.
- Dated: orthophoto 2021 VRT 227 tiles (0.15 m); air photo 2012 305 frames georeferenced (388 old frame thumbnails reused), 0 covered points without one, 4.41 m. fly warned 13 of 1,589 corrected frames are <95% DEM-covered.
- Wayback chips: 960 fetched, 0 failed, every point reads its own chip, 766 MB, 14.5 min.
- S2 chip build started (480 x 4).
