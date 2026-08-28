# Task: run_region.R silently destroys hand-maintained area config (#44)

`run_region.R:96-117` regenerates `config/<wsg>/area.yml` and `flood_scenarios.csv` for every
runnable group on **every invocation**, from `base_scenarios(sp)` — a function that knows about one
species and writes `citations = ""`. It also deletes `break_points.csv`. Three silent losses: the
second species' scenario rows (undoing #23), every citation, and `break_points.csv`.

**It does this under `DRY=1` too** — the dry path skips the *pipeline*, not the config write, so the
safe-looking preview command is exactly as destructive as a real run. That is how it surfaced: a
`DRY=1` run to preview an unrelated one-line region change came back with 50 deletions across
`config/{bulk,morr}/`.

## The ownership rule (stated once, used everywhere)

Region-owned keys — the region file is the source of truth, and stale values must be **cleared**,
not merely overwritten:

    name  watershed_group  species  min_order  schema  primary_scenario
    network_source  network_guard  attribute_by

Everything else in `area.yml` (`subset`, `tile_size`, `change_interval`, anything added later) is
area-owned and survives. Strip the region-owned set from what is on disk, then apply the region's
current values — a plain `modifyList` would silently fail to clear a dropped key.

`flood_scenarios.csv`: create when absent; append when the resolved species has no rows; never
rewrite existing rows. `break_points.csv`: never deleted.

## Phase 1 — Factor config resolution into a pure, testable function
- [x] `fp_region_plan(cfg_dir, region_owned, base)` in `scripts/floodplain_lcc/fp_region.R` — reads
      what is on disk, returns the merged `area.yml` list, the scenario rows to write (or `NULL`),
      and a human-readable action per file
- [x] `fp_region_write(plan)` — applies it. No DB, no globals, no side effects in the planner
- [x] Region-owned key set defined once, as a constant, so runner and checker cannot drift

## Phase 2 — Make `DRY=1` actually dry
- [x] Move config resolution before the dry gate and the write after it
- [x] `DRY=1` prints the per-group action lines and writes nothing
- [x] Correct the usage comment at `run_region.R:6-7` ("plan + generate configs only") — the wording
      that made the trap look intentional

## Phase 3 — Wire it into the runner
- [x] Replace `run_region.R:96-117` with the plan/write pair; `base_scenarios()` stays as the
      generator for the absent-file case
- [x] Log per group what changed, so a real run says what it touched

## Phase 4 — Assert the acceptance criteria
- [x] `scripts/floodplain_lcc/region_config-check.R` — runs `fp_region_plan` against a temp copy of
      `config/morr` and `config/bulk`, asserts #44's three criteria plus the ownership rule. No DB
- [x] Cold path: assert it on a config dir that does NOT exist (the create path every new group
      takes), not only the merge path
- [x] The regression that would have caught this: a stale region-owned key is cleared when the
      region file stops setting it

## Phase 5 — Docs + close
- [x] `CLAUDE.md`: the ownership rule, and that `DRY=1` is now genuinely read-only. The current text
      documents the behaviour being fixed ("**writes** each group's `area.yml`", hand-edits "do not
      survive") and must not be left standing
- [x] File the MORR `break_points.csv` doc/config inconsistency as its own issue — #48
- [ ] `/planning-archive`, `/gh-pr-push`

## Validation
- [x] `DRY=1 Rscript scripts/run_region.R skeena` -> `git status` clean (the one that failed before)
- [x] A real `run_region.R skeena` preserves MORR's six `ch_*` rows, all 12 citations, break_points
- [x] `FP_SPECIES=ch FP_PRIMARY_SCENARIO=ch_ff06 Rscript scripts/run_area.R morr` still resolves
- [x] `region_config-check.R` passes, including create path and stale-key regression
- [x] A generated-only group (`config/tabr/`) is byte-identical after a region run
- [ ] `/code-check` clean on each commit
