# Task: The accuracy module reads area.yml's scenario, not its design's: NECR's ch_ff04 sample is checked against all_ff04 (#140)

**If we fix it:** the accuracy module reads the population its reference sample was drawn from, whatever an area's config says today.
**If we never do:** every NECR accuracy stage reads `all_ff04`, a different grid and population from the `ch_ff04` sample in `reference/necr/`, and nothing checks that the two match.


## Context

`fp_acc_area()` (`scripts/landcover_accuracy/fp_accuracy.R:12-24`) takes the scenario from
`config/<area>/area.yml`. #125 moved NECR's to `all_ff04`; NECR's design (`reference/necr/design.json`,
`transition_layer = transition_ch_ff04_2017_2023`, dims 6288 x 8945) is on `ch_ff04`. Nothing compares
the two, so every stage now reads a different grid and population from the sample.

Measured in exploration (2026-10-23):
- `data/necr/rasters/ch_ff04/transition.tif` is still exactly the design grid (8945 x 6288, origin
  381677.13 / 6008953.56); `all_ff04` is 9423 x 6832. So a grid guard against `design.json` is viable.
- **Live consequence:** the B review project (`necr_lulc_review_b/patches.gpkg`, rebuilt today 06:08)
  carries all_ff04's **11,469** patches; the A project (10-06) carries ch_ff04's **5,692**. Only the
  "9 After labelling" theme reads it.
- `wetland_composition.csv` has no scenario column; its 6,436.64 ha is ch_ff04's. composition-check (5)
  binds it to whatever `area.yml` names (`composition-check.R:280`).
- #131's body already carries "never prune a species output a committed design names".

Stages reading the scenario: `fp_acc_grid` (via `cfg$dir_rast`), `sample_draw-pilot.R`,
`reference_composition-wetland.R`, `reference_omission-disturbance.R`, `review_build-qgis.R`,
`window_count-clear.R`, `wayback_coverage-area.R`, `floodplain_lcc/channel_probe-migration.R`. All
go through `fp_acc_area()`, so fixing the resolver fixes them all.

## Decided at the gate

- Rebuild the B review project in the PR run once the fix lands (user, 2026-10-23: nobody is in it).
- Scenario and change interval come from `design.json`'s `transition_layer` when a design exists;
  `area.yml` only when none does (first draw, or an area with no `reference/`). `area.yml` differing
  is an INFO line, not a refusal: it legitimately moved for the pipeline.
- design.json is not rewritten (never hand-edited); the scenario is parsed from `transition_layer`.

## Phase 1: Resolve the scenario from the design
- [ ] `fp_acc_design_scenario(path)`: parse `transition_layer` (`^transition_(.+)_([0-9]{4})_([0-9]{4})$`) into scenario + interval; refuse a malformed or missing value. Also usable by #131.
- [ ] `fp_acc_area(area, scenario = NULL)`: with a design, take scenario, species (scenario prefix) and interval from it, record `cfg$scenario_source = "design"`, refuse an explicit `scenario` that differs; message when area.yml names another. Without a design, today's behaviour, `scenario_source = "area.yml"`.
- [ ] `fp_acc_grid()`: when a design exists, refuse a transition grid whose dims, extent or CRS differ from `design.json`'s (the guard that catches the wrong grid whatever the scenario string says).
- [ ] `sample_draw-pilot.R`: takes an optional `[scenario]` argument; a scenario other than the design's is refused unless `FORCE=1` (a redraw on a new grid orphans every label anyway).
- [ ] `accuracy-check.R`: offline arms on a temp reference dir — design wins over area.yml; explicit mismatch refused; malformed `transition_layer` refused; grid mismatch refused, with must-fail arms (the pre-fix resolver returns area.yml's scenario; a grid guard with the dims check removed passes the wrong grid).

## Phase 2: wetland_composition.csv records its scenario
- [ ] `reference_composition-wetland.R` writes a `scenario` column.
- [ ] `composition-check.R` (5): compare only when the csv's scenario equals the scenario under check; a csv without the column is an INFO skip ("predates #140; re-run reference_composition-wetland.R"); drop the `identical(scen, acfg$primary_scenario ...)` gate.
- [ ] Re-run `reference_composition-wetland.R necr` (needs fwapg; check `docker ps` + `pg_isready -h localhost` first). Expect fwa_wetland 2017 total 6,436.64 ha unchanged, now tagged `ch_ff04`.

## Phase 3: Repair what ran on the wrong scenario, docs, #131
- [ ] Re-run `REVIEWER=b review_build-qgis.R necr`; confirm `patches.gpkg` has 5,692 features and `labels.gpkg` is unchanged (cmp before/after).
- [ ] CLAUDE.md #93 bullet: the module's scenario comes from the design; `area.yml` only before a first draw.
- [ ] Edit #131's body to name `fp_acc_design_scenario()` as the check the prune must call.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

Verification:
- `Rscript scripts/landcover_accuracy/accuracy-check.R` → ALL PASS, new arms included; each must-fail arm shown red against the pre-fix form (in a copy).
- `Rscript scripts/floodplain_lcc/composition-check.R necr ch_ff04` → (5) PASS at 6,436.64 ha; `composition-check.R necr` (all_ff04) → (5) INFO skip, not FAIL. Report any other FAIL in the species run as pre-existing (#53 forward-only), not this work.
- A NECR stage that calls `fp_acc_grid` (e.g. `reference_omission-disturbance.R necr`) reads `ch_ff04` and its output matches the committed one; temporarily pointing the resolver at all_ff04 (in a copy) is refused by the grid guard.
- B project patches 5,692.
