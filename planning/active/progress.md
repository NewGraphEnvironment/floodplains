# Progress — NECR accuracy review (#111)

## Session 2026-10-06

- Plan approved (opaque review_id + key; hay/pasture = Crops; regen = Trees only at canopy; keep local build)
- Created branch `111-necr-accuracy-review-blind-randomised-ce` off main
- Next: Phase 1
- Phase 1: `## Labelling key` pre-registered in research/landcover_accuracy.md (IO definitions quoted
  from Esri Living Atlas; 7 decision rules); `fp_acc_labelling_key()` extracts it and the build writes
  it into the project as `labelling_key.md`. Pasture rule corrected with the user (follow IO exactly).
