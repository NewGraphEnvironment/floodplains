# Code-check round 2 (#126): branch 92502338...HEAD

## Findings

- **[severity: fragile]** scripts/floodplain_lcc/fp_provenance.R:315-361 (`fp_prov_restamp`), called from
  `fp_prov_reconcile_late` (:437) and raster_strip-tags.R. **The re-stamp disables
  `fp_composition_build()`'s only "step 2 re-ran after step 3" guard.**
  `scripts/floodplain_lcc/fp_composition.R:187-191` refuses when
  `floodplain[<scen>].run.datetime_utc > landcover[<scen>].run.datetime_utc`. It reads that
  field as "when step 3 ran, and so which floodplain its rasters were masked to". The landcover
  record pins no floodplain digest (`03` records only `floodplain_layer = scenario_id`), so this
  ordering is the guard's only evidence. The re-stamp moves the same field forward to the repair
  time, so any repair made after a step-2 re-run hides the stale state:
  step 3 at T3, step 2 re-run at T2 > T3, strip/re-stamp at TR > T2 gives TR > T2, and
  `composition_build.R` then builds from rasters masked to the OLD floodplain against the NEW
  polygon. Reproduced in a scratch copy (`fp_prov_restamp` on a fixture with floodplain run
  20:00Z and landcover run 19:00Z, re-stamped to 22:00Z): the guard predicate goes from TRUE
  (refuses) to FALSE (builds). The raster_strip-tags.R header (line 54-55) checked this guard in
  the other direction only ("moving floodplain[] past landcover[] would trip the composition
  guard"). One field now carries two meanings, "step 3 ran" and "bytes last written", and one
  consumer still reads the first.
  - **Not live:** necr floodplain runs are 2026-09-03 and kotl's are 2026-09-03, both before
    their original landcover stamps (2026-09-05T19:14Z / 19:46Z).
  - **Remedy (either):** have the composition guard compare against the original step-3 time,
    `run$repairs[[1]]$previous_datetime_utc %||% run$datetime_utc`. Or have
    `fp_prov_restamp`/`fp_prov_reconcile_late` refuse when `floodplain[key].run.datetime_utc` is
    later than the stamp being replaced. The first keeps a legitimate repair possible; the second
    is a one-line refusal.

- **[severity: fragile, minor]** scripts/floodplain_lcc/raster_strip-tags.R:628. This is the
  round-1 fix 2 axis, one call over. `keys <- names(fp_prov_read(cfg)[["landcover"]])` sits
  outside the per-key `tryCatch`, so an unreadable provenance.json raises past both summaries
  after the sweep has already renamed repaired rasters into place:
  - the `FAILED (left untouched): …` list (line 659) is never printed;
  - the `NOT RE-STAMPED` list is never printed.

  The exit status is still non-zero (an R error), so this is a lost report, not a silent pass.
  Wrapping the read in the same `tryCatch` and recording `restamp_failed <- "provenance"` would
  keep the end-of-run summary.

## Checked, no defect found

- **Fix 1 (toolchain).** The repair writes through `fp_rast_write()`, which is
  `terra::writeRaster` (fp_raster.R:132-133), so `terra` plus `terra::gdal()` is the right
  writer. `fp_rast_stray_tags` reads through sf's GDAL, but it only reads. The backfill branch
  records no toolchain, as designed. No other new site records a toolchain.
- **Fix 2 (per-key tryCatch).** Every exit from `fp_prov_reconcile_late` returns one of the four
  statuses, and an error becomes `refused`, which feeds `restamp_failed` and the `quit(status =
  1L)`. No refusal path exits 0. The restore-and-stop inside `fp_prov_restamp` also surfaces as
  `refused`.
- **The mirror of stac's `fp_prov_rasters_current`:** same raster set (classified + transition.tif),
  same floor arithmetic, same stamp format.
- **`inputs`/`run` and `outputs`/`run` key-overlap checks:** unaffected by the new `run.repairs`
  key.
- **Digest lookups:** they return NA on an absent year or field, and NA refuses. An unreadable
  file gives NA from `fp_raster_content_sha256`, which refuses before the stray-tag probe.
