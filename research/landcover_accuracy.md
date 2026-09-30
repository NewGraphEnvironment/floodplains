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
