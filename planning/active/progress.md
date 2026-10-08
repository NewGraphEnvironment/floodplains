# Progress — Wayback chips (#115)

## Session 2026-10-08

- Plan-mode exploration — phases approved by user ("go all phases to pr")
- Created branch `115-wayback-chips-sharp-imagery-at-the-captu` off main
- Scaffolded PWF baseline from issue #115 with approved phases
- Next: start Phase 1 (probes)
- Phase 1 committed (probes). Plan review (Plan agent) returned 4 blockers + gaps; dispositions in `review-plan.md`. B2 (`esri` vs new form value) went to the user, who chose `esri_dated`.
- Phase 2: `fp_acc_wayback_pick` + helpers in `fp_accuracy.R`; `wayback_index-capture.R` run on NECR: 197 releases x layers 4-6, 32.2 min cold, 1.3 min from cache, `wayback.csv` byte-identical across the two runs. 90,538 (point, release) captures, 52 distinct capture dates.
  - 2017: 6 same year, 237 +/-1, 106 +/-2, 131 further. 2023: 148 / 115 / 102 / 115. No point is without a capture.
  - Point 1 (`17_00009`): 2017 -> capture 2017-06-11, 0.31 m (release 16245, the latest release serving it; 15045 serves the same capture).
- `/code-check` round 1 over the working tree: 1 bug (metadata cache keyed without the bbox -> fixed, existing cache re-keyed) + 5 fragile (fixed in the build script and `cells_outline.qml`).
- Phase 3: `wayback_build-chips.R`. Voronoi-clipped lossless nodata chips, guarded manifest, own-chip read-back. NECR cold build: 21.2 min, 956 built / 4 failed (1 transient warp error, 3 "flat" = open lake -> flat guard removed). Re-run: 960 built, 711 MB, every point reads its own chip.
- `/code-check` round 2: 2 fragile (manifest written before the guards; `wb_ok` could not tell an earlier sample's build) -> fixed. Round 3 (asked for the mechanism + enumeration of every reused artifact): `fp_acc_link_tree`'s inode test was `identical(NULL, NULL)` (pre-existing; its own check arm was vacuous too), plus `cells.gpkg` / `built.csv` without location, plus WMS xml written only-if-absent -> all fixed, with a must-fail relink arm.
