# Progress — Config-driven disturbance attribution (#19)

## Session 2026-07-20

- Plan-mode exploration + Plan-agent design review — phases approved by user
- Plan-agent caught the harvest-layer bbox-prefilter blocker, the in-memory-vs-re-read parity risk,
  the missing DB conn in fp_lulc, and the hardcoded change interval — all folded into the plan
- Confirmed harvest layer (bcdata b1b647a6-…, HARVEST_START_YEAR_CALENDAR) via bcdata
- Created branch `19-config-driven-layer-agnostic-disturbance` off main
- Scaffolded PWF baseline from issue #19 with approved phases
- **Phase 1 done** (324bd68 + hardening 6c3848d, pushed) — `fp_disturbance.R`
  (`fp_disturbance_tag` + `fp_disturbance_report`, server-side AOI bbox prefilter), shared
  `config/disturbance.yml` (fire), `fp_read_config` loads `cfg$disturbance` + `cfg$change_interval`,
  `fire_tag.R` refit as wrapper. **Parity gate PASSES exactly** (BULK 103.2 / MORR-co 27.1 /
  MORR-ch 29.4). code-check: 2 low-severity fixes (regex anchor, `%||%` portability).
- ⚠️ **Parallel-session collision:** a concurrent session switched the shared working tree to branch
  `morr-publish-targets-co-ch` mid-Phase-1, leaving my uncommitted work floating on their branch.
  Recovered: backed up to scratchpad, confirmed no file overlap (they only touched
  `config/morr/area.yml`), checked out branch 19 (carried my changes back), committed + pushed
  immediately. Two sessions sharing one git working tree is the hazard — commit+push early.
- **Phase 2 done** — wired `fp_disturbance_tag` into `fp_lulc` (tag `trans_polys` in memory before the
  transition write; conn opened only when `cfg$disturbance` set, explicit disconnect + on.exit net).
  Hoisted the change interval to `cfg$change_interval` (drives fetch years, transition from/to, layer
  name; `sort()` guards a reversed config). Wired-path parity: BULK 103.22 vs 103.2, MORR 27.07 vs
  27.1 (both ±0.5); transition layers now carry `in_fire`/`fire_year`/`fire_number` in-pipeline.
  code-check: 1 real fix (reversed-interval `sort`) + on.exit norm alignment.
- **Phase 3 done** — bc2pg-loaded consolidated cutblocks (121,836, 2017–2026); added `harvest` to
  `config/disturbance.yml`. Multi-source validated: harvest 29–36% of loss (BULK 739 ha), residual
  95%→62–65%, ~3% salvage (fire AND harvest). Evidence log in `scripts/fwapg/logs/`.
- **Phase 4 done** — README + CLAUDE.md document the disturbance step, config, change_interval, pest
  deferred, stac#6 ripple. Validation all green (parity, no-op guard, downstream-safe, multi-source).
- Next: `/planning-archive` + `/gh-pr-push`.
