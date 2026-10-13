# Task: Published floodplains do not reproduce on today's toolchain, and provenance names the wrong GDAL (#117)

## Context

On 2026-10-09, a replay of step 2 for MORR `co_ff04` came out 0.42% smaller than the published record. The DEM grid had moved about 1.3 m. The cause turned out to be PROJ's datum operation: PROJ 9.8.1, linked by terra, routes NAD83(CSRS)→NAD83 through WGS 84. It is not the GDAL version, as the issue first said. flooded#67 fixed it in **flooded 0.7.0** (merged 2026-10-13), which uses a fixed 30 m grid aligned to multiples of 30 and a pinned projection-only datum step.

Two things remain in this repo:
1. **Adopt flooded 0.7.0.** 0.6.6 is installed. Every step-2 output moves once: `dem_res_m` 30.43→30, `dem_ncell` drops, `dem_content_sha256` changes, and MORR moves +0.17%.
2. **Record the toolchain that actually warped the DEM.** `fp_toolchain()` (`scripts/floodplain_lcc/fp_provenance.R:992`) reads `sf::sf_extSoftVersion()`, which reports GDAL 3.8.5 and PROJ 9.5.1. terra links GDAL 3.13.0 and PROJ 9.8.1, measured with `terra::gdal(lib = "all")`.

The issue's "pin and re-run deliberately, or accept the move" fork is settled by #125 (2026-10-13). We pin through flooded 0.7.0. Every area re-runs as whole-network under #125, and the species items retire rather than re-run (stac_floodplains_bc#76). So this issue does not re-run published areas. It re-baselines only the `neexdzii` parity fixture, so #125's runs start from a known contract on the new grid.

## Phase 1: Record terra's GDAL and PROJ in provenance
- [x] `fp_toolchain()` adds `gdal_terra` and `proj_terra` from `terra::gdal(lib = "all")`. This matches the `gdal_terra` name the repair record already uses (`fp_provenance.R:461`). sf's `gdal`/`geos`/`proj` stay: sf still writes every vector. The comment above it says which library warps the DEM.
- [x] `provenance-check.R`: a separate `KEYS_TOOLCHAIN_TERRA`, required by step time (`TOOLCHAIN_TERRA_SINCE`, repair-aware `prov_step_time()`): missing or NA after the cutover is a FAIL; older entries are INFO in §7 only. The producer check is `setequal` over both sets. (Revised per plan review B1/G3/G4: the original text, INFO for any record missing the keys, failed toward pass.)
- [x] Offline premise arm: `fp_toolchain()$gdal_terra == terra::gdal()` and `$proj_terra == terra::gdal(lib = "all")$proj`. Must-fail arm: a copy of `fp_toolchain` sourcing the terra fields from sf fails it. This machine's two GDALs differ, so the arm can tell the two apart.
- [x] Run `provenance-check.R` offline: green, and red with the defect restored.

## Phase 2: Adopt flooded 0.7.0
- [x] Install flooded 0.7.0 (`pak::pak("NewGraphEnvironment/flooded")`) and confirm `packageVersion("flooded") == "0.7.0"`.
- [x] `02_floodplain_model.R`: stop on flooded < 0.7.0 for every area, not just whole-network, beside the existing 0.6.4 gate (line 46). The DEM digest in `inputs` is a sound input only on the pinned grid.
- [x] Replace the "OPEN" comment at `02_floodplain_model.R:151-155`. It is resolved: the move was PROJ's datum step on one machine across an upgrade, now pinned by flooded#67, which measured reproduction across GDAL 3.8.5↔3.13.0 and PROJ 9.5.1↔9.8.1. Fix the "GDAL picks the grid" wording around it.
- [x] Grep for other `fl_dem_aoi()` callers (`attribute_tag.R:68`, probe lines 178/236). They inherit the pin and need no change. Confirm none passes `res` or `pipeline`.

## Phase 3: Re-baseline the neexdzii parity fixture (live)
(Revised per plan review O1/O2/A3: steps 2,3 for the determinism run; gate on per-entry stamps.)
- [x] Snapshot `data/neexdzii/provenance.json` before any run.
- [x] Run 1: `run_area.R neexdzii` (1,2,3 — launched before the review). Control: the network entry's `outputs_hash` byte-identical to the snapshot, so a network change is not mixed in. Gate: zero in-band errors and every floodplain/landcover/composition `run.datetime_utc` after the launch marker.
- [x] Field-by-field `inputs`/`outputs` diff per entry, before vs after: only the expected fields moved.
- [x] Run 2: `run_area.R neexdzii 2,3`. Every floodplain and landcover entry's `inputs_hash`/`outputs_hash` (incl. `dem_content_sha256`) byte-identical to run 1; run stamps moved.
- [x] `dem_res_m == 30`, raster origin a multiple of 30, and non-NA `gdal_terra`/`proj_terra` on every new entry.
- [x] `provenance-check.R neexdzii` and `composition-check.R neexdzii` pass.
- [x] Record the new contract as a fresh contract in `scripts/run_area.R:22`, the CLAUDE.md `neexdzii` bullet and `README.Rmd`; re-render `README.md` + `index.html`, then run `readme_determinism-check.sh` and `readme_content-check.py`.
- [x] Log: `scripts/floodplain_lcc/logs/20261013_flooded070_rebaseline_neexdzii.md`.

## Phase 3b: Plan-review fixes
- [x] `attribute_tag.R` refuses a pre-0.7.0 delineation by name (G2): tested, refuses `morr`, passes new `neexdzii`.
- [x] In-suite must-fail for a terra pair sourced from sf (G5), and for a post-cutover NA pair (G3); mutant of the NA arm goes red.
- [x] Stale sites: `config/neexdzii/area.yml` contract comment, `fp_provenance.R` repair comment, `packages.R` floor comment, probe header (G6); `fp_toolchain` comment notes sf's PROJ picks the DEM read window and gdalcubes warps step 3 (A1, A2).
- [x] File on flooded: `fl_dem_aoi()`'s read-window `st_transform` is unpinned (A1).
- [x] Note on #125: DUNC's cached summary is on the pre-0.7.0 grid, so a region run would skip it (G1); mark CLAUDE.md DUNC figures pre-0.7.0.

## Phase 4: Correct the record
- [x] CLAUDE.md #110 bullet: "The cause is the GDAL version, isolated" → PROJ's datum operation. `fp_toolchain()` now records terra's GDAL/PROJ. Published records predate the pin.
- [x] `research/whole_fwa_floodplain.md`: correct the dated "Isolated: the GDAL version" paragraph to PROJ (with the correction date). Note that the probe's figures are on the pre-0.7.0 grid and were not re-run. Update the header's Verified line.
- [x] File a soul issue: the convention "`terra::project()` given only a CRS lets GDAL choose the grid, and GDAL versions choose differently" names the wrong mechanism (PROJ's operation, not the GDAL version). It goes through an issue because soul conventions are not edited in place.
- [ ] Edit the #117 body: decision recorded (pinned via flooded 0.7.0; published areas re-run under #125, species items retired), plus the new neexdzii contract.

## Validation
- [ ] `provenance-check.R` (offline + neexdzii live), `composition-check.R neexdzii`, README checks pass
- [ ] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion


## Critical files
- `scripts/floodplain_lcc/fp_provenance.R` (`fp_toolchain`, ~line 992)
- `scripts/floodplain_lcc/provenance-check.R` (`KEYS_TOOLCHAIN` line 98, `viol_split` ~line 170, check at ~1874)
- `scripts/floodplain_lcc/02_floodplain_model.R` (floor at 46, DEM block 113–160)
- `scripts/run_area.R:22`, `README.Rmd:296`, `CLAUDE.md`, `research/whole_fwa_floodplain.md`

## Not in scope
- Re-running published areas (they go to #125 as whole-network runs).
- DEM caching (#122, next).
- Re-running the whole-FWA probe.
