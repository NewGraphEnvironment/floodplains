# Progress — Published floodplains do not reproduce on today's toolchain, and provenance names the wrong GDAL (#117)

## Session 2026-10-13

- Plan-mode exploration — phases approved by user
- Created branch `117-published-floodplains-do-not-reproduce-o` off main
- Scaffolded PWF baseline from issue #117 with approved phases
- Next: start Phase 1

- Phase 1 done. `fp_toolchain()` records `gdal_terra`/`proj_terra` from `terra::gdal(lib = "all")`. `provenance-check.R` requires them by step time (cutover `2026-10-13T22:00:00Z`, repair-aware via `prov_step_time()`), reports older entries as INFO in §7, and checks the terra pair against terra itself. Offline: PASS. Two mutants in scratch copies, each red: terra fields sourced from sf (1 FAIL), date arm disabled (2 FAIL).
- Installed flooded 0.7.0 (github@698042e).
- Phase 2 done. 02 refuses flooded < 0.7.0 for every area; the OPEN comment is replaced with the #117 outcome. flooded#67 measured cross-GDAL agreement to 0.12 mm per cell, which is not byte identity, so the comment says the digest can still differ between GDAL builds (the issue body's "reproduces" was stronger than the measurement).
- Other `fl_dem_aoi()` callers: `attribute_tag.R`, the probe, and two `landcover_accuracy/` scripts (airphoto footprint sizing, no `target_crs`). None passes `res`/`pipeline`; all inherit the new grid. The accuracy scripts' `imagery.csv` may shift marginally on its next regeneration.
- Phase 4 (part): CLAUDE.md's #110 bullet and `research/whole_fwa_floodplain.md` now attribute the grid move to PROJ's datum operation, note that the probe's figures are on the pre-0.7.0 grid, and point at #125 for re-runs. Filed soul#402 for the spatial convention that names GDAL.
- Plan review (`review-plan.md`) received mid-run; dispositions recorded there. Phase 1 and 3 text revised to the landed / reviewed design.
- Run 1 (1,2,3; launched 22:10:59Z, done by 22:16:32Z): 0 in-band errors, every entry stamped after launch, toolchain carries gdal_terra 3.13.0 / proj_terra 9.8.1. Network `outputs_hash` byte-identical to the snapshot (673.48 km, 1,915 segments); its `inputs_hash` moved only through package stamps (fresh 0.33.0->0.39.0, link SHA unresolved as checkout != installed). Floodplain moved only in dem_* and flooded stamp; landcover only in classified digests and the transition. New measurements: co_ff04 142.040 km2 (157,822 cells at 30 m, origin multiple of 30), tree loss 773.43 ha over 788 of 2,018 patches.
- Review fixes landed (Phase 3b): attribute_tag refusal, G3/G5 in-suite arms, stale comments.
