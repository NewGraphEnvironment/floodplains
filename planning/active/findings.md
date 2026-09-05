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

**The isolation was already paid for.** `logs/20260905_lulc-annual_split-run.md` records that
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
returns the same nc-backed raster, so the NetCDF attributes survive. `dft_rast_transition()`
builds a **new** raster, which drops them on either terra. That asymmetry is the issue's
"something differs in how the four were written" question, answered.

Origin of the metadata: `drift/R/dft_stac_fetch.R:230` —
`terra::mask(terra::rast(cache_file), terra::vect(aoi_target))`, where `cache_file` is the
gdalcubes `write_ncdf()` output under `~/Library/Caches/drift/v2/io-lulc/<year>_<key>.nc`.

## Blast radius — swept, not assumed

Every `.tif` under `data/`: **116 files, 23 areas, 14 dirty.** All 14 are `classified_*` in
`necr` (`ch_ff04`) and `kotl` (`bt_ff04`), 7 years each. No other area. No `transition.tif`.

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

## Errors Encountered

| Error | Resolution |
|-------|------------|

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

