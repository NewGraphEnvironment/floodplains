# Code review — round 1 (#83 staged diff)

Reviewed `git diff --cached`: `scripts/fp_raster.R` (new), `scripts/floodplain_lcc/03_lulc_classify.R`,
`scripts/fp_gpkg.R`, `scripts/run_area.R`, `scripts/run_region.R`.

Everything below was measured on this machine (terra 1.9.34, GDAL 3.x via homebrew, R 4.5.2), not
reasoned about. Commands are reproducible from `/tmp/fpr2/`.

## Findings

### 1. **[bug]** `scripts/fp_raster.R:69` — `if (!nrow(tg))` aborts when `metags()` returns `NULL`, and `NULL` is what a zero-tag raster returns

`terra::metags()` does **not** return a 0-row data.frame when a raster has no dataset metadata. It
returns `NULL`. Measured:

```
> r0 <- terra::rast(nrows=4, ncols=4, vals=1); terra::metags(r0)
NULL
> class(terra::metags(r0)); nrow(terra::metags(r0))
NULL
NULL
```

So line 69 evaluates `!nrow(NULL)` → `!NULL` → **`Error in !nrow(tg) : invalid argument type`**,
confirmed deterministically over four consecutive reads of a real file:

```
$ Rscript /tmp/fpr2/t7.R
1 is.null: TRUE  class: NULL  nrow: NULL
2 is.null: TRUE  class: NULL  nrow: NULL
3 is.null: TRUE  class: NULL  nrow: NULL
4 is.null: TRUE  class: NULL  nrow: NULL
--- now emulate the guard body verbatim ---
ERROR: invalid argument type
```

The file used was a GTiff written by `terra::writeRaster(..., gdal = "PROFILE=BASELINE")`, i.e. a
GeoTIFF with no dataset-level metadata at all. The `is.null` check has to come **before** `nrow`;
the existing `if ("domain" %in% names(tg))` fallback on line 70 is written defensively for exactly
this shape but is unreachable, because line 69 aborts first.

Why this matters rather than being theoretical: the function's whole premise is
`fp_rast_strip_tags()` → `writeRaster()` → *"terra re-adds `AREA_OR_POINT`, so a stripped raster
lands with exactly one tag"* (fp_raster.R:41-43, task_plan Phase 1). **That re-add was measured on
terra 1.9.34 only.** The machine the defect actually lives on is m4, terra **1.9.11**. If 1.9.11
does not re-add `AREA_OR_POINT` after `metags(r) <- NULL`, the very first `classified_2017.tif`
write on m4 aborts step 3 with `invalid argument type` — an error that names neither the raster nor
the guard and reads as a terra bug. That is the fixture-cannot-reach-the-failure-mode shape: the
premise is asserted on the terra where the defect is absent, and the guard is only ever exercised on
the terra where the defect is present.

Fix is one letter — `NROW(NULL)` is `0` and `NROW(data.frame())` is `0` (both measured):

```r
if (!NROW(tg)) return(character(0))
```

or explicitly `if (is.null(tg) || !nrow(tg)) return(character(0))`.

### 2. **[fragile]** `scripts/fp_raster.R:96-97` — the remedy in the error message cannot clear either cause of the failure it fires on, and the script it names does not exist

Two separate problems in one sentence.

**(a) The named script is absent.** `find . -name "*strip*"` returns nothing; `scripts/floodplain_lcc/`
holds no `raster_strip-tags.R`. task_plan Phase 4 creates it and Phase 4 is unchecked, so at this
commit the guard hands the operator a path that does not resolve. Fine within the PR provided Phase
4 lands before merge — flagged so it does not ship as-is.

**(b) The remedy is the operation that just failed.** `fp_rast_write` fires only when a
strip-then-write on *this machine* left tags outside the allowlist. `raster_strip-tags.R` is
specified (Phase 4) as *"terra strip + rewrite"* — the same two calls. So:

- Cause A, "the strip did not take on this terra" (the cause the message names): re-running a terra
  strip + rewrite on the same terra reproduces the identical tag set. The remedy loops.
- Cause B, a future terra/GDAL adding a second benign default tag beside `AREA_OR_POINT`: the
  rewrite reproduces that too, and every step-3 run on every area stops until someone edits
  `FP_RAST_TAGS_OK`. The message does not mention the allowlist, so nothing points at the only fix.

`code-check.md`: *"A guard whose error message must not recommend a remedy that walks back through
it"* and *"A guard that fires correctly and then points at the wrong fix"*. The repair script is for
**legacy files written on a machine whose terra is now fixed**; that is a different situation from
the one the guard detects, and the message conflates them. Worth naming the allowlist as the other
possible resolution, and saying that the repair script only helps from a machine where the strip
does work.

### 3. **[fragile]** `scripts/floodplain_lcc/02_floodplain_model.R:226` — the other `writeRaster` site was not routed, and the diff's own rationale covers it

```r
terra::writeRaster(valleys, out_raster, overwrite = TRUE, datatype = "FLT4S")
```

`floodplain_<scenario>.tif` is written by the same repo, from a raster built on an externally-fetched
DEM, and is a published product. The staged comment at `03_lulc_classify.R:151-155` argues the case
for pinning `transition.tif` *even though it measured clean*:

> "an unpinned write is one refactor upstream from carrying whatever its input carries"

That argument applies verbatim to 02, and 02 is the one write site left unpinned. This is the
"a fix lands in one of two callers that share a harness" shape, with the asymmetry now written into
the code as if it were principled.

**Empirically there is no data defect today** — I swept all 184 `.tif` under `data/` with the same
default-domain/allowlist logic:

```
--- files with stray tags ---
 data/kotl/rasters/bt_ff04/classified_2017..2023.tif   30 each
 data/necr/rasters/ch_ff04/classified_2017..2023.tif   30 each
--- summary ---
  classified            74 clean / 14 dirty
  floodplain_bt_ff02/04/06, ch_*, co_*   all clean (72 files)
  transition            24 clean
```

So this is a consistency/pin gap, not a live bug. Either route 02 through `fp_rast_write` or say in
02 why the raster it writes is exempt — the current state reads as an oversight.

### 4. **[fragile]** `scripts/fp_raster.R:68` — `terra::rast(path)` reads PAM-merged metadata, so a `.aux.xml` sidecar can make the guard report stray tags on a clean file

GDAL merges a `.aux.xml`'s dataset-level `<Metadata>` block into the default metadata domain, and
terra surfaces it through `metags()`. Measured on a clean single-tag GTiff with a hand-written
sidecar:

```
              name value domain
1    AREA_OR_POINT  Area
2  STATISTICS_MEAN   1.0
3 TIFFTAG_SOFTWARE  QGIS
stray: STATISTICS_MEAN,TIFFTAG_SOFTWARE
```

**On the `fp_rast_write` path this is closed**, and I checked rather than assumed:
`terra::writeRaster(overwrite = TRUE)` deletes the pre-existing sidecar before the read, so a stale
sidecar cannot survive into the post-write check (measured: `aux before rewrite: TRUE` →
`aux after rewrite: FALSE`, guard result `ok`).

It is **not** closed for `fp_rast_stray_tags()` used standalone, which is what task_plan's Validation
line prescribes — *"Full sweep: every `.tif` under `data/` reports 0 stray tags across all 23 areas"*
— and what the Phase 4 repair script's before/after check will do. There, opening a classified
raster in QGIS once is enough to make the sweep report a file dirty that is not, with the same
message blaming terra's metags strip. `data/` already carries 88 `.aux.xml` sidecars beside these
rasters, so the mechanism is live in the directory the sweep runs over. Worth either excluding the
sidecar at read time (`GDAL_PAM_ENABLED=NO` around the read — the repo already knows this knob from
#64) or having the sweep report sidecar-sourced tags distinctly from in-file ones.

## Answers to the specific questions

**Q1 — `tg$domain` filter shapes.** Correct for every shape *except* `NULL`, which is finding 1. For
the shapes that do reach line 70-71: `dom %in% c("", NA)` handles `NA` correctly (`match()` matches
`NA`, verified). A stray tag in a **non-default domain cannot reach a published COG through this
write path** — measured, `metags(r, domain = "MYDOM") <- c(secret = "/tmp/Rtmpleak")` then
`writeRaster` produces a file whose only tag is `AREA_OR_POINT`; terra does not write user domains to
GTiff. And all 30 real gdalcubes tags on `data/necr/.../classified_2020.tif` are in the default
domain (`crs#*`, `data#*`, `NC_GLOBAL#*`, `NETCDF_DIM_*`, `time#*`, `x#*`, `y#*`), so the filter sees
every one. The `IMAGE_STRUCTURE` rationale in the docstring is over-stated but harmless — terra's
`metags()` never surfaces `COMPRESSION`/`INTERLEAVE` at all, so there is nothing to exclude.

**Q2 — writeRaster succeeding without producing `path`.** No silent divergence found. A filename with
no recognised extension **errors** rather than appending one (measured: `try-error`, neither `noext`
nor `noext.tif` created), and both call sites pass explicit `.tif` paths. The `file.exists()` guard
in `fp_rast_stray_tags` covers the residual.

**Q3 — Pass 2 reuse of `classified_all`.** Safe, and for two independent reasons. Re-confirmed no
aliasing on 1.9.34 (`caller tags after strip: 2, local: 0`). And even if a future terra did alias,
Pass 2 only does `terra::crop`/`terra::mask`/`terra::as.polygons`, none of which read dataset
metadata — the outputs are values and geometry.

**Q4 — `...` passthrough.** No hazard found. Both call sites pass only `overwrite` and `datatype`;
`writeRaster`'s second positional is `filename`, so the positional call is right.

**Q5 — `FP_RAST_TAGS_OK`.** Correct as an allowlist against today's population: across all 184 tifs
under `data/`, `AREA_OR_POINT` is the only default-domain tag on every clean file, and the 14 dirty
files carry it plus the 30. It does **not** refuse anything legitimate that exists today. Its
fragility is the future-tag case in finding 2(b), which is a message problem rather than an allowlist
problem.

**Q6 — missed write sites.** `02_floodplain_model.R:226` (finding 3). The six `writeRaster` calls in
`provenance-check.R` are fixtures that must set tags deliberately and are correctly left alone.
`fire_tag.R`, `gpkg_backfill-wsg.R` and `attribute_tag.R` are standalone CLIs that write no rasters,
so they correctly source only `fp_gpkg.R`. Only `run_area.R` sources `03_lulc_classify.R`, so there
is no path that reaches `fp_rast_write` without `fp_raster.R` sourced.

## Verified, not a finding

Recorded because each was a plausible break that I checked rather than assumed.

- **The strip does not move `classified_content_sha256`.** Round-tripped a real dirty file
  (`data/necr/rasters/ch_ff04/classified_2020.tif`, 31 tags) through `fp_rast_write`:
  `sha256:23b9a66c…` before **and** after, CRS `32610` both sides, `cats()` identical, band name,
  `NAflag` and `time()` unchanged, `stray after:` empty. So re-running step 3 on an existing area
  will not invalidate any recorded landcover digest.
- **The RAT survives the strip.** Category names and the colour table are band-level PAM, untouched by
  `metags(r) <- NULL`; confirmed both on a synthetic categorical raster and on the necr round-trip.
  The one colour-table row that moves (index 255, `alpha = 0` on both sides) is a **pre-existing**
  terra rewrite artefact — it moves identically on a rewrite with no strip at all (measured), so it
  is not attributable to this change.
- **`fp_raster_content_sha256`'s extra file open.** Routing through `fp_rast_write` inserts one more
  `terra::rast(path)` before the digest. This does not reintroduce #64's PAM storage-mode divergence:
  the read computes no statistics, `fp_norm_block` collapses NaN/NA regardless, and the digest was
  byte-identical across the round-trip above.
- **`utils::packageVersion("terra")` in the error path** — `utils` is always attached under Rscript.
- **Sourcing `fp_raster.R` in `run_region.R`** before terra is loaded is fine; the file only defines
  functions and every terra call is namespaced.
