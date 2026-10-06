# Task: NECR accuracy review: blind, randomised, cell-level labelling, built as an rtj Mergin project (#111)

**If we do it:** the NECR pilot labels are made blind, in random order, on the cell they describe, under written rules. They are collected through a Mergin project rtj builds and syncs, so any machine (m4) pulls the latest and the labels come back without rsync.
**If we never do:** the labels are made seeing IO's own answer, stratum by stratum, on a point with no visible cell, with no labelling key. That inflates the very accuracy #93 measures, and the pilot carries the bias into the full sample, because pilot labels carry over. The project also lives only in m1's gitignored `data/` and moves by hand.


## Context

The #93 reference sample (480 NECR points, 30 in each of 16 strata, 0 labelled) is about to be labelled. As built, the review would show the map's answer and bias the labels:

- `labels.gpkg` carries `map_class`, `map_2017`…`map_2023`, `stratum_label` and `in_*` flags.
- **`point_id` itself encodes the stratum** (`10_00001` is stratum 10; `fp_acc_design_check`'s own comment says so).
- `chips/manifest.csv` inside the project maps `point_id` to each chip.
- `Change patches` sits in every theme, and points come grouped by stratum.
- No cell outline is drawn, and there is no written labelling key.

#111 fixes all of that before the first label. rtj#367 then composes and syncs the Mergin project.

**Decisions at the gate (user, 2026-10-06):**
- **Blinding:** an opaque `review_id` plus a committed key, not hidden fields.
- **Hay and pasture:** labelled **Crops**.
- **Regenerating stands:** **Trees only at canopy**.
- **Local build:** keep it and update it until rtj#367 retires it.

Already decided in the issues:
- Change patches go in a separate after-labelling theme, picked from the drop-down.
- The ortho VRTs are fine on Mergin.
- The second labeller is in scope.

## Phase 1: Labelling key (pre-registered before any label)
- [x] Add a `## Labelling key` section to `research/landcover_accuracy.md`, committed before labelling starts:
  - **IO's class definitions,** quoted from Impact Observatory / Esri's published legend and cited (fetched, not recalled).
  - **Decision rules:**
    - The label is the class of the outlined 10 m cell at each endpoint (2017, 2023), and the two endpoints are judged independently.
    - A mixed cell takes the plurality class. With no clear plurality, the label is `cannot_label`.
    - Each label describes that year's growing season. Imagery within ±1 year of the endpoint supports high or medium confidence; anything further supports low at most. Undated basemaps alone support low at most.
    - Hay and pasture fields with visible boundaries, mowing, rows or tillage are **Crops**; unmanaged open grass and shrub is Rangeland.
    - Regenerating stands are **Trees only once they read as tall, dense canopy over most of the cell**; until then they are Rangeland, or Bare Ground if sparse.
    - Flooded Vegetation needs visible standing water or saturation in the imagery. A dry wet meadow is Rangeland.
    - `cannot_label` applies when no imagery resolves the cell near the endpoint, or when no plurality can be judged.
    - `imagery` records what actually decided the label.
  - **Pre-registration rule:** never edit the key to fit labels already made. This is the same rule as the criteria.
- [x] `review_build-qgis.R` copies that section into the project as `labelling_key.md`, extracted from the research file so there is one source.

## Phase 2: Opaque review IDs and a blind labels layer
- [ ] Add `fp_acc_review_key(smp, seed, have = NULL)` in `fp_accuracy.R`:
  - It shuffles the points with a seed derived from `design.json`'s `seed`, giving `review_id` 1..n.
  - It is **append-only**: when the sample grows (pilot to full sample), existing IDs never change and new points take the next IDs, shuffled among themselves.
  - Columns: `review_id`, `point_id`, `cell`, `stratum`, `map_class`.
- [ ] Commit `reference/<area>/review_key.csv`, written by the build. It is never hand-edited, and it is checked against `sample.gpkg` with `fp_acc_design_check`.
- [ ] Rebuild `labels.gpkg` with schema `review_id`, `cell`, `dated_imagery`, plus the label fields. It carries **no** `point_id`, stratum, `map_*`, `in_*` or `use`.
  - The build refuses to replace an old-schema `labels.gpkg` that holds any `label_status`.
  - Today it holds none, so the old one is moved aside.
- [ ] Move `chips/manifest.csv` out of the shipped project, to `data/<area>/accuracy/chips_manifest.csv`. Update `chip_build-composite.R` and its readers.
- [ ] `labels_export.R <area> [labels.gpkg]` takes an optional path, so it can read the Mergin working copy for rtj#367.
  - It maps `review_id` to `point_id` through the key.
  - It refuses an unknown `review_id`, or a working-copy `cell` that disagrees with the key.
  - Everything else goes through `fp_acc_labels_frame` unchanged, so `labels.csv` keeps its format.
- [ ] `accuracy-check.R` gains these arms:
  - **Must-fail:** the built labels schema contains no design column, and a schema with `point_id` or `map_2017` is caught.
  - The key is not ordered by stratum (rank correlation near 0), and the must-fail arm sorts it by `point_id`.
  - Growing the sample keeps the pilot IDs.
  - **Must-fail:** the export refuses a cell mismatch.
  - **Must-fail:** the export refuses an unknown `review_id`.

## Phase 3: Review surface
- [ ] Cell outlines: `cells.gpkg` holds one square per point, built from `cell` on the design grid (`dims`, `extent` and `crs` in `design.json`), keyed by `review_id` and displayed in BC Albers.
- [ ] `dated_imagery` text per point from `reference/<area>/imagery.csv`, e.g. `orthophoto 2021; airphoto 2012`.
- [ ] `labels_form.qml`:
  - Drop the design-field configs; add `review_id`, `cell` and `dated_imagery` as read-only.
  - Keep every label field a drop-down, with `note` the only free text.
  - Add a renderer that shows progress by `label_status` (blank, labelled, cannot label).
  - Label each point with its `review_id`.
- [ ] Themes:
  - `Change patches` leaves the shared base layers.
  - A new **`After labelling - change patches`** theme is picked from the drop-down.
  - The cell outlines join every labelling theme.
  - An arm checks that patches appear in no labelling theme (parsed from the `.qgs`).

## Phase 4: Second labeller
- [ ] Subset: 3 points per stratum (48), drawn with a seed derived from the design seed and recorded as a `second` column in `review_key.csv`. Pre-registered.
- [ ] `labels_b.gpkg` holds the same schema for the subset only. `REVIEWER=b review_build-qgis.R` builds a separate local project, so labeller B never sees A's labels. On Mergin this becomes rtj#367's second project.
- [ ] `labels_export.R` writes `labels_b.csv` from `labels_b.gpkg`. `accuracy_estimate.R` reports percent agreement and Cohen's kappa per endpoint over the overlap, as information only and never in the estimates. An arm covers it.

## Phase 5: Rebuild NECR, verify, hand off
- [ ] Rebuild the NECR project.
- [ ] Open it in QGIS:
  - the form shows only label fields, review ID and imagery;
  - themes and outlines are right;
  - the key file is present.
- [ ] Run a synthetic-label export round trip in a temp copy.
- [ ] Run `accuracy-check.R`, and show each new must-fail arm going red in a copy.
- [ ] Update the docs: CLAUDE.md's #93 bullet (review ID, the key file, the blind schema), and the Review setup section in `research/landcover_accuracy.md`.
- [ ] Comment on rtj#367 with the exact input list:
  - `labels.gpkg`, `labels_b.gpkg`, `cells.gpkg`;
  - `labels_form.qml`, `labelling_key.md`;
  - `chips/` and `dated/`;
  - the themes;
  - and the `labels_export.R <area> <path>` round trip.

## Critical files
- `scripts/landcover_accuracy/review_build-qgis.R`
- `fp_accuracy.R` (`fp_acc_design_check`, `fp_acc_labels_frame`, `FP_ACC_*`)
- `labels_export.R`, `accuracy_estimate.R`, `chip_build-composite.R`, `accuracy-check.R`
- `reference/necr/labels_form.qml`
- new: `reference/necr/review_key.csv`
- `research/landcover_accuracy.md`

Reused: rfp `rfp_qgs_vector_add`, `rfp_qgs_theme_set`, `rfp_qgs_layer_rm`; `fp_acc_design_check` for the key.

## Verification
- Offline: `accuracy-check.R` with all new arms, each mutation shown red in a copy.
- Live: rebuild NECR and inspect the `.qgs` (XML parse plus QGIS). A synthetic export goes `review_id` → `labels.csv` and matches `point_id` and design.
- `labels.csv` is unchanged in format, so `accuracy_estimate.R` runs on synthetic labels as before.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
