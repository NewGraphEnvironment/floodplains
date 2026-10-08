# Findings — Wayback chips (#115)

## Issue context

**If we do it:** each review point gets sharp, dated imagery near both endpoints. That is Esri's actual capture nearest 2017 and nearest 2023, as local rasters in the project, so labelling is offline and the 2017 call no longer rests on IO's own 10 m Sentinel-2.
**If we never do:** the first-year label has no sharp imagery. The 2012 air photo is a 4.4 m thumbnail, and Wayback cannot be used in QGIS at all (see below). So the 2017 reference is barely better than the map it checks, and that undermines the change accuracy #93 exists to measure.

## Findings (2026-10-08, measured)

- **Release date is not capture date.** At NECR point 1 (`17_00009`):
  - the 2017-11-16 release serves a **2013-05-06** capture;
  - the **2020-04-29** release (id 15045) serves a **2017-06-11** capture at 0.31 m;
  - the 2023-12-07 release serves a **2021-06-22** capture.

  Capture dates differ point by point, so no single release is "the 2017 layer". Over 6 random NECR points, the 2017-11-16 release served captures from 2013 to 2016. See rtj's `research/esri_wayback.md`.
- **Wayback cannot be drawn in QGIS.** Releases deduplicate tiles: a tile that did not change in a release 301-redirects to the release holding it, with a **relative** `Location`. QGIS's tile loader requests the bare path and fails ("Tile request max retry error ... url: /arcgis/rest/services/world_imagery/..."), so a release layer draws only the tiles that changed in that release. curl and GDAL follow the redirect.

## QGIS: a known upstream bug, not fixed in any release

**qgis/QGIS#54161**, "Unable to load images from World Imagery Wayback due to wrong redirected tile url". It is open since 2023-08 and confirmed as recently as 2026-09-23 with this exact XYZ reproduction.
- No pull request references it. The only related merged change is #53792 (2023), which fixed *caching* of redirected XYZ tiles, not relative URLs.
- Not fixed in 4.2.3 or the 3.44.15 LTR (both 2026-09-25). m1 and m4 run 4.2.1, so we are not behind.
- No report needed from us.

## Decisions (2026-10-08)

- **Code home:** floodplains scripts now, beside `imagery_index-dated.R` / `imagery_build-dated.R`. File a drift issue to promote them to `dft_wayback_*` once proven.
- **No network at label time:** fetch once at build time into the project.
- **`labels.gpkg` is not touched:** its schema is frozen now that labelling has started on Mergin. Capture dates go in `cells.gpkg`, which is read-only.

## Plan (for `/planning-init 115`)

## Phase 1: Probe the two unknowns
- [ ] **Metadata.** Find the per-release metadata MapServer layer that resolves capture polygons at full zoom. Confirm one query per release over the area's bbox returns `SRC_DATE2`, `SRC_RES`, `NICE_DESC` polygons that can be joined to points locally, rather than one identify per point.
- [ ] **Fetch.** Write a GDAL WMS (TMS) XML for one release, then `gdal_translate -projwin` a ±150 m chip around point 1. Confirm GDAL follows the relative redirect, find the deepest zoom that returns data, and confirm a 404 tile becomes nodata, not an abort. Render the chip for 2017 and 2023 and look at it.
- [ ] Record both in findings; they decide Phases 2 and 3.

## Phase 2: Index: `scripts/landcover_accuracy/wayback_index-capture.R <area>`
- [ ] Read the release list from `waybackconfig.json`. Per release, read the capture polygons over the sample points (Phase 1 method), then join them to points.
- [ ] For each point and each endpoint (`change_interval`), pick the release whose capture date is nearest the endpoint. On a tie, take the finer `SRC_RES`, then the later release.
- [ ] Write `reference/<area>/wayback.csv` (regenerated, never hand-edited, design-checked like `imagery.csv`) with these columns: `point_id`, `stratum`, `cell`, `map_class`, `endpoint`, `release_id`, `release_date`, `capture_date`, `src_res`, `source`, `years_from_endpoint`.
- [ ] Print the distribution of capture distance from each endpoint (same year, ±1, ±2, further), which shows how far this fixes 2017.

## Phase 3: Build: `scripts/landcover_accuracy/wayback_build-chips.R <area>`
- [ ] Fetch one chip per point per endpoint from its chosen release, about ±150 m at the deepest available zoom, into `<project>/dated/wayback_<year>/<review_id>.tif`.
  - Files are named by `review_id`, **never** `point_id`, which encodes the stratum.
  - Tiles are cached so a re-run fetches nothing new.
- [ ] Write `<project>/dated/wayback_<year>.vrt` over that year's chips, warped to BC Albers like the orthophoto VRT. Report failures and points left with no chip.
- [ ] `REVIEWER=b` hard-links them like the other imagery (existing `fp_acc_link_tree`).

## Phase 4: Review inputs and checks
- [ ] `cells.gpkg` gains read-only display columns: `capture_<first>` / `capture_<last>`, e.g. "2017-06-11, 0.31 m". `labels.gpkg` is left alone, because its schema is frozen now that labelling has started on Mergin.
- [ ] `review_build-qgis.R` adds the layers with themes `<year> Esri capture (nearest per point)`, which sort beside that year's Sentinel-2 theme in the drop-down.
- [ ] `accuracy-check.R` arms:
  - the selection rule on toy metadata (nearest, the tie-breaks, an endpoint with no capture);
  - chip names carry no `point_id`, with a must-fail arm;
  - `wayback.csv` passes the design check;
  - the `cells.gpkg` capture columns match `wayback.csv`.

## Phase 5: Run NECR, document, hand off
- [ ] Run the index and the build on NECR (A, then B). Render a handful of chips to PNG and look at them. Record the capture-distance distribution and run time in a log under `scripts/landcover_accuracy/logs/`.
- [ ] Docs:
  - `research/landcover_accuracy.md` "Dated reference imagery": Wayback release vs capture, and the QGIS bug.
  - CLAUDE.md #93 bullet: `wayback.csv`.
- [ ] Hand-off on rtj#377: the file pattern `dated/wayback_<year>.vrt`, the `cells.gpkg` columns, and that the release services and themes go.
- [ ] Note on rfp#398 that this is the drawable route. File the drift issue to promote the code to `dft_wayback_*`.

## Critical files
- new: `scripts/landcover_accuracy/wayback_index-capture.R`, `wayback_build-chips.R`
- `scripts/landcover_accuracy/review_build-qgis.R`, `fp_accuracy.R`, `accuracy-check.R`
- new: `reference/necr/wayback.csv`

Reused:
- `fp_acc_area`, `fp_acc_design_check` and `fp_acc_link_tree` (`fp_accuracy.R`)
- the `imagery_index-dated.R` / `imagery_build-dated.R` pattern: per-point index, design columns copied, VRT per epoch, BC Albers warp

## Verification
- **Offline:** `accuracy-check.R` with the new arms, each must-fail shown red.
- **Live:** the NECR index and build. For point 1, the 2017 chip shows the 2017-06-11 capture, cross-checked against the per-point identify query. View chips as PNG.
- **Blind:** grep the review inputs for `point_id`-shaped names (`[0-9]+_[0-9]{5}`); expect none.


Relates: #93, #111, NewGraphEnvironment/rtj#367, NewGraphEnvironment/rtj#377, NewGraphEnvironment/rfp#398



## Phase 1 probes (2026-10-08, measured)

### Metadata: one envelope `query` per release and layer, then a local join
- `waybackconfig.json` holds 197 releases. Each has a `metadataLayerUrl`
  (`World_Imagery_Metadata_<yyyy>_r<nn>/MapServer`) with 14 layers, one per scale band:
  - layer 0 is 1.9 cm (scale 106-0) and layer 13 is 150 m;
  - layer `L` describes tile zoom `23 - L`: layer 6 (1.2 m, scale 6800-3400) is zoom 17, layer 5 is zoom 18, layer 4 is zoom 19.
- Fields: `SRC_DATE` (int yyyymmdd), `SRC_DATE2` (epoch ms), `SRC_RES`, `SRC_DESC` (sensor), `NICE_DESC`, `MinMapLevel`, `MaxMapLevel`, `DrawOrder`. maxRecordCount is 1000, and the services are in EPSG:3857.
- Release 15045 over the NECR sample bbox (-124.80,53.66,-123.46,54.21):
  - layers 3-5 return **0** polygons and layer 6 returns **40**, all with MaxMapLevel 17;
  - a point `query` on layer 6 at point 1 gives SRC_DATE 20170611, 0.31 m, WV03, which agrees with `identify` (layers 6-11 report the same capture).
- So it is one envelope query per release per layer, with `returnGeometry`, followed by an `st_join` to the points. That is 197 releases x 3 layers (4-6) of small queries, not 480 x 197 identifies.

### Fetch: GDAL WMS (TMS) follows the relative redirect
- Tile depth at point 1, for both 15045 and 25521: zoom 16-17 return 200, and zoom **18-20 return 404**. Zoom 17 is the deepest level here, ~0.70 m on the ground at 54 N (1.194 m x cos 54).
- Release 25521 301-redirects every tile at z16/z17 to release 4073, with a relative-style `Location`. A GDAL WMS XML (TMS, `${z}/${y}/${x}`, TileLevel 17, `<Cache>`) fed to `gdalwarp -t_srs EPSG:3005 -te <+/-150 m> -tr 0.5` produces a correct 600x600 RGB chip for both releases, in 2.5 s cold and 0.9 s with a warm cache.
- Rendered side by side, 25521 (2013 capture) and 15045 (2017-06-11 capture) are visibly different captures: different houses and clearing. Both are sharp.
- A 404 tile (TileLevel 18) does **not** abort. `ZeroBlockHttpCodes` 404 makes the block zeros, and gdal emits warnings. So a chip that is all zero means "no data at this zoom", and the build must test for it.

### Decisions these settle
- The index queries layers 4-6 per release. Per point and release, the deepest layer whose polygon covers the point gives the capture **and** the fetch zoom (`23 - layer`). Where several polygons in one layer cover a point, the highest `DrawOrder` wins.
- Selection is by year distance first, then days from 1 July of the endpoint year, then finer `SRC_RES`, then the later release. Year distance comes first because the pre-registered labelling key sets confidence by +/-1 year from the endpoint.
- A capture with a null date (Earthstar base layers) is not a capture and is dropped.
- The build uses gdalwarp straight to EPSG:3005 at 0.5 m, with nearest-zoom tiles from the GDAL cache. An all-zero chip counts as a failure.

## Errors Encountered

| Error | Resolution |
|-------|------------|
