# Plan review — #140 (Plan agent, 2026-10-23, background; findings relayed and dispositioned here)

| # | Cat | Finding | Disposition |
|---|-----|---------|-------------|
| 1 | Blocker | `min_order` stays area.yml's (2) while species moves to ch: channel probe would read `streams_ch2`, absent (only `streams_ch3`) | **Reproduced** (`ogrinfo`, area.yml:4). Species + min_order now from the scenario's `flood_scenarios.csv` row; no row refused. Arm + mutation red. |
| 2 | Gap | species from the name is a parallel rule | Folded into 1: csv row is the authority (`run_area.R:70` does the same). |
| 3 | Gap | explicit scenario w/o design keeps area.yml's species | Fixed by 1 (lookup runs on every branch). Arm: redesign to co_ff04 gives species co. |
| 4 | Gap | FORCE=1 redraw on the same scenario after a grid move is refused by the guard | Fixed: `redesign` drops `cfg$design` whatever the scenario. Arm added. |
| 5 | Gap | sample.gpkg `scenario` column not cross-checked | Not adopted: both written by one run from one variable (`sample_draw-pilot.R:58,108`), never hand-edited; a second reader would compare a value with itself. |
| 6 | Assumption | `compareGeom` CRS via WKT may break on PROJ upgrade | **Disproved by measurement:** WKT vs `EPSG:32610` vs proj4 all TRUE; 1e-7 and 0.05-cell shifts TRUE; one-cell shift and EPSG:32609 FALSE. |
| 7 | Assumption | wetland re-run expects 6,436.64 exactly; fwapg may have moved | Accepted: a difference is recorded as drift, not a fix failure. |
| 8 | Assumption | B labels.gpkg may be rewritten (unlabelled) | Accepted: pass is "unchanged, or rewritten with 0 labels". |
| 9 | Acceptance | arms cannot go through `fp_acc_area` (here::here paths) | Arms call `fp_acc_design_scenario` / `fp_acc_scenario` directly. |
| 10 | Acceptance | all_ff04 fixture differs in dims AND extent; no single check can go red | Separate fixtures: dims-only, one-cell shift, EPSG:32609. Mutation dropping the guard turns all three red. |
| 11 | Acceptance | pre-fix arm must be a real call | It is: `fp_acc_scenario(yml, NULL, sc)`. |
| 12 | Scope | callers needing the design's value: channel probe, wayback_coverage, window_count, wayback_index | All go through `fp_acc_area`; covered. |
| 13 | Scope | issue says "refuses"; plan makes area.yml mismatch an INFO | Decided at the gate; state in PR and #140. |
| 14 | Ordering | fix 1 before Phase 3; add channel probe to verification | 1 fixed in Phase 1. Probe verified to resolve `streams_ch3` live; full probe re-run not needed for this fix. |
