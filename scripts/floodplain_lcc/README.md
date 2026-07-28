# Floodplain Land Cover Change Pipeline

Modelled floodplain delineation and satellite-derived land cover change analysis, run per area
(a watershed group, optionally subset to a reach). Driven by `scripts/run_area.R`.

## Architecture

Each step is a function taking a single `cfg` list (built once by `fp_read_config()` in
`run_area.R` from `config/<area>/`). No ambient/sourced context — data flows as explicit
arguments. Adding a new area is adding `config/<area>/`; the code does not change.

| Step | Script | Function | Tool | Purpose |
|------|--------|----------|------|---------|
| 1 | `01_network_extract.R` | `fp_network(cfg)` | link/fresh | Coho-accessible stream network (order ≥ `cfg$min_order`) + filtered waterbodies |
| 2 | `02_floodplain_model.R` | `fp_floodplain(cfg, scenarios = "run")` | flooded | Sub-basins + VCA floodplain at each selected flood_factor scenario |
| 3 | `03_lulc_classify.R` | `fp_lulc(cfg, scenario = cfg$primary_scenario)` | drift | Classify land cover + transition (tree loss / ag expansion) within the floodplain |

Zone-stratified LULC and sub-basin prioritization are possible future steps — not yet built.

Steps 1–2 need the fwapg database — see [Prerequisite — fwapg database](../README.md). The DEM
comes from the national MRDEM-30 via `flooded::fl_dem_aoi()`; LULC imagery from the Microsoft
Planetary Computer STAC.

## Running

```sh
Rscript scripts/run_area.R <area> [steps]     # steps default "1,2,3"
Rscript scripts/run_area.R neexdzii            # full pipeline for one area
Rscript scripts/run_area.R morr 1,2            # steps 1 and 2 only
scripts/run_areas.sh neexdzii morr             # loop several areas (soft-fail + logs)
```

## Config (`config/<area>/`)

| File | Purpose |
|------|---------|
| `area.yml` | Area identity: `watershed_group`, `species`, `min_order`, `schema`, `subset` (blk + drm, or `null` for whole WSG), `primary_scenario` |
| `flood_scenarios.csv` | VCA parameters per scenario. `run=TRUE` rows execute (step 2 default). |
| `break_points.csv` | Sub-basin delineation points on the FWA network (step 2) |

## Outputs (`data/<area>/`, gitignored)

Multi-layer GeoPackages grouped by theme; layer names include the scenario ID so outputs are
self-documenting.

| GeoPackage / file | From | Layers / contents |
|-------------------|------|-------------------|
| `aquatic_network.gpkg` | 1 | `streams_{sp}{order}`, `waterbodies_{sp}{order}` (e.g. `streams_co3`) |
| `subbasins.gpkg` | 2 | Single layer |
| `floodplain_{scenario_id}.tif` | 2 | Floodplain raster per scenario |
| `floodplain.gpkg` | 2 | One layer per scenario (`co_ff02`, `co_ff04`, ...) |
| `floodplain_landcover.gpkg` | 3 | `classified_{scenario}_{year}`, `transition_{scenario}_{from}_{to}` |
| `rasters/{scenario_id}/` | 3 | Classified + transition tifs |
| `lulc_summary_{scenario_id}.rds`, `lulc_summary.rds` | 3 | Per-scenario store; `lulc_summary.rds` = last-writer-wins pointer |

## Multiple species per area

Outputs are keyed by species (`streams_{sp}{order}`) and by species-prefixed scenario id
(`co_ff04`, `ch_ff06`), so a second species coexists in the same `data/<area>/` gpkgs without
destroying the first — re-running a species replaces only its own layers. Run a non-default species
against an area's config with env overrides (no config edit):

```
FP_SPECIES=ch FP_PRIMARY_SCENARIO=ch_ff06 Rscript scripts/run_area.R morr 1,2,3
```

The area's `flood_scenarios.csv` must carry the target species' rows (step 2 runs only rows whose
`species` matches). **Scope:** coexistence is at the data layer (steps 1–3); zone-stratified LULC
and prioritization are future work, not yet built.

## Disturbance attribution

Step 3 tags each transition (change) patch with the disturbance layers listed in the shared
`config/disturbance.yml` (province-wide DataBC layers loaded into fwapg via `bc2pg`). Each source
adds `in_<name>` + carried attributes (e.g. `in_fire` + `fire_year`/`fire_number`, `in_harvest` +
`harvest_start_year_calendar`) from the dominant overlapping feature, windowed to `change_interval`
(default 2017–2023, one source of truth also driving the transition years). Attribution is
**additive** — a patch may match several sources (burned AND salvage-logged) — so the residual
(matches nothing) is the classification-noise floor. `fp_disturbance.R` holds the routine; the AOI
bbox is pushed into the SQL server-side so a province-wide layer never streams into R.

Config is opt-in by file presence: no `config/disturbance.yml` ⇒ step 3 runs unchanged (no DB conn,
no columns). Adding a source is config-only. `scripts/floodplain_lcc/fire_tag.R <area> [scenario]`
re-tags an existing gpkg (writes a `*_disturbance` layer) without re-running the STAC fetch.

Representative result (Trees→non-Trees loss, BULK co_ff04): fire 5% · harvest 36% · residual 62%.
**Scope:** fire + harvest wired; pest/forest-health deferred (the config contract already supports
it via `filter:` + `confidence:`). The transition layer now carries N disturbance attributes → the
STAC publish schema must carry them (NewGraphEnvironment/stac_floodplains_bc#6).

## Adding scenarios

Add a row to the area's `flood_scenarios.csv` with the desired parameters and set `run=TRUE`,
then re-run step 2. The new scenario appears as a layer in `floodplain.gpkg`; run step 3 with
that scenario id to classify land cover within it.
