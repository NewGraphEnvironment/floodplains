#!/usr/bin/env Rscript
#
# 03_lulc_classify.R  —  defines fp_lulc(cfg, scenario = cfg$primary_scenario)
#
# Land cover classification and transition detection for the modelled floodplain.
# Two passes:
#   1. Whole-floodplain: classify + transition for interactive map
#   2. Per-sub-basin: summarize for tables/plots
#
# `scenario` selects the floodplain AOI (a layer in floodplain.gpkg). Defaults to
# cfg$primary_scenario (co_ff04, the functional floodplain).
#
# Consumes subbasins.gpkg + floodplain.gpkg (from step 2). Runs the drift pipeline:
# fetch, classify, summarize, transition.
#
# Outputs (data/<area>/):
#   floodplain_landcover.gpkg       -- classified_{scenario}_{year} + transition layer
#   lulc_summary_{scenario_id}.rds  -- area/pct by class, sub-basin, year
#   lulc_summary.rds                -- copy of active scenario (report reads this)
#   rasters/{scenario_id}/          -- classified + transition tifs
#
# Called by scripts/run_area.R (step 3). cfg comes from fp_read_config().

fp_lulc <- function(cfg, scenario = cfg$primary_scenario) {
  library(drift)
  library(sf)
  library(terra)
  library(dplyr)

  # fp_lulc passes tile_size to dft_stac_fetch unconditionally (NULL = off), a param that
  # only exists in drift >= 0.6.0 — on an older drift the call errors with "unused argument"
  # for EVERY area, tiled or not. update_packages defaults FALSE, so guard loudly here.
  if (utils::packageVersion("drift") < "0.6.0") {
    stop("fp_lulc requires drift >= 0.6.0 (dft_stac_fetch tile_size); installed ",
         as.character(utils::packageVersion("drift")),
         ". Update: pak::pak('newgraphenvironment/drift')", call. = FALSE)
  }

  sf::sf_use_s2(FALSE)
  terra::terraOptions(threads = 12)

  out_dir <- cfg$dir_out
  fs::dir_create(out_dir)
  ag_classes <- c("Crops", "Rangeland", "Bare Ground")
  years <- c(2017, 2020, 2023)

  # Patch-size sieve: drop transition patches smaller than 1.0 ha (100 px at
  # 10 m IO LULC resolution). 0.5 ha (BC VRI minimum mapping unit) and 1.0 ha
  # outputs were compared manually in QGIS during report preparation; 1.0 ha was
  # selected as the better noise/signal tradeoff. Applied bidirectionally in
  # dft_rast_transition() -- affects transition.tif, the gpkg, and any downstream
  # tree-loss numbers computed from transition.tif.
  patch_min_m2 <- 10000

  # --- Select scenario ---
  scenarios <- cfg$scenarios
  scenario_id <- scenario
  if (is.null(scenario_id) || !scenario_id %in% scenarios$scenario_id) {
    scenario_id <- cfg$primary_scenario
  }
  scenario_row <- scenarios |> dplyr::filter(scenario_id == !!scenario_id)
  message("=== Scenario: ", scenario_id, " (ff=", scenario_row$flood_factor, ") ===")
  message("  ", scenario_row$description)

  # --- Load inputs ---
  subbasins <- sf::st_read(
    file.path(out_dir, "subbasins.gpkg"), quiet = TRUE
  ) |> sf::st_transform(4326)

  fp_file <- file.path(out_dir, "floodplain.gpkg")
  floodplain <- sf::st_read(fp_file, layer = scenario_id, quiet = TRUE) |> sf::st_transform(4326)

  # Use name_basin from break_points (carried through via fresh::frs_watershed_split)

  # --- Pass 1: Whole floodplain (for interactive map) ---
  # tile_size (drift#36, opt-in via area.yml; NULL = off) bounds the STAC download to
  # tiles intersecting the AOI instead of the whole floodplain bounding box (~10x the
  # polygon for a thin corridor). Left NULL for the parity fixture + already-published
  # groups so their fetch path is byte-for-byte unchanged; set per-area for large
  # whole-WSG floodplains where the bbox waste dominates the ~30 min fetch.
  message("=== Whole floodplain ===")
  rasters_all <- dft_stac_fetch(floodplain, source = "io-lulc", years = years,
                                tile_size = cfg$tile_size)
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

  # --- Vectorize to floodplain_landcover.gpkg ---
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

  # Transition patches -- exploded with area + sub-basin attribution.
  # changes_only = TRUE (drift#34) builds polygons ONLY for actual changes (from != to),
  # never materializing the stable "Trees -> Trees" / "Water -> Water" patches that
  # dominate a large floodplain and OOM the vectorizer. So the post-filter is unneeded.
  if (nrow(trans_all$summary) > 0) {
    lyr <- paste0("transition_", scenario_id, "_2017_2023")
    trans_polys <- dft_transition_vectors(
      trans_all$raster,
      zones = subbasins,
      zone_col = "name_basin",
      changes_only = TRUE
    )
    parts <- strsplit(trans_polys$transition, " -> ", fixed = TRUE)
    trans_polys$from_class <- vapply(parts, `[`, character(1), 1)
    trans_polys$to_class   <- vapply(parts, `[`, character(1), 2)

    # Recompute area_ha from geometry post-intersection. drift's column is
    # pre-intersection so patches straddling sub-basin boundaries are
    # double-counted when summed by row.
    trans_polys$area_ha <- as.numeric(sf::st_area(trans_polys)) / 1e4

    sf::st_write(trans_polys, out_lc_gpkg, layer = lyr, append = TRUE,
                 delete_layer = TRUE, quiet = TRUE)
    message("  Layer: ", lyr, " (", nrow(trans_polys),
            " change patches >= ", patch_min_m2 / 1e4, " ha)")
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
    # Reuse Pass 1's whole-floodplain classified raster instead of re-fetching per
    # sub-basin: each sub-basin is a subset of classified_all, so crop + mask gives the
    # same pixels with no STAC round-trip. classified_all is auto-UTM; fp_clip is in the
    # floodplain CRS, so project it to the raster CRS before cropping. (#11)
    v <- terra::project(terra::vect(fp_clip), terra::crs(classified_all))
    classified <- terra::mask(terra::crop(classified_all, v), v)
    summary <- dft_rast_summarize(classified, unit = "ha")
    summary$name_basin <- lab
    results[[i]] <- summary
  }

  # --- Save ---
  lulc_summary <- dplyr::bind_rows(results)
  lulc_summary$scenario_id <- scenario_id
  lulc_summary$flood_factor <- scenario_row$flood_factor

  # Scenario-specific file + copy as lulc_summary.rds for report consumption
  saveRDS(lulc_summary, file.path(out_dir, paste0("lulc_summary_", scenario_id, ".rds")))
  saveRDS(lulc_summary, file.path(out_dir, "lulc_summary.rds"))

  message("\nDone. Scenario: ", scenario_id, " -- outputs in ", out_dir)
  invisible(out_lc_gpkg)
}
