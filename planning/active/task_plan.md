# Task: Wetland context flag on transition patches: undated context: overlays (in_wetland from FWA wetlands) (#95)

Wetland-related change patches cannot be found by attribute. #92 decided how to flag them, and #93 needs the flag to build its wetland strata. It was carved out of #92 so it can ship alone, ahead of the report.

NECR scale for context (2026-09-27): about 65 ha left Flooded Vegetation 2017→2023 (Rangeland 30.1 ha over 104 patches, Water 28.4 ha) and about 35 ha entered it.

## Plan context

#93 (land-cover accuracy) needs wetland-related change patches to be findable by attribute, so it can build its wetland strata. #92 decided the design: an **undated `context:` list** in `config/disturbance.yml`, kept separate from `sources:`.

The separation is needed because every `sources:` entry is read as a *cause*:

- `fp_disturbance_report()` counts every `in_<source>` as explaining tree loss (`scripts/floodplain_lcc/fp_disturbance.R`).
- `fp_fig_attribution()` builds the README bar from `fp_readme_sources()` (`scripts/readme_functions.R:73,303`).

So an `in_wetland` under `sources:` would shrink the "not attributed" share for no reason.

Exploration findings that shape the plan:

- **`.dst_fetch()` hardcodes `WHERE <year_col> BETWEEN …`** (`fp_disturbance.R:27`). An undated entry needs the predicate skipped, and a *source* without `year_col` has to be refused rather than silently un-windowed.
- **Carry collision.** `fp_disturbance_tag()` writes carried columns straight onto the patches (`patches[[a]] <- …`). `fwa_wetlands_poly` has an `area_ha` column, so carrying it would **overwrite the patch's own `area_ha`** with no warning. Carry only `waterbody_poly_id` (the unique key), and add a guard that refuses a carry name colliding with any column the tagger does not own.
- **`fire_tag.R` still writes the #55 orphan** (`transition_*_disturbance`, lines 40–41), while step 3 tags the main layer. Its `on.exit(dbDisconnect)` sits at script top level, so it never fires (code-check-r rule).
- **Config plumbing.** `fp_read_config()` loads only `$sources` into `cfg$disturbance` (`scripts/run_area.R:157`). Step 3 tags inside `if (!is.null(cfg$disturbance))` (`03_lulc_classify.R:218`), and item keys are set *after* tagging (line 228).
- **Provenance does not record the disturbance config**, so no provenance field moves.
- **`stac_floodplains_bc` has no reference to `in_*` columns**, so a new column passes through on the next rebuild. The coupling is a heads-up on stac_floodplains_bc#6 only.
- The repo's check scripts are standalone `*-check.R` files with no testthat. #91 says a check must **not default to one area**.
- NECR has 4,495 FWA wetland polygons. `waterbody_poly_id` is the unique key, and the table has a gist index on `geom`.

## Phase 1: Offline check first (fails until Phase 2)
- [x] `scripts/floodplain_lcc/disturbance-check.R`, with no database. It covers:
  - the validator refuses a `sources:` entry with no `year_col`, a `context:` entry *with* a `year_col`, duplicate names across both lists, duplicate carry columns across entries, and a missing required field
  - the query builder includes `BETWEEN` for a source and omits it for a context entry
  - the carry-collision guard refuses carrying `area_ha`, but allows re-tagging a layer that already carries this tagger's own columns (`fire_year`, `in_fire`)
  - on synthetic patches tagged through an injected stub fetch, `fp_disturbance_report()` gives an identical residual with and without the `context:` entry
  - **must-fail arm:** moving `wetland` under `sources:` changes the residual
- [x] Run it and confirm it goes red for the right reasons.

## Phase 2: Tagger and config
- [ ] `fp_disturbance.R`:
  - `fp_disturbance_validate(dst)` (pure), enforcing the rules above
  - `.dst_query()` (pure SQL builder), with the year predicate only when `year_col` is set
  - `.dst_fetch()` calls `.dst_query()`
  - `fp_disturbance_tag()` gains a `fetch = .dst_fetch` argument so the check can inject a stub, plus the carry-collision guard
  - update the header comment to document `context:`
- [ ] `config/disturbance.yml`: add a `context:` list with `wetland` (`whse_basemapping.fwa_wetlands_poly`, `geom`, `carry: [waterbody_poly_id]`). The header explains why it is not under `sources:` and names the `area_ha` collision.
- [ ] `run_area.R` `fp_read_config()`: validate the file, set `cfg$disturbance` from `sources` (unchanged) and `cfg$disturbance_context` from `context`.
- [ ] `03_lulc_classify.R`: tag `c(sources, context)` when either is non-null. The attribution message names both. Item keys stay last.
- [ ] Phase 1 check passes. Restore-the-bug: delete the year-predicate branch and the collision guard in a copy, and confirm the check goes red.

## Phase 3: fire_tag.R writes the main layer
- [ ] Tag with sources + context, then write back onto the **main** transition layer (not `_disturbance`), keeping the item keys `wsg`, `species` and `scenario` as the last columns, as step 3 does. Replace the top-level `on.exit` with an explicit disconnect. Print an `in_<context>` count and area line after the attribution report. Update the header comment.

## Phase 4: Live, NECR and BULK (the database is the `fresh-db` container; `pg_isready -h localhost`)
- [ ] Snapshot both areas' transition layers, then run `fire_tag.R necr` and `fire_tag.R bulk`.
- [ ] Extend `disturbance-check.R` with a live section. It **requires** an area argument (#91) and prints the resolved area and layer first. It asserts:
  - `in_wetland` and `waterbody_poly_id` are present
  - `in_fire`, `in_harvest`, their carried columns, `area_ha` and `patch_id` are identical to the snapshot, so the BULK attribution figure's inputs are unchanged
  - there is no `_disturbance` layer
  - `gpkg_prune-legacy.R` with `DRY=1` reports nothing
- [ ] `fp_disturbance_report()` numbers for BULK are identical before and after.
- [ ] Measure NECR: FWA wetland area, the share of it inside the `ch_ff04` floodplain, and the wetland-flagged patch count and hectares. Record these in `findings.md`.

## Phase 5: Docs
- [ ] CLAUDE.md disturbance bullet: the `context:` list, why it is not a source, the carry-collision guard, and that `fire_tag.R` now writes the main layer. **Forward-only:** other areas gain `in_wetland` on their next step 3 or `fire_tag.R` run.
- [ ] README.Rmd: one sentence in the attribution paragraph (context layers such as `in_wetland` locate change, and never count as a cause). Render with `rmd_on = TRUE`, then run `readme_determinism-check.sh` and `readme_content-check.py`.
- [ ] Update #93's body where it assumed the flag's shape, and comment on stac_floodplains_bc#6 with the new columns.

## Phase 6: Close out
- [ ] `/code-check` on each commit, `/planning-archive`, `/gh-pr-push` (Closes #95).

## Verification (from the approved plan)

- `Rscript scripts/floodplain_lcc/disturbance-check.R`: the offline section passes, and each must-fail arm is shown to go red against a restored bug.
- `Rscript scripts/floodplain_lcc/disturbance-check.R necr` and `… bulk`: the live section passes.
- `DRY=1 Rscript scripts/floodplain_lcc/gpkg_prune-legacy.R necr` (and bulk) prune nothing.
- `bash scripts/readme_determinism-check.sh` and `python3 scripts/readme_content-check.py` pass.
- The existing `bridge-check.R necr ch_ff04` still passes, since the bridge reads the same transition layer.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
