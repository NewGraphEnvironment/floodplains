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
## Session 2026-07-11 (Phase 2/3 — benchmark + decision)
- Whole NGE stack brought current (link 0.44.1 -> 0.44.2; fresh/flooded/drift already latest).
- neexdzii same-stack gate: untiled reproduces 943.13 ha; tiled (5000 m) 941.25 ha (Δ −1.88 ha,
  sieve-quantized); accuracy ≥ 99.999%, no seam band. Tiled full step-3 was 6.3× slower.
- Speedup tested directly on the existing FRAN 883 km² floodplain (no PCEA steps 1,2 needed —
  speedup is a pure fetch question): untiled 177 s vs tiled 20000 m 0.79× / 10000 m 0.31×.
- **Decision: DO NOT adopt tile_size** — slower at every size on every AOI; floodplain corridors
  tile badly. Opt-in stays wired (default off). Real fix is in-cube (gdalcubes#110).
- Evidence: logs/20260711_lulc_tile-benchmark_{neexdzii,fran}.md; verdict in research memo.
- Closes #8.
