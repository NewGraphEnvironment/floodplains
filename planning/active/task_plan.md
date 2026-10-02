# Task: Dated orthophotos and air photos as review themes, and prior-fire regrowth attribution (#103)

## Problem

#93's review project (PR #102) gives the reviewer two kinds of imagery. Sentinel-2 chips are dated but coarse (10 m). Esri, Google and Bing are sharp but undated. We hold two dated, higher-resolution sources and use neither:

- **BC orthophotos** via our private orthophoto STAC (endpoint in `FP_ORTHO_STAC`; never named here — this repo is public).
- **Historic air photos**, through the `fly` package: `fly_select`, `fly_footprint`, `fly_overlap`, `fly_coverage`, `fly_fetch`, `fly_georef`.

Separately, **fire attribution is windowed to the change interval** (`cfg$change_interval`, 2017–2023). A fire a few years *before* 2017 (say 2010–2016) explains post-fire **regrowth** inside the window: Rangeland or Bare → Trees, and shrub transitions. Today that regrowth lands in "not attributed".

Approved plan (2026-10-01 plan gate): lookback list not a cause; 15 yr; one stratum "change in prior fire"; digital air photo themes now, film after fly#53; windows.csv unchanged.

## Phase 0: Issue hygiene
- [x] Edit #103's body:
  - remove the private repo name and endpoint, and say "our private orthophoto STAC";
  - record the measured numbers and the decisions above;
  - correct the premise: prior fire bears on tree *loss* (criterion 2) as well as regrowth, and the lookback is deliberately not a cause.
- [x] Note in the final report that GitHub's edit history still shows the old text.

## Phase 1: Prior fires into fwapg
- [x] Add `scripts/floodplain_lcc/fire_load-prior.sh`, which runs `bcdata bc2pg --append --query "FIRE_YEAR < 2017"` into `whse_land_and_natural_resource.prot_historical_fire_polys_sp`. The header carries the BCDC record and states why it appends rather than refreshes.
- [x] Guard: take an md5 over the ordered in-window rows (`fire_year >= 2017`: `fire_number`, `fire_year`, `ST_AsBinary(geom)`) before and after. Refuse if they differ.
- [x] Take a `disturbance-check.R` live snapshot of necr before loading.
- [x] Run the load and record the row counts by year band in `findings.md`.
- [x] Update the `config/disturbance.yml` comment on what the table holds.

## Phase 2: A `lookback:` list in the disturbance framework (`fp_disturbance.R`)
- [x] `fp_disturbance_validate()`:
  - accept a new top-level `lookback:` list;
  - an entry needs `year_col` and a positive integer `lookback:` in years, and may not carry `window`;
  - add `lookback` to `FP_DST_ENTRY_KEYS`.
- [x] Carry aliasing: `carry:` may be a map `{source_col: patch_col}` (e.g. `fire_year: fire_prior_year`). Collision and ownership checks run on the **patch** names, case-folded. A plain list keeps working unchanged.
- [x] `.dst_query()`:
  - emit `col AS alias`;
  - for a lookback entry, the window is `[start - lookback, start - 1]`, derived from the change interval passed in, so it follows `cfg$change_interval`.
- [x] The tagger writes `in_<name>` plus the aliased carries for lookback entries. Rows are still joined by position.
- [x] Config entry: `lookback: [{name: fire_prior, table: <fire table>, year_col: fire_year, lookback: 15, carry: {fire_year: fire_prior_year, fire_number: fire_prior_number}}]`.
- [x] Plumbing:
  - step 3 (`03_lulc_classify.R`) and `fire_tag.R` pass `cfg$lookback_overlays` to the tagger. The name is deliberately not a `disturbance_*` prefix, because `$` partial-matches.
  - `fire_tag.R` treats lookback columns like context: they are never cause columns.
- [x] `fp_disturbance_report()`: causes are unchanged. Add one informational line, "of the residual, X ha lies in <lookback>". It never counts as explained.
- [x] `disturbance-check.R` offline arms, each with a must-fail:
  - a lookback entry with `window` is refused;
  - a lookback entry with no `year_col` is refused;
  - an alias that collides with a cause carry or a patch column is refused;
  - the SQL emits `AS` and `BETWEEN 2002 AND 2016`;
  - a lookback never reaches the report's explained share;
  - the cfg prefix sweep covers `lookback_overlays`.

## Phase 3: Re-tag NECR and the data contract
- [x] Run `fire_tag.R necr`. Cause columns must not move (no `FORCE`). Run the `disturbance-check.R` live comparison against the Phase 1 snapshot.
- [x] Record `in_fire_prior` patch counts and ha in `findings.md`. Other areas pick it up forward-only, on their next step 3.
- [x] Schema: added a "lookback columns are context, not attribution" section to the existing spec issue stac_floodplains_bc#6 (body edit, not a new issue; #6 already owns carrying disturbance into the schema). The coupling stays one-way.

## Phase 4: The "change in prior fire" stratum and the NECR redraw
- [x] `fp_accuracy.R`:
  - add stratum **19 "change in prior fire"**, kind `change`, ranked directly after the cause strata;
  - `fp_acc_strata()` gains a `prior` argument, a 1/NA cell-level raster (`fp_acc_fetch` with the lookback window), with NO stray-cell guard -- the polygons cover stable/sieved land, so `chg & !is.na(prior)` like wetland (plan review B1);
  - stratum 19 is present only when the area configures a lookback.
- [x] `sample_draw-pilot.R`:
  - fetch the lookback polygons cell-level;
  - each point carries `in_fire_prior_poly`;
  - `design.json` records the lookback (name and window).
  - Check how drift handles an empty stratum.
- [x] `accuracy-check.R` arms:
  - precedence: a cause wins over prior, and prior wins over the transition-class strata;
  - a prior cell on stable/sieved land never takes 19 (replaces the stray-guard arm, per plan review B1);
  - each arm has a must-fail.
- [x] Confirm `labels.gpkg` holds 0 labels and no `labels.csv` exists. Then redraw necr with the same `SEED` and `N`, and commit `sample.gpkg`, `strata.csv` and `design.json`.
- [x] `research/landcover_accuracy.md`: add a dated amendment to "Strata" stating that it was made before any label. The pre-registered criteria are not touched.

## Phase 5: Per-point dated imagery index
- [x] `scripts/landcover_accuracy/imagery_index-dated.R <area>`:
  - **Ortho:** rstac search over the sample bbox, paginated, endpoint from `FP_ORTHO_STAC`. Fail loudly if it is unset. Join item footprints to points.
  - **Air photos:** BCDC centroids over the buffered sample bbox → `fly::fly_footprint(dem = flooded::fl_dem_aoi(...))`, so digital frames get sized → `st_join` to points.
- [x] Write `reference/<area>/imagery.csv` with one row per (point, source, epoch): `point_id, source, epoch, year, date, gsd_m, media, scale, n_images, airp_id` (air photo only, public ids). No ortho hrefs or ids.
- [x] Print per-epoch coverage and which epochs earn a theme: those covering **≥ 25% of points**, and for air photos only digital media.
- [x] Append `FP_ORTHO_STAC=<endpoint>` to `~/.Renviron`, the only machine change. The repo documents the variable name only.

## Phase 6: Imagery layers and map themes in the review project
- [x] `scripts/landcover_accuracy/imagery_build-dated.R <area>` writes into the project directory, which is gitignored:
  - **Ortho:** one VRT per themed epoch over the `/vsicurl/` COG tiles covering the points.
  - **Air photos:** per themed digital epoch, per point the nearest covering frame that georeferences, with `fly_georef` given the year's FULL frame set so every frame has its roll neighbours for a bearing (the first build passed only the fetched sample and lost 87 of 250 frames; fly#88 filed then withdrawn as a caller error): 250/250 frames, 480/480 points → `fly_fetch(type = "thumbnail")` + `fly_georef()` → one VRT per epoch. Ortho VRT is WARPED to EPSG:3005 (tiles are UTM 10 / EPSG:3157, which rfp refuses).
- [x] `review_build-qgis.R`:
  - add the dated layers to a "Reference imagery - dated" group;
  - create a base **"Review"** theme (labels, patches, wetland and lakes), plus **one theme per imagery layer** (each S2 window-year, Ortho 2021, Airphoto 2012…), rewritten every run with `rfp_qgs_theme_set()` (no base theme exists to `theme_create` from -- plan review);
  - rebuild `patches.gpkg` when its columns lag the source layer.
- [x] Add `orthophoto` and `airphoto` to `FP_ACC_IMAGERY` and to the `labels_form.qml` value map, keeping them consistent with `accuracy-check.R`.
- [x] Rebuild the necr review project: old project moved aside to `necr_lulc_review_pre103` (0 labels), chip cache carried over, rebuilt, dated imagery built, themes checked in the XML.
- [ ] Re-chip finishes (`chip_build-composite.R necr`, started 2026-10-02 07:44 UTC, ~3.4 h), then `review_build-qgis.R necr` once more to add the S2 layers + their themes.

## Phase 7: Docs
- [x] `research/landcover_accuracy.md`:
  - dated imagery sources and coverage;
  - why `windows.csv` is unchanged;
  - film air photos are waiting on fly#53.
- [x] `CLAUDE.md`:
  - a bullet on the lookback list, alongside #95's causes/context;
  - the env var and the privacy rule;
  - fix the "fire table" facts.
- [x] README check (`readme_content-check.py`) still passes; the figure is unchanged because it reads `sources:` only.

## Validation

- [x] Tests pass (disturbance-check, accuracy-check, provenance-check, region_config-check, README determinism + content)
- [x] `/code-check` on each code commit (phase 2: 3 rounds; phases 4-6: 3 rounds + closing enumeration; phase 1's shell script was reviewed inside phase 2's rounds)
- [x] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
