## Outcome

The accuracy module (#93) took its scenario from `area.yml`, so when #125 moved NECR to `all_ff04`
every stage silently followed it, away from the `ch_ff04` grid its committed sample was drawn on.
`fp_acc_area()` now reads the scenario and interval from `design.json`'s `transition_layer`, and the
species and `min_order` from that scenario's `flood_scenarios.csv` row. `fp_acc_grid()` refuses any
transition grid other than the design's, and only `sample_draw-pilot.R` under `FORCE=1` may move the
scenario. The plan review added `min_order`: #125 had also moved NECR from order 3 to 2, so the
channel probe would have read a `streams_ch2` that does not exist. `wetland_composition.csv` and
`omission_disturbance.csv` (criterion 4's input) now name their scenario, and their readers compare
like with like. The mechanism, a derived file whose scenario is "whatever the stage resolved when it
ran", was walked over every write in `scripts/landcover_accuracy/`; the one output left unstamped is
the composite windows, deferred to #148 by the user's choice (not live: measured on `ch_ff04`). One
artefact had already gone wrong: the B review project built on 2026-10-23 carried `all_ff04`'s
patches, and it was rebuilt.

## Measurement

- Grids: `ch_ff04/transition.tif` is 8945 x 6288 at origin 381677.13 / 6008953.56, exactly
  `design.json`; `all_ff04` is 9423 x 6832. The grid guard passes the first and refuses the second.
- `terra::compareGeom` (terra 1.9.50) compares CRS by meaning: WKT with USAGE, `EPSG:32610` and
  proj4 are equal. A 1e-7 m or 0.5 m (0.05-cell) shift is equal; a one-cell shift or EPSG:32609 is
  not. This disproved the plan review's worry that a PROJ upgrade would refuse the right grid.
- B review project: `patches.gpkg` 11,469 -> 5,692 features (the `all_ff04` vs `ch_ff04` transition
  layers); `labels.gpkg` byte-identical (75 points, 0 labelled). Local only, no Mergin sync.
- `wetland_composition.csv` re-run: identical apart from `scenario = ch_ff04`; 2017 FWA wetland
  6,436.64 ha. `composition-check.R necr ch_ff04` (5) PASS at 6,436.64 vs 6,436.64. `necr`
  (`all_ff04`) used to FAIL (5) at 12,809.04 vs 6,436.64 and now skips with INFO and passes.
- `omission_disturbance.csv` re-run twice: byte-identical to the pre-#140 copy, then identical apart
  from the new column. Criterion 4 reads 0.2549 (omission_io over 92.0 ha), so the stage is back on
  the design's population.
- `accuracy-check.R`: 24 new arms. The mutations (drop `min_order`, drop the grid guard, let
  area.yml win, drop the omission guard) each turn arms red.
- `/code-check branch`: 4 rounds (Clean; 1 fragile + stale comments; 1 fragile; 1 fragile,
  deferred to #148). No round found a defect inside a previous fix, and the loop ended on round 4's
  enumeration of every write.

## Evidence

Run logs were kept in the session scratchpad only. The numbers above are the record. The review
files in this directory carry each round's checklist and findings.

Closed by: PR for #140 (branch `140-the-accuracy-module-reads-area-yml-s-sce`)
