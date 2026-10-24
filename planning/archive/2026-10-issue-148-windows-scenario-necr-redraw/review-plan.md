# Plan review (Plan agent, spawned 2026-10-23T20:42Z, returned ~20:51Z)

Findings (condensed from the agent's reply) and disposition.

| # | Kind | Finding | Disposition |
|---|------|---------|-------------|
| 1 | Blocker | `fp_acc_sheet_title_ok()` hard-coded `(Aug\|Aug-Sep)`; any other measured window aborts sheet rendering | Reproduced by reading fp_accuracy.R:1052. Fixed: any month or month span; arm added (pass Jul, Jul-Sep; refuse July, three-month span) |
| 2 | Blocker | `derive` may refuse on all_ff04 (only 2017 may widen; HLS fallback unbuilt) | Gate added: if derive refuses, stop and ask; the rule is not tuned |
| 3 | Blocker | Model-labeller subsection says the sheet map is frozen once any label exists; replacing the hash needs a recorded reason | Phase 5: dated amendment note in that subsection, citing 4072a24 and the reason, before the new hash is committed |
| 4 | Gap | Research numbers on ch_ff04 beyond those the plan named (wetland table, dated-imagery table, windows sentence, Wayback shares, Status) | Added to Phase 5 |
| 5 | Gap | CLAUDE.md stale lines beyond the #93 bullet (all_ff04 under ch_ff04, windows (#148), sieve 18%, expected-failure note, review_key append-only) | Added to Phase 5 |
| 6 | Gap | Pre-registered rationale holds ch_ff04 measurements (sieve 18%, prior fire 27%, 48/39/86%) | Left unedited as dated rationale; all_ff04 values go in the Reference-sample section |
| 7 | Gap | Criterion 4 was scored on ch_ff04 (0.255, does not hold); moving the population after scoring must be recorded first | Recorded in findings.md before reference_omission-disturbance.R runs on all_ff04; ch_ff04 value kept visible in research |
| 8 | Gap | chips_manifest.csv joined by point_id, outside the review dirs | Already moved aside in Phase 2; acceptance check added (manifest point set = sample, 4 windows each) |
| 9 | Gap | Air-photo thumbnails live in the project; a moved project re-fetches | Phase 3: reuse the aside copies if keyed by frame, not point |
| 10 | Gap | chip_build header columns; curated windows log copy; research "NECR run" line; NEWS.md | Header done in Phase 1; log copy and research line in Phase 5. NEWS: declined, `/gh-pr-merge` writes it (CLAUDE.md) |
| 11 | Ordering | accuracy-check's live wayback arm fails from the redraw until wayback.csv is regenerated | Confirmed (1 FAIL now). The reference commit waits for imagery.csv, wayback.csv and windows.csv |
| 12 | Ordering | Stage order otherwise correct | Kept |
| 13 | Assumption | 75/480/12 assume 16 strata, 3 stable | Measured on the draw: 16 strata, 3 stable, 480 points. Counts derived from strata.csv in acceptance |
| 14 | Assumption | "Nobody labelled" checked locally; projects carry mergin-config.json | The user stated it (2026-10-23); the reviewer's sqlite count agrees (0 in all three). Mergin still serves the first draw until the user syncs: reported |
| 15 | Assumption | The windows guard compares names; a same-name re-run of step 2/3 passes | Accepted residual risk, recorded in findings |
| 16 | — | drift count cache keyed by AOI; bbox fetches cover the outside 1.3% | Fine |
| 17 | Assumption | Three review dirs, not four; an `_aside_20261023` exists | Moved under a distinct name, `_aside_20261023_ch_ff04/` |
| 18 | Scope | Keep the old hash auditable | Cited (4072a24) in the amendment note |
| 19 | Acceptance | SYNTHETIC estimate; composition (5) ok line; title arm; manifest check; B count from strata.csv | Added to verification |
