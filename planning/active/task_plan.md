# Task: Support multiple species per area coexisting in shared data/<area>/ outputs (#23)

The pipeline is one-species-per-area: `area.yml` carries a single `species`, and each run writes
per-species outputs into `data/<area>/`. Let a second species coexist with the first in the SAME
`data/<area>/` gpkgs — model MORR chinook (`ch_ff02/04/06` floodplains + LULC `ch_ff06`) alongside
the existing coho, as new species-prefixed layers, WITHOUT destroying the coho outputs.

**Regression contract:** neexdzii coho parity must still reproduce 678.2 km network / 171.0 km²
co_ff04 / 943 ha tree loss (±~0.004%).

**Scope boundary:** coexistence at the data layer (01 network, 02 floodplain, 03 LULC) + driver.
Zones (04) and prioritization (05) remain coho-hardwired — out of scope.

**Species selection (decided):** `FP_SPECIES` + `FP_PRIMARY_SCENARIO` env overrides (not a CLI arg —
`run_region.R` calls `run_area.R` via `system2` positional args; env propagates for free). Do NOT
regex-swap the `co`→`ch` prefix; default `primary_scenario` to `paste0(species,"_ff04")` only when
unset, and guard that it belongs to the selected species and exists in `cfg$scenarios`.

## Phase 1 — Species-keyed, non-destructive network (01 + 02 read + run_region read)
- [x] Derive network layer names `paste0("streams_", cfg$species, cfg$min_order)` /
      `paste0("waterbodies_", cfg$species, cfg$min_order)` in `01` (write) and `02` (read).
      Coho-order-3 → `streams_co3` (backward compatible).
- [x] `01`: remove `file.remove(aquatic_network.gpkg)`. Write both streams and waterbodies
      with `append = file.exists(out_gpkg), delete_layer = TRUE`.
- [x] `01`: species-suffix stamp sidecar → `aquatic_network_<sp><min_order>.stamp.md`; update
      `streams_co3` message + header doc strings.
- [x] `run_region.R:131`: replaced hardcoded `layer = "streams_co3"` with
      `paste0("streams_", sp, min_order)`.

## Phase 2 — Species-scoped, non-destructive floodplain + land-cover (02 + 03)
- [x] `02`: removed `file.remove(floodplain.gpkg)`. Each scenario layer written with
      `append = file.exists(out_gpkg), delete_layer = TRUE`.
- [x] `02`: filter scenario selection by species:
      `run_scenarios <- run_scenarios[run_scenarios$species == cfg$species, ]`.
- [x] `03`: removed `file.remove(floodplain_landcover.gpkg)` — the blocker; L112's
      `append = file.exists(out_lc_gpkg)` already handles create/preserve.
- [x] `03`: documented generic `lulc_summary.rds` as last-writer-wins pointer;
      per-scenario `lulc_summary_<scenario_id>.rds` is the durable store. No consumer change.

## Phase 3 — Runtime species selection (run_area) + MORR config + docs
- [ ] `run_area.R` `fp_read_config()`: add `FP_SPECIES` + `FP_PRIMARY_SCENARIO` env overrides
      (parallel L54-66); default `primary_scenario <- paste0(cfg$species, "_ff04")` only when unset;
      guard `stop()` if resolved `primary_scenario` not a row in `cfg$scenarios` for the species.
- [ ] Add `ch_ff01..12` rows (copy from `config/ufra/flood_scenarios.csv`) to
      `config/morr/flood_scenarios.csv` — AFTER the Phase-2 species filter is in place.
- [ ] Update `scripts/floodplain_lcc/README.md` (L50/53): species-keyed layers,
      `FP_SPECIES`/`FP_PRIMARY_SCENARIO`, and the 04/05-still-coho scope boundary.

## Phase 4 — Parity gate + MORR chinook run
- [ ] Reset `data/neexdzii/` clean; re-run `run_area.R neexdzii` (1,2,3); verify 678.2/171.0/943.
- [ ] Run `FP_SPECIES=ch FP_PRIMARY_SCENARIO=ch_ff06 caffeinate -s Rscript scripts/run_area.R morr
      1,2,3`; verify coho `co_*` layers preserved and `ch_*` coexist in `data/morr/` gpkgs.
- [ ] Record MORR chinook headline numbers (network km, ch_ff02/04/06 km², ch_ff06 tree loss) in
      `findings.md`.

## Validation
- [ ] neexdzii parity gate passes on a clean dir (regression contract)
- [ ] `data/morr/` shows both `co_*` and `ch_*` layer families coexisting (co untouched)
- [ ] Re-running MORR coho after the chinook run still reproduces the coho layers (idempotency)
- [ ] `/code-check` clean on each commit; PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
