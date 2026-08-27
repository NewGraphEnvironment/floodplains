# Task: Add a columbia region (KOTL/LARL/SLOC) — bull trout (#36)

`stac-floodplains-bc` has a spatial extent of `-128.77, 52.71, -118.48, 56.47` — northern BC.
Nelson sits at 49.5 N, so the collection returns nothing over the Kootenays and the
land-cover-change framework has never been run there. The framework is config-driven and
area-agnostic, so this is a configuration gap, not a capability one.

Decisions taken at plan time (user): **bt only** for all three groups (the pre-pass picks the
first species with any access, not the best, so `wct` never fires — documented, not live);
**through publish**, since the collection extent is the stated problem.

## Phase 1 — Region + area configs
- [x] `run_region.R`: pass `network_source` / `network_guard` from the region yml into the
      generated `area.yml` (it currently writes neither, so a region can only BUILD)
- [x] Write `config/regions/columbia.yml` — bt/wct preference, GRAB from `fresh_default`,
      guard `warn`, with the barrier history and the guard-calibration finding in the header
- [x] `DRY=1 Rscript scripts/run_region.R columbia` — verify pre-pass resolves **bt** for all
      three with zero SKIPs, and the generated `area.yml`s carry species/scenario/source
- [x] `/code-check` + commit

## Phase 2 — Run the region
- [x] `caffeinate -s Rscript scripts/run_region.R columbia` (steps 1,2,3), resumable
- [x] Gate every group on BOTH in-band error markers (`Execution halted|Error:` count 0) AND
      `lulc_summary.rds` mtime newer than a run-start marker — a wrapper's exit 0 is not success
- [x] Verify LULC classified coverage ≈ floodplain area per group (the "scales on small AOIs,
      breaks on large ones" failure class). **KOTL at 936,950 ha is the largest group run to
      date** (BULK, previous largest, is 776,201 ha)
- [x] KOTL contingency: on stall/OOM use `FP_TILE_SIZE=` + `run_area.R`, never a hand-edited
      `area.yml` (run_region rewrites it every invocation)

## Phase 3 — Report coverage + attribution
- [x] Per group: network km, floodplain `bt_ff04` km², tree loss ha, fire/harvest/residual split
- [x] Cross-check the split against the BULK baseline (fire 5% / harvest 36% / residual 62%)
- [x] Confirm the item key (`wsg`, `species`, `scenario`) is native on the new layers

## Phase 4 — Publish
- [ ] stac two-step: `run_pipeline.sh` then `catalogue_release.sh` (order matters)
- [ ] Verify 20 items live, the three `*_bt_ff04` items resolve, assets 200, and the
      **collection extent now reaches below 49.5 N** — the issue's actual acceptance test

## Phase 5 — Docs + close
- [ ] `README.md` + `CLAUDE.md`: 17 → 20 groups, four regions, Columbia numbers
- [ ] `/planning-archive`, `/gh-pr-push` (PR body refs rtj#213, sred#35)

## Validation
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
