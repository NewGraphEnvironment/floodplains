# Progress — #8 tiled STAC fetch

## Session 2026-07-11
- Audited packages: `flooded` 0.3.2 unchanged; `drift` 0.4.0 -> 0.6.0 (installed + local ff'd).
- Wired `tile_size` opt-in into `fp_lulc` (both fetch sites) + documented the `area.yml` key in
  `fp_read_config`; bumped drift floor >= 0.6.0 and refreshed the CLAUDE.md gotcha.
- Established evidence structure: `research/` (README + dated benchmark memo) and
  `scripts/floodplain_lcc/logs/` (README).
- Landed alongside under #3: MCGR + BOWR chinook areas, Peace region (PCEA + PARS bull trout);
  PINE flagged pending a link build.
- Commits: cc51ee8 (MCGR+BOWR), d05761c (Peace/PCEA/PARS), b0ecb00 (tile_size wiring + docs),
  + this PWF baseline.
- Next: Phase 2 — run neexdzii both ways for the parity gate (943.13 ha), then accuracy +
  speedup on PCEA/PARS. Needs local fwapg + `caffeinate -s`.
