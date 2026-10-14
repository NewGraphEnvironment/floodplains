# Progress — Whole-network floodplains for every region (#125)

## Session 2026-10-14

- Plan-mode exploration — phases approved by user (scope: code + region files + Skeena run; keep species rows/outputs; no neexdzii twin; DUNC joins columbia.yml)
- Created branch `125-whole-network-floodplains-for-every-regi` off main
- Scaffolded PWF baseline from issue #125 with approved phases
- Next: start Phase 1
- Phases 1-3: `fp_region_mode` / `fp_region_owned` / `fp_region_min_order` / `fp_region_cache_stale` in
  `fp_region.R`; `fp_region_plan` converts species areas under a whole region and refuses species
  `targets`; `run_region.R` whole-mode pre-pass (segment count in `network_source`), pre-0.7.0 cache
  rule, SKIP-row rbind fix; checks moved to frozen fixtures, whole-mode arms added, mutation table
  (8 mutations, all red) in findings.md.
- Plan review (Plan agent) spawned 2026-10-14T12:31:49Z, running in background.
- Phase 4: all four region files `network: whole` (KISP folded into skeena.yml, skeena_ch.yml deleted,
  DUNC added to columbia.yml, Columbia's `network_guard: warn` dropped); `fp_readme_roster()` reads the
  mode; README re-rendered (md with `rmd_on = FALSE` per the build chunk), determinism + content checks OK.
- Phase 5 started: Skeena area.yml hand-edited and committed (b4414eb); DRY preview read as planned and
  wrote nothing (md5 of config/*/area.yml + flood_scenarios.csv unchanged). Live run launched
  2026-10-14T12:37:17Z from a frozen worktree at b4414eb (data/ symlinked), log + RSS sampler in scratchpad.
- Phase 6: CLAUDE.md updated for the region mode (Skeena numbers pending the run); filed #131
  (species-output prune, gated on stac#76 + #128); #76 body updated with MCGR/PINE whole-mode km.
- Plan review landed (planning/active/review-plan.md). Fixes: DUNC comment (G1), cache invalidated by a
  moved region-owned key (G2), citations carried onto appended rows (G6), README roster calls
  fp_region_mode (G7), whole min_order floor (A2), gnis_name arm (AC1). Mutations M8/M9 red.
  provenance-check baseline: MORR + KISP PASS pre-run.
- code-check round 1: 2 findings, both fixed — `reg$network` partial-matched `network_source` (species regions refused); config-moved cache signal now read from the network record (survives a resume). M10/M11 red.
- code-check round 2: 1 finding inside round 1's fix — cache records are rewritten by steps 1-2 before step 3 replaces the summary, so an interrupted re-run read as complete. Fixed by retiring the primary summary on every re-run path (also covers the no-provenance and FORCE paths, same mechanism). Not offline-testable: run_region.R opens a DB at load.
- code-check round 3: mechanism named (co-presence read as co-provenance); fixed with fp_region_cache_unordered + fp_region_cache_reason, coverage CSV date re-read after the child; terminated by enumerating every provenance writer (findings.md). M12/M13 red.
- Phase 5 done: Skeena run rc 0, 3/3 ok (BULK 59.0 / MORR 15.7 / KISP 24.0 min, ~16.5 GiB peak).
  provenance/bridge/disturbance(all_ff04) PASS on all three; composition-check +1.47/+4.40/+1.27% is
  the #53 edge effect (change inside the polygon == patch totals, measured). Reconciled csvs regenerated
  in the main checkout with the current code (citations carried), non-citation columns identical to the
  run's. Log: scripts/floodplain_lcc/logs/20261014_whole_network_skeena.md.
- Phase 6 done: #59/#73 pointers posted, #125 body gains a Status section (decisions, Skeena done,
  Fraser/Peace/Columbia left, stac stage_years-check note, publish freeze). Origin unmoved; offline
  checks + README determinism/content PASS on the final tree; worktrees removed, data/ intact.
