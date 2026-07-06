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

`04_lulc_zones.R` (zone-stratified LULC — a sketch) and `05_prioritization_score.R`
(sub-basin prioritization — carries absolute machine/OneDrive paths) are **not yet generalized**
and are **not wired into `run_area.R`**. Deferred to a later issue.

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
| `aquatic_network.gpkg` | 1 | `streams_co3`, `waterbodies_co3` |
| `subbasins.gpkg` | 2 | Single layer |
| `floodplain_{scenario_id}.tif` | 2 | Floodplain raster per scenario |
| `floodplain.gpkg` | 2 | One layer per scenario (`co_ff02`, `co_ff04`, ...) |
| `floodplain_landcover.gpkg` | 3 | `classified_{scenario}_{year}`, `transition_{scenario}_{from}_{to}` |
| `rasters/{scenario_id}/` | 3 | Classified + transition tifs |
| `lulc_summary_{scenario_id}.rds`, `lulc_summary.rds` | 3 | Area/pct by class, sub-basin, year |

## Adding scenarios

Add a row to the area's `flood_scenarios.csv` with the desired parameters and set `run=TRUE`,
then re-run step 2. The new scenario appears as a layer in `floodplain.gpkg`; run step 3 with
that scenario id to classify land cover within it.
