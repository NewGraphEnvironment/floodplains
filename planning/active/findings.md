# Findings — NECR accuracy review (#111)

## Issue context

**If we do it:** the NECR pilot labels are made blind, in random order, on the cell they describe, under written rules. They are collected through a Mergin project rtj builds and syncs, so any machine (m4) pulls the latest and the labels come back without rsync.
**If we never do:** the labels are made seeing IO's own answer, stratum by stratum, on a point with no visible cell, with no labelling key. That inflates the very accuracy #93 measures, and the pilot carries the bias into the full sample, because pilot labels carry over. The project also lives only in m1's gitignored `data/` and moves by hand.

## What changes in floodplains (the accuracy-specific inputs)

Before the first label:
1. **Blind the review.** `map_class`, `map_2017`…`map_2023` and `stratum_label` must not be visible in the form or the attribute table, where seeing them anchors the label. The design check needs those values; the reviewer must not see them. The export already joins the design on `point_id` and checks it, so moving them off the review layer loses nothing.
2. **Randomise the review order.** Add a `review_order` field from a fixed seed. Points are grouped by stratum, which primes the call.
3. **Draw the 10 m sample cell.** Labels are per cell (`cell` → square polygon on the classified grid). A point on a 0.5 m orthophoto gives no sense of the square being judged.
4. **Write a labelling key.** No decision rules exist yet. It should cover:
   - IO's class definitions, especially Rangeland vs Crops vs Flooded Vegetation;
   - mixed cells;
   - when "cannot label" is the right answer.

   Commit it beside the pre-registered criteria in `research/landcover_accuracy.md` before labelling starts. Editing it later, to fit labels already made, is exactly what pre-registration forbids.

During review:

5. **Imagery coverage per point.** Carry `reference/<area>/imagery.csv`'s epochs onto the label layer as a read-only field.
6. **Progress symbology** by `label_status`.
7. **Second labeller on ~10%.** Inter-rater agreement separates IO's error from imagery that is genuinely ambiguous. This needs a reviewer field and an agreement step in `accuracy_estimate.R`.

## The project moves to rtj

`review_build-qgis.R` currently builds the whole rfp project under `data/<area>/accuracy/review/`. Composition and Mergin sync belong in rtj (`scripts/gis/README.md`: a project's build scripts do not live in one of its consumers). The rtj side is in its own issue. On this side:
- **Narrow `review_build-qgis.R`** to producing inputs: the labels seed gpkg, cell polygons, chips, dated VRTs and the form `.qml`.
- **Point `labels_export.R` at the Mergin working copy** (`~/Projects/gis/<generation>/`), not `data/`.
- **Carry labels across rebuilds.** Labels must survive a project generation rebuild. The `point_id` + design check already refuses labels from another draw.

## Notes

- **Private endpoint: decided 2026-10-06, fine on Mergin.** The dated orthophoto VRTs hold hrefs to the **private** endpoint (CLAUDE.md, #93 rules). On Mergin they sit in the org's private workspace (members: us only), never in git.
- **Change patches: decided 2026-10-06.** They show IO's answer, so they go in a separate theme used after labelling, chosen from the theme drop-down (rtj#367). They never appear in the labelling view.
- **Order:** this issue first, then NewGraphEnvironment/rtj#367 composes and syncs the project.
- No labels exist yet: 480 points, 0 labelled as of 2026-10-06. Nothing needs migrating if this lands before labelling starts.

Relates: #93, #94, #103



## Planning measurements (2026-10-06)

- `point_id` encodes the stratum (`<stratum>_<k>`), so hiding map columns cannot blind the review; hence opaque `review_id`.
- `chips/manifest.csv` inside the project maps point_id -> chip file; chip tif names are hashes (no leak).
- Current build puts `Change patches` in `base`, i.e. in every theme including Review.
- `labels.gpkg`: 480 points, 0 with a label_status.
- rfp manifest source types: bcdata fwa aws osm url stac frozen (no local-file type) -- rtj#367 decides ingestion.

## Errors Encountered

| Error | Resolution |
|-------|------------|

## IO class definitions (fetched 2026-10-06)

- Planetary Computer `io-lulc-annual-v02` STAC names the classes but carries no definitions.
- Definitions come from Esri Living Atlas item `cfcb7609de5f478eb7666240902d4d3d` ("Sentinel-2 10m Land Use/Land Cover Time Series").
- **IO's Rangeland explicitly includes "pastures"; Crops is "human planted/plotted cereals, grasses".** The gate decision "hay+pasture = Crops" (my recommendation, claimed to follow IO) was wrong for pasture. Re-asked, and the user chose to follow IO exactly: hay = Crops, pasture = Rangeland.
- **Trees threshold is "~15 feet or higher"** (~4.6 m), not 15 m.
