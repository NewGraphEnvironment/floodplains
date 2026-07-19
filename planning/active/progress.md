# Progress — Support multiple species per area (#23)

## Session 2026-07-18

- Plan-mode exploration — phases approved by user (env-override species selection, 4 phases)
- Plan-agent review caught 3 additional blockers (03:105 wipe, run_region:131 read, lulc_summary.rds
  clobber) — folded into the plan before baseline
- Created branch `23-support-multiple-species-per-area-coexis` off main
- Scaffolded PWF baseline from issue #23 with approved phases
- **Phase 1 done** — species-keyed network layers (`streams_<sp><min_order>`) in 01 (write) + 02
  (read) + run_region:131; removed the `file.remove(aquatic_network.gpkg)` wipe; `append=file.exists
  + delete_layer=TRUE` per-layer writes; species-suffixed stamp sidecar. code-check: round 1 caught a
  stale-waterbodies-layer risk (fixed with a guarded `st_delete` on a 0-waterbody re-run), round 2
  clean (reviewer empirically verified co+ch coexistence + same-species replace in sf 1.1.1).
- **Phase 2 done** — 02: species filter on scenario selection (`run_scenarios$species == cfg$species`)
  + loud stop if empty; removed `file.remove(floodplain.gpkg)`; scenario writes now
  `append=file.exists + delete_layer=TRUE`. 03: removed `file.remove(floodplain_landcover.gpkg)`
  (the blocker) + made the transition write `append=file.exists` for idiom consistency; documented
  generic `lulc_summary.rds` as last-writer-wins. code-check round 1 clean; applied 2 reviewer-
  suggested hardening items.
- Next: Phase 3 (FP_SPECIES/FP_PRIMARY_SCENARIO overrides + guard in run_area; MORR ch scenario rows; README)
