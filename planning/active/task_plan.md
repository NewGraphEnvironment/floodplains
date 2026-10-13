# Task: Cache the step-2 DEM per area: NRCan's S3 serves MRDEM at ~145 KB/s, so BULK's fetch takes ~37 min (#122)

## Problem

`02_floodplain_model.R:108` calls `flooded::fl_dem_aoi()` on every run. The DEM is cropped and reprojected in memory and is not written to disk. Only the whole-FWA probe writes one (`data/<area>/probe_whole_fwa/dem_common.tif`).

The fetch time is set by NRCan's bucket throughput, not by the read pattern. Measured 2026-10-11 (flooded#72 follow-up):

- MRDEM-30 is a proper COG: 512x512 tiles, LZW, overviews, 84 GB (`Last-Modified` 2026-06-24). So it is not a strip-organised remote read.
- BULK's window is 8,195 x 8,581 source pixels, or 289 tiles. MORR's is 5,821 x 5,669, or 144 tiles. That is about 2x the data.
- The probe's fetches (`data/<area>/probe_whole_fwa/logs/dem.log`): MORR took 60 s wall. BULK took **2,240 s wall against 51 s CPU**, so the time was spent waiting on the network.
- Today a 5 MB range from the bucket ran at **145 KB/s**, against 5.8 MB/s from a control host on the same connection. A plain `gdal_translate` of MORR's window had not finished after 10 min.

**Decided (user, 2026-10-13):** the cache lives in the driver (step 2 + attribute_tag.R), and the driver owns the DEM URL (`FP_DEM_SOURCE`, passed as `source =`). No flooded change. Space is a non-issue (~2 GB across all areas, 783 GB free).

## Phase 1: DEM cache helper + offline check
- [x] `scripts/floodplain_lcc/fp_dem.R`: `FP_DEM_SOURCE`, `fp_dem_last_modified()`, `fp_dem_key()`, `fp_dem_cached()`
- [x] `scripts/floodplain_lcc/dem_cache-check.R` offline section. Each key ingredient (AOI, buffer, CRS, source, Last-Modified, flooded version, each toolchain member) moves the key hash, and an unchanged input keeps it. Must-fail arms for a tampered tif (it must re-fetch, not hit), a missing json (a miss), and a key hash that matches but a digest that does not
- [x] Assert `FP_DEM_SOURCE` equals flooded's default by parsing `body(flooded::fl_dem_aoi)`, so a flooded default change is reported rather than silently diverged from

## Phase 2: Wire into step 2 + provenance
- [x] `02_floodplain_model.R`: replace the `fl_dem_aoi()` call with `fp_dem_cached()`. Rewrite the `02:123-139` comment, since the URL is now recoverable because the driver passes it. Source `fp_dem.R` wherever `run_area.R` sources the helpers
- [x] Provenance: `inputs$dem_source` = the URL, and `dem_resolver` becomes `"flooded::fl_dem_aoi(source = dem_source)"`. `run$dem_cache` = the hit or miss, the key hash, `last_modified` and the path. That goes in `run`, not `inputs`, because Last-Modified can move without the content moving, and `dem_content_sha256` already covers the content
- [x] `provenance-check.R`: add `dem_source` to `KEYS_FLOODPLAIN`. 7c reconciles `dem_content_sha256` against `dem_<stem>.tif` when the sidecar's key hash equals `run$dem_cache$key`, and FAILs on a digest mismatch. Otherwise it reports "cache replaced since". A must-fail arm covers the mismatch. Pre-#122 entries (no `dem_cache`) keep today's "not reconcilable" skip
- [x] Confirm `stac_floodplains_bc`'s reader ignores unknown floodplain `inputs` keys (grep shows it reads no `dem_*` field) and note it in findings

## Phase 3: attribute_tag.R reuses the cache
- [ ] Replace its `fl_dem_aoi()` call with `fp_dem_cached(buffer = sc$max_width, …)`. `max_width` is 2000 = step 2's `buf` in every current scenario table, so it hits step 2's cache. A differing `max_width` misses and rewrites the cache, which is correct but slow; a comment says so

## Phase 4: Live verification
- [ ] `dem_cache-check.R` live section on a tiny AOI in a scratch directory. The first call misses, the second hits, and the digests are identical. The second call does no fetch, which is shown by the attribute and its timing
- [ ] neexdzii `run_area.R neexdzii 2,3` cold. The floodplain and landcover digests must equal today's #117 re-baseline (`dem_content_sha256` `192ea21e…`). Only `inputs_hash` moves, from `dem_source` and `dem_resolver`
- [ ] neexdzii `2,3` again warm. Step 2 reports a hit, every digest is unchanged, and the DEM phase is timed with `date -u`. Then run `provenance-check.R neexdzii` and `composition-check.R neexdzii`
- [ ] Log at `scripts/floodplain_lcc/logs/<date>_dem_cache_neexdzii.md`. Gate on the in-band error count and the output mtimes, not exit codes

## Phase 5: Docs
- [ ] CLAUDE.md: a bullet on the DEM cache (the key, the toolchain in the key and why, fail-closed HEAD, per-species stem, the driver owns `FP_DEM_SOURCE`). Update the Prerequisites "internet for MRDEM-30" line: a cache hit still needs the HEAD request
- [ ] Edit the #122 issue body to record the decision (driver-owned URL; the open question resolved)

## Validation
- [ ] Tests pass: `dem_cache-check.R`, `provenance-check.R`, `composition-check.R neexdzii`
- [ ] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

