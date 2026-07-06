#!/usr/bin/env Rscript
#
# lulc_classify.R
#
# Land cover classification and transition detection for the Neexdzii Kwa
# modelled floodplain. Two passes:
#   1. Whole-floodplain: classify + transition for interactive map
#   2. Per-sub-basin: summarize for tables/plots
#
# Reads active scenario from data/lulc/flood_scenarios.csv to select the
# floodplain AOI. Naming convention: floodplain_{scenario_id}.gpkg
# Default scenario: co_ff04 (flood_factor = 4.5, functional floodplain).
#
# Consumes subbasins.gpkg (from break app) and floodplain polygon (from flooded).
# Runs drift pipeline: fetch, classify, summarize, transition.
#
# Outputs to data/lulc/:
#   lulc_summary_{scenario_id}.rds  — area/pct by class, sub-basin, year
#   lulc_summary.rds                — copy of active scenario (for report)
#   rasters/{scenario_id}/          — classified + transition tifs
#
# Gated by params$update_lulc in index.Rmd
#
# Relates to #116, #67, #123

library(drift)
library(sf)
library(terra)
library(dplyr)
library(readr)

sf::sf_use_s2(FALSE)
terra::terraOptions(threads = 12)

out_dir <- here::here("data", "lulc")
ag_classes <- c("Crops", "Rangeland", "Bare Ground")
years <- c(2017, 2020, 2023)

# Patch-size sieve: drop transition patches smaller than 1.0 ha (100 px at
# 10 m IO LULC resolution). 0.5 ha (BC VRI minimum mapping unit) and 1.0 ha
# outputs were compared manually in QGIS during report preparation;
# 1.0 ha was selected as the better noise/signal tradeoff. Applied bidirectionally
# in dft_rast_transition() — affects transition.tif, the QGIS gpkg, and any
# downstream tree-loss numbers computed from transition.tif.
patch_min_m2 <- 10000

# Gate the auto-copy into the QGIS project on the report's update_gis param
# (default FALSE) so a fresh pipeline run never silently overwrites the live QGIS
# data. Set update_gis: TRUE in index.Rmd after inspecting the outputs in data/lulc/.
copy_to_qgis <- isTRUE(rmarkdown::yaml_front_matter(here::here("index.Rmd"))$params$update_gis)

# --- Select scenario ---
# Override at command line: Rscript scripts/lulc_classify.R co_ff04
scenarios <- readr::read_csv(file.path(out_dir, "flood_scenarios.csv"), show_col_types = FALSE)
scenario_id <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(scenario_id) || !scenario_id %in% scenarios$scenario_id) {
  scenario_id <- "co_ff04"
}
scenario <- scenarios |> dplyr::filter(scenario_id == !!scenario_id)
message("=== Scenario: ", scenario_id, " (ff=", scenario$flood_factor, ") ===")
message("  ", scenario$description)

# --- Load inputs ---
subbasins <- sf::st_read(
  file.path(out_dir, "subbasins.gpkg"), quiet = TRUE
) |> sf::st_transform(4326)

fp_file <- file.path(out_dir, "floodplain.gpkg")
floodplain <- sf::st_read(fp_file, layer = scenario_id, quiet = TRUE) |> sf::st_transform(4326)

# Use name_basin from break_points.csv (carried through via fresh::frs_watershed_split)

# --- Pass 1: Whole floodplain (for interactive map) ---
message("=== Whole floodplain ===")
rasters_all <- dft_stac_fetch(floodplain, source = "io-lulc", years = years)
classified_all <- dft_rast_classify(rasters_all, source = "io-lulc")
trans_all <- dft_rast_transition(
  classified_all, from = "2017", to = "2023",
  patch_area_min = patch_min_m2
)

# Save rasters as tif
fp_dir <- file.path(out_dir, "rasters", scenario_id)
dir.create(fp_dir, recursive = TRUE, showWarnings = FALSE)
for (yr in names(classified_all)) {
  terra::writeRaster(classified_all[[yr]], file.path(fp_dir, paste0("classified_", yr, ".tif")),
                     overwrite = TRUE, datatype = "INT1U")
}
if (nrow(trans_all$summary) > 0) {
  terra::writeRaster(trans_all$raster, file.path(fp_dir, "transition.tif"),
                     overwrite = TRUE, datatype = "INT4S")
}
message("Floodplain rasters saved to ", fp_dir)

# --- Vectorize to floodplain_landcover.gpkg for QGIS ---
out_lc_gpkg <- file.path(out_dir, "floodplain_landcover.gpkg")
if (file.exists(out_lc_gpkg)) file.remove(out_lc_gpkg)
message("Vectorizing to ", basename(out_lc_gpkg), "...")

# Classified land cover per year (dissolved by class)
for (yr in names(classified_all)) {
  lyr <- paste0("classified_", scenario_id, "_", yr)
  polys <- terra::as.polygons(classified_all[[yr]]) |> sf::st_as_sf()
  sf::st_write(polys, out_lc_gpkg, layer = lyr, append = file.exists(out_lc_gpkg),
               delete_layer = TRUE, quiet = TRUE)
  message("  Layer: ", lyr)
}

# Transition patches — exploded with area + sub-basin attribution
# Filter to actual changes only (drop stable from == to patches, which would
# otherwise dominate as fragmented "Trees -> Trees" / "Water -> Water" pieces).
if (nrow(trans_all$summary) > 0) {
  lyr <- paste0("transition_", scenario_id, "_2017_2023")
  trans_polys <- dft_transition_vectors(
    trans_all$raster,
    zones = subbasins,
    zone_col = "name_basin"
  )
  parts <- strsplit(trans_polys$transition, " -> ", fixed = TRUE)
  trans_polys$from_class <- vapply(parts, `[`, character(1), 1)
  trans_polys$to_class   <- vapply(parts, `[`, character(1), 2)
  trans_polys <- trans_polys[trans_polys$from_class != trans_polys$to_class, ]

  # Recompute area_ha from geometry post-intersection. drift's column is
  # pre-intersection so patches straddling sub-basin boundaries are
  # double-counted when summed by row.
  trans_polys$area_ha <- as.numeric(sf::st_area(trans_polys)) / 1e4

  sf::st_write(trans_polys, out_lc_gpkg, layer = lyr, append = TRUE,
               delete_layer = TRUE, quiet = TRUE)
  message("  Layer: ", lyr, " (", nrow(trans_polys),
          " change patches >= ", patch_min_m2 / 1e4, " ha)")
}

# Copy to QGIS project (gated — only run after inspecting outputs)
if (isTRUE(copy_to_qgis)) {
  params <- rmarkdown::yaml_front_matter(here::here("index.Rmd"))$params
  if (dir.exists(params$path_gis)) {
    file.copy(out_lc_gpkg, file.path(params$path_gis, "floodplain_landcover.gpkg"),
              overwrite = TRUE)
    message("Copied to QGIS project: ", params$path_gis)
  }
} else {
  message("QGIS copy SKIPPED (copy_to_qgis = FALSE).")
  message("After inspecting ", out_lc_gpkg, ", promote with:")
  params <- rmarkdown::yaml_front_matter(here::here("index.Rmd"))$params
  message("  cp ", out_lc_gpkg, " ", file.path(params$path_gis, "floodplain_landcover.gpkg"))
}

# --- Pass 2: Per-sub-basin summaries (for tables/plots) ---
message("\n=== Per-sub-basin summaries ===")
results <- list()

for (i in seq_len(nrow(subbasins))) {
  sb <- subbasins[i, ]
  lab <- sb$name_basin

  fp_clip <- sf::st_intersection(floodplain, sb) |>
    sf::st_collection_extract("POLYGON") |>
    sf::st_union() |>
    sf::st_sf(geometry = _)
  sf::st_crs(fp_clip) <- sf::st_crs(floodplain)

  if (nrow(fp_clip) == 0 || as.numeric(sf::st_area(fp_clip)) < 1e4) {
    message("Skipping ", lab, " -- no floodplain overlap")
    next
  }

  message("Processing: ", lab)
  rasters <- dft_stac_fetch(fp_clip, source = "io-lulc", years = years)
  classified <- dft_rast_classify(rasters, source = "io-lulc")
  summary <- dft_rast_summarize(classified, unit = "ha")
  summary$name_basin <- lab
  results[[i]] <- summary
}

# --- Save ---
lulc_summary <- dplyr::bind_rows(results)
lulc_summary$scenario_id <- scenario_id
lulc_summary$flood_factor <- scenario$flood_factor

# Scenario-specific file + copy as lulc_summary.rds for report consumption
saveRDS(lulc_summary, file.path(out_dir, paste0("lulc_summary_", scenario_id, ".rds")))
saveRDS(lulc_summary, file.path(out_dir, "lulc_summary.rds"))

message("\nDone. Scenario: ", scenario_id, " — outputs in ", out_dir)
