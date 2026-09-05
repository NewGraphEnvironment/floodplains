# Findings — classified_*.tif carry 30 stray gdalcubes/NetCDF tags (#83)

## The discriminator, measured

Read from each area's own `data/<area>/provenance.json` — the `run.toolchain.terra` field #64
added so exactly this class would be diagnosable — against a `gdalinfo -json` sweep of the
rasters. Measured 2026-09-05 on m1.

| area | machine | terra | drift | stray tags on `classified_*.tif` | `transition.tif` |
|---|---|---|---|---:|---|
| `bulk` | m1 | 1.9.34 | 0.13.0 | 0 | clean |
| `lnth` | m1 | 1.9.34 | 0.13.0 | 0 | clean |
| `necr` | m4 | **1.9.11** | 0.13.0 | **30 x 7 years** | clean |
| `kotl` | m4 | **1.9.11** | 0.13.0 | **30 x 7 years** | clean |

**The isolation was already paid for.** `scripts/floodplain_lcc/logs/20260905_lulc-annual_split-run.md` records that
m4 was deliberately levelled to m1 on `drift` (0.8.0 -> 0.13.0), `sf` (1.1.2) and `gdalcubes`
(0.7.4), and that terra could not be matched and was left at 1.9.11 — "which made terra the
*only* remaining difference and the control a test of exactly one variable". So this is a
controlled result, not the unisolated attribution CLAUDE.md warns against repeating (that
warning is about the `storage.mode`/NaN symptom, whose real trigger was the PAM sidecar).

Corroborated independently: CLAUDE.md's #64 measurement of TIFF tag **42112 (`GDAL_METADATA`)**
at 382 bytes under terra 1.9.34 and 5,396 under 1.9.11, "the older terra carrying the gdalcubes
NetCDF attributes into the header".

What has **not** been done here, and is not claimed: terra 1.9.11 has not been run on m1, so
the read-side/write-side split inside terra is not bisected. The fix is designed not to depend
on it — see "Why the fix is a pin" below.

## Why `transition.tif` is clean and `classified_*.tif` is not

`dft_rast_classify()` mutates in place — `terra::set.cats()` then `terra::coltab()<-` — and
returns the same nc-backed raster, so the NetCDF attributes survive.

**"builds a new raster, so it drops them" is NOT the mechanism** — that was the first answer
written here and it is wrong. `crop()`, `mask()` and `deepcopy()` all build new rasters and
**preserve** metags (measured: 31 in, 31 out), and `mask()` is precisely how
`drift/R/dft_stac_fetch.R:230` delivers the tags in the first place. The discriminator is which
*kind* of op: geometry ops carry metadata forward, value-rewriting ops (`classify`, `app`,
`ifel`, arithmetic, `patches`) drop it. `dft_rast_transition()` is the second kind, which is why
`transition.tif` is clean on both terras and `classified_*.tif` is not.

That sentence is the answer to the issue's headline Question, so it is stated from the
measurement rather than from the plausible-sounding version.

Origin of the metadata: `drift/R/dft_stac_fetch.R:230` —
`terra::mask(terra::rast(cache_file), terra::vect(aoi_target))`, where `cache_file` is the
gdalcubes `write_ncdf()` output under `~/Library/Caches/drift/v2/io-lulc/<year>_<key>.nc`.

## Blast radius — swept, not assumed

Every `.tif` under `data/` — **184 files**: 88 `classified_*`, 72 `floodplain_*` (step 2's
output) and 24 `transition.tif`, across 23 areas. **14 dirty**, all `classified_*` in `necr`
(`ch_ff04`) and `kotl` (`bt_ff04`), 7 years each. No other area, no `transition.tif`, no
`floodplain_*`.

The first count written here was **116**, because the glob was `data/*/rasters/*/*.tif` and step
2 writes `floodplain_<scenario>.tif` one directory up. Same dirty set either way, but the clean
population was understated by 68 files and the sweep did not cover the third write site at all —
"an inventory is only complete relative to a boundary", on a boundary chosen by a glob.

## The 30 stray tag names

Verbatim from `data/necr/rasters/ch_ff04/classified_2017.tif`. `AREA_OR_POINT` is the 31st tag
and is **legitimate** — bulk and lnth carry it too, so it is the negative control, not a target.

```
NC_GLOBAL#Conventions            NETCDF_DIM_EXTRA          time#axis
NC_GLOBAL#gdalcubes_datetime_dt  NETCDF_DIM_time_DEF       time#calendar
NC_GLOBAL#gdalcubes_datetime_t0  NETCDF_DIM_time_VALUES    time#long_name
NC_GLOBAL#gdalcubes_datetime_t1  crs#GeoTransform          time#standard_name
NC_GLOBAL#gdalcubes_datetime_type crs#spatial_ref          time#units
NC_GLOBAL#process_graph          data#_FillValue           x#axis   x#long_name
NC_GLOBAL#source                 data#add_offset           x#standard_name   x#units
                                 data#grid_mapping         y#axis   y#long_name
                                 data#scale_factor         y#standard_name   y#units
                                 data#type
```

Prefix set for the guard: `NC_GLOBAL#`, `NETCDF_`, `crs#`, `data#`, `time#`, `x#`, `y#`.

The two that contradict the raster: `data#type = float64` and `data#_FillValue = nan`, on a
file whose header reads `Type=Byte, NoData Value=255`. `crs#spatial_ref` happens to be correct
(32610 necr / 32611 kotl) — correct and still not ours to publish.

## Why the fix is a pin, not a machine upgrade

Levelling m4's terra removes the symptom and leaves nothing behind. #65 already answered this
class one field over: `02` pins `datatype = "FLT4S"` so "a terra version choosing a different
on-disk type" cannot move the container, and it was kept even though it measured byte-identical.
`scripts/fp_gpkg.R` closes with *"GeoTIFF output (terra::writeRaster) was measured deterministic
already and needs nothing"* — falsified by this issue and corrected in Phase 2.

## Phase 1 — mechanism, measured (2026-09-05, m1, terra 1.9.34 / GDAL 3.13.0)

### The strip works, and reproduces the clean areas exactly

`metags(r) <- NULL` clears all 31 tags in memory, and a subsequent `writeRaster()` produces a
file carrying **`AREA_OR_POINT` alone** — byte-for-byte the tag set `bulk` and `lnth` already
have. So a full clear is right; `AREA_OR_POINT` does not need restoring by hand.

It does **not alias**: `x <- lst[[1]]; metags(x) <- NULL` leaves `lst[[1]]` at 31 tags, so
stripping cannot disturb the `classified_all` list Pass 2 crops and masks. Strip into a local
anyway, because the read is what makes that safe and a future terra could change it.

### terra 1.9.34 propagates faithfully on WRITE — the difference is on the READ side

Reading a dirty `necr` raster on 1.9.34 and writing it straight through **keeps all 30 tags**.
So 1.9.34 does not "drop" NetCDF metadata at write time; it never picks it up from a `.nc` in
the first place, where 1.9.11 does. That matters twice: the strip is genuinely load-bearing on
any terra whose read populates them, and the Phase 3 guard is **reachable on this machine**,
since explicitly-set metags do reach the written file (`§5c`'s premise, re-asserted rather than
inherited).

### The repair route: four candidates, three rejected on measurement

| route | stray tags | band categories | palette 255 | content sha | size per run | idempotent |
|---|---|---|---|---|---|---|
| `gdal_edit.py -unsetmd` | clean | ~~DESTROYED~~ **preserved** (see below) | — | same | **+54 KB** | no |
| GDAL dataset-only `SetMetadata` | clean | ~~DESTROYED~~ **preserved** | — | same | **+54 KB** | no |
| ... + `SetCategoryNames()` restore | clean | ~~still DESTROYED~~ | — | same | +54 KB | no |
| **terra strip + rewrite** | clean | **preserved** | `0,0,0,0` -> `255,255,255,0` | same | -10 KB | yes |

**CORRECTED IN PHASE 4 — the "DESTROYED" column above is WRONG, and the row is left standing
because the error is the useful part.** `gdal_edit.py -unsetmd` does **not** wipe the band's
category names. Re-measured with the `.aux.xml` sidecar in place, all 512 rows survive and the
tags go. The first test copied the `.tif` **without** its sidecar and compared it against an
original that had one, so the categories were never there to lose: a comparison whose two sides
differed in something other than the treatment. The conclusion — "the route named at the plan
gate destroys the published RAT" — was written into a commit message and a script header before
anything re-measured it.

The fact that discriminates, and that nothing in this issue had established until Phase 4:
**the category names are not in the TIFF at all.** `GDAL_PAM_ENABLED=NO gdalinfo` on an untouched
classified raster shows no `Categories` block; they live only in the `.aux.xml` sidecar, which is
where `stac_floodplains_bc` reads the RAT from (stac#34/#35).

`gdal_edit` stays rejected, on the reasons that survive measurement: it grows the file ~54 KB per
invocation by orphaning the TIFF directory it rewrites (1,699,519 → 1,753,590 → 1,807,660 →
1,861,730 over three runs) so it is not byte-idempotent, it needs `osgeo` Python bindings nothing
else in this repo depends on, and it would edit files written by GDAL 3.8.5 using the 3.13.0 on
PATH.

**terra strip + rewrite is adopted**, on the reason that holds: it is the fixed step 3's own
write path, so a repaired raster is byte-for-byte what a re-run would produce rather than a third
thing. `fp_raster_content_sha256()` is identical, the file is 10 KB *smaller* because the tags are
gone rather than orphaned, and it is idempotent in bytes.

### The one deviation, bounded rather than hidden

The nodata palette entry moves `255: 0,0,0,0` -> `255: 255,255,255,0`. Alpha is 0 in both, so
nothing renders differently, and it is the **only** line that differs in the whole band section.
It is a property of the round-trip, not of the strip: it survives `NAflag(r) <- 255`,
`writeRaster(NAflag = 255)` and re-applying the source colour table verbatim. Every published
area carries `0,0,0,0` (bulk, lnth, necr, kotl, neexdzii, morr — checked), because a fresh step-3
raster is masked in memory and never round-trips.

Chasing it further meant rebuilding drift's palette inside a repair script — re-implementing
package logic in the driver, which the repo's core principle forbids — so it stops here. The
repair **asserts** it instead: the only band-section difference permitted is that one line, and
anything else aborts the file.

### A trap found while probing, and designed against

`fp_raster_content_sha256()` returns `NA_character_` for a path that does not exist. A repair
comparing before/after with `identical()` therefore reports **"content unchanged"** when the
probe was broken — two `NA`s compare equal. Measured live: an unexported `SP` gave a relative
path, both sides came back `NA`, and the comparison passed. The repair script rejects `NA` on
either side as a hard error, not as a match.

A second one, same session: `jsonlite` renames `gdalinfo -json`'s empty-string metadata-domain
key, so `j$metadata$_` reads `NULL` and every raster looks clean. It produced three confident
wrong readings before the Python reader from the original sweep disagreed. Tag reads go through
one reader.

## Phase 2 — the pin, and two defects it introduced

### On this machine the strip is a NO-OP, and that is the honest position

`terra::rast(<gdalcubes .nc>)` on 1.9.34 returns **zero** metags — measured directly against
`~/Library/Caches/drift/v2/io-lulc/2017_*.nc`. So for step 3's own path on m1 there is nothing to
strip, and no live run here can demonstrate the fix working. terra 1.9.11 is not installed and is
not reachable from CRAN (current is 1.9-46), so the m4 arm is not run either.

What carries the assurance instead is the **post-write check**, and it is designed so the strip
does not have to be trusted: whatever terra does, `fp_rast_write()` re-reads the file it just wrote
and refuses to continue if stray tags are on it. That is why the reader matters (below), and why a
`run_area.R neexdzii 3` in the Validation list is a **regression** test — it proves the pin damages
nothing — and not evidence the pin fixes anything.

### The guard does not read through terra

`fp_rast_stray_tags()` asks GDAL via `sf::gdal_utils("info", …, "-json")`, not
`terra::metags()`. terra is the library under suspicion — the entire defect is that one terra
surfaces a NetCDF's attributes and another does not — so a guard built on `metags()` would report
clean on exactly the toolchain where the strip fails. CLAUDE.md carries this twice already ("a
verifier built on the writer's own library shares its blind spot"); it would have been the third.

Scope is the dataset-level, **default** domain, on measurement. `IMAGE_STRUCTURE` is GDAL
describing its own encoding, and every classified raster — clean and dirty alike — carries
band-level `DATE_TIME` and `STATISTICS_*` that terra writes. A guard reading either fires on every
correct file in the repo.

The default-domain key is the **empty string**, which `md[[""]]` does not index; it is selected by
position. Indexed by name the guard sees no tags on any raster and passes everything.

### Two defects in the first draft of the fix, both in the empty case

Neither is reachable from any file on disk, because every raster already written carries
`AREA_OR_POINT` — so only a constructed zero-tag case finds them.

1. **`metags(r) <- NULL` ERRORS on a raster that has no tags.** terra 1.9.34 returns `NULL` from
   `metags()` — not a 0-row frame — and the setter then dies with `value[, 3] <- "" : incorrect
   number of subscripts on matrix`. That is the m1 raster exactly. An unguarded strip would have
   **aborted step 3 on every area on this machine**, while working fine on the one machine that
   needed it: the fix breaking everywhere except where the bug was.
2. **`if (!nrow(tg))` on that same `NULL`** raises `invalid argument type`, so the tag reader
   errored on any clean raster. Superseded by the GDAL reader, and the shape lesson kept: `NULL`,
   a 0-row frame and `character(0)` are three different things and `metags()` returns the first.

### Scope corrections from the plan review

- **`run_region.R` does not write rasters** and the source line added there has been removed. It
  sources `fp_gpkg.R` for a specific reason — `fp_gpkg_pin_date()` sets a process env var its
  per-WSG children inherit — and `fp_raster.R` has no process-level effect. Sourcing it there
  would tell the next reader that `run_region` writes rasters.
- **`02_floodplain_model.R:226` is a third write site** and is now pinned too. All 72
  `floodplain_*.tif` on disk are already clean, so the strip is a measured no-op there — wired
  anyway, because leaving one of three sites unpinned on the grounds that its input happens to be
  clean is a fact about `flooded`'s internals rather than a contract, and is how "the fix landed
  in one of the callers" comes back.

### Out of scope, and worth its own issue

Every classified and transition raster in `data/` — clean areas included — carries band-level
`STATISTICS_MEAN=-9999` and `STATISTICS_STDDEV=-9999`, terra's own placeholders, and those ride
into the published COGs. Wrong values in a published asset, same family as this issue, different
cause. Filed as [#84](https://github.com/NewGraphEnvironment/floodplains/issues/84), not widened into #83.

## Phase 3 — the guard, and a false-positive it would have had

`provenance-check.R` §5f, 14 checks, on the §5c pattern. The fixture sets the tags **explicitly**,
which is not a convenience: `rast(<.nc>)` on 1.9.34 yields nothing, so a fixture built from a real
cube would carry no tags, the strip would be a no-op and every assertion would pass against a
deleted implementation.

**Restore-the-bug, both defects, message-grepped rather than exit-code-read.** Disabling the strip
turns three checks red and prints the guard's own message; restoring the unguarded
`metags(r) <- NULL` turns the two empty-case checks red. A first draft let the first of those abort
the whole script — `fp_rast_write()` stops by design, so an uncaught `stop()` took sections 6 and 7
down with it and read as a crash rather than as this property failing. It is caught, recorded as a
named FAIL, and the run continues.

### A PAM sidecar made a clean raster read as dirty

Found by the round-1 reviewer and reproduced: GDAL merges a dataset-level `<Metadata>` block from a
`.aux.xml` into the default domain, so a sidecar carrying `TIFFTAG_SOFTWARE=QGIS` put two "stray"
tags on a clean file. Latent rather than live — none of the **112** sidecars under `data/` carries
such a block today — and it matters for two reasons beyond the false alarm:

1. **The repair cannot fix what the guard would flag.** `raster_strip-tags.R` rewrites the TIFF,
   which cannot remove a tag living in a sidecar. The file would be reported dirty, "repaired", and
   reported dirty again, forever.
2. **It is machine-local.** CLAUDE.md's #64 block records that GDAL writes that sidecar as a side
   effect of anyone *opening* the raster — so a PAM-sensitive guard makes a published-artifact
   property depend on who has looked at the file in QGIS. That is the machine dependence #64 was
   opened to remove, arriving one field over.

The reader now sets `GDAL_PAM_ENABLED=NO` for the duration of the call and restores the previous
value, so the subject is the TIFF's own tag 42112 and nothing else. Pinned in §5f with a premise arm
proving the sidecar really is visible to GDAL, so the assertion is not about something that could
never happen.

### `classified_content_sha256` was the one recorded digest never re-derived

§7 asserted its year *set* against `inputs$years` — both written by the same run, so they cannot
disagree — and nothing read the rasters. It now re-derives all seven digests from
`rasters/<scen>/classified_<yr>.tif` and checks each file's container, and does the same for
`transition.tif` and step 2's `floodplain_*.tif`. That is what makes Phase 4's claim checkable by a
committed guard rather than by hand: run it on `necr` today and it reports **7 of 7 dirty** with the
digests already reconciling, which is the repair's whole thesis stated as a test before the repair
runs.

## Phase 4 — the repair, and the bug it had

Fourteen files: seven `classified_*.tif` in `necr` (`ch_ff04`), seven in `kotl` (`bt_ff04`). Full
evidence, including the numbers, is committed at
`scripts/floodplain_lcc/logs/20260905_raster-tags_strip_necr-kotl.md` — `data/` is gitignored, so a
repair that touches 14 files otherwise leaves nothing in the PR.

### The repair deleted the published class names, and the content digest agreed

The first draft renamed the rewritten `.tif` into place and `unlink`ed the target's `.aux.xml`, on
the reasoning that a PAM sidecar is a regenerable statistics cache. Measured after the run:
`is.factor()` FALSE, `cats()` NULL — the RAT `stac_floodplains_bc` publishes, silently gone, while
`fp_raster_content_sha256()` matched perfectly, because it digests cell values and geometry and the
class labels are neither.

That is the exact shape stac#34/#35 already cost this project once: a well-formed file the consumer
reads nothing from, passing every checksum. The script now renames **both** files and asserts
`terra::cats()` is identical before and after — asserted directly, because the band-section diff
cannot see it: that diff reads each file with its own sidecar, so it is blind to the sidecar going
missing at rename time.

### Two smaller defects, both caught by running it

- **The temp file needs a `.tif` extension.** `.classified_2017.tif.strip<pid>` made terra abort
  with "cannot guess file type from filename" — which the abort path handled correctly, leaving both
  originals untouched and exiting non-zero.
- **`DRY=1` printed "Would repair 0 of 11"** over a list of seven files it had just said it would
  repair, because the counter only increments on a real write. A preview that contradicts itself.

### Interrupted mid-run, and it resumed

The kotl pass was killed by a 2-minute command timeout after four files. No temp file was left, the
four completed files were intact, and re-running picked up at `classified_2020.tif` — because the
script tests each file's tags rather than tracking progress. Idempotence bought resumability; it was
exercised by accident rather than by design.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `stat: invalid option -- '%'` | GNU coreutils `stat` is on PATH ahead of BSD; `stat -f%z` is BSD-only. Used `wc -c` — portable either way. |
| `diff` printed a git-style diff | `diff` is a shell function delegating to `git diff` (CLAUDE.md's shadowed-command trap). Used `command diff` for anything treated as evidence. |
| `fp_raster_content_sha256()` returned `NA` on both sides | `SP` was set but not exported, so `Sys.getenv("SP")` was empty and the path was relative. Two `NA`s compare equal — see the trap note above. |
| `j$metadata$_` read `NULL` for every raster | jsonlite renames the empty-string JSON key. Read tags with the Python reader used for the original sweep. |
| `value[, 3] <- "" : incorrect number of subscripts on matrix` | `metags(r) <- NULL` on a raster with no tags. Guard the assignment on `!is.null(tg) && NROW(tg) > 0`. |
| `if (!nrow(tg))` -> `invalid argument type` | `terra::metags()` returns `NULL`, not a 0-row frame, when empty. Superseded by reading through `sf::gdal_utils()`. |
| `sf::gdal_utils(...)` returned `NA`, then a jsonlite lexical error | The file did not exist -- an earlier write had failed. The NA propagated into the parser instead of failing where it happened. |
| `[writeRaster] cannot guess file type from filename` | The repair's temp file must still end in `.tif`; terra reads the driver from the extension. |
| `bfs: Invalid timestamp` on `find -newermt "-2 minutes"` | `find` is the `bfs` shim, which takes ISO-8601 only. Compared a digest of the whole tree instead -- a stronger check than mtimes anyway. |

## Issue context

## What happens

Two of the four areas re-run for #79 write their `classified_<yyyy>.tif` with **30 stray
gdalcubes / NetCDF metadata tags** attached. The other two do not. Measured 2026-09-05 on m1,
directly on `data/<area>/rasters/<scen>/classified_2017.tif`:

| area | scenario | tags on the raster | gdalcubes block |
|---|---|---:|---|
| `bulk` | `co_ff04` | 1 | no |
| `necr` | `ch_ff04` | 31 | **yes (30)** |
| `lnth` | `ch_ff04` | 1 | no |
| `kotl` | `bt_ff04` | 31 | **yes (30)** |

The `transition.tif` in all four areas is clean — only the classified series carries them.

## Why it matters

Two of the tags **contradict the file they are attached to**:

```
raster header : dtype uint8,  nodata 255
data#type     : 'float64'
data#_FillValue: 'nan'
```

They describe the gdalcubes NetCDF cube the raster was cut from, not the raster. `crs#spatial_ref`
is at least correct (32610 for `necr`, 32611 for `kotl`, matching each raster).

A third leaks a local temp path from the producing session into a file that gets published:

```
NC_GLOBAL#process_graph : {"chunk_size": [1, 1024, 1024], "cube_type": "image_collection",
                           "file": "/tmp/RtmpOPwc60/file143d644d5df9.db", ...}
NC_GLOBAL#source        : 'gdalcubes 0.3.2'
```

The rest are CF/NetCDF dimension boilerplate: `NETCDF_DIM_EXTRA`, `NETCDF_DIM_time_DEF`,
`NETCDF_DIM_time_VALUES`, `time#*`, `x#*`, `y#*`, `data#scale_factor`, `data#add_offset`,
`data#grid_mapping`, `NC_GLOBAL#Conventions`, `NC_GLOBAL#gdalcubes_datetime_*`.

## Where it surfaces

`stac_floodplains_bc` converts these to COGs with `rasterio.shutil.copy` (a `CreateCopy`), which
carries source metadata through — so the tags reach the published assets. They were caught by a
pre-publish gate in stac_floodplains_bc#59 comparing each rebuilt COG against the bytes S3 was
serving: pixels, geometry, nodata, dtype, block layout and the embedded RAT are **all identical**,
and these 30 tags were the only unexplained difference. The currently published `necr` and `kotl`
COGs do **not** carry them, so this arrived with the #79 re-run.

The data is correct — this is metadata that describes something other than the file it is on.

## Repro

```r
library(rasterio)  # or, from the stac_floodplains_bc uv env:
# uv run python -c "
# import rasterio
# for a, s in [('bulk','co_ff04'), ('necr','ch_ff04'), ('lnth','ch_ff04'), ('kotl','bt_ff04')]:
#     with rasterio.open(f'data/{a}/rasters/{s}/classified_2017.tif') as d:
#         t = d.tags()
#         print(a, d.dtypes[0], d.nodata, len(t), t.get('data#type'), t.get('NC_GLOBAL#source'))
# "
```

## Question

The inconsistency is the interesting part — `bulk` and `lnth` came out clean from the same #79
run, so something differs in how the four were written (a different write path, or a
`gdalcubes`-backed read that only some areas took). Worth finding before deciding whether the fix
is to drop the tags on write or to stop them being attached at all.

Related: #80 (record gdalcubes in provenance — same library, different concern), #79 (the re-run),
NewGraphEnvironment/stac_floodplains_bc#59 (the publish that found it).

