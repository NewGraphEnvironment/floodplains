# IO LULC accuracy inside our floodplains

**Verified:** 2026-09-29 · **Issues:** #93 (this work), #92 (report), #94 (review surface), #95
(wetland flag), drift#79 / drift#81 (composites, sampling + estimators) · **Produced by:**
`scripts/landcover_accuracy/` (logs under `scripts/landcover_accuracy/logs/`) · **Status:**
OPEN — criteria pre-registered; measurements and verdict below as they land.

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
