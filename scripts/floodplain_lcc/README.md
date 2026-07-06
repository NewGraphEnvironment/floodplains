# Floodplain Land Cover Change Pipeline

Modelled floodplain delineation and satellite-derived land cover change analysis for the Neexdzii Kwah watershed.

## Pipeline Order

| Script | Tool | Purpose |
|--------|------|---------|
| `01_network_extract.R` | fresh | Build coho-accessible stream network + filtered waterbodies |
| `02_floodplain_model.R` | flooded | Run VCA at each flood_factor scenario |
| `03_lulc_classify.R` | drift | Classify land cover per sub-basin within floodplain |
| `04_lulc_zones.R` | drift | Zone-stratified LULC (nested flood zones) |
| `05_prioritization_score.R` | — | Score sub-basins from all above |

Scripts `01`–`02` need the fwapg database — see [Prerequisite — fwapg database](../README.md#prerequisite--fwapg-database) (a local fwapg DB works; no SSH tunnel required). The DEM comes from the national MRDEM-30 via `flooded::fl_dem_aoi()`.

## CSV Controls

All in `data/lulc/`:

| File | Purpose |
|------|---------|
| `flood_scenarios.csv` | VCA parameters per scenario. `run=TRUE` rows are executed. |
| `parameters_fresh.csv` | Access gradient, spawn gradient min per species |
| `parameters_habitat_thresholds.csv` | Spawn/rear gradient, channel width, MAD thresholds |
| `break_points.csv` | Sub-basin delineation points on FWA network |

## Outputs

All outputs live in `data/lulc/` (gitignored — regenerate by running the pipeline).

### Naming Convention

Outputs are multi-layer GeoPackages grouped by theme. Each pipeline step owns one gpkg. Layer names include the scenario ID (e.g., `co_ff04`) so outputs are self-documenting regardless of when or how they were generated.

| GeoPackage | From | Layers | Copied to QGIS |
|------------|------|--------|----------------|
| `aquatic_network.gpkg` | 01 | `streams_classified`, `streams_co3`, `waterbodies_co3` | Yes |
| `floodplain.gpkg` | 02 | One layer per scenario: `co_ff02`, `co_ff04`, `co_ff06` | Yes |
| `floodplain_landcover.gpkg` | 03 | `classified_{scenario}_{year}`, `transition_{scenario}_{from}_{to}` | Yes |
| `subbasins.gpkg` | 02 | Single layer | No |

### Other outputs

| File | From | Description |
|------|------|-------------|
| `floodplain_{scenario_id}.tif` | 02 | Floodplain raster per scenario |
| `lulc_summary_{scenario_id}.rds` | 03 | Area/pct by class, sub-basin, year |
| `lulc_summary.rds` | 03 | Copy of active scenario (report reads this) |
| `rasters/{scenario_id}/` | 03 | Classified + transition tifs per scenario |

## External Paths

Pipeline scripts read `params$path_gis` from `index.Rmd` YAML via:

```r
params <- rmarkdown::yaml_front_matter(here::here("index.Rmd"))$params
```

This is the QGIS project directory where gpkgs are copied for field/team use. Edit `path_gis` in `index.Rmd` if your file system differs. DEM and slope rasters are expected at `{path_gis}/dem_neexdzii.tif` and `{path_gis}/slope_neexdzii.tif`.

## Adding Scenarios

Add a row to `flood_scenarios.csv` with the desired parameters and set `run=TRUE`. Re-run `02_floodplain_model.R` — the new scenario appears as a layer in `floodplain.gpkg`. Then run `03_lulc_classify.R {scenario_id}` to classify land cover within the new floodplain extent.
