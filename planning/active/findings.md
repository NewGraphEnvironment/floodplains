# Findings — #93 windows + chips

## Issue context

> **Status (2026-09-29): phases 1–6 delivered in PR #101. Labelling, estimates and the verdict remain.** The criteria and their operational definitions were committed before any result (`research/landcover_accuracy.md`, the topic file for this issue). Measured so far: 2023 is the drought year and IO's change endpoint; IO misses 25.5% of qualifying clearcut, so **criterion 4 does not hold**; IO labels 0.3–0.9% of FWA wetland as Flooded Vegetation. The NECR pilot sample (450 points, 15 strata) is committed in `reference/necr/`, and the rfp review project is built by `review_build-qgis.R`. Two blockers and one side finding:
> - **Phase 2 (windows) is held on drift#92.** `aggregation = "count"` silently returns reflectance, so the recipe in phase 2 below does not work yet.
> - **2017 summer imagery is thin.** 5 of 15 test points had no usable July–August scene under 20% cloud, so the 2017 window needs measuring or HLS (drift#82).
> - **Side finding, filed as #100:** half of NECR's harvest-attributed tree loss lies outside any cutblock.
>
> **Remaining, in order** (all in `scripts/landcover_accuracy/`):
> 1. After drift#92: `Rscript window_count-clear.R necr validate`, then `caffeinate -s Rscript window_count-clear.R necr run`. Write `reference/necr/windows.csv` (columns `window,year,months`).
> 2. `caffeinate -s Rscript chip_build-composite.R necr` (~44 s per chip), then `Rscript review_build-qgis.R necr` to add the chip layers.
> 3. **Label** in QGIS: `data/necr/accuracy/review/necr_lulc_review/`, layer "Reference labels".
> 4. `Rscript labels_export.R necr` → commit `reference/necr/labels.csv`.
> 5. `Rscript accuracy_estimate.R necr`: error-adjusted areas with CIs, the four criteria and the verdict, and the full-sample size. Then raise `N` in `sample_draw-pilot.R`, keeping the seed so pilot labels carry over, and weight the extra points toward the stable strata.
> 6. Record the verdict in the research note, and add the numbers to the NECR report (#92).

## Problem

Every land-cover number this repo produces inherits the error of one external product, IO LULC, and **we have never measured that error where we use it.** That covers tree loss, the fire/harvest attribution split, the unattributed residual, and wetland change.

- IO LULC's published accuracy is a global, map-level figure. It says nothing about narrow BC floodplain corridors, and nothing about **change**. Change accuracy is usually far worse than map accuracy, because a change pixel needs both dates labelled correctly and a single wrong date manufactures a transition.
- So when NECR reports 46% of floodplain tree loss as "not attributed", we cannot say how much of that is real disturbance we have no layer for and how much is two mislabelled years.
- NECR's transition table has several classes that look like label confusion or acquisition timing, not change on the ground (patch counts from `transition_ch_ff04_2017_2023`, 2026-09-27):

| transition | patches | likely |
|---|---:|---|
| Trees ↔ Rangeland | 894 / 716 | shrub, regen and open-canopy boundary |
| Crops ↔ Rangeland | 429 / 424 | hay and pasture vs grassland |
| Crops ↔ Trees | 481 / 415 | ? |
| Snow/Ice → Rangeland | 93 | snow at acquisition |
| Flooded Vegetation → Rangeland / Water | 104 / 71 | drought, season, or water level |
| any ↔ Water | ~1,000+ | real channel migration vs stage at acquisition |

This is **not only a drought or wetland question.** The wetland case (#92) is one stratum of a general one: how right is the landcover under all of our analysis?

That measurement also answers a bigger question: **is it worth classifying land cover ourselves?** We can only make that case with numbers. That means IO's error-adjusted accuracy on our targets, set against what a local classifier would need to beat.

## What lives where

This repo's rule is that methods live in packages and this repo is only the driver. Split accordingly (revised 2026-09-28, after the first draft had floodplains doing the statistics):

| piece | home |
|---|---|
| dated composites (`dft_stac_composite()`), NDWI/MNDWI, RGB layers in `dft_map_interactive(rgb = )` | **drift#79, delivered in drift 0.17.1** |
| HLS as a second source | drift#82 |
| stratified point sampling, error-adjusted area and CIs, label contract | **drift#81** |
| Bing basemap | drift#78 |
| wetland `context:` flag on transition patches | #95 (delivered: `in_wetland` + `waterbody_poly_id`, necr and bulk re-tagged) |
| **strata** built from our layers (`in_fire`/`in_harvest`, wetland flag, bridge), composite windows, **stored labels**, fire/harvest omission check, the report, the classify-ourselves criteria | **this issue** |

> **drift#81 as delivered (2026-09-29, PR pending):**
> - `dft_accuracy_sample(strata, n, seed, map =)`. `strata` is a **raster** of integer codes. Build the cause/wetland/stable strata as a raster on the transition grid: rasterise in memory, then `mask()` to the map footprint, as the roxygen shows. `map =` writes `map_class` (or `map_<year>` for a series) at every point. The output's `$strata` carries the weights, and `$design` carries the seed, RNG kinds and grid; commit both with `sample.gpkg`.
> - **Pilot → full sample:** keep the same seed and raise `n`. Each stratum's first points are the pilot's, so the pilot labels carry over.
> - Labels need `point_id`, `stratum`, `map_class` and `ref_class` (`dft_accuracy_labels()`). For change, `ref_class = ref_from * 1000 + ref_to`. Blank or NA labels are refused as nonresponse, and `use == "training"` rows are refused.
> - `dft_accuracy_estimate(labels, s$strata)` gives `$area` in ha with CIs, `$accuracy`, a long `$matrix`, and a `$stratum` table. Union targets (all tree loss, the unattributed residual) are recode-then-estimate.
> - `dft_accuracy_size(weights, se_target, s_h = <pilot $stratum sd for the target>)` sizes the full sample.
> - Caution measured on the drift tiles: a rare class inside a large stable stratum gives CIs that run narrow at around 25 points per stratum. Do not starve the stable strata; omission hides there.

### 1. Build dated reference imagery we control

IO LULC and Esri/Google/Bing all share one problem: we don't know when, or in what season, what we're looking at was captured. The reference has to be **dated composites for windows we choose**:

- **Sentinel-2 L2A via Planetary Computer** (10 m, no login, and the same sensor IO LULC is built from). Built: `drift::dft_stac_composite()` returns dated, cloud-masked median composites of any bands, for chosen months, cached as COGs. For review, call it **once per buffered sample point** (small chips, each cached on its own), as drift documents. A floodplain-wide composite streams the whole bbox (drift#88: a 3-hour read that then failed).
- **HLS via Earthdata** (30 m, from 2013, 2–3 day revisit; drift#82). Use it for a pre-2017 baseline and for seasonal density within a year.
- **Standard windows:**
  - the same season in every year, so season is held constant
  - early vs late season within one year, so we can see normal seasonal amplitude
  - the IO endpoint years 2017 and 2023, plus the drought years
- **Indices from the same cubes:** `ndmi` for moisture, and NDWI/MNDWI for water and wetness (drift#79).
- Esri/Google stay as undated high-resolution context. They are useful for "what is this?", and useless for "when did it change?".

The composite building and RGB display are **drift's job** (method in packages; drift#79, delivered). This repo configures windows and targets.

### 2. Stratified reference sample, not a browse

Reviewing patches that look interesting measures our curiosity, not the map. Use the standard design for land-change accuracy (Olofsson et al. 2014, *Good practices for estimating area and assessing accuracy of land change*, RSE 148). The sampler and the estimators are **drift#81**. This repo defines the strata and calls them:

- **Sample points, not patches.** Picking whole patches favours big ones, and area is what we report.
- **Strata come from the map:**
  - change attributed to fire or harvest
  - change unattributed
  - wetland-related change: `from/to == Flooded Vegetation`, or inside `fwa_wetlands_poly`
  - the confusion-prone transitions in the table above
  - **stable land**, including stable land inside FWA wetlands. Without it we can measure commission (false change) but never omission (change IO missed).
- **Pilot on NECR at roughly 30 points per stratum** to get variance estimates. Size the full sample from those.

### 3. Free reference we already hold

- **Known change:** the fire and harvest polygons are independent evidence that change happened. Inside the floodplain and window, the share of each polygon's area that IO labels as tree loss is a direct omission estimate, and it costs no review time. Caveats: partial cuts, `harvest_start_year_calendar` vs actual removal, and fires that burned without replacing the stand.
- **FWA wetlands** as a mapped-wetland reference for how IO labels a known wetland (Flooded Vegetation, Rangeland or Trees), independent of change.

### 4. A review tool that records labels as data

**QGIS first:** a project with the sample points in a gpkg and a constrained attribute form (value maps, so reviewers pick classes rather than type them). The dated composites load as local COGs and Esri/Google as XYZ layers. A collaborator-friendly surface that needs no GIS install (Mergin, leaflet + CSV, or a web form) is #94, built after the NECR pilot has exercised the form.

- For each sample point: a map zoomed to the point, the dated composites as switchable layers, IO's label for every year, and the patch's `in_*` flags.
- The reviewer records:
  - the reference class at each endpoint
  - change yes/no
  - confidence
  - which imagery settled it
  - a free-text note
- **Labels are committed data** (keyed by sample id and point, plus reviewer and date), so every accuracy number regenerates from them. They go in the per-WSG report (#92) the way `fig/attribution.png` does.
- Keep the **accuracy sample separate from any training data.** If this goes on to a local classifier, labels used to train it cannot also measure it. Decide the split before anyone labels anything.

### 5. Error-adjusted numbers

Computed by drift#81's estimators from our labels. Per stratum and overall, report:

- user's and producer's accuracy
- **error-adjusted area with confidence intervals** for tree loss, the unattributed residual, and wetland change

That turns "we map 1,942.6 ha of tree loss" into "X ± Y ha". It is the number a reader actually needs, and the one that decides whether the attribution residual means anything.

### 6. Decide the classify-ourselves question on criteria set in advance

**Before looking at results,** write down what would justify a local classification. **Adopted 2026-09-28** as the starting set. They are committed first on the branch and editable in PR review, still before any result exists. Pilot a local classifier if **any two** hold:

1. Flooded Vegetation producer's accuracy < 0.5
2. The 95% CI half-width on error-adjusted unattributed tree loss is > 50% of its estimate
3. The Trees→Rangeland stratum's user's accuracy is < 0.6
4. IO misses > 30% of in-window stand-replacing harvest area (from the free-reference check in move 3)

Setting the bar afterwards makes the result argue for whatever we already wanted. If the criteria are met, the local classifier is a drift issue: Sentinel-2/HLS composites, terrain, and FWA wetlands as covariates, trained on a held-out label set. **This issue delivers the evidence, not the classifier.**

## Decisions (settled 2026-09-28)

- **Sampling unit: points**, in drift#81.
- **Labels live in `reference/<wsg>/`, committed in this repo.** They are inputs, like `config/`, and every accuracy number regenerates from them. They are public through Pages, which is fine for point labels.
- **Review surface: QGIS project + gpkg form** to begin with. The collaborator-facing surface is #94.
- **Composite windows and drought years are measured, not chosen by hand** (phases 2–3 below).

## Phases (for `/planning-init`)

Revised 2026-09-28 from the `/planning-init 93` exploration. Criteria come first because the free-reference checks are already results.

1. **Pre-registered criteria.** Write move 6's criteria into `research/landcover_accuracy.md` and commit them before any measurement below runs.
2. **Windows, measured.**
   - Count clear observations per month over the NECR `ch_ff04` floodplain (396.5 km², 89 × 61 km bbox, EPSG:3005) with `drift::dft_stac_composite(bands = "red", aggregation = "count", res = 100, months = m, years = 2017:2023, clip = TRUE)`. The SCL mask is applied before aggregation, so the count is clear observations per pixel.
   - **Validate on one month first**: against a finer `res` over a small sub-AOI, and against the scene-level `eo:cloud_cover` item count, which stays as a cheap cross-check.
   - "Same season" is the month span with clear coverage in every year. Also record one early and one late window in a single year, for the normal seasonal amplitude.
3. **Drought years, measured.** The earlier premise here was wrong.
   - The only active gauge inside NECR is **08JC001 Nechako at Vanderhoof, and it is regulated** (Kenney Dam releases), so its low flow measures reservoir operations, not drought.
   - Use **unregulated reference gauges within 80 km** instead:
     - 08KC001 Salmon R near Prince George (4,230 km²)
     - 08JB002 Stellako at Glenannan
     - 08JE004 Tsilcoh near the mouth (431 km²)
     - 08KG001 West Road near Cinema
     - 08JB003 Nautley and 08JE001 Stuart, both lake-buffered, reported but weighted as such
   - **Refresh HYDAT first.** The local copy is the 2024-04-16 release, where most of these gauges end in 2022. The 2026-07-17 release is available. `tidyhydat::download_hydat()` replaces the shared local database, which is a machine change and is stated as such.
   - Metric: August–September mean flow per year against each gauge's long-term record. State which of 2017–2023 fall in the lowest quantile at most gauges.
   - Record phases 2–3 in `research/landcover_accuracy.md` with the script and log prefix.
4. **Free reference** (results, so they run after phase 1):
   - Fire/harvest omission: the share of each in-window polygon's floodplain area that IO labels as tree loss, with move 3's caveats beside the number. This feeds criterion 4.
   - How IO labels mapped wetlands: per-year class composition inside `fwa_wetlands_poly` within the floodplain. This is an overlay of the **classified rasters** with the wetland polygons, not #95's flag: `in_wetland` sits on **changed** patches only (step 3 vectorizes `changes_only = TRUE`), so it cannot describe stable land.
5. **Strata and sample (needs drift#81; #95 delivered).** Build change strata from the transition layer, the cause flags and `in_wetland`. **Causes are exactly the names under `sources:` in `config/disturbance.yml`, never "every `in_*` column"**: `in_wetland` is context and would be misread as a cause by a generic `in_*` rule. Stable strata, including stable land inside FWA wetlands, come from the classified rasters plus `fwa_wetlands_poly` directly, for the same changed-patches-only reason as phase 4. Draw the NECR pilot at about 30 points per stratum and write `reference/necr/sample.gpkg` with weights.
6. **Review setup.** Build a `dft_stac_composite()` chip per buffered sample point for the phase-2 windows, then the QGIS project and form (#94 takes it to collaborators later).
7. **Label the pilot.** A human labels here; the automated work stops at "sample and project ready". Then run drift#81's estimators, report the error-adjusted numbers in the NECR report (#92), size the full sample from the pilot variance, and record the verdict against the phase-1 criteria.

## Acceptance

- NECR has a committed stratified reference sample with labels.
- The NECR report states error-adjusted tree loss, unattributed residual and wetland change with confidence intervals, regenerated from the labels.
- The fire/harvest omission estimate is computed from existing polygons.
- A short research note (`research/landcover_accuracy.md`, a topic file revised in place, #86) records the criteria from move 6 (phase 1) **before** the results, and then the verdict.

Relates: #92 (report), #95 (wetland flag), #94 (collaborator review surface), drift#78 (Bing), drift#79 (composites), drift#81 (sampling + estimators)








## Exploration (2026-09-30)

- drift#92 closed by drift PR #97 → drift 0.20.0. `aggregation = "count"` is now distinct clear
  days per pixel (P1D steps, same-day MGRS tiles once), INT2U COG `count_<key>.tif`, NA = no clear
  day, snow masked. Skip warning text unchanged (`Skipping the {label} composite: {why}.`).
- Installed drift 0.19.0 at start.
- drift#88 (floodplain-wide composite 3 h read then fail) is OPEN; that was 10 m + tile_size.
- Previous branch archive: `planning/archive/2026-09-issue-93-lulc-accuracy-pilot/`.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `grep` returned nothing / "ugrep: warning" on a file that has the string | `grep` is shadowed by ugrep in this shell; use `/usr/bin/grep` or python |

## Validate (2026-09-30)

res 100 = res 20 (median 5); max 6 = distinct dates 6 of 17 items; floodplain-wide 2021-07 in
0.8 min, share >= 1 clear day 0.9996. Log `scripts/landcover_accuracy/logs/20260930_window_count-clear_necr_validate.md`.

## /code-check

- Round 1: `months` read back as integer when every `windows.csv` row is a single month (fixed:
  colClasses). Two rule gaps: 2017's span never counted directly, and the tie-break missing from
  the prose. Both fixed, with the prose amendment noted before any result was read.
- Round 2: gdalcubes chunk failures are invisible (drift#87, upstream). The documented log-grep
  step was added.
- Round 3: inside round 2's fix, the grep did not cover derive or cache-filling logs, and there
  was no `force` path (fixed: FORCE=1 and the header procedure). Terminal enumeration in
  `review-enumeration.md` (13 sites).
- Live log: 2017-04, 2017-05 and 2017-07 returned 0 items (`empty`). 2017 will need the
  widening.
