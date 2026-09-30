# IO LULC accuracy inside our floodplains

**Verified:** 2026-09-29 · **Issues:** #93 (this work), #92 (report), #94 (review surface), #95
(wetland flag), drift#79 / drift#81 (composites, sampling + estimators); spawned #100 (patch-level
harvest attribution) and drift#92 (clear-observation counts) · **Produced by:**
`scripts/landcover_accuracy/` (logs under `scripts/landcover_accuracy/logs/`) · **Status:**
OPEN — criteria and definitions pre-registered; drought years and free reference measured
(criterion 4 does not hold); NECR pilot sample and review project ready; composite windows held on
drift#92; **verdict pending human labels.**

Every land-cover number this repo publishes — floodplain tree loss, the fire/harvest attribution
split, the unattributed residual, wetland change — inherits the error of one external product, IO
LULC (Impact Observatory 10 m annual land use / land cover), and that error has never been measured
where we use it. IO's published accuracy is global and map-level. It says nothing about narrow BC
floodplain corridors and nothing about **change**. A change pixel needs both dates labelled
correctly, so a single wrong date manufactures a transition.

The measurement follows Olofsson et al. (2014), *Good practices for estimating area and assessing
accuracy of land change* (RSE 148, 42–57): a stratified random sample of **points**, strata taken
from the map, reference labels from dated imagery we control, and error-adjusted area with
confidence intervals. The sampler and estimators live in drift (`dft_accuracy_*`, drift#81). This
repo builds the strata, the imagery windows, the stored labels and the verdict.

## Pre-registered criteria for classifying ourselves

**Committed before any measurement in this file was run** (adopted in #93 on 2026-09-28, and
editable only in the review of the PR that first commits them, still before any result exists).
Setting the bar after seeing results would make the result argue for whatever we already wanted.

Pilot a local classifier if **any two** of these hold:

1. Flooded Vegetation producer's accuracy < 0.5.
2. The 95% CI half-width on error-adjusted **unattributed** tree loss is > 50% of its estimate.
3. The Trees→Rangeland stratum's user's accuracy is < 0.6.
4. IO misses > 30% of in-window stand-replacing harvest area (from the free-reference omission
   check below, which needs no labelling).

If they are met, the local classifier is a drift issue: Sentinel-2/HLS composites, terrain and FWA
wetlands as covariates, trained on a **held-out** label set. This work delivers the evidence, not
the classifier.

### How each criterion is computed

**Pinned 2026-09-29, before any phase 4 or phase 5 result existed** (a review of the plan found the
criteria above had no mechanical definition). Everything here is read from
`drift::dft_accuracy_estimate()` on the committed labels. Class codes are IO's (1 Water, 2 Trees,
4 Flooded Vegetation, 5 Crops, 7 Built Area, 8 Bare Ground, 9 Snow/Ice, 11 Rangeland), and a
transition is `from * 1000 + to`.

1. **Flooded Vegetation producer's accuracy**, estimated **per endpoint**:
   - `map_class = map_2017`, `ref_class = ref_from`
   - `map_class = map_2023`, `ref_class = ref_to`

   `$accuracy`, measure `producer`, class `4`. The criterion holds if the estimate is < 0.5 at
   **either** endpoint, since an error at either date corrupts every transition built on it. The
   sample is stratified by transition, not by year class. Stehman's estimator (which drift uses) is
   valid when the strata are not the map classes.
2. **Unattributed tree loss.** Recode, then estimate:
   - **Map side:** the reported transition is Trees→non-Trees **and** the point is not in a cause
     stratum.
   - **Reference side:** `ref_from == 2 & ref_to != 2` **and** the point's cell lies inside no
     windowed cause polygon (`in_<cause>_poly`, cell level, taken from the `sources:` tables).
   - The criterion holds if `z × area_se / area > 0.5` for that class at the 95% level.
3. **Trees→Rangeland user's accuracy** = `$accuracy`, measure `user`, class `2011`, on the reported
   transition map. This is the **map class**, not within-stratum agreement, so it does not depend
   on the order of the strata. The criterion holds if the estimate is < 0.6.
4. **Harvest omission** = the IO-view number from the free-reference check below. The criterion
   holds if it is > 0.30.

### Free-reference omission (criterion 4), defined before it is computed

- **Qualifying harvest:**
  - `data_source` in (`RESULTS`, `VRI`). "Satellite Imagery - Change Detection" (18% of the table)
    is excluded, because it is optical change detection and so not independent of IO.
  - `percent_clearcut >= 90`, as the stand-replacing proxy.
  - `harvest_start_year_calendar` in 2018–2022 and `harvest_end_date` ≤ 2022-12-31 (not null).
  - Together these mean the stand was standing for IO's 2017 map and removed before its 2023 map.
- **Qualifying fire:** `fire_year` 2018–2022. There is no severity field, so "burned" is not
  "stand-replaced". That is a caveat, not a filter.
- **Denominator:** the floodplain footprint ∩ `classified_2017 == Trees` ∩ the **dissolved union**
  of qualifying polygons, so that overlaps count once.
- **Numerators**, both reported:
  - **IO view**, which feeds criterion 4: `classified_2023 != Trees`, unsieved. This is what "IO
    misses" means.
  - **Published view:** `transition.tif` Trees→non-Trees, after the 1 ha sieve.
- Omission is `1 − numerator / denominator`, pooled and area-weighted. Per-polygon values are
  supplementary.
- **Caveats beside the number:**
  - Cutblocks include retained riparian reserves, and the floodplain ∩ cutblock intersection is
    disproportionately riparian. That inflates apparent omission, which `percent_clearcut` only
    partly controls.
  - The start year is not the removal date.
  - Regrowth to Rangeland or Crops by 2023 counts as detected. Regrowth to Trees counts as missed.

### Strata

- **Population:** the whole floodplain footprint (`classified_2017` non-NA). It is **not**
  `transition.tif`, where step 3's 1 ha sieve set 18% of IO's change cells in NECR to NA.
- **Sieved change** is a stratum of its own, and its map claim is "no change". Omission of the
  published map hides there.
- **Wetland** is decided per **cell** (a Flooded Vegetation endpoint, or a cell inside
  `fwa_wetlands_poly`), and the same way for change and stable land. The patch flag `in_wetland`
  is any-touch and would take 78% of Trees→Rangeland into the wetland stratum.
- **Causes** are the names under `sources:` in `config/disturbance.yml`, taken in that order. They
  use the published patch flags, because that is the attribution the report states.

## Free reference: results

**Verified:** 2026-09-29 · **Produced by:** `scripts/landcover_accuracy/reference_omission-disturbance.R`
and `reference_composition-wetland.R`, logs `scripts/landcover_accuracy/logs/20260929_reference_*_necr.*`.

### Omission of known disturbance

These are computed exactly as defined above. The breakdown is **per start year** rather than per
polygon (79 polygons, most under 1 ha of floodplain Trees). That is a reporting choice and changes
nothing in the criterion.

| source | polygons | IO Trees 2017 inside (ha) | IO omission | published omission |
|---|---:|---:|---:|---:|
| harvest (clearcut ≥ 90%, RESULTS/VRI, 2018–2022) | 79 | 92.1 | **0.255** | 0.411 |
| fire (2018–2022) | 3 | 635.2 | 0.314 | 0.329 |

- **Criterion 4 does not hold.** IO labels 74.5% of qualifying harvest area as tree loss by 2023,
  so it misses 25.5%, under the 30% bar. The annual rows range 0.20–0.33, over 12–24 ha each.
- **The sieve costs more than IO does.** The published map misses 41.1% of the same harvest area,
  so step 3's 1 ha sieve adds 16 points of omission on top of IO's. That is a property of our
  product, not of IO, and it is the reason the stratified sample carries a sieved-change stratum.
- The denominator is small. NECR's floodplain holds only 92 ha of qualifying clearcut that IO saw
  as Trees in 2017, so this is a census of a small population, not a precise rate. Nearly all of
  the fire row is the two 2018 fires.
- Caveats, as defined: riparian reserves inside cutblock polygons inflate apparent omission;
  start year is not removal date; regrowth to Trees by 2023 reads as missed.

### How IO labels a mapped wetland

Inside FWA wetlands, per cell centre: 1,122 polygons touch the floodplain, covering 6,436.6 ha of
the 41,838 ha footprint.

| IO class | 2017 | 2018 | 2019 | 2020 | 2021 | 2022 | 2023 |
|---|---:|---:|---:|---:|---:|---:|---:|
| Trees | 0.583 | 0.568 | 0.508 | 0.565 | 0.527 | 0.552 | 0.518 |
| Rangeland | 0.340 | 0.350 | 0.412 | 0.349 | 0.387 | 0.380 | 0.411 |
| Crops | 0.052 | 0.057 | 0.058 | 0.058 | 0.056 | 0.047 | 0.049 |
| Water | 0.012 | 0.018 | 0.017 | 0.017 | 0.022 | 0.016 | 0.018 |
| Flooded Vegetation | 0.003 | 0.006 | 0.004 | 0.009 | 0.006 | 0.005 | 0.004 |

- **IO almost never calls a mapped wetland "Flooded Vegetation"**: 0.3–0.9% in every year. Treed
  swamp is legitimately Trees under IO's legend, so this is not an error rate by itself. It does
  mean that wetland change in IO terms is almost entirely **Trees ↔ Rangeland** movement inside
  wetlands, not a Flooded Vegetation signal. Criterion 1 (FV producer's accuracy) and criterion 3
  (Trees→Rangeland user's accuracy) are the two places the sample will test it.
- **The Trees/Rangeland split inside wetlands moves 7 points between years** (Trees 0.508 in 2019,
  0.583 in 2017), with nothing on the ground known to move it. Across the whole floodplain, Trees
  moves 3.5 points (0.411–0.445). That year-to-year flicker, 2× stronger in wetlands, is
  what a change map built from two single years inherits.

## Reference sample (NECR pilot)

**Drawn:** 2026-09-29 · **Produced by:** `scripts/landcover_accuracy/sample_draw-pilot.R`, log
`scripts/landcover_accuracy/logs/20260929_sample_draw-pilot_necr.md` · **Record:**
`reference/necr/{sample.gpkg,strata.csv,design.json}` · seed 930093, 30 points per stratum.

The 15 strata partition the 41,838 ha footprint exactly. The change strata sum to the 472,998
published change cells, and the sieved stratum holds the 104,947 cells the 1 ha sieve removed.
The design record redraws **byte-identical**.

| stratum | ha | weight |
|---|---:|---:|
| change: fire | 582.5 | 0.0139 |
| change: harvest | 621.5 | 0.0149 |
| wetland change | 950.5 | 0.0227 |
| Trees → Rangeland | 274.3 | 0.0066 |
| Rangeland → Trees | 532.7 | 0.0127 |
| Crops ↔ Rangeland | 1,319.1 | 0.0315 |
| Crops ↔ Trees | 178.8 | 0.0043 |
| Snow/Ice → any | 3.9 | 0.0001 |
| any ↔ Water | 132.7 | 0.0032 |
| other tree loss | 31.8 | 0.0008 |
| other change | 102.2 | 0.0024 |
| sieved change (<1 ha) | 1,049.5 | 0.0251 |
| stable wetland (FWA or Flooded Vegetation) | 5,198.5 | 0.1243 |
| stable Trees | 13,206.1 | 0.3156 |
| stable other | 17,654.1 | 0.4220 |

- **Cell-level causes are not the published attribution, and for harvest the gap is large.** 3 of
  the 30 fire-stratum points lie outside every fire polygon at cell level, but **17 of the 30
  harvest-stratum points** lie outside every cutblock. Measured over the whole grid, only 48.9% of
  NECR's harvest-attributed tree loss (287.8 of 588.9 ha) lies inside a qualifying cutblock. For fire
  it is 94.2%. Step 3 tags a patch with a cause if it touches the polygon anywhere, so half of the
  "harvest" credit is change beside a block. Filed as #100. Criterion 2 scores the reference
  against cell-level polygons for exactly this reason.
- **Stable strata are thin at 30 points.** drift measured a rare class hiding in a large stratum
  giving 95% intervals that cover 61% of the time at 25 points per stratum (drift#81). The stable
  strata hold 86% of the footprint and are where omission hides. The pilot keeps the allocation
  chosen at the plan gate. The full sample should raise the stable strata first: same seed, larger
  `n`, and the pilot's labels carry over.

## Review setup

**Verified:** 2026-09-29 · **Produced by:** `review_build-qgis.R`, `chip_build-composite.R`,
`labels_export.R`, `accuracy_estimate.R` in `scripts/landcover_accuracy/`.

- **Project.** `review_build-qgis.R` builds an rfp restoration-template project, which needs QGIS
  4.x, under `data/<area>/accuracy/review/` (gitignored). It holds the label layer with a
  constrained form (`reference/necr/labels_form.qml`), the published change patches, FWA
  wetlands and lakes, and the undated Esri/Google/Bing basemaps. Review layers are display copies
  in BC Albers, because rfp's templates carry no UTM layer. Identity is never taken from geometry.
- **Labels.** Labels are stored in IO's own class codes (`ref_from`, `ref_to`). "Cannot label" is a
  status, not a class. The committed record is `reference/<area>/labels.csv`, exported by
  `point_id` **and checked against the design** (stratum, cell, map class). A redraw keeps point
  ids but moves points, so id alone is not an identity. The export, the estimate, and a re-run of
  the project build all refuse labels made on another draw.
- **Chips cost about 44 s each.** Measured on 15 points × 2 windows: 30 chips in 22.1 min. The
  full pilot (450 points) at four windows would be 1,800 chips, roughly 22 h. That is a
  `caffeinate -s` background job, and the chips are built only once the windows are measured.
- **2017 summer imagery is thin.** Under the 20% scene-cloud filter, **5 of 15** test points had
  no usable July–August 2017 scene at all ("no scenes"). Only Sentinel-2A was flying, and 2017 was
  a heavy smoke year. The 2017 endpoint is the one every transition depends on, so the window
  measurement (drift#92) has to find a 2017 window that exists everywhere, or the review falls back
  to HLS (drift#82) for that year.
- **Estimation is wired end to end.** On synthetic labels (IO's own endpoints with 20% of `ref_to`
  flipped, `SYNTHETIC=1`) it returns the nonresponse table, error-adjusted areas with CIs for
  tree loss, unattributed tree loss and wetland change, the four criteria, and the full-sample
  size. Those synthetic numbers mean nothing and are never written to `reference/`.

## Accuracy labels and training labels never mix

Decided before anyone labels anything. Every point in the reference sample carries
`use = "accuracy"`, and `dft_accuracy_estimate()` refuses `use == "training"` rows. If criteria are
met and a local classifier is piloted, its training labels come from a **separate draw** with its
own seed. They are never taken from this sample, because a label that trains a classifier cannot
also measure it.

## Composite windows (measurement held)

**Held on drift#92.** The plan was to count clear Sentinel-2 observations per month with
`dft_stac_composite(aggregation = "count")`. drift 0.19.0 passes that value to gdalcubes'
`cube_view()`, which has no count, and returns red **reflectance** with no error: a median of
0.03–0.04 on a 2 km NECR test square, where a true count would be at most 17 (17 items over 6
dates). `scripts/landcover_accuracy/window_count-clear.R` now refuses a non-integer count, and the
guard fired on the live output. The windows get measured once drift can count.

## Drought years

**Verified:** 2026-09-29 · **Produced by:** `scripts/landcover_accuracy/drought_rank-gauges.R`,
log `scripts/landcover_accuracy/logs/20260929_drought_rank-gauges_necr.*` · HYDAT 2026-07-17.

The only active gauge inside NECR, **08JC001 Nechako at Vanderhoof, is regulated** (HYDAT flags it
from 1952; Kenney Dam releases). It ranks 2023 at the 45th percentile of its own record, so it would
have hidden the one drought in the window. The ranking uses unregulated gauges within ~80 km.
August–September mean daily flow per year is ranked against each gauge's full record (0 = driest).
"Low" means the lowest quintile at more than half of the four free-flowing gauges:

| year | free-flowing gauges in lowest quintile | median rank | lake-buffered (Nautley, Stuart) |
|---|---:|---:|---|
| 2017 | 0 / 4 | 0.35 | 0.47, 0.23 |
| 2018 | 2 / 4 | 0.21 | 0.28, 0.18 |
| 2019 | 1 / 4 | 0.52 | 0.29, 0.15 |
| 2020 | 0 / 4 | 0.85 | 0.76, 0.86 |
| 2021 | 1 / 4 | 0.31 | 0.25, 0.21 |
| 2022 | 0 / 4 | 0.62 | 0.83, 0.67 |
| **2023** | **3 / 4** | **0.14** | **0.03, 0.01** |

**2023 is the drought year, and it is IO's change endpoint.** Every NECR transition is measured
2017→2023, so any late-summer wetness signal (Flooded Vegetation, Water, wet meadow read as
Rangeland) compares an average year with a dry one. 2018 is borderline dry and 2020 is the wet
contrast. The reference windows therefore include 2017, 2023, 2018 and 2020. The wetland and
`↔ Water` strata are the ones to read in that light.
