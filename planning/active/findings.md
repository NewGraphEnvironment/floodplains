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



## Errors Encountered

| Error | Resolution |
|-------|------------|
