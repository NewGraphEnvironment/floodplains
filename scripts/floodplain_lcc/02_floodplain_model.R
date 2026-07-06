#!/usr/bin/env Rscript
#
# 02_floodplain_model.R
#
# 1. Generate sub-basin polygons from break_points.csv via frs_watershed_split()
# 2. Run flooded VCA for each scenario in flood_scenarios.csv
#
# Stream network and waterbodies are pre-built by 01_network_extract.R:
#   data/lulc/fresh_streams_co3.gpkg      (coho-accessible, order 3+)
#   data/lulc/fresh_waterbodies_co3.gpkg   (lakes/wetlands on accessible network)
#
# VCA parameters (flood_factor, slope_threshold, etc.) are read from
# flood_scenarios.csv — each row is a fully specified scenario.
# Only rows with run=TRUE are executed.
#
# Usage:
#   Rscript scripts/02_floodplain_model.R           # runs scenarios where run=TRUE
#   Rscript scripts/02_floodplain_model.R co_ff04   # runs specific scenario
#   Rscript scripts/02_floodplain_model.R all        # runs ALL scenarios (ignores run column)
#
# Requires:
#   - fwapg database for sub-basin generation (frs_watershed_split) — local fwapg
#     via standard libpq env vars; see scripts/README.md
#   - Output from 01_network_extract.R
#   - Network access — DEM fetched from national MRDEM-30 via flooded::fl_dem_aoi()
#
# Outputs:
#   data/lulc/subbasins.gpkg                  (sub-basin polygons)
#   data/lulc/floodplain_{scenario_id}.tif (raster)
#   data/lulc/floodplain_{scenario_id}.gpkg (vector)
#
# Relates to #67, #123, #138

library(flooded)
library(fresh)
library(sf)
library(terra)
library(readr)

sf_use_s2(FALSE)
terra::terraOptions(threads = 12)

out_dir <- here::here("data", "lulc")
buf <- 2000

# --- DB connection (needed for sub-basin generation only) ---
# fwapg DB via standard libpq env vars (PGHOST/...); local fwapg for portable builds.
conn <- DBI::dbConnect(RPostgres::Postgres())

# --- Step 1: Generate sub-basins from break_points.csv ---
message("=== Generating sub-basins ===")
bp <- readr::read_csv(
  file.path(out_dir, "break_points.csv"),
  show_col_types = FALSE
)
subbasins <- fresh::frs_watershed_split(conn, bp)
sb_path <- file.path(out_dir, "subbasins.gpkg")
sf::st_write(subbasins, sb_path, layer = "subbasins", delete_dsn = TRUE, quiet = TRUE)
message("  ", nrow(subbasins), " sub-basins -> ", basename(sb_path))

DBI::dbDisconnect(conn)

# --- Step 2: Load streams and waterbodies from 01_network_extract.R ---
network_gpkg <- file.path(out_dir, "aquatic_network.gpkg")
if (!file.exists(network_gpkg)) stop("Run 01_network_extract.R first: ", network_gpkg)

message("Loading streams from ", basename(network_gpkg), " (layer: streams_co3)")
streams <- sf::st_read(network_gpkg, layer = "streams_co3", quiet = TRUE) |> sf::st_zm(drop = TRUE)
# Ensure numeric columns (gpkg can store as character)
for (col in c("upstream_area_ha", "map_upstream", "channel_width", "stream_order")) {
  if (col %in% names(streams)) streams[[col]] <- as.numeric(streams[[col]])
}
message("  ", nrow(streams), " segments, orders: ",
        paste(sort(unique(streams$stream_order)), collapse = ", "))

message("Loading waterbodies from ", basename(network_gpkg), " (layer: waterbodies_co3)")
waterbodies <- sf::st_read(network_gpkg, layer = "waterbodies_co3", quiet = TRUE) |> sf::st_zm(drop = TRUE)
message("  ", nrow(waterbodies), " features")

# External paths from index.Rmd YAML params
params <- rmarkdown::yaml_front_matter(here::here("index.Rmd"))$params
# --- DEM from national MRDEM-30 (portable; no local DEM dependency) ---
# flooded::fl_dem_aoi() fetches NRCan MRDEM-30 (30 m) via /vsicurl for the stream
# network + buffer, reprojected to the streams CRS. Slope is derived from this DEM
# inside fl_valley_confine() (slope = NULL below). Replaces the former bcfishpass
# habitat_lateral DEM/slope that had to be hand-placed in the GIS project.
message("Fetching national MRDEM-30 for stream network + ", buf, " m buffer...")
dem <- flooded::fl_dem_aoi(streams, buffer = buf, target_crs = sf::st_crs(streams))
message("  DEM: ", terra::ncol(dem), " x ", terra::nrow(dem), " pixels")

# --- Rasterize precipitation (shared across scenarios) ---
message("  Rasterizing precipitation...")
precip_r <- fl_stream_rasterize(streams, dem, field = "map_upstream")

# --- Load scenarios ---
scenarios <- readr::read_csv(file.path(out_dir, "flood_scenarios.csv"), show_col_types = FALSE)

arg <- commandArgs(trailingOnly = TRUE)[1]
if (!is.na(arg) && arg == "all") {
  run_scenarios <- scenarios
} else if (!is.na(arg) && arg %in% scenarios$scenario_id) {
  run_scenarios <- scenarios[scenarios$scenario_id == arg, ]
} else {
  run_scenarios <- scenarios[scenarios$run == TRUE, ]
}

message("Scenarios to run: ", paste(run_scenarios$scenario_id, collapse = ", "))

# --- Multi-layer gpkg for all scenarios ---
out_gpkg <- file.path(out_dir, "floodplain.gpkg")
if (file.exists(out_gpkg)) file.remove(out_gpkg)

# --- Loop scenarios ---
for (i in seq_len(nrow(run_scenarios))) {
  sc <- run_scenarios[i, ]
  message("\n=== Scenario: ", sc$scenario_id, " (ff=", sc$flood_factor, ") ===")
  message("  ", sc$description)

  # --- Run Valley Confinement Algorithm ---
  message("  Running VCA (flood_factor=", sc$flood_factor,
          ", slope=", sc$slope_threshold,
          ", max_width=", sc$max_width, ")...")
  valleys <- fl_valley_confine(
    dem, streams,
    field = "upstream_area_ha",
    slope = NULL,   # derived from the national DEM inside fl_valley_confine()
    slope_threshold = sc$slope_threshold,
    max_width = sc$max_width,
    cost_threshold = sc$cost_threshold,
    flood_factor = sc$flood_factor,
    precip = precip_r,
    waterbodies = waterbodies,
    size_threshold = sc$size_threshold,
    hole_threshold = sc$hole_threshold
  )

  n_valley <- sum(terra::values(valleys) == 1, na.rm = TRUE)
  message("  Valley cells: ", n_valley, " / ", terra::ncell(valleys),
          " (", round(100 * n_valley / terra::ncell(valleys), 1), "%)")

  # --- Polygonize ---
  message("  Converting to polygons...")
  valleys_poly <- fl_valley_poly(valleys)
  message("  ", nrow(valleys_poly), " polygon features")

  # --- Write outputs ---
  out_raster <- file.path(out_dir, paste0("floodplain_", sc$scenario_id, ".tif"))
  terra::writeRaster(valleys, out_raster, overwrite = TRUE)
  sf::st_write(valleys_poly, out_gpkg, layer = sc$scenario_id, append = TRUE, quiet = TRUE)
  message("  Saved: ", basename(out_raster), " + layer ", sc$scenario_id, " in ", basename(out_gpkg))
}

# --- Copy to QGIS project (gated on update_gis) ---
if (isTRUE(params$update_gis) && dir.exists(params$path_gis)) {
  file.copy(out_gpkg, file.path(params$path_gis, "floodplain.gpkg"), overwrite = TRUE)
  file.copy(sb_path, file.path(params$path_gis, "subbasins.gpkg"), overwrite = TRUE)
  message("Copied floodplain.gpkg + subbasins.gpkg to QGIS project: ", params$path_gis)
}

message("\nDone. Floodplain AOI(s) ready for drift pipeline (03_lulc_classify.R).")
