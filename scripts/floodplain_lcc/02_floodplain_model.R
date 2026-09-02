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
    subbasin_source <- "fwa_watershed_groups_poly"
  } else {
    subbasins <- fresh::frs_watershed_split(conn, cfg$break_points)
    subbasin_source <- "break_points"
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

  # Guard cfg$attribute_by (#40) HERE rather than at the call site: the call happens after the DEM
  # fetch and the VCA, so a typo'd column name would otherwise surface tens of minutes into a run.
  # fl_valley_attribute() rejects it too, but without naming the area that has to be fixed.
  if (!is.null(cfg$attribute_by)) {
    if (!cfg$attribute_by %in% setdiff(names(streams), attr(streams, "sf_column"))) {
      stop("attribute_by '", cfg$attribute_by, "' is not a column of ", streams_lyr,
           " for area '", cfg$name, "'. Available: ",
           paste(setdiff(names(streams), attr(streams, "sf_column")), collapse = ", "),
           call. = FALSE)
    }
    message("  Attribution: will attribute ", cfg$primary_scenario, " by '", cfg$attribute_by,
            "' (", length(unique(streams[[cfg$attribute_by]])), " groups)")
  }

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
  # Provenance (#33): the DEM's identity is NOT recoverable here, and saying so is the honest
  # record. fl_dem_aoi() builds the MRDEM-30 URL inside its body (source = NULL is the formal), so
  # formals() does not expose it and restating it here would duplicate package knowledge the core
  # principle forbids. terra::sources() does not help either -- fl_dem_aoi always crops and
  # reprojects, so the returned object is DERIVED. Measured on terra 1.9.34: sources() on a crop or
  # a project is "" when the result fits in memory, and a RANDOM PER-PROCESS TEMP PATH when terra
  # spills to disk -- which is the large-AOI case, exactly where this matters. Recording that path
  # would be a plausible-looking string that differs every run, silently breaking byte-stability.
  #
  # So: record the resolver and the raster's MEASURABLE geometry, which does distinguish MRDEM-30
  # from a lidar COG should one ever be passed. The URL stays recoverable from flooded's version.
  dem_geom <- tryCatch(list(
    dem_crs_epsg = sf::st_crs(terra::crs(dem))$epsg,
    dem_res_m    = round(as.numeric(terra::res(dem))[1], 6),
    dem_ncell    = as.numeric(terra::ncell(dem))
  ), error = function(e) list(dem_crs_epsg = NA, dem_res_m = NA, dem_ncell = NA))

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

    # --- Machine-readable provenance (#33) ---
    # One entry per scenario, keyed the same way the gpkg layer and the STAC item are. Every field
    # here is a function of the INPUTS -- the VCA parameter set, the DEM, the sub-basin source --
    # so two runs over an unchanged config must produce identical bytes. Nothing about this run
    # (when, how long, which host) belongs here; provenance-check.R fails if one appears.
    fp_prov_set(cfg, "floodplain", sc$scenario_id, list(
      inputs = list(
        wsg             = cfg$watershed_group,
        species         = cfg$species,
        scenario        = sc$scenario_id,
        flood_factor    = sc$flood_factor,
        slope_threshold = sc$slope_threshold,
        max_width       = sc$max_width,
        cost_threshold  = sc$cost_threshold,
        size_threshold  = sc$size_threshold,
        hole_threshold  = sc$hole_threshold,
        anchor_order    = sc$anchor_order,
        dem_resolver    = "flooded::fl_dem_aoi(source = NULL) default",
        dem_crs_epsg    = dem_geom$dem_crs_epsg,
        dem_res_m       = dem_geom$dem_res_m,
        dem_ncell       = dem_geom$dem_ncell,
        dem_buffer_m    = buf,
        # Names the artefact this scenario was delineated FROM, so the merged file is a chain and
        # not three independent statements.
        network_layer   = streams_lyr,
        attribute_by    = cfg$attribute_by,
        subbasin_source = subbasin_source,
        crs_epsg        = sf::st_crs(streams)$epsg,
        flooded         = fp_pkg_stamp("flooded")),
      run = fp_prov_run(toolchain = fp_toolchain())))

    # --- Per-watercourse attribution (#40) ---
    # Which part of this floodplain belongs to which river? flooded::fl_valley_attribute() applies
    # the VCA's own stream-dependent criteria (distance <= max_width/2, cost < cost_threshold) to
    # ONE group's streams at a time against the delineation just computed. The delineation is NOT
    # recomputed per group -- re-running the VCA on a subset would move the boundary (the flood
    # surface interpolates from every seed), so "the floodplain of this river" must be an
    # attribution of a fixed delineation, not a separate model run.
    #
    # max_width/cost_threshold MUST match the delineation being attributed, so they come from the
    # same scenario row -- not from defaults.
    #
    # Rows OVERLAP near confluences, deliberately: ground there belongs to both floodplains, and a
    # hard partition would be a false answer exactly where a sampling design cares most.
    #
    # Primary scenario only: attribution is a cost-distance pass per group, so doing ff02/ff04/ff06
    # alike would triple the cost for no current need. Widen via cfg if that changes.
    if (!is.null(cfg$attribute_by) && identical(sc$scenario_id, cfg$primary_scenario)) {
      message("  Attributing ", sc$scenario_id, " by '", cfg$attribute_by, "' ...")
      attributed <- flooded::fl_valley_attribute(
        valleys, streams,
        group          = cfg$attribute_by,
        dem            = dem,              # slope derived internally, guaranteed to match `valleys`
        max_width      = sc$max_width,
        cost_threshold = sc$cost_threshold
      )
      # Item key (#30) + the grouping column: the grouping key is effectively a fourth member of
      # the key, so an attributed floodplain stays separable after areas are merged into one gpkg.
      attributed$wsg      <- cfg$watershed_group
      attributed$species  <- cfg$species
      attributed$scenario <- sc$scenario_id
      # Label column (#48): grouping by an opaque key (blue_line_key) resolves every watercourse,
      # but a click in QGIS then returns `360885316` rather than "Morice River" -- complete and
      # unusable in the field. Carry the human-readable name alongside when the network offers one
      # that is a clean function of the grouping key: on MORR all 340 keys map to 0 or 1 gnis_name,
      # so 33 rows get a name and 307 are honestly NA. Skipped (with a message) when the mapping is
      # ambiguous, rather than picking one name arbitrarily and quietly mislabelling a watercourse.
      label_col <- "gnis_name"
      if (!identical(cfg$attribute_by, label_col) &&
            label_col %in% setdiff(names(streams), attr(streams, "sf_column"))) {
        lut <- unique(sf::st_drop_geometry(streams)[, c(cfg$attribute_by, label_col)])
        lut <- lut[!is.na(lut[[label_col]]), , drop = FALSE]
        n_per_key <- tapply(lut[[label_col]], lut[[cfg$attribute_by]], function(x) length(unique(x)))
        if (any(n_per_key > 1)) {
          message("  Label: skipped -- ", sum(n_per_key > 1), " ", cfg$attribute_by,
                  " value(s) carry more than one ", label_col, "; not guessing")
        } else {
          lut <- lut[!duplicated(lut[[cfg$attribute_by]]), , drop = FALSE]
          attributed[[label_col]] <- lut[[label_col]][match(attributed[[cfg$attribute_by]],
                                                            lut[[cfg$attribute_by]])]
          message("  Label: ", sum(!is.na(attributed[[label_col]])), " of ", nrow(attributed),
                  " groups carry a ", label_col)
        }
      }
      attr_lyr <- paste0(sc$scenario_id, "_by_", cfg$attribute_by)
      sf::st_write(attributed, out_gpkg, layer = attr_lyr,
                   append = file.exists(out_gpkg), delete_layer = TRUE, quiet = TRUE)
      # fallback_cells = valley cells no group reached within thresholds (morphological closing,
      # hole filling, channel buffer, waterbody polygons get no spatial filter). complete = TRUE
      # assigns them to the nearest group, so this is a QA signal on how much of the delineation
      # attribution could not reach on its own terms -- log it rather than let it pass silently.
      fb <- attr(attributed, "fl_fallback_cells")
      message("  Saved: layer ", attr_lyr, " (", nrow(attributed), " groups",
              if (!is.null(fb)) paste0("; ", fb, " fallback cells assigned to nearest") else "", ")")
    }
  }

  message("\nDone. Floodplain AOI(s) ready for drift pipeline (step 3, fp_lulc).")
  invisible(out_gpkg)
}
