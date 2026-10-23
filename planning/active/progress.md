# Progress — #140

## Session 2026-10-23

- Plan-mode exploration — phases approved by user
- Created branch `140-the-accuracy-module-reads-area-yml-s-sce` off main
- Scaffolded PWF baseline from issue #140 with approved phases
- Next: start Phase 1
- Plan review (background Plan agent) returned; `review-plan.md`. Blocker #1 (min_order) reproduced and fixed; #6 disproved by measurement.
- Phase 1 done: resolver, grid guard, sampler arg, 21 offline arms. Mutations (drop min_order, drop grid guard, area.yml wins) each red; unmutated copy ALL PASS. Live: necr -> ch_ff04/ch/3/design, bulk + dunc -> all_ff04/all/2/area.yml.
- Phase 2 done. `reference_composition-wetland.R necr` re-run: identical to the pre-#140 csv apart from the new `scenario` column (ch_ff04), fwa_wetland 2017 = 6,436.64 ha. `composition-check.R necr ch_ff04`: (5) PASS 6436.64 vs 6436.64; 1 FAIL `in_open_water` missing on the retired species table (#138 forward-only, pre-existing). `composition-check.R necr` (all_ff04): (5) INFO skip, ALL PASS.
- Phase 3: B review project rebuilt (REVIEWER=b) 18:37 UTC: patches.gpkg 11,469 -> 5,692; labels.gpkg byte-identical (75 points, 0 labelled). Local only, no Mergin sync. CLAUDE.md rule added. #131 and #140 bodies edited.
- Verification: `reference_omission-disturbance.R necr` (reads `fp_acc_grid`) rewrote `omission_disturbance.csv` at 18:45 UTC byte-identical to the pre-#140 copy (criterion 4: omission_io 0.255 over 92.0 ha). The stage reads ch_ff04 again.
- `/code-check branch` round 1 (spawned 18:38 UTC): Clean (`review-round1.md`). Round 2 spawned 18:43 UTC.
- Round 2 (`review-round2.md`): 1 fragile: every stage now needs the design scenario's `flood_scenarios.csv` row, and #131 may drop species rows. Accepted as loud-by-design; #131 body now says keep that row. Also fixed three comments the change made stale. Not inside a previous fix (round 1 made none).
- Round 3 (`review-round3.md`): 1 fragile, a missed instance of the implicit-scenario-key mechanism, not a defect inside a fix: `omission_disturbance.csv` feeds criterion 4 and recorded no scenario. Fixed: the writer stamps `scenario`; `fp_acc_omission_read()` refuses a missing or other scenario; 3 arms, a mutation turns 2 red. Reviewer's enumeration of where the mechanism reaches: transition and classified rasters (grid guard), transition layer and streams (named from the design), wetland and omission csvs (stamped), `floodplain.gpkg` layer (name only, predates #140, retired species not re-run), `windows.csv` (committed pre-#125, on ch_ff04).
