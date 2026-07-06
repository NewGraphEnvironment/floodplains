# Task: Generalize pipeline to AOI-driven, prove Neexdzii parity, run MORR (#1)

The `scripts/floodplain_lcc/01–05` are the verbatim Neexdzii (rwk) originals — per-area
identity (`blk`, `drm_confluence`, `aoi_wsg`, `schema`, `min_order`) is hardcoded and duplicated
across scripts, outputs write to a shared `data/lulc/`, CSV controls are read from `data/lulc/`
instead of the scaffolded `config/<area>/`, and the QGIS-copy blocks call
`rmarkdown::yaml_front_matter(here::here("index.Rmd"))$params` — but `index.Rmd` does not exist
in this repo, so those calls error today. `run_area.R` is a skeleton that `stop()`s.

Lift the per-area bits into `config/<area>/`, refactor 01–03 into explicit config-driven
functions, wire a working runner, prove Neexdzii parity, then run MORR. Method stays in the
packages (`link`/`flooded`/`drift`/`fresh`); we only generalize the driver.

**Scope: steps 1–3 only** (scripts 01/02/03). Scripts 04 (zones sketch) and 05 (prioritization —
absolute paths, duplicated `blk`/`drm`) are out of scope, deferred.

**Parity targets** (rwk `planning/archive/2026-07-issue-152-*`): coho order-3+ network
**678.2 km** · floodplain `co_ff04` **171.0 km²** · tree loss **943.13 ha**. Allow ~0.004% VCA
raster noise. `link` is 0.44.2 locally (≥0.44.0).

## Approved architecture

Explicit config object + step functions — no ambient/sourced context; data flows as visible
arguments and returns.

- `run_area.R` is the single entry point and the only place mapping area → config:
  `cfg <- fp_read_config(area)`; then `fp_network(cfg)`, `fp_floodplain(cfg)`,
  `fp_lulc(cfg, scenario = cfg$primary_scenario)`.
- `fp_read_config(area)` returns one `cfg` list: `name`, `watershed_group`, `species`,
  `min_order`, `schema`, `subset` (list or `NULL`), `primary_scenario`, `dir_out`
  (= `here::here("data", area)`), `scenarios` (df), `break_points` (df). Lives in `run_area.R`.
- Each `0X` script defines one function taking `cfg`; logic unchanged, only literals → `cfg$…`
  and paths → `cfg$dir_out`.
- `index.Rmd` dependency removed entirely; QGIS auto-copy blocks deleted from 01/02/03. GIS
  landing is a separate explicit step (Phase 4).

Adding a future area = adding `config/<area>/`, zero code change.

## Phase 1 — Generalize 01–03 to config-driven + working runner

- [ ] `fp_read_config(area)` in `run_area.R` (yaml + 2 CSVs → `cfg`; create `dir_out`). Add
      `primary_scenario: co_ff04` to both `area.yml` files.
- [ ] `01_network_extract.R` → `fp_network(cfg)`: literals → `cfg$…`; **branch on subset** —
      `NULL` = whole WSG (skip `frs_watershed_at_measure` + `st_filter`), else confluence subset;
      delete QGIS-copy block; keep `lnk_config("default")` as method constant.
- [ ] `02_floodplain_model.R` → `fp_floodplain(cfg, scenarios = "run")`: break_points + scenarios
      from `cfg`; paths → `cfg$dir_out`; keep run/all/id selection; delete QGIS-copy block; fix
      stale header filenames.
- [ ] `03_lulc_classify.R` → `fp_lulc(cfg, scenario)`: default `cfg$primary_scenario`; paths →
      `cfg$dir_out`; scenarios from `cfg`; delete copy_to_qgis/index.Rmd blocks; keep `years`,
      `patch_min_m2`, `ag_classes`, `zone_col` as method constants.
- [ ] Build `run_area.R` driver: parse `<area> [steps]`, source packages.R + step files, resolve
      `cfg`, dispatch steps 1/2/3 in order, remove skeleton `stop()`.
- [ ] `scripts/run_areas.sh` — thin multi-area loop modelled on `link`'s `study_area_run.sh`
      (per-area soft-fail + timestamped logs).
- [ ] Update `scripts/floodplain_lcc/README.md`: CSVs in `config/<area>/`, outputs in
      `data/<area>/`, drop index.Rmd/External-Paths section, note 04/05 deferred.

## Phase 2 — Prove Neexdzii parity (regression gate)

- [ ] Run `Rscript scripts/run_area.R neexdzii` (steps 1,2,3) against local `fwapg` + `link` 0.44.2.
- [ ] Verify from `data/neexdzii/` outputs:
  - network km: `sum(sf::st_length(streams_co3))/1000` → **678.2 km**
  - floodplain km²: `sum(sf::st_area(co_ff04))/1e6` → **171.0 km²**
  - tree loss ha: sum `area_ha` of `transition_co_ff04_2017_2023` where
    `from_class == "Trees" & to_class != "Trees"` → **943.13 ha** (±~0.004%).
- [ ] If any number is off beyond VCA noise, fix before Phase 3.

## Phase 3 — Run MORR (first new area)

- [ ] Resolve `config/morr/area.yml` open question: whole WSG (`subset: null`, default) vs. reach
      subset. Default: whole WSG.
- [ ] Replace placeholder MORR `break_points.csv` with real MORR points; review
      `flood_scenarios.csv`.
- [ ] Run `Rscript scripts/run_area.R morr` steps 1–3.
- [ ] Record MORR headline numbers in `planning/active/findings.md`.

## Phase 4 — Land MORR outputs in GIS (local, interim)

- [ ] Copy MORR gpkgs into the rwk QGIS project under a `morr/` subdir — local only, **do NOT
      Mergin-sync**.

## Validation

- [ ] Neexdzii parity gate (Phase 2) passes before MORR is trusted
- [ ] `Rscript scripts/run_area.R <area>` runs clean end-to-end for both areas
- [ ] `/code-check` clean on each commit; PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
