# Step-2 DEM cache, live verification on neexdzii (#122)

**Run:** 2026-10-13, 23:12Z–23:25Z, one machine (m1), branch `122-cache-the-step-2-dem-per-area-nrcan-s-s3`.
**Toolchain:** flooded 0.7.0, terra 1.9.50 (GDAL 3.13.0 / PROJ 9.8.1), sf (GDAL 3.8.5 / PROJ 9.5.1, GEOS 3.13.0).
**Source:** MRDEM-30 `mrdem-30-dtm.tif`, Last-Modified `Wed, 24 Jun 2026 15:08:08 GMT`, ETag `1bf055857edce86b1311967c8d88395e-9997`.

The baseline is `data/neexdzii/provenance.json` as it stood after the #117 re-baseline (22:19Z), copied before the first run.

## Runs

| run | command | DEM | DEM time | result |
|-----|---------|-----|----------|--------|
| cold | `run_area.R neexdzii 2,3` (first key form) | miss: no cached DEM | fetched 16.5 s | 0 errors |
| re-key | `run_area.R neexdzii 2,3`, after the review put the whole toolchain in the key | miss: key differs (the toolchain members) | fetched 14.7 s | 0 errors |
| warm | `run_area.R neexdzii 2,3` | hit | 0.29–0.61 s (timed separately, 3 calls, digest included) | 0 errors |
| attribution | `attribute_tag.R neexdzii` | hit, digest equals step 2's record | — | 0 errors |

Each run was gated on its log's error count (`^Error|Execution halted`, 0 every time) and on `provenance.json` being newer than a stamp touched at launch. The wrapper's exit status was not used as the gate.

Today the bucket served neexdzii's window in about 15 s, so the saving here is roughly 15 s per run. The issue's motivating figure is BULK, 2,240 s wall against 51 s CPU (`data/bulk/probe_whole_fwa/logs/dem.log`). BULK's hit time has not been measured: BULK is on the pre-pin grid and is re-run under #125. A hit costs one HEAD request plus a content digest of the cached file, which step 2 computed anyway.

## What moved, and what did not

Every pre-run record was compared with every post-run record, field by field over `inputs` and `outputs` plus both hashes, for every floodplain and landcover entry.

- `dem_content_sha256` was `sha256:192ea21e380f…` before and after all three step-2 runs. That is the #117 re-baseline value, so passing `source = FP_DEM_SOURCE` explicitly, and handing step 2 a file-backed FLT8S DEM, reproduces the DEM byte for byte.
- Every floodplain `outputs_hash` is unchanged, as are the landcover `inputs_hash` and `outputs_hash` and the composition `outputs_hash`. A file-backed DEM gives the identical VCA.
- `co_ff04_by_blue_line_key` came out at 105 rows and 252.1233 km² after the cold run, the warm run and `attribute_tag.R` alike. That layer is vector and has no digest (#72), so it was compared by count and area.
- Only `inputs.dem_resolver` (now `flooded::fl_dem_aoi(source = dem_source)`) and the new `inputs.dem_source` differ, on all three floodplain entries. So floodplain `inputs_hash` moved, as expected. `provenance_ab-compare.R` against the pre-#122 record would therefore fail STABILITY on `inputs_hash` alone.
- `run.dem_cache.status` reads `miss` on the cold and re-key records and `hit` on the warm one.

## Checks

- `provenance-check.R neexdzii`: PASS. 7c reports `dem_content_sha256 matches the cached DEM (dem_co3.tif)` for co_ff02, co_ff04 and co_ff06. Before #122 these three lines read "not reconcilable".
- `composition-check.R neexdzii`: ALL PASS.
- `LIVE=1 dem_cache-check.R`: PASS. On a tiny AOI it missed in 3.3 s and then hit in 0.1 s, and the cached DEM equals `fl_dem_aoi(source = NULL)`'s own fetch.
- The re-key miss names the ingredients that moved (`gdal_terra, proj_terra, proj_sf, tc_*`), which is the miss message working on a real key change.
