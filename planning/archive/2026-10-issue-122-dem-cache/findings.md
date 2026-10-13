# Findings — Cache the step-2 DEM per area (#122)

## Issue context

**If we do it:** a re-run of an area reads its DEM from disk instead of NRCan's S3. BULK's step 2 loses ~37 min of each re-run, and the DEM a floodplain was built on is a file we can digest, re-use and compare.
**If we never do:** every re-run of an area pays the full fetch again, at whatever rate NRCan's bucket is serving that day. On a large group that rate decides whether a run fits in an hour.

## Problem

`02_floodplain_model.R:108` calls `flooded::fl_dem_aoi()` on every run. The DEM is cropped and reprojected in memory and is not written to disk. Only the whole-FWA probe writes one (`data/<area>/probe_whole_fwa/dem_common.tif`).

The fetch time is set by NRCan's bucket throughput, not by the read pattern. Measured 2026-10-11 (flooded#72 follow-up):

- MRDEM-30 is a proper COG: 512x512 tiles, LZW, overviews, 84 GB (`Last-Modified` 2026-06-24). So it is not a strip-organised remote read.
- BULK's window is 8,195 x 8,581 source pixels, or 289 tiles. MORR's is 5,821 x 5,669, or 144 tiles. That is about 2x the data.
- The probe's fetches (`data/<area>/probe_whole_fwa/logs/dem.log`): MORR took 60 s wall. BULK took **2,240 s wall against 51 s CPU**, so the time was spent waiting on the network.
- Today a 5 MB range from the bucket ran at **145 KB/s**, against 5.8 MB/s from a control host on the same connection. A plain `gdal_translate` of MORR's window had not finished after 10 min.

## Proposal

Cache the cropped, reprojected DEM per area in step 2. Write `data/<area>/dem.tif` after the fetch, and read it back when its key matches. The key has to cover everything that decides the grid and the values:
- the AOI bbox, buffer, target CRS and source URL;
- the source's `Last-Modified`;
- the flooded version.

The flooded version is in the key because of flooded#67. Until the grid is pinned, GDAL chooses it, so a cache keyed on the AOI alone would keep an old grid alive after #67 lands (see also #117). The provenance record's DEM digest then describes the cached file exactly.

Open question: this belongs in step 2, unless more than one consumer needs it. If so, a `cache =` argument on `fl_dem_aoi()` would be the place, as a flooded change.

Relates: flooded#67, #117, flooded#72.

## Plan-mode exploration (2026-10-13)

- Consumers of `fl_dem_aoi()`: step 2 (`02:128`, buffer 2000), `attribute_tag.R:86` (buffer = `sc$max_width`, 2000 in every current table), the whole-FWA probe (own `dem_common.tif`), and two accuracy scripts (tiny bboxes).
- flooded 0.7.0's `fl_dem_aoi()` builds the MRDEM URL in its body when `source = NULL` (flooded#58 open). The grid is a template aligned to multiples of `res` from the bbox of the buffered AOI in target CRS; the source read window still uses an unpinned `sf::st_transform()` (flooded#78), so sf's PROJ can move edge cells.
- Size: `data/bulk/probe_whole_fwa/dem_common.tif` 96 MB, MORR's 47 MB. `data/` is 4.1 GB; 783 GB free.
- `stac_floodplains_bc/scripts/fp_provenance.R` reads `run$datetime_utc` and named fields only; no `dem_*` field is read.
- `provenance-check.R` pins floodplain inputs keys exactly (`KEYS_FLOODPLAIN`) and skips `dem_content_sha256` in 7c as "not reconcilable (the DEM is never written)".

## Phase 2 (2026-10-13)

- `stac_floodplains_bc/scripts/fp_provenance.R` publishes through `FP_PROV_MAP`, a fixed map of named leaf paths, and refuses only unknown TOP-LEVEL keys (`known <- c("area", ...)`). `inputs$dem_source` and `run$dem_cache` reach no published property and refuse nothing.
- Adding `dem_source` to `KEYS_FLOODPLAIN` turned every existing area red (`provenance-check.R neexdzii`: 3 "inputs missing: dem_source"). The fix is #117's pattern: required by step time from `DEM_CACHE_SINCE` = 2026-10-13T23:00:00Z (after the newest pre-#122 step-2 record, neexdzii 22:19:48Z), and `run$dem_cache` is required on the same entries.
- The probe's step-2 replay (`floodplain_probe-whole-fwa.R`) calls `fp_floodplain()` and so needed `fp_dem.R` sourced. Its replay dir is wiped each run, so it always misses, which is what an anchor replay should do.

## Plan review (Plan agent, delivered 2026-10-13 ~23:16Z) and what was done with it

Verified before acting. Folded in:
- **B1 (blocker, verified by reading):** `attribute_tag.R` fetched at `buffer = sc$max_width`. Any value other than 2000 gives a different grid, replaces step 2's cache, and then stops at `fl_valley_attribute()`'s extent check. It now reads `dem_buffer_m` from step 2's record and requires the digest to match `dem_content_sha256`.
- **G1:** the key now carries every `fp_toolchain()` member (terra, sf, gdal, geos, proj, gdal_terra, proj_terra). A test asserts the key's list equals `names(fp_toolchain())`.
- **G2:** `FP_DEM_CACHE_RECORD` in `fp_dem.R` is the single list that 02 writes and provenance-check requires.
- **G3/G4:** `dem_cache_reconcile()` now does four things. It checks the path against `network_layer`. It digests whenever the file exists, so a match is a match whatever the key. It treats a same-key sidecar that contradicts the record as a mismatch. It skips only when the key has moved. 5h has an arm for each.
- **G5:** temp files carry a `.dem_tmp_` prefix and are removed by `on.exit`; a stale `.aux.xml` is removed on a miss. Proven by a failed-write arm (a mutation that drops the `on.exit` turns it red).
- **G6:** a second HEAD after the fetch refuses to cache if the object changed.
- **O1:** the cutover is gated on the `dem_resolver` string, not on a clock (`DEM_CACHE_SINCE` removed). One arm covers pre-#122 code running after the merge, one covers a missing resolver.
- **A1 (verified):** the warp output is float32-exact (neexdzii: 2,935,855 of 2,935,855 non-NA cells). The FLT8S comments in fp_dem.R, 02 and the probe are reworded. FLT8S stays, because it is lossless whatever terra returns.
- **A2:** the stale comments in fp_provenance.R, provenance-check.R 5c and CLAUDE.md's "cannot be recorded" list are fixed. **A3:** documented.
- **Acc2/Acc3/Acc5:** Phase 4 now requires "matches the cached DEM" for all three entries, runs `attribute_tag.R neexdzii`, and names the expected `inputs_hash` move.

Not taken:
- **(4) `curl` missing from packages.R:** wrong. It was added in Phase 1 (commit 8b9b329).
- **S2 (synthetic in-memory vs file-backed VCA):** not needed. The neexdzii cold run is that test on real data, and every floodplain `outputs_hash` was unchanged.

## Errors Encountered

| Error | Resolution |
|-------|------------|
