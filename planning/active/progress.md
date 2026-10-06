# Progress — NECR accuracy review (#111)

## Session 2026-10-06

- Plan approved (opaque review_id + key; hay/pasture = Crops; regen = Trees only at canopy; keep local build)
- Created branch `111-necr-accuracy-review-blind-randomised-ce` off main
- Next: Phase 1
- Phase 1: `## Labelling key` pre-registered in research/landcover_accuracy.md (IO definitions quoted
  from Esri Living Atlas; 7 decision rules); `fp_acc_labelling_key()` extracts it and the build writes
  it into the project as `labelling_key.md`. Pasture rule corrected with the user (follow IO exactly).
- Phase 2: `fp_acc_review_key()` (append-only shuffled ids, seed stream from design.json, design RNG
  kind via withr, session RNG untouched), `fp_acc_blind_leaks()`, `fp_acc_unblind()`; the build writes
  `reference/<area>/review_key.csv` and a blind `labels.gpkg` (review_id, cell, dated_imagery + label
  fields), replaces an unlabelled pre-#111 copy and refuses a labelled one; chips manifest moved out of
  the project; `labels_export.R <area> [labels.gpkg]` unblinds through the key. 16 accuracy-check arms.
  Verified on the NECR sample: 480 ids, Spearman(review_id, stratum) = -0.013. Live build after Phase 3.
