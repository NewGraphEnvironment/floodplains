# Wayback coverage, BULK — 2026-10-23 (#145)

#145 step 1: before a BULK sample is drawn or a chip built, how near the 2017 and 2023 endpoints can Esri
Wayback see BULK's floodplain? Metadata only; no tile was fetched.

## Run

- `caffeinate -s Rscript scripts/landcover_accuracy/wayback_coverage-area.R bulk 1000`, started
  15:01:51Z, finished 15:59:25Z (57.6 min, almost all of it the 197 releases' metadata queries over
  BULK's bbox, which a re-run reads from drift's cache). drift 0.24.3.
- **Points:** 1,000 equal-probability random points over `all_ff04` (the primary scenario), seed 145. So
  each share below estimates a share of floodplain **area**; a 95% interval on a share near 0.37 is about
  ±0.03.
- **Pick:** `drift::dft_wayback_captures(zoom = 17:19)`, then `dft_wayback_pick()` toward 1 July of each
  endpoint. drift picks by days from that date, where NECR's `fp_acc_wayback_pick` picks by whole years
  first. With a mid-year anchor the two give the same whole-year band (a capture `k` years off is
  between `k - 0.5` and `k + 0.5` years away), so the bands compare.
- Output: `data/bulk/accuracy/wayback_coverage.csv` (gitignored), one row per point and endpoint. Every
  point had a capture at both endpoints.

## Result

| endpoint | same year | +/-1 year | +/-2 years | further | within +/-2 |
|---|---:|---:|---:|---:|---:|
| 2017 | 32 | 242 | 106 | 620 | 38.0% |
| 2023 | 53 | 264 | 34 | 649 | 35.1% |

- **Both endpoints within +/-2 years: 15.7%** of the floodplain; exactly one 41.7%, neither 42.6%. 27.6% (276 points) has the same capture at
  both endpoints, so Wayback dates at most one side of any change there: one side at 92 of them, neither
  at 184.
- **2017's gap is 2014.** 449 of the 2017 picks are 2014 captures, 3 years early, so no release shows
  those points between 2015 and 2019.
- **2023's gap is a missing recent flight.** 264 picks are 2022 (-1), but 375 are 2020 (-3) and 258 are
  2010-2016 (-7 to -13): a quarter of the floodplain has no capture newer than 2016 in any release. The newest
  capture at any sample point is 2025-06-10.
- Resolution 0.31-0.6 m (median 0.5 m at 2017, 0.46 m at 2023). Zoom 17 serves 755 of the 2017 picks and
  zoom 18 serves 936 of the 2023 picks; zoom 19 serves none.

## Against NECR

NECR's sample had a capture within +/-2 years of 2017 at 349 of 480 points (73%) and of 2023 at 365
(76%) (`research/landcover_accuracy.md`, "Esri Wayback captures nearest each endpoint"). Those points are
a stratified sample, not area-random, so the two are not the same estimate. Per endpoint the gap is
about double: BULK's Wayback dates an endpoint for roughly a third of its floodplain, against
three-quarters of NECR's sample. Both endpoints: 56.2% of NECR's points (270 of 480) against 15.7%.
Neither: 7.5% (36) against 42.6%.

## What it decides

- At each endpoint, most of BULK's floodplain (62% at 2017, 65% at 2023) has no Wayback capture within
  +/-2 years; 42.6% has none at either endpoint, 41.7% at exactly one. Only Wayback was measured. The
  other dated sources (BC orthophotos and air photos, `imagery.csv`, #103) are not indexed for BULK, and
  in NECR the 2021 orthophoto covers 204 of 480 points. So where Wayback is far, Sentinel-2 dates that
  side unless an orthophoto or air photo does. Rule 5 caps a label on an undated or far source; unless
  those sources make up the gap, expect a lower share of high and medium confidence than NECR's, and size
  the BULK design (#145 step 2) with that in mind. Indexing BULK's orthophoto and air photo coverage
  belongs with that design.
- Where both endpoints are within +/-2 years (15.7%), Wayback can confirm a change. Elsewhere it dates
  at most one side.
