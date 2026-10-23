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
