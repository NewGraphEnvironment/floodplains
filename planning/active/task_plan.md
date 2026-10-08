# Task: Wayback chips: sharp imagery at the capture nearest each endpoint, per review point (#93) (#115)

## Context

The accuracy review (#93) labels each point at 2017 and 2023. At 2017 the only sharp view is a 2012
air-photo thumbnail (4.4 m), so the first-year label rests on IO's own 10 m Sentinel-2. Esri Wayback
holds sub-metre captures near both endpoints, but a release date is not a capture date (rtj
`research/esri_wayback.md`), and QGIS cannot draw Wayback because of a relative-redirect bug
(qgis/QGIS#54161). This work picks, per point and endpoint, the release whose **capture** is nearest,
fetches a local chip with GDAL (which follows the redirect), and adds it to the review project.
Decisions already taken in the issue: code lives in floodplains for now (drift issue to promote later),
there is no network at label time, and `labels.gpkg` is not touched.

Exploration confirmed the reuse points: `fp_acc_area`, `fp_acc_design_check`, `fp_acc_link_tree`,
`fp_acc_review_dir`, `FP_ACC_DESIGN_KEY` (`fp_accuracy.R`), plus the full shape of
`imagery_index-dated.R` / `imagery_build-dated.R` (point-set check, design columns copied, stale-layer
removal, VRT warped to EPSG:3005, counting what a VRT holds).

Three things the issue's plan does not mention, now folded in:
- `review_build-qgis.R` rewrites `cells.gpkg` **only when the review_id set changes** (line ~230), so
  the new capture columns need their own trigger.
- `dated_name()`, the dated-layer glob (line ~310) and the orphan regex (line ~321) match only
  `orthophoto|airphoto`, so all three need `wayback`.
- `imagery_build-dated.R`'s stale sweep matches only its own sources, so it will not remove wayback
  files; the wayback build needs its own stale sweep.

**Decision for the gate (recommended first):** the label form's `imagery` field already has `esri`.
A label decided on a Wayback chip records `esri`, the capture date per point is in `wayback.csv`, and
`labels_form.qml` / `FP_ACC_IMAGERY` stay unchanged, since labelling on Mergin has already started.
The alternative is a new `esri_wayback` value, which changes the form mid-labelling and splits one
source across two codes.

## Phase 1: Probe the two unknowns
- [ ] **Metadata.** Find the per-release metadata MapServer layer that resolves capture polygons at full zoom. Confirm that one `query` per release over the sample bbox returns `SRC_DATE2`, `SRC_RES`, `NICE_DESC` polygons that can be joined to points locally, instead of one `identify` per point.
- [ ] **Fetch.** Write a GDAL WMS (TMS) XML for one release with a `<Cache>` path, then `gdal_translate -projwin` a ±150 m chip around point 1. Confirm GDAL follows the relative redirect, find the deepest zoom that returns data, and confirm a 404 tile becomes nodata rather than an abort. Render the chip for 2017 and 2023 and look at it.
- [ ] Record both in `findings.md`; they decide Phases 2 and 3.

## Phase 2: Index: `scripts/landcover_accuracy/wayback_index-capture.R <area>`
- [ ] Read the release list from `waybackconfig.json`. For each release, read the capture polygons over the sample points (Phase 1 method) and join them to the points.
- [ ] Put the selection rule in `fp_accuracy.R` as a pure function (`fp_acc_wayback_pick`), so the check can test it. For each point and endpoint (`change_interval`) it takes the release whose capture date is nearest the endpoint. Ties go to the finer `SRC_RES`, then to the later release. An endpoint with no capture gets a row with an empty source.
- [ ] Write `reference/<area>/wayback.csv`: `point_id`, `stratum`, `cell`, `map_class`, `endpoint`, `release_id`, `release_date`, `capture_date`, `src_res`, `source`, `years_from_endpoint`. It lists every point at both endpoints, is regenerated and never hand-edited, and copies the design columns.
- [ ] Print the distribution of capture distance from each endpoint (same year, ±1, ±2, further).

## Phase 3: Build: `scripts/landcover_accuracy/wayback_build-chips.R <area>`
- [ ] Refuse unless `wayback.csv` lists exactly `sample.gpkg`'s points and passes `fp_acc_design_check`, the same guard as `imagery_build-dated.R`.
- [ ] Fetch one chip per point per endpoint from its chosen release, about ±150 m at the deepest available zoom, into `<project>/dated/wayback_<year>/<review_id>.tif`.
  - Files are named by `review_id` (from `review_key.csv`), **never** `point_id`.
  - Tiles go in a GDAL cache outside the project, so a re-run fetches nothing new and an existing chip is kept.
- [ ] Write `<project>/dated/wayback_<year>.vrt` over that year's chips, warped to EPSG:3005. Count what the VRT holds, report failures and points left with no chip, and sweep stale `wayback_*` files.
- [ ] `REVIEWER=b` needs nothing new: `review_build-qgis.R` already hard-links the whole `dated/` tree with `fp_acc_link_tree`. Confirm the B project carries the chips.

## Phase 4: Review inputs and checks
- [ ] `review_build-qgis.R` and `cells.gpkg`:
  - add read-only display columns `capture_<first>` / `capture_<last>` (e.g. "2017-06-11, 0.31 m") from `wayback.csv`, joined via the review key and checked against the design first;
  - rewrite `cells.gpkg` when those columns differ as well as when the id set does;
  - leave `labels.gpkg` alone.
- [ ] `review_build-qgis.R` layers:
  - extend `dated_name()`, the dated glob and the orphan regex to `wayback`;
  - name the layer and theme `<year> Esri capture (nearest per point)<endpoint tag>`, so it sorts beside that year's Sentinel-2 theme;
  - skip the layer if `wayback.csv` is stale, as is done for `imagery.csv`.
- [ ] `accuracy-check.R` arms, each with a must-fail:
  - the selection rule on toy metadata (nearest, both tie-breaks, an endpoint with no capture);
  - chip names carry no `point_id`;
  - `wayback.csv` passes the design and point-set check;
  - the `cells.gpkg` capture columns match `wayback.csv`.

## Phase 5: Run NECR, document, hand off
- [ ] Run the index, the build, and `review_build-qgis.R` on NECR, A and then B. Render a handful of chips to PNG and look at them. Record the capture-distance distribution and the run time in `scripts/landcover_accuracy/logs/<date>_wayback_necr.md`.
- [ ] Docs:
  - `research/landcover_accuracy.md`, "Dated reference imagery": Wayback release vs capture, the QGIS bug, and the `esri` form value;
  - CLAUDE.md #93 bullet: `wayback.csv`.
- [ ] Hand-off comment on rtj#377: the file pattern `dated/wayback_<year>.vrt`, the `cells.gpkg` columns, and that the release services and themes go. Note on rfp#398 that this is the drawable route. File the drift issue to promote to `dft_wayback_*`. All of these are our own repos.

## Validation
- [ ] `accuracy-check.R` green, every new must-fail shown red against the restored defect
- [ ] Live: on NECR point 1, the 2017 chip shows the 2017-06-11 capture (release 15045), cross-checked against the per-point `identify`
- [ ] Blind: grep the review project's file names for `[0-9]+_[0-9]{5}`; expect none
- [ ] `/code-check` clean per commit
- [ ] PWF checkboxes match landed work; `/planning-archive` on completion

