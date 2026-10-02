# IO LULC accuracy inside our floodplains

**Verified:** 2026-10-02 · **Issues:** #93 (this work), #92 (report), #94 (review surface), #95
(wetland flag), #103 (prior-fire stratum, dated imagery), drift#79 / drift#81 (composites, sampling + estimators); spawned #100 (patch-level
harvest attribution) and drift#92 (clear-observation counts) · **Produced by:**
`scripts/landcover_accuracy/` (logs under `scripts/landcover_accuracy/logs/`) · **Status:**
OPEN — criteria and definitions pre-registered; drought years and free reference measured
(criterion 4 does not hold); NECR pilot sample and review project ready; composite-window rule
measured (August; 2017 August–September); chips built and in the review project;
**verdict pending human labels.**

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
- **Change in prior fire** (stratum 19). This is an amendment of 2026-10-02 (#103), made **before
  any label existed**; the criteria above are untouched.
  - The stratum is published change inside a fire from the `lookback:` window in
    `config/disturbance.yml` (`fire_prior`, the 15 years before the interval: 2002–2016).
  - It is decided per **cell**, like wetland. The polygons also cover stable and sieved land, and
    only change cells take the stratum.
  - It ranks after the causes and before every transition-class stratum.
  - **It is not a cause.** Its label is not `change: <name>`, and its cells stay in criterion 2's
    unattributed tree loss. It exists because 2002–2016 fires overlap 27% of NECR's unattributed
    tree loss and 172 ha of Rangeland→Trees (cell level; 177 ha by patch any-touch). The labels have to say whether that change is real
    before it can be credited to anything.

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

**Drawn:** 2026-09-29, redrawn 2026-10-02 with stratum 19 (#103) · **Produced by:**
`scripts/landcover_accuracy/sample_draw-pilot.R`, logs
`scripts/landcover_accuracy/logs/2026*_sample_draw-pilot_necr.md` · **Record:**
`reference/necr/{sample.gpkg,strata.csv,design.json}` · seed 930093, 30 points per stratum.

The 16 strata partition the 41,838 ha footprint exactly. The change strata sum to the 472,998
published change cells, and the sieved stratum holds the 104,947 cells the 1 ha sieve removed.
The design record redraws **byte-identical**.

The 2026-10-02 redraw added stratum 19. Strata that lost no cells to it kept every point, across
drift 0.19.0 → 0.20.0. Eight gave it cells; seven moved under the same ids, and Crops ↔ Trees (0.02 ha given) kept its points. Nothing had been
labelled; the 2026-10-02 log has the per-stratum detail.

| stratum | ha | weight |
|---|---:|---:|
| change: fire | 582.5 | 0.0139 |
| change: harvest | 621.5 | 0.0149 |
| wetland change | 758.0 | 0.0181 |
| Trees → Rangeland | 180.6 | 0.0043 |
| Rangeland → Trees | 390.1 | 0.0093 |
| Crops ↔ Rangeland | 1,304.4 | 0.0312 |
| Crops ↔ Trees | 178.8 | 0.0043 |
| Snow/Ice → any | 3.4 | 0.0001 |
| any ↔ Water | 126.1 | 0.0030 |
| other tree loss | 31.8 | 0.0008 |
| other change | 99.5 | 0.0024 |
| change in prior fire (2002–2016) | 453.4 | 0.0108 |
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
- **Chips are built.** The 450 pilot points × the 4 measured windows give **1,800 chips with 0
  missing**, built 2026-09-30 to 10-01 in 15.8 h at 31.5 s each. The 2026-09-29 estimate was 44 s
  each from 30 chips. The worst chip is 1.0% NA (2017) and every other year is complete. Log:
  `scripts/landcover_accuracy/logs/20260930_chip_build-composite_necr.md`. The review project
  carries one "S2 same season_<year>" layer per window-year, at one fixed stretch.
- **2017 summer imagery is thin.** Under the 20% scene-cloud filter, **5 of 15** test points had
  no usable July–August 2017 scene at all ("no scenes"). Only Sentinel-2A was flying, and 2017 was
  a heavy smoke year. The window measurement settled it: July 2017 has no scene at all on the
  floodplain and August reaches 0.852, but August–September clears everywhere. The 2017 chips use
  that window (see Composite windows), so HLS (drift#82) is not needed for the endpoint.
- **Estimation is wired end to end.** On synthetic labels (IO's own endpoints with 20% of `ref_to`
  flipped, `SYNTHETIC=1`) it returns the nonresponse table, error-adjusted areas with CIs for
  tree loss, unattributed tree loss and wetland change, the four criteria, and the full-sample
  size. Those synthetic numbers mean nothing and are never written to `reference/`.

## Dated reference imagery (#103)

**Verified:** 2026-10-02 · **Produced by:** `scripts/landcover_accuracy/imagery_index-dated.R`
(writes `reference/necr/imagery.csv`), `imagery_build-dated.R`, `review_build-qgis.R` · **Issues:**
#103, fly#88 (withdrawn: a caller error, see below).

The Sentinel-2 chips are dated but 10 m; Esri/Google/Bing are sharp and undated. Two sources are
both dated and sharper, and `imagery.csv` records per point which of their epochs cover it. Every
sample point is listed, so a stale index can be detected and not just a disagreeing one.

| source | epoch | points covered (of 480) | resolution | review theme |
|---|---|---:|---|---|
| orthophoto (private catalogue) | 2021 | 204 (42.5%) | 0.15 m | yes |
| air photo, digital | 2012 | 480 (100%) | 4.43 m (georeferenced thumbnails) | yes |
| air photo, digital | 2019 | 14 | | no (< 25%) |
| air photo, film | 1963–2006 | up to 480 (1988, 1996, 2000) | | no: indexed only |

- **Orthophoto coverage is measured from pixels, not footprints.** The footprints touch 229 points,
  but 25 of them sit on a tile's zero-filled collar. The orthophotos are read remotely from the
  private catalogue, through a VRT warped to BC Albers inside the gitignored review project.
  **That catalogue's endpoint is never written into this public repo, and every remote call
  redacts URLs and hosts from its messages.**
- **2012 air photos are the only themed pre-interval view**, five years before the 2017 endpoint.
  - **The 4.43 m thumbnails are the limit.** They are sharper than the chips, not sharper than the
    orthophoto, and they help with structure (stand edges, channel position) more than with
    class.
- **Film epochs wait for per-roll rotations (fly#53).** `fly_georef` skips a film frame that has a
  flight bearing but no measured rotation.
- **fly#88 was a caller error, and the wrong turn is kept here deliberately.**
  - The first build passed `fly_georef` only the frames being fetched. A frame needs its roll
    neighbours for a bearing, so 87 of 250 frames had none, met the stretch guard, and were
    skipped, while `suppressWarnings()` hid fly's warning naming the cause.
  - It was filed as a fly defect. Code review traced it back, and the issue was corrected and
    withdrawn.
  - Passing the year's full frame set georeferences 250 of 250 frames.
- **`windows.csv` does not change.**
  - The windows come from a pre-registered rule over clear-day counts (Composite windows).
  - No dated epoch falls on an endpoint: the orthophoto is 2021, and the latest themed air photo is
    2012.
  - Re-choosing windows to suit an ortho year would mean editing a pre-registered definition after
    seeing data. Dated imagery is instead extra evidence the reviewer records through the label's
    `imagery` field (`orthophoto`, `airphoto`), with the epoch per point in `imagery.csv`.
- **Map themes.** The review project carries "Review" (labels, patches, FWA context, Esri), plus
  one theme per reference imagery layer: base vectors plus that one image. A theme hides layers by
  absence, so switching theme flips epochs. The themes are rewritten on every build, and a layer
  whose index or VRT went stale is removed together with its theme.

## Accuracy labels and training labels never mix

Decided before anyone labels anything. Every point in the reference sample carries
`use = "accuracy"`, and `dft_accuracy_estimate()` refuses `use == "training"` rows. If criteria are
met and a local classifier is piloted, its training labels come from a **separate draw** with its
own seed. They are never taken from this sample, because a label that trains a classifier cannot
also measure it.

## Composite windows

**Rule pre-registered 2026-09-30, before any count ran** (drift 0.20.0, which fixed drift#92). The
code is `fp_acc_window_*` in `scripts/landcover_accuracy/fp_accuracy.R`, and
`accuracy-check.R` pins it with must-fail arms.

- **The measure.** `window_count-clear.R <area> run` counts **distinct clear days** per pixel for
  each month 4–10 of 2017–2023. It runs over the whole primary floodplain at res 100, with the
  chips' own scene filter (`cloud_cover_max = 20`). "Clear" means outside the SCL mask, so it
  excludes snow as well as cloud and shadow.
- **A month is clear everywhere in a year** when at least **95%** of floodplain cells have one
  or more clear days (`share_ge1 >= 0.95`).
  - A month with no scene at all is a measured zero.
  - A month whose call failed is refused, not scored.
- **The same-season span** is the longest run of contiguous months that is clear everywhere in
  **every** year. Ties go to the higher minimum share over the run's cells, then to the earlier run.
- **The one deviation allowed in advance is 2017.** It is the thin year: Sentinel-2A only, plus
  heavy smoke. If no span exists across all seven years but one exists without 2017:
  - The span itself is counted directly for 2017 first. Each of its months can fail on its own
    while their union clears the bar.
  - If the span fails, 2017 is widened one adjacent month at a time. The higher-share neighbour
    goes first, and a tie takes the earlier month.
  - Each window is accepted only when a **direct count of that whole window** clears 95%. A union
    of months cannot be read off per-month shares.
  - *Amended 2026-09-30:* the span-first count and the tie-break were added after the counts
    started, but before any result was read. Both came from code review, and the tie-break was
    already in the code.
  - If nothing within months 4–10 passes, the fallback is HLS (drift#82).
- **Chipped windows.** `derive` writes `reference/<area>/windows.csv` with one `same_season` row
  each for **2017, 2018, 2020 and 2023**: the endpoints, the borderline-dry year and the wet year
  (see Drought years).
- **Early and late windows.** The first and last month clear everywhere in each year are
  reported here, not chipped. Chips cache per point, so adding them later rebuilds nothing.

**Measured 2026-09-30** (`window_count-clear.R`, logs
`scripts/landcover_accuracy/logs/20260930_window_count-clear_necr*`). The drift#87 grep was clean
on every cache-filling log.

- **No month is clear everywhere in all seven years.** Four month-years have no scene under 20%
  cloud anywhere on the floodplain: 2017 April, May and July, and 2021 September. Mid-summer is
  also not reliably clear: July 2019 is 0.180 and June 2019 is 0.811.
- **The same season is August.** Without 2017, only May and August pass in every year. August
  takes the tie on minimum share (0.9985 against 0.988).
- **2017 needed the pre-registered deviation.** August 2017 alone reaches 0.852. Adding September
  (0.999 on its own) gives a direct count of **1.000**, so the 2017 window is **August–September**.
  HLS is not needed for the endpoint.
- **Reference windows** (`reference/necr/windows.csv`): 2017 `8-9`; 2018, 2020 and 2023 `8`.
- **Early and late windows.** The first month clear everywhere is May in five of the seven years
  (April in 2021, June in 2017). The last is October in four (September in 2017 and 2020, August in
  2021).
  - This is a statement about **clear imagery, not phenology**.
  - It means a May composite and an August–October composite exist in most years, for reading
    seasonal amplitude by eye.
  - Neither is chipped. Chips cache per point, so adding them later rebuilds nothing.

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
