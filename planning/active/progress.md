# Progress — #8 tiled STAC fetch

## Session 2026-07-11
- Audited packages: `flooded` 0.3.2 unchanged; `drift` 0.4.0 -> 0.6.0 (installed + local ff'd).
- Wired `tile_size` opt-in into `fp_lulc` (both fetch sites) + documented the `area.yml` key in
  `fp_read_config`; bumped drift floor >= 0.6.0 and refreshed the CLAUDE.md gotcha.
- Established evidence structure: `research/` (README + dated benchmark memo) and
  `scripts/floodplain_lcc/logs/` (README).
- Landed alongside under #3: MCGR + BOWR chinook areas, Peace region (PCEA + PARS bull trout);
  PINE flagged pending a link build.
- Plan-agent review before baseline caught 2 blockers (no runtime drift floor; cache-wipe would
  clobber the shared cache) + gaps (fixture-tiling injection path, accuracy subject, parity
  tolerance, thresholds) — all folded in. See findings.md.
- Commits: cc51ee8 (MCGR+BOWR), d05761c (Peace/PCEA/PARS), b0ecb00 (tile_size wiring + docs),
  03bf025 (plan-review hardening: drift>=0.6.0 assert + FP_TILE_SIZE override), eae82a3 (this
  PWF + research/ + logs/ baseline).
- Branch `8-tile-fetch-benchmark`, not yet pushed.
- Next: Phase 2 — generate PCEA steps 1,2; run neexdzii step 3 both ways for the ~1 ha parity
  gate (untiled must hold 943.13 ha); accuracy on PCEA corridor; speedup direct-time. Needs
  local fwapg + `caffeinate -s`.
