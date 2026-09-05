# Stripping gdalcubes/NetCDF container tags from 14 published rasters — necr, kotl

**2026-09-05 · issue #83 · m1 · terra 1.9.34 / GDAL 3.8.5 (terra) / standalone GDAL 3.13.0**

`data/` is gitignored, so a repair that touches 14 files leaves nothing in the PR. This is the
committed evidence. The writer-side fix is `scripts/fp_raster.R`; this file records the
reconciliation of what was already written. Upstream note filed as
[drift#63](https://github.com/NewGraphEnvironment/drift/issues/63).

## What was wrong, and how far it reached

Seven `classified_<yr>.tif` in `necr` (`ch_ff04`) and seven in `kotl` (`bt_ff04`) carried 30
dataset-level metadata tags describing the gdalcubes NetCDF cube they were cut from. Two contradict
the raster they sit on — `data#type = float64` and `data#_FillValue = nan` on a `Byte` file whose
nodata is 255 — and `NC_GLOBAL#process_graph` carries the producing session's
`/tmp/RtmpOPwc60/...` path.

Swept over **every** `.tif` under `data/` — 184 files across 23 areas: 88 `classified_*`, 72
`floodplain_*` (step 2) and 24 `transition.tif`. Exactly **14 dirty**, all classified, all in those
two areas. (An earlier sweep reported **112** — `data/*/rasters/*/*.tif` — and prose around it said 116, a
number stated rather than counted. Step 2 writes one directory up, so 184 − 112 = the 72
`floodplain_*.tif`. Same dirty set either way.)

## Why those two areas

The #79 annual run was split across m1 and m4, and that split had already levelled every package
except terra (`20260905_lulc-annual_split-run.md`). The tags follow the terra version exactly, read
from each area's own `provenance.json`:

| area | machine | `run.toolchain.terra` | dirty |
|---|---|---|---|
| bulk | m1 | 1.9.34 | no |
| lnth | m1 | 1.9.34 | no |
| necr | m4 | 1.9.11 | **7 of 7** |
| kotl | m4 | 1.9.11 | **7 of 7** |

The divergence is on the **read** side: `terra::rast(<gdalcubes .nc>)` returns zero metags on
1.9.34, and `writeRaster` propagates faithfully on both (a dirty raster read and written straight
through on 1.9.34 keeps all 30). `transition.tif` is clean everywhere because
`dft_rast_transition()` rewrites values, and value-rewriting ops drop metags where geometry ops
(`crop`, `mask`, `deepcopy`) preserve them — `mask()` is how the tags arrive in the first place.

## The route, and the route that was rejected for the wrong reason

`raster_strip-tags.R` reads each raster with terra, clears `metags()`, writes to a temp file in the
same directory, verifies, and renames. It is the fixed step 3's own write path, so a repaired
raster is what a re-run would produce rather than a third thing.

**`gdal_edit.py -unsetmd` was tried first and rejected on a measurement that was wrong.** It was
reported as destroying the band's category names. Re-measured with the `.aux.xml` sidecar in place, all
**256 category rows and 256 palette entries** survive and the tags go: the first test had copied the `.tif` **without** its sidecar
and compared it against an original that had one, so the categories were never there to lose. It
stays rejected on reasons that hold — it grows the file ~54 kB per invocation by orphaning the TIFF
directory it rewrites (1,699,519 → 1,753,590 → 1,807,660 → 1,861,730 over three runs), it is
therefore not byte-idempotent, it needs `osgeo` Python bindings nothing else here depends on, and
it would edit files written by GDAL 3.8.5 using the 3.13.0 on PATH.

**The category names are not in the TIFF.** `GDAL_PAM_ENABLED=NO gdalinfo` on an untouched
classified raster shows no `Categories` block at all — they live in the `.aux.xml` PAM sidecar, and
that is what `stac_floodplains_bc` reads the RAT from (stac#34/#35 is the incident where an XML
declaration in one made GDAL ignore the file and publish COGs with zero class labels). The first
draft of the repair deleted the target's sidecar as a regenerable statistics cache; measured after,
`is.factor()` was FALSE and `cats()` NULL on the repaired raster — the published RAT silently gone,
with the content digest agreeing. The script now renames both files and asserts the category names
survived.

## The one permitted deviation

The nodata palette entry moves `255: 0,0,0,0` → `255: 255,255,255,0`. Alpha is 0 both ways, so
nothing renders differently. It is a property of the round-trip, not of the strip — it survives
`NAflag(r) <- 255`, `writeRaster(NAflag = 255)` and re-applying the source colour table verbatim —
and every area published before this carried the former, because a fresh step-3 raster is masked in
memory and never round-trips. The script permits that **one** band-section line and aborts the file
on any other difference, so "only the container moved" is a check rather than a claim.

## Acceptance

Per file, before the rename, with the original left untouched on any failure:

- `fp_raster_content_sha256()` identical before and after. `NA` on either side is a hard error, not
  a match — the function returns `NA_character_` for a path it cannot read and `identical(NA, NA)`
  is TRUE, so a broken probe on both sides would otherwise report "content unchanged" and bless
  whatever happened. Measured live while writing the script, from an unexported env var.
- `terra::cats()` identical before and after.
- The `gdalinfo` band section identical apart from the one palette line above.
- `fp_rast_stray_tags()` empty on the rewritten file.

After the run:

| check | result |
|---|---|
| stray tags across all 184 tifs in 23 areas | **0** |
| necr: 7 `classified_content_sha256` vs `provenance.json` | **7 match, 0 mismatch** |
| necr: class names present on all 7 | **7 of 7** |
| `raster_strip-tags.R necr` re-run | `Repaired 0 of 11; 11 already clean` |
| `DRY=1` on a dirty area | tree digest unchanged |

The digests are an **independent** reference: `provenance.json` recorded them during the #79 run,
before this repair existed, so the comparison is not the change checking itself. They are also now
re-derived by `provenance-check.R` §7 on every invocation, which they never were before — that
field's year *set* was asserted against `inputs$years`, both written by the same run.

## Interrupted mid-run, and it resumed correctly

The kotl pass was killed by a 2-minute command timeout after four files. It left **no** temp file,
the four completed files were intact, and re-running picked up at `classified_2020.tif` and
finished the remaining four — because the script tests each file's tags rather than tracking
progress. That is the resumability the idempotence buys, exercised by accident rather than by
design.

## Not done here

- **`STATISTICS_MEAN=-9999` / `STATISTICS_STDDEV=-9999`** ride into every published COG on every
  area, band-level, written by terra. Wrong values in a published asset, same family, different
  cause. Filed as **#84** rather than widened into #83.
- **Republishing.** `necr` and `kotl` need a COG rebuild in `stac_floodplains_bc` to pick this up
  (stac#59). The coupling stays one-way; this repo does not reach into the publish layer.
