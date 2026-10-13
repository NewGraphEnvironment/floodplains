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

## Errors Encountered

| Error | Resolution |
|-------|------------|
