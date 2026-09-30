# Task: Measure IO LULC accuracy in our floodplains against dated imagery: stratified reference sample, error-adjusted areas, and the case for classifying ourselves (#93)

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


## Phase 1: Pre-registered criteria
- [ ] `research/landcover_accuracy.md` with the header line (Verified/Issues/Produced by), the
      four move-6 criteria verbatim ("any two ⇒ pilot a local classifier"), and the
      accuracy/training split decision (every point in this sample has `use = "accuracy"`;
      training labels will only ever come from a separate draw)
- [ ] `research/README.md`: add the index row, and replace the dated-memo rule with the
      topic-file rule plus a cutover line (closes #86)
- [ ] Commit before any phase-2 to phase-4 measurement runs

## Phase 2: Windows, measured
- [ ] Upgrade drift to ≥ 0.19.0 (`pak`). Bump `scripts/packages.R` and the `fp_lulc` floor
      comment only if something here needs it
- [ ] `window_count-clear.R`: validate one month first, at `res=100` against a finer `res` on a
      small sub-AOI, and against the per-month `eo:cloud_cover` item count
- [ ] Run months 4–10 × 2017–2023 over the NECR `ch_ff04` floodplain (`aggregation="count"`,
      `bands="red"`, `clip=TRUE`) under `caffeinate -s`. Per-month/year median clear-obs → CSV + log
- [ ] Derive the same-season span (clear coverage in every year), plus one early and one late
      window in a single year. Record both in the research note

## Phase 3: Drought years, measured
- [ ] `tidyhydat::download_hydat()` (machine change: replaces the shared local DB). Record the
      old and new release dates
- [ ] `drought_rank-gauges.R`: Aug–Sep mean flow per year against each gauge's long-term record
      for 08KC001, 08JB002, 08JE004, 08KG001, with 08JB003 and 08JE001 flagged lake-buffered and
      08JC001 excluded as regulated. Output: which of 2017–2023 sit in the lowest quantile at
      most gauges
- [ ] Research note section plus a log

## Phase 4: Free reference (results)
- [ ] `reference_omission-disturbance.R`: per in-window fire and harvest polygon, floodplain
      area ∩ IO Trees-in-2017 vs the area IO labels as tree loss by 2023. Denominator stated.
      Harvest start ≤ 2022 so the 2023 map can see it. Caveats beside the number (partial cuts,
      start-year vs removal, non-stand-replacing fire). Feeds criterion 4
- [ ] `reference_composition-wetland.R`: per-year IO class composition inside
      `fwa_wetlands_poly` ∩ floodplain, from the **classified rasters** (not `in_wetland`,
      which exists on changed patches only)
- [ ] Both into the research note plus logs. Criterion 4 evaluated

## Phase 5: Strata and pilot sample
- [ ] `fp_accuracy.R` strata builder on the transition grid, with **first-match precedence**:
      fire → harvest (causes read from `sources:` names only, never `in_*`) → wetland change
      (Flooded Veg from/to, or `in_wetland`) → Trees→Rangeland → Rangeland→Trees →
      Crops↔Rangeland → Crops↔Trees → Snow/Ice→* → *↔Water → other tree loss → other change.
      Stable strata: stable ∩ FWA wetland → stable Trees → stable other. Rasterise in memory,
      then `mask()` to the map
- [ ] `accuracy-check.R` covers: precedence, a context column never becoming a cause,
      stable-vs-change completeness (every mapped cell gets exactly one stratum), and
      recode-then-estimate union targets (all tree loss, the unattributed residual) on a toy grid
- [ ] `sample_draw-pilot.R`: `dft_accuracy_sample(strata, n = 30, seed = <fixed>, map = <2017..2023 + transition>)`
      → `reference/necr/sample.gpkg` (OGR date pinned), `strata.csv`, `design.json`

## Phase 6: Review setup
- [ ] `chip_build-composite.R`: one `dft_stac_composite()` per buffered point per phase-2 window
      (true colour), cached as COGs under `data/necr/reference_chips/` (gitignored)
- [ ] Label layer: the sample points plus empty `ref_from`, `ref_to`, `change`, `confidence`,
      `imagery`, `note`, `reviewer`, `date`, `use`. The value-map QML is committed in
      `reference/necr/`
- [ ] `review_build-qgis.R`: build the project with rfp (label layer + QML, chips, Esri/Google
      services, transition patches with `in_*`). If rfp cannot build a bare non-fieldwork
      project, file an rfp issue and ship the gpkg + QML + chips as the deliverable
- [ ] `labels_export.R`: gpkg label layer → `reference/necr/labels.csv` (committed, diffable),
      validated with `dft_accuracy_labels()`
- [ ] `accuracy_estimate.R` wired end-to-end and exercised on **synthetic** labels only
      (clearly marked, never committed as `labels.csv`), so labelling is the only missing input

## Phase 7: Handoff (human labelling is outside this branch)
- [ ] Research note "Status": sample and project ready; verdict pending labels
- [ ] Edit the #93 body: phases 1–6 delivered (PR "Part of #93", #93 stays open). The remaining
      steps are label → `labels_export.R` → `accuracy_estimate.R` → `dft_accuracy_size` → the
      verdict against the criteria → #92, with the exact commands

## Decisions (plan gate, 2026-09-29)
- The PR is **Part of #93**, and #93 stays open for labelling, estimates and the verdict
- Pilot: **14 strata × 30** (~420 points)
- Labels: **gpkg form layer for editing + committed `labels.csv`** as the record

## Validation

- [ ] Tests pass (`scripts/landcover_accuracy/accuracy-check.R`, each must-fail arm red when its rule is broken)
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
