# Progress — #145 model labeller on NECR

## Session 2026-10-23

- Plan-mode exploration; phases approved by user (audit subset = existing 48; threshold κ ≥ 0.7 both endpoints and change agreement ≥ 0.85; #113 decisions folded in)
- Measured before the gate: both NECR working copies hold 0 labels (480 / 48 rows); no `reference/necr/labels*.csv`
- Created branch `145-check-bulk-s-change-against-dated-imager` off main
- Scaffolded PWF baseline from issue #145 with approved phases
- Next: start Phase 1
- Phase 1: pre-registered the model labeller (roles, what the model sees and never sees, threshold, fail path) and folded #113's two decisions (rule 5 ±2 years; growth blinding accepted and reported) into `research/landcover_accuracy.md`, committed before any label. Plan review spawned in the background at 05:59Z.
- Plan review landed (`review-plan.md`, extracted from the transcript by script). Verified before acting: drift 0.20.0 lacks `dft_wayback_captures`; the 48-point subset is 36 change / 3 sieved / 9 stable; `accuracy-check.R`'s agreement arm pins `ag$n`. Three forks went to the user (orthophoto out; +9 per stable stratum; abstention ≤ 10%).
- Phase 1b: pre-registration amended before any label; batch prompt committed; stable top-up drawn (48 → 75, 36 stable, idempotent).
- Phase 2: `review_render-sheets.R` + blind helpers (`fp_acc_sheet_plan`, title whitelist, PNG text-chunk guard, directory check). First render showed S2 near-black and blurred (linear 0–0.25, terra `smooth = TRUE`): fixed with a fixed square-root stretch and `smooth = FALSE`; Wayback warped unclipped from the build's tile cache; orthophoto out. Hit `terra::rast(<SpatRaster>)` = empty template (logged).
- Phase 4: change row + printed intervals in `fp_acc_agreement()`, `fp_acc_model_gate()` (κ, change, abstention), gate before any estimate in `accuracy_estimate.R`; 166 checks pass.
- Audit growth applied: `REVIEWER=b review_build-qgis.R necr` wrote `review_key.csv` (27 rows `second` FALSE→TRUE; 75 = 36 change, 3 sieved, 36 stable). B's 48-row working copy held 0 labels; it was set aside to `data/necr/accuracy/review/_aside_20261023/` and rebuilt fresh, 75 rows in `review_id` order, 0 labels.
- Canary (Plan and Explore, no tools): every design term absent from both contexts, no CLAUDE.md contents. Labeller type: Plan.
- Mutation table: 9 of 9 new guards go red when their defect is restored (abstention, last csv block, audit, duplicate sheet, PNG text chunk, title whitelist, idempotent growth, synthetic bypass, change row).
- Phase 3: 12 batches × 40 sheets labelled by blind Plan agents (13:14:56Z spawn → 13:31:15Z last extraction); every transcript audited clean (41 reads, 0 violations), every first message equal to the pre-registered prompt. Import: 471 labelled, 9 cannot_label; `labels_model.csv` kept gitignored, SHA-256 committed. Log: `scripts/landcover_accuracy/logs/20261023_model_labels_necr.md`. Transcripts kept in gitignored `data/necr/accuracy/model/transcripts/`.
