# Plan review — #111 (Plan agent, 2026-10-06), with dispositions

Read-only review of plan + committed code + live project. Condensed.

## Blockers
1. Template themes (5) show Change patches; guard checked `th` not the .qgs. -> fixed independently in
   Phase 3 (foreign themes removed; guard reads the written .qgs via rfp_qgs_themes).
2. Change patches CHECKED in the layer tree -> draws on first open before a theme is picked. -> re-added
   with visible = FALSE, themes = none; written-file assertion on the tree check state.
3. labelsEnabled="0" (rfp default) unless the qml root sets it -> review_id labels would not draw.
   -> labelsEnabled="1" on the qml root; assertion on the written maplayer.
4. Append path: blind() names geometry `geometry`, a gpkg read back names it `geom` -> sample growth
   errors "undefined columns selected". -> blind() moved to fp_acc_blind_points() with `geom`; arm appends
   to a temp gpkg.
5. B's export could become labels.csv. -> the export derives A/B from the working copy's id set (all keyed
   ids = A, exactly the `second` subset = B, anything else refused); REVIEWER env no longer decides output.

## Gaps
- G1 qml changes never reach an existing layer -> rfp_qgs_style_set on every run.
- G2 previewExpression -> `"review_id"`.
- G3 stale dated_imagery -> rewritten while the working copy holds no label.
- G4 imagery.csv joined without the design check -> fp_acc_design_check first.
- G5 B project imagery -> hard links (fp_acc_link_tree), real files inside the project.
- G6 `second` erased -> carried through the append path (done in Phase 4 code).
- G7 agreement rules -> pre-registered in research (both-labelled only; cannot_label reported apart; kappa
  per endpoint over IO codes).
- G8 withr undeclared -> replaced with base RNG save/restore.
- G9 growth on Mergin -> rtj#367 hand-off note: floodplains' gpkg is a seed, never copied over the Mergin
  working copy; freeze schema before first sync.
- G10 docs -> research Dated imagery section; build header "never rewritten".

## Assumptions
- A1 FWA wetland in every labelling theme is a stratifier hint -> moved to the after-labelling theme.
- A2 +/-1-year rule caps NECR dated high-res at `low` -> NOT changed; raised to the user before labelling
  (confidence is not used in the estimates).
- A3 plan decision text stale on pasture -> corrected in task_plan.md.
- A4 seed streams collide at n0 = 111 -> digest::digest2int over a purpose string; golden arm.
- A5 blinding is procedural for anyone with the repo (sample.gpkg, review_key.csv) -> stated in hand-off.
- A6 low-severity (VRT source order, cache mtimes, template WMS, error messages print point_id) -> noted,
  not fixed.
- AC2 `reviewer` is free text -> plan text corrected.
