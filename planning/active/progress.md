# Progress — Annual IO LULC series (2017-2023) (#79)

## Session 2026-09-05

- Plan-mode exploration on m4; phases approved by user
- User decisions: run split across m1 + m4; PINE dropped from #79
- Created branch `79-annual-io-lulc-series-2017-2023-for-bulk` off main
- Scaffolded PWF baseline with approved phases
- Next: Phase 1 (level m4) and Phase 2 (the code change)

### Phase 1 — m4 levelled
- Capability probe before/after: 8 operations, no regression (versions are not the assertion)
- drift 0.8.0 -> **0.13.0** (>= 0.10.0 is mandatory: 0.8.0 is single-page and would truncate
  KOTL's item set into a wrong raster with no error), sf -> 1.1.2, gdalcubes -> 0.7.4
- terra left at 1.9.11 vs m1's 1.9.34 — deliberate; it is now the only difference between the
  machines, and the neexdzii control tests exactly it
- `data/{neexdzii,kotl,necr}` + the 1.1 GB drift cache rsynced from m1 (the cache key hashes
  AOI+params, not paths, so it is portable and makes m4's areas warm)
- m4's `PGHOST` already pointed at m1 — no change needed, verified with a real query

### Phase 2 — the code change
- `lulc_annual` in `fp_read_config` beside `tile_size`, with `FP_LULC_ANNUAL` and a type guard
- Env override uses a CLOSED vocabulary: `%in% c("1","TRUE",...)` would read a typo as FALSE and
  run three years under a config that says annual — the same silent-off failure the type guard
  exists to stop, one layer out. Caught reviewing my own diff.
- All guard paths exercised: 4 areas TRUE / 4 untouched FALSE, 4 on-values, 4 off-values,
  2 typos error, empty = no override, and quoted/length-2/numeric configs all refused
- README re-rendered; determinism check green on all three properties

### Phases 3-5 — runs, acceptance, evidence
- Baselines backed up and asserted real (v2, 3 years, digests present) on all four areas BEFORE
  anything overwrote them — a v1 record would have degraded the acceptance to nothing (#73's trap)
- Split run: m4 necr+kotl (41.6 min), m1 lnth+bulk (49.3 min); 49.3 min wall vs 91.9 sequential
- All four areas rc=0 on the full acceptance set
- bulk's 7,161 change patches match CLAUDE.md's recorded 2026-09-02 figure exactly
- Disturbance tags (`in_fire`/`in_harvest`) present and populated on all four; m4 reached m1's
  fresh-db over tailscale for its two
- Outputs rsynced back to m1 and provenance digests verified identical across the copy
- Evidence log: scripts/floodplain_lcc/logs/20260905_lulc-annual_split-run.md

### Two of my own harness bugs, both caught by in-band checks rather than exit codes
- The first m1 waiter reported completion while lnth was still running — local `sleep` is blocked
  in this harness, so the loop exited early. Replaced with a loop whose sleep runs on m1.
- The acceptance script called `bridge-check.R <area>` without a scenario; it defaults to `co_ff04`,
  so chinook necr failed looking for a layer that never existed. The code was fine.
Neither touched the outputs. Both are the reason the convention says gate on in-band markers.
