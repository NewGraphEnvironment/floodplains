# Progress — Composite windows name their scenario; NECR's accuracy sample moves to all_ff04 (#148)

## Session 2026-10-23

- Plan-mode exploration — phases approved by user (option 1: redraw NECR on all_ff04)
- Phase 0: #148 body and title rewritten for the redraw scope
- Created branch `148-composite-windows-name-their-scenario-ne` off #140's branch (stacked; PR #149 open)
- Scaffolded PWF baseline from issue #148 with approved phases
- Next: start Phase 1
- Phase 1: `fp_acc_windows_read()` and `fp_acc_window_obs_read()` (fp_accuracy.R); `run` and `derive` stamp `scenario`; chip_build, review_build and review_render-sheets read through the guard. review_render-sheets' month label generalised (it named only "8" and "8-9", so a re-measured window would have aborted it). accuracy-check: 9 new arms, ALL PASS; in a copy, removing the windows guard gives 4 FAIL, removing derive's input guard 2 FAIL.
