# Task: Whole-network floodplains for every region: region mode for species: all, species items retired (#125)

**If we do it:** every region (Skeena, Fraser, Peace, Columbia) runs as whole-network floodplains (`species: all`, order >= 2, keyed by `blue_line_key`, #104) through `run_region.R`, and the publish layer picks its groups up from the region roster.
**If we never do:** whole-network areas run only standalone (`run_area.R`), none is published, and the catalogue stays on the per-species model we are moving away from.


## Context

Whole-network mode (`species: all`, #104) runs only standalone today. `run_region.R` refuses it in both
directions: the species pre-pass would query `access_all`, and reconciling would turn the area back
into a species item. #125 moves every region (Skeena, Fraser, Peace, Columbia) to the whole network and
retires the species items. That retirement is the publish layer's job (stac#75, stac#76). #117 (grid
pin) and #122 (DEM cache) have both landed.

**Decided at the gate (2026-10-13):**
- This branch carries the code, all four region files, and a **live Skeena run** (BULK, MORR, KISP).
  #125 stays open for the Fraser, Peace and Columbia runs, so the PR says "Relates #125".
- Species rows in `flood_scenarios.csv` and the species outputs in `data/<wsg>/` stay. They feed the
  README (#128) and stac staging until stac#76. A follow-up issue covers a prune pattern for them.
- No whole-network twin of neexdzii.
- DUNC joins `columbia.yml`.

**Measured during exploration (2026-10-13), and it changes the plan:**
- Order ≥ 2 km per group, in each region's schema, equals `fresh.streams_vw_bcfp` to the km for all
  23 groups. MCGR has 2,833 km in `fresh.streams`; #76 said 0, but that was the accessible network.
  PINE has 5,768 km, which matches bcfp, so #76's 10.8% shortfall does not appear in whole mode.
  Neither group is blocked for whole mode. Their runs will confirm it.
- Columbia (KOTL, LARL, SLOC) exists only in `fresh_default`, and BOWR, MCGR, THOM, LNTH and UNTH only
  in `fresh`. So the per-region `network_source` stays as it is.
- The freshness guard already handles whole mode (`fp_bcfp_km_sql("all", …)`, which compares total
  km). Columbia's `network_guard: warn` existed for species divergence, so it is dropped (strict).
- Every group has `streams_habitat_<sp>` rows in its region's schema, so step 1's habitat read will not
  refuse.
- Breakage found: `fp_readme_roster()` requires a `species:` key. `region_config-check.R` uses the
  live `config/bulk` and `config/morr` as fixtures, and those become whole-network areas. MORR's
  area-owned `targets:` block names `co_ff04` and `ch_ff06`. `run_region.R`'s coverage `rbind` fails
  whenever a group is SKIPPED, because the skipped frame lacks the `provenance` column.

## Phase 1: Region mode in `fp_region.R` (pure, offline-testable)
- [x] `fp_region_mode(reg)`: returns `"whole"` when the region says `network: whole`, else `"species"`.
  - It refuses any other `network:` value.
  - Whole mode refuses a `species:` key, an `attribute_by` other than `blue_line_key`, and a missing
    `network_source`.
  - Species mode refuses an empty `species` list, or one naming `all` (via `fp_region_refuse_whole`).
- [x] `fp_region_owned(reg, wsg, sp, min_order)`: builds the region-owned list. It is lifted from
  `run_region.R:116-121` so the runner and the checks build it one way. Whole mode forces
  `species: all` and `attribute_by: blue_line_key`, and `min_order` defaults to 2 (#110 floor).
- [x] `fp_region_plan()`:
  - Refuses an existing whole area only when the region is **not** whole (the species-to-all
    conversion becomes legal).
  - Calls `fp_whole_network_validate()` on the resulting area, so DRY catches it.
  - In whole mode, refuses an area whose `targets:` names any non-`all` scenario, with the remedy (the
    species items are retired, stac#76) in the message. `targets` stays area-owned.
- [x] `fp_region_cache_stale(prov, scenario)`: TRUE when `floodplain[<scenario>].inputs.flooded.version`
  is below 0.7.0 or absent (#117). That is DUNC's 10-12 record.
- [x] Update the comment block above `fp_region_refuse_whole` / `FP_SPECIES_WHOLE` to the new rule.

## Phase 2: `run_region.R`
- [x] Mode dispatch:
  - **Species mode** keeps its pre-pass; the pre-0.7.0 cache rule applies in both modes (review G3).
  - **Whole mode** has no species pre-pass. It runs a cheap per-group count of
    `<network_source>.streams` at order ≥ `min_order` instead, so a group absent from the schema is a
    loud SKIP, as MCGR would have been.
- [x] Use `fp_region_owned()`, and pass `base_scenarios("all")` at `min_order` 2.
- [x] Cache:
  - A whole-mode group is stale when `fp_region_cache_stale()` says so (it re-runs and reports why).
  - Fix the SKIP-row `rbind` (missing `provenance` column).
- [x] Update the header usage text and the startup message (`mode: whole`).

## Phase 3: Checks
- [x] `region_config-check.R`: move the fixtures off live config. Commit today's `config/morr/` and
  `config/bulk/` as frozen copies under `scripts/floodplain_lcc/fixtures/region_config/`. Every
  existing arm then runs on them unchanged.
- [x] Add whole-mode arms to `region_config-check.R`:
  - Converting a species area: `species` becomes `all`, `min_order` 2, `attribute_by` blue_line_key.
  - The `all` rows are appended and the species rows stay byte-identical.
  - Comments survive, and a second run is a byte-identical no-op.
  - `targets` refusal plus its control.
  - `fp_region_cache_stale` on 0.6.5 / 0.7.0 / absent.
  - `fp_region_mode` must-fail arms: `species` + `network: whole`, a missing `network_source`,
    `network: foo`, and `species: [bt, all]`.
- [x] `whole_network-check.R`: the region section goes from "refuse both directions" to "refuse unless
  whole".
  - Keep the must-fail arm for a species region naming `all`.
  - Keep the arm refusing a species region reconciling a whole area.
  - Add: a whole region converting a species area passes, and a whole plan with no `network_source`
    is refused.
- [x] Restore each new guard's defect once and confirm the check goes red (mutation table in
  `findings.md`).

## Phase 4: Region files + README roster
- [x] `skeena.yml`: add `network: whole` and drop `species`/`min_order`. Groups are `[BULK, MORR, KISP]`.
  Rewrite the coho rationale comments. Delete `skeena_ch.yml`.
- [x] `fraser.yml` and `peace.yml`: `network: whole`, drop `species`/`min_order`, and update the
  comments. PINE's "not in bcfp view" caveat and Fraser's co/ch note are now dead; replace them with
  the measured whole-network km.
- [x] `columbia.yml`: `network: whole`, `fresh_default`, and drop `network_guard: warn` (whole km
  matches bcfp to the km). Add DUNC and update its header and `config/dunc/area.yml`'s "not in
  columbia.yml" comment.
- [x] `fp_readme_roster()`: accept `network: whole` (species column `all`). Re-render README
  (`rmd_on = TRUE`, `update_figs = FALSE`) and run `readme_determinism-check.sh` and
  `readme_content-check.py`.

## Phase 5: Skeena live run
- [x] Hand-edit `config/{bulk,morr,kisp}/area.yml` before the run:
  - Remove MORR's `targets:` block.
  - Rewrite the species comments the in-place writer would leave beside `species: all`, including
    the trailing `# coho runs the whole Bulkley`.
- [x] `DRY=1 Rscript scripts/run_region.R skeena`, and confirm the reconciliation reads as planned.
- [x] `caffeinate -s Rscript scripts/run_region.R skeena > log 2>&1`, run in the background and gated
  on in-band errors plus output mtimes, not the exit code.
- [x] Per area:
  - Run `provenance-check.R`, `composition-check.R <area>` and `dem_cache-check.R`.
  - Check that classified coverage ≈ floodplain area.
  - Record km, km², gross tree loss, and wall and peak-RSS figures in
    `scripts/floodplain_lcc/logs/<date>_whole_network_skeena.md`.
- [x] Commit the reconciled configs and the log.

## Phase 6: Docs + follow-ups
- [x] `CLAUDE.md`:
  - The region mode.
  - The refuse-unless-whole rule.
  - Skeena's whole-network numbers.
  - The MCGR/PINE whole-mode measurement.
  - Removing `skeena_ch.yml` from the KISP pattern note.
  - Columbia's guard.
  - The `run_region.R` description.
- [x] File follow-ups (#131 prune issue; #76 body updated with the whole-mode measurement):
  - A species-output prune pattern for `gpkg_prune-legacy.R`, gated on stac#76 and #128.
  - Comment on #76 with the whole-mode MCGR/PINE measurement.
- [x] Re-check origin (`git log HEAD..origin/main`), then `/code-check branch`.

## Validation

- [x] Tests pass (`region_config-check.R`, `whole_network-check.R`, `provenance-check.R` offline)
- [x] `/code-check` clean (each commit, or once over the branch with `/code-check branch`) — 3 rounds + plan review; ended by enumeration (findings.md)
- [x] PWF checkboxes match landed work
- [x] `/planning-archive` on completion
