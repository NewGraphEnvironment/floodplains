# Progress — Published floodplains do not reproduce on today's toolchain, and provenance names the wrong GDAL (#117)

## Session 2026-10-13

- Plan-mode exploration — phases approved by user
- Created branch `117-published-floodplains-do-not-reproduce-o` off main
- Scaffolded PWF baseline from issue #117 with approved phases
- Next: start Phase 1

- Phase 1 done. `fp_toolchain()` records `gdal_terra`/`proj_terra` from `terra::gdal(lib = "all")`. `provenance-check.R` requires them by step time (cutover `2026-10-13T22:00:00Z`, repair-aware via `prov_step_time()`), reports older entries as INFO in §7, and checks the terra pair against terra itself. Offline: PASS. Two mutants in scratch copies, each red: terra fields sourced from sf (1 FAIL), date arm disabled (2 FAIL).
- Installed flooded 0.7.0 (github@698042e).
