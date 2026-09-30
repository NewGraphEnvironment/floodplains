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
