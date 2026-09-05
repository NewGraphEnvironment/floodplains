# Task: classified_*.tif carry 30 stray gdalcubes/NetCDF tags on 2 of 4 #79 areas, two of them wrong (#83)

Two of the four areas re-run for #79 write their `classified_<yyyy>.tif` with 30 stray
gdalcubes / NetCDF metadata tags attached. The other two do not. Two of the tags contradict
the file they are attached to (`data#type = float64`, `data#_FillValue = nan` on a `uint8`,
nodata-255 raster) and one leaks a `/tmp/Rtmp…` path from the producing session into a file
that gets published. `stac_floodplains_bc` COGs these with `rasterio.shutil.copy`
(a `CreateCopy`), so they reach the published assets.

The pixels are correct. This is a **container** defect, which is why nothing here saw it:
`fp_raster_content_sha256()` (#64) is deliberately container-invariant.

**Cause, already isolated by the #79 run itself** — that run was split across two machines
with terra left as the only unlevelled package (`logs/20260905_lulc-annual_split-run.md`).
The tags split exactly on that line, read from each area's own `provenance.json`:
bulk/lnth (m1, terra 1.9.34) clean; necr/kotl (m4, terra **1.9.11**) 30 tags on all 7 years.
`transition.tif` is clean everywhere because `dft_rast_transition()` builds a **new** raster,
while `dft_rast_classify()` only sets cats/coltab in place and the source metadata survives.

**Blast radius, swept:** 116 `.tif` across 23 areas, **14 dirty** — all `classified_*` in
`necr` and `kotl`. No other area, no `transition.tif`.

**The fix is a pin, not a machine upgrade.** This is #64 with a new cause, and #65 already
answered the class by pinning `datatype = "FLT4S"` in 02. `scripts/fp_gpkg.R`'s closing line
— "GeoTIFF output (terra::writeRaster) was measured deterministic already and needs nothing"
— is the stale claim this issue falsifies.

## Phase 1: Pin the mechanism offline, before changing anything

- [x] Confirm `metags(r) <- NULL` clears every tag including `AREA_OR_POINT`, and that a
      subsequent `writeRaster()` still produces `AREA_OR_POINT=Area` — i.e. GDAL re-adds it
      and a cleared raster matches bulk/lnth exactly. If not, restore it explicitly rather
      than shipping a container that differs from the clean areas in the other direction.
- [x] Confirm terra 1.9.34 **writes** explicitly-set metags to GTiff, so the Phase 3 guard is
      reachable on this machine. Assert inline rather than inheriting §5c's premise.
- [x] Confirm `metags(x) <- NULL` on a list element does not alias `classified_all[[yr]]`
      (terra wraps an external pointer). Strip into a local and write the local if it does.
- [x] On a **copy** of a dirty file, run `gdal_edit.py -unsetmd -mo AREA_OR_POINT=Area` and
      diff before/after: `gdalinfo` Band 1 section (type, block, ColorInterp, Description,
      NoData, every category) and `fp_raster_content_sha256()`. Both identical; tags 31 -> 1.

## Phase 2: Pin the write path

- [x] New `scripts/fp_raster.R`, sibling to `scripts/fp_gpkg.R`: `fp_rast_strip_tags(r)` and
      `fp_rast_stray_tags(path)` (returns **names**, so an error can name the offender).
- [x] Source it in `scripts/run_area.R` and `scripts/run_region.R` beside `fp_gpkg.R`.
- [x] `03_lulc_classify.R` — strip before both `writeRaster()` calls (classified per year, and
      `transition.tif` defensively: measured clean today, pinned anyway, as #65 pinned
      `datatype` where it measured byte-identical).
- [x] Post-write verify with `stop()` on the first classified year, naming the repair script
      and the running terra version; re-verify each subsequent year.
- [x] Correct `scripts/fp_gpkg.R`'s closing "GeoTIFF … needs nothing" line.

## Phase 3: Guard it offline

- [x] New section in `provenance-check.R` on the §5c pattern: premise asserted inline;
      strip + write => no stray tags; **must-fail** arm (same write without the strip reports
      the names); **negative control** (`AREA_OR_POINT` and `IMAGE_STRUCTURE` not flagged).
- [x] Assert `fp_rast_stray_tags()` against the real tag names recorded in findings.md.
- [x] Reconcile the per-year `classified_content_sha256` against their rasters in §7, and check
      every on-disk raster's container there too — the one recorded digest never re-derived.

## Phase 4: Reconcile the 14 written files

- [x] `scripts/floodplain_lcc/raster_strip-tags.R <area>` — idempotent, `DRY=1` returns before
      the first write, joining the `gpkg_backfill-wsg.R` / `gpkg_prune-legacy.R` family.
      **Route changed in Phase 1: terra strip + rewrite, NOT `gdal_edit.py -unsetmd`** — every
      GDAL in-place variant destroys the band's category names (the RAT stac publishes) and
      grows the file 54 KB per run. See findings.md for the four-route measurement.
      Per file: content sha before, rewrite, re-read after, `stop()` if it moved — and reject
      `NA` on either side, since two `NA`s compare equal and would report a false match.
      Assert the band section differs in **at most** the one known palette line.
- [x] Run it on `necr` and `kotl` (14 files).
- [x] Verify every `classified_content_sha256` in `data/<area>/provenance.json` still matches
      — an **independent** reference written before this repair existed.
- [x] Commit the evidence log — `data/` is gitignored, so the repair leaves no other trace.

## Phase 5: Record and hand off

- [x] CLAUDE.md: extend the #64/#65 block — discriminator, the isolation the split-run gave
      for free, the `transition.tif`-is-clean asymmetry and why, the pin.
- [x] File an informational issue in `drift` (our own repo): untiled `dft_stac_fetch()`
      returns nc-backed rasters carrying gdalcubes attributes — filed as drift#63.
- [x] File the band-level `STATISTICS_*=-9999` finding separately rather than widening #83 — #84.
- [ ] PR body names stac_floodplains_bc#59 — necr/kotl need a COG rebuild + republish.

## Validation

- [x] `provenance-check.R` green, must-fail arm exercised with the strip removed and the
      output **grepped for the expected message**
- [x] `gpkg_determinism-check.R` still green
- [x] Full sweep: every `.tif` under `data/` reports 0 stray tags across all 23 areas
- [x] `raster_strip-tags.R necr` re-run is a no-op; `DRY=1` leaves mtimes unchanged
- [x] `run_area.R neexdzii 3`: transition sha, 2032 patches, every classified sha unchanged
- [ ] `/code-check` clean on each commit; PWF checkboxes land with the code
- [ ] `/planning-archive` on completion
