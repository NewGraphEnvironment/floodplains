# Task: Config-driven, layer-agnostic disturbance attribution (#19)

Generalize the one-off `fire_tag.R` into a config-driven, layer-agnostic step wired into the
pipeline: N overlay polygon layers declared as config, each tagging every change patch (`in_<source>`
+ carried attributes) windowed to the change interval. Additive attribution (fire AND harvest);
residual (matches nothing) = classification-noise floor. Fire/harvest/pest = config, not code.

**Regression contract (this session's fire numbers):** BULK 103.2 ha (5%), MORR coho 27.1 ha (6%),
MORR chinook 29.4 ha (6%) of Trees→non-Trees loss inside a 2017–2023 fire perimeter.

**Scope:** framework + fire (parity) + harvest (multi-source proof). Pest deferred, but the config
contract supports it (`filter:` + `confidence:`).

**Decisions:** disturbance attrs = columns on the transition layer (non-breaking — `05` reads by
name); shared `config/disturbance.yml` (mirrors `config/regions/`); hoist change interval to
`cfg$change_interval`; sources loaded into fwapg via bc2pg with a **server-side AOI-bbox prefilter**
(mandatory for the huge harvest layer); `fire_tag.R` refit as a thin wrapper + parity harness.

## Phase 1 — Generalized routine + shared config + change_interval (fire only)
- [x] `fp_disturbance.R`: `fp_disturbance_tag(patches, sources, conn, window)` — data-driven
      dominant-overlap tagging; `st_make_valid()` both sides; transform source to `st_crs(patches)`;
      AOI-bbox server-side SQL prefilter; `fp_disturbance_report` (additive residual).
- [x] `config/disturbance.yml` with the `fire` source (reproduces fire_tag.R's current query).
- [x] `fp_read_config`: load `cfg$disturbance` (guarded, absent⇒NULL⇒skip) + `cfg$change_interval`;
      source the new file.
- [x] Refit `fire_tag.R` to call `fp_disturbance_tag`; **parity gate PASSES exactly** —
      BULK 103.2 / MORR-co 27.1 / MORR-ch 29.4.

## Phase 2 — Wire into fp_lulc + fire parity gate
- [x] Tag `trans_polys` before the transition write when `cfg$disturbance` set; open DB conn only then
      (explicit disconnect + `on.exit` safety net) so offline step-3 is unaffected.
- [x] Consume `cfg$change_interval` (fetch years, transition from/to, layer name); `sort()` guards a
      reversed config.
- [x] Parity: BULK + MORR step 3 wired → transition carries `in_fire`/`fire_year`/`fire_number`;
      in_fire loss BULK **103.22** vs 103.2, MORR **27.07** vs 27.1 (both within ±0.5).

## Phase 3 — Load harvest + add as source + validate multi-source
- [x] One-time bc2pg load of `veg_consolidated_cut_blocks_sp` (filter `HARVEST_START_YEAR_CALENDAR >=
      2017`) into fwapg — 121,836 cutblocks, 2017–2026. Evidence log in `scripts/fwapg/logs/`.
- [x] Add `harvest` to `config/disturbance.yml`.
- [x] Validated multi-source (BULK/MORR): harvest explains **29–36%** of tree loss (BULK 739 ha,
      MORR-co 125, MORR-ch 150); residual dropped 95%→62–65%; ~3% salvage (fire AND harvest).

## Phase 4 — Docs + STAC ripple
- [ ] README + CLAUDE.md: the disturbance step, `config/disturbance.yml`, `change_interval`, pest
      deferred; transition layer now carries N disturbance attrs → stac_floodplains_bc#6.

## Validation
- [ ] Parity: wrapper reproduces BULK/MORR fire numbers exactly; wired path within ±0.5 ha
- [ ] No-config no-op: an area with no `config/disturbance.yml` runs step 3 byte-identically
- [ ] Downstream intact: `05_prioritization_score.R` runs (extra columns ignored)
- [ ] Multi-source: patches carry `in_fire` + `in_harvest`; residual reported; both-overlap tagged both
- [ ] `/code-check` clean per phase; PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
