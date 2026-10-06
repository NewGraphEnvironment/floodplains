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
- Phase 3: `cells.gpkg` (480 squares from `cell` on the design grid, keyed by review_id) + outline qml;
  form qml rewritten (rule renderer by label_status, review_id labels, read-only review_id/cell/
  dated_imagery, no design fields); themes: Change patches only in "After labelling - change patches";
  template themes removed; written-file guard. NECR rebuilt live: labels.gpkg blind, 8 themes, 0 labels.
  Visual check of the hand-written renderer/labeling needs QGIS (user, on m4).
- Phase 4: `fp_acc_second_subset()` (3 per stratum = 48, own seed stream, recorded as `second` in the
  key, never grown), `fp_acc_agreement()` (both-labelled only; % agree + kappa per endpoint),
  `fp_acc_link_tree()` (hard links). REVIEWER=b builds `<area>_lulc_review_b` (48 points, imagery
  hard-linked). The export picks labels.csv / labels_b.csv from the working copy's own id set.
- Plan review folded in (planning/active/review-111.md): patches + FWA Wetland hidden in the tree and
  out of every labelling theme; labelsEnabled="1" + previewExpression; style_set every run; blind rows
  use `geom` (append path); imagery.csv design-checked; withr dropped; seed via digest2int (collision
  at n0 = 111 removed) with a literal golden arm; written-project assertions.
- Themes redesigned for the workflow (user, mid-run): names sort in working order in the drop-down
  ("0 Start", imagery by year with FIRST/LAST YEAR tags and composite months, "9 After labelling");
  legend names "Points to label", "Cell being labelled (10 m)". Key regenerated (seed derivation
  changed; 0 labels). NECR A + B rebuilt; synthetic export round trip in a temp repo copy passes.
- /code-check round 1 (review-round1.md): agreement rules were claimed pre-registered (review-111 G7)
  but never written -> written now, before any label, and cannot_label disagreement counted apart;
  labels_b.csv design-checked in the estimate; the redraw guard covers labels_b.csv and review_key.csv;
  a pre-growth A copy (ids 1..n) exports. The growth-batch leak is a design question -> documented as a
  known limit in research and raised to the user.
- Docs: research Review setup (blind review, growth limit, second labeller + agreement rules, theme
  names); CLAUDE.md #93 bullet (review_key.csv, labels_b.csv, the blind rule).
