#!/usr/bin/env Rscript
#
# 02_floodplain_model.R  —  defines fp_floodplain(cfg, scenarios = "run")
#
# 1. Generate sub-basin polygons from cfg$break_points via frs_watershed_split()
# 2. Run flooded VCA for each selected scenario in cfg$scenarios
#
# Stream network and waterbodies are pre-built by fp_network() (step 1):
#   data/<area>/aquatic_network.gpkg  (layers streams_<sp><order>, waterbodies_<sp><order>)
#
# VCA parameters (flood_factor, slope_threshold, etc.) are read from cfg$scenarios --
# each row is a fully specified scenario.
#
# `scenarios` arg selects which rows to run:
#   "run"        rows where run == TRUE   (default)
#   "all"        every row
#   "<id>"       a single scenario_id (e.g. "co_ff04")
#
# Requires:
#   - fwapg database for sub-basin generation (frs_watershed_split) -- local fwapg
#     via standard libpq env vars; see scripts/README.md
#   - Output from fp_network() (step 1)
#   - Network access -- DEM fetched from national MRDEM-30 via flooded::fl_dem_aoi()
#
# Outputs (data/<area>/):
#   subbasins.gpkg                    (sub-basin polygons)
#   floodplain_<scenario_id>.tif      (raster, per scenario)
#   floodplain.gpkg                   (one vector layer per scenario)
#
# Called by scripts/run_area.R (step 2). cfg comes from fp_read_config().

fp_floodplain <- function(cfg, scenarios = "run") {
  library(flooded)
  library(fresh)
  library(sf)
  library(terra)

  sf_use_s2(FALSE)
  terra::terraOptions(threads = 12)

  out_dir <- cfg$dir_out
  fs::dir_create(out_dir)
  buf <- 2000

  # --- DB connection (needed for sub-basin generation only) ---
  # fwapg DB via standard libpq env vars (PGHOST/...); local fwapg for portable builds.
  conn <- DBI::dbConnect(RPostgres::Postgres())

  # --- Step 1: Generate sub-basins ---
  # break_points present => interior sub-basins via frs_watershed_split (e.g. a reach).
  # break_points absent  => whole-WSG single sub-basin = the group polygon (fp_wsg_subbasin);
  # this is exact and avoids the mainstem-outlet delineation that over-shoots tributary WSGs.
  message("=== Generating sub-basins ===")
  if (is.null(cfg$break_points) || nrow(cfg$break_points) == 0) {
    message("  whole-WSG sub-basin (", cfg$watershed_group, " group polygon; no break points)")
    subbasins <- fp_wsg_subbasin(conn, cfg$watershed_group, cfg$name)
  } else {
    subbasins <- fresh::frs_watershed_split(conn, cfg$break_points)
  }
  sb_path <- file.path(out_dir, "subbasins.gpkg")
  sf::st_write(subbasins, sb_path, layer = "subbasins", delete_dsn = TRUE, quiet = TRUE)
  message("  ", nrow(subbasins), " sub-basins -> ", basename(sb_path))

  DBI::dbDisconnect(conn)

  # --- Step 2: Load streams and waterbodies from fp_network() ---
  # Network layers are species-keyed (streams_<sp><min_order>); read the layer for this run's
  # species so the coho and chinook networks in one gpkg don't cross-contaminate (#23).
  network_gpkg <- file.path(out_dir, "aquatic_network.gpkg")
  if (!file.exists(network_gpkg)) stop("Run step 1 (fp_network) first: ", network_gpkg)
  streams_lyr     <- paste0("streams_", cfg$species, cfg$min_order)
  waterbodies_lyr <- paste0("waterbodies_", cfg$species, cfg$min_order)

  message("Loading streams from ", basename(network_gpkg), " (layer: ", streams_lyr, ")")
  streams <- sf::st_read(network_gpkg, layer = streams_lyr, quiet = TRUE) |> sf::st_zm(drop = TRUE)
  # Ensure numeric columns (gpkg can store as character)
  for (col in c("upstream_area_ha", "map_upstream", "channel_width", "stream_order")) {
    if (col %in% names(streams)) streams[[col]] <- as.numeric(streams[[col]])
  }
  message("  ", nrow(streams), " segments, orders: ",
          paste(sort(unique(streams$stream_order)), collapse = ", "))

  message("Loading waterbodies from ", basename(network_gpkg), " (layer: ", waterbodies_lyr, ")")
  waterbodies <- sf::st_read(network_gpkg, layer = waterbodies_lyr, quiet = TRUE) |> sf::st_zm(drop = TRUE)
  message("  ", nrow(waterbodies), " features")

  # --- DEM from national MRDEM-30 (portable; no local DEM dependency) ---
  # flooded::fl_dem_aoi() fetches NRCan MRDEM-30 (30 m) via /vsicurl for the stream
  # network + buffer, reprojected to the streams CRS. Slope is derived from this DEM
  # inside fl_valley_confine() (slope = NULL below).
  message("Fetching national MRDEM-30 for stream network + ", buf, " m buffer...")
  dem <- flooded::fl_dem_aoi(streams, buffer = buf, target_crs = sf::st_crs(streams))
  message("  DEM: ", terra::ncol(dem), " x ", terra::nrow(dem), " pixels")

  # --- Rasterize precipitation (shared across scenarios) ---
  message("  Rasterizing precipitation...")
  precip_r <- fl_stream_rasterize(streams, dem, field = "map_upstream")

  # --- Select scenarios ---
  all_scenarios <- cfg$scenarios
  if (identical(scenarios, "all")) {
    run_scenarios <- all_scenarios
  } else if (length(scenarios) == 1 && scenarios %in% all_scenarios$scenario_id) {
    run_scenarios <- all_scenarios[all_scenarios$scenario_id == scenarios, ]
  } else {
    run_scenarios <- all_scenarios[all_scenarios$run == TRUE, ]
  }
  # Keep only this run's species so a flood_scenarios.csv holding both co_* and ch_* rows does not
  # compute the other species' scenarios against this species' network (#23).
  run_scenarios <- run_scenarios[run_scenarios$species == cfg$species, ]
  if (nrow(run_scenarios) == 0) {
    stop("No scenarios for species '", cfg$species, "' in flood_scenarios.csv — check the ",
         "species column and run flags for area '", cfg$name, "'.", call. = FALSE)
  }
  message("Scenarios to run: ", paste(run_scenarios$scenario_id, collapse = ", "))

  # --- Multi-layer gpkg: one layer per scenario_id (species-prefixed => species coexist). Do NOT
  # wipe the file; each scenario write below uses delete_layer=TRUE so re-running replaces only its
  # own layer while other species'/scenarios' layers persist (#23). ---
  out_gpkg <- file.path(out_dir, "floodplain.gpkg")

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
    # Item key (#30): scenario-layer names (co_ff04, ch_ff04) are identical across every area, so
    # these columns are the only way a merged multi-area floodplain.gpkg stays separable.
    valleys_poly$wsg      <- cfg$watershed_group
    valleys_poly$species  <- cfg$species
    valleys_poly$scenario <- sc$scenario_id
    sf::st_write(valleys_poly, out_gpkg, layer = sc$scenario_id,
                 append = file.exists(out_gpkg), delete_layer = TRUE, quiet = TRUE)
    message("  Saved: ", basename(out_raster), " + layer ", sc$scenario_id, " in ", basename(out_gpkg))
  }

  message("\nDone. Floodplain AOI(s) ready for drift pipeline (step 3, fp_lulc).")
  invisible(out_gpkg)
}
