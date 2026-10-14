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
#   - Network access -- DEM fetched from national MRDEM-30 via flooded::fl_dem_aoi(), and cached in
#     data/<area>/dem_<sp><order>.tif (#122); a cache hit still makes one HEAD request for its key
#
# Outputs (data/<area>/):
#   subbasins.gpkg                    (sub-basin polygons)
#   dem_<sp><order>.tif + .json       (cached DEM and its key, #122)
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

  # Whole-network mode (#104) is affordable only from flooded 0.6.4: before it, fl_valley_attribute()'s
  # complete = TRUE fallback ran a full-grid distance (flooded#71), and blue-line attribution at
  # order >= 2 measured 170 min per scenario on BULK. A cost floor, refused up front rather than
  # discovered hours into a run.
  fp_whole_network_validate(cfg)
  if (fp_whole_network(cfg) && utils::packageVersion("flooded") < "0.6.4") {
    stop("whole-network area '", cfg$name, "' needs flooded >= 0.6.4 (flooded#71); installed ",
         as.character(utils::packageVersion("flooded")), call. = FALSE)
  }
  # Every area, a reproducibility floor (#117). Before 0.7.0, fl_dem_aoi() let GDAL pick the output
  # grid from edges PROJ had transformed, and PROJ 9.8.1 routes NAD83(CSRS)->NAD83 through WGS 84:
  # the DEM moved ~1.3 m with no data change and MORR co_ff04 came out -0.42% against its
  # published record. 0.7.0 fixes the grid (30 m, aligned to multiples of 30) and pins the datum
  # step (flooded#67). Below it, the DEM digest
  # recorded in `inputs` moves with the machine's PROJ, so the record would not mean what it says.
  if (utils::packageVersion("flooded") < "0.7.0") {
    stop("step 2 needs flooded >= 0.7.0 for a DEM grid that does not move with PROJ (flooded#67, ",
         "#117); installed ", as.character(utils::packageVersion("flooded")), call. = FALSE)
  }

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

  # --- DEM from national MRDEM-30 (portable; no local DEM dependency), cached per area (#122) ---
  # flooded::fl_dem_aoi() fetches NRCan MRDEM-30 (30 m) via /vsicurl for the stream
  # network + buffer, reprojected to the streams CRS. Slope is derived from this DEM
  # inside fl_valley_confine() (slope = NULL below).
  #
  # fp_dem_cached() (fp_dem.R) writes it to data/<area>/dem_<sp><order>.tif and reads it back while
  # its key matches: the AOI, buffer, CRS, source URL, the object's Last-Modified and ETag, the
  # flooded version and the toolchain fp_toolchain() records. NRCan's bucket has served at ~145 KB/s, which made
  # BULK's fetch 37 min of every re-run.
  #
  # Provenance (#33): the DEM's identity used to be recorded as absent, because flooded resolved the
  # URL in its own body and a restated copy here could drift from the one it fetched. The driver now
  # PASSES the URL (FP_DEM_SOURCE), so the record names exactly what was fetched. terra::sources() is
  # still no help: on a derived raster it is "" or a random per-process temp path.
  message("DEM: national MRDEM-30 for stream network + ", buf, " m buffer...")
  dem <- fp_dem_cached(streams, buffer = buf, target_crs = sf::st_crs(streams),
                       dir = out_dir, stem = paste0(cfg$species, cfg$min_order))
  dem_cache <- attr(dem, "fp_dem_cache")
  message("  DEM: ", terra::ncol(dem), " x ", terra::nrow(dem), " pixels (cache ", dem_cache$status, ")")
  # Record the raster's MEASURABLE geometry too, which distinguishes MRDEM-30 from a lidar COG
  # should one ever be passed.
  dem_geom <- tryCatch(list(
    dem_crs_epsg = sf::st_crs(terra::crs(dem))$epsg,
    dem_res_m    = round(as.numeric(terra::res(dem))[1], 6),
    dem_ncell    = as.numeric(terra::ncell(dem))
  ), error = function(e) list(dem_crs_epsg = NA, dem_res_m = NA, dem_ncell = NA))

  # ... and the ELEVATIONS themselves (#65). The three fields above pin the GRID, not the heights:
  # NRCan re-derives MRDEM, we get the same tile at the same footprint on the same 30 m grid with
  # different values, we produce a different floodplain, and not one character of the record moves.
  # Before #122 the DEM URL was not recorded either, so NOTHING in the record described the
  # elevation data the published floodplain was cut from.
  #
  # The cache writes the DEM at FLT8S, so the file holds exactly the cells terra returned and digests
  # the same as the in-memory object did before #122 (fp_dem_cached() checks this on every write;
  # measured on neexdzii, the cold run's digest equals the pre-#122 record).
  #
  # ONCE, here, outside the scenario loop: every scenario is delineated from this same DEM, so
  # digesting per scenario would repeat identical work three times for an identical answer.
  #
  # AND IT GOES IN `inputs` DESPITE BEING WARP OUTPUT -- which looks like the opposite of the call
  # 01 makes one file over, so state the difference rather than let a reader find the contradiction.
  # fl_dem_aoi() crops and reprojects internally, so these cells (and the header's ext/res) are
  # GDAL/PROJ output. For the NETWORK there was a toolchain-free alternative -- digest pre-subset --
  # and taking it cost nothing. For the DEM there is none: digesting the un-warped source window
  # would mean reading that window of the 84 GB COG a second time, at NRCan's rate. So the choice is not "warp-dependent digest" vs "clean digest", it is
  # warp-dependent digest vs NOTHING AT ALL about the elevations, which is the status quo this issue
  # exists to end. The header formats ext/res at %.9f, a tolerance well above the ~1e-15 ULP of a
  # double near 30, so ULP-level warp noise cannot move it.
  #
  # This digest DID move with the data unchanged (#117), across a terra upgrade on one machine rather
  # than across two machines. The cause was not GDAL but PROJ's NAD83(CSRS)->NAD83 operation, which
  # the grid GDAL chose followed. Moving the digest to `outputs` would have hidden that rather than
  # fixed it; the fix is a deterministic grid, so it stays in `inputs`. flooded 0.7.0 pins the grid
  # and the datum step (gated above). Across GDAL 3.8.5 and 3.13.0 with the pin, flooded#67 measured
  # cell values agreeing to 0.12 mm -- agreement, not byte identity, so this digest can still differ
  # between two GDAL builds with the grid and the heights the same. That residual is why the terra
  # GDAL/PROJ that warped the DEM is now in run$toolchain: a digest change is diagnosable from it.
  # The cache key carries that toolchain too, so on a cache hit run$toolchain still describes the warp
  # that produced the cells.
  #
  # fp_dem_cached() has already digested it: a hit is only a hit when the file digests as recorded,
  # and a miss digests the fetch to check the write. The same function, so the same value.
  dem_sha <- dem_cache$dem_content_sha256

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
    # datatype PINNED (#65). Unpinned, terra chooses the on-disk type from the in-memory object, so a
    # version that chose differently would change the nodata sentinel and move the output digest with
    # zero cells changed -- the #64 failure with a new cause. FLT4S is exactly what terra picks today
    # for this 0/1 double mask: measured, writing the same raster with and without the argument
    # produces BYTE-IDENTICAL files, so the pin changes no shipped artefact. 03 already pins INT1U.
    # fp_rast_write, for the same reason the datatype above is pinned (#83). This raster is
    # DEM-derived, not gdalcubes-backed, and all 72 floodplain_*.tif on disk carry AREA_OR_POINT
    # and nothing else -- so the strip is a measured no-op here today. It is wired anyway because
    # the alternative is one of three write sites left unpinned on the grounds that its input
    # happens to be clean, which is a fact about flooded's internals rather than a contract, and
    # "the fix landed in one of the callers" is how this class comes back.
    fp_rast_write(valleys, out_raster, overwrite = TRUE, datatype = "FLT4S")
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
        dem_resolver    = "flooded::fl_dem_aoi(source = dem_source)",
        dem_source      = dem_cache$source,
        dem_crs_epsg    = dem_geom$dem_crs_epsg,
        dem_res_m       = dem_geom$dem_res_m,
        dem_ncell       = dem_geom$dem_ncell,
        # The only field in this block derived from the elevation DATA rather than its grid (#65).
        dem_content_sha256 = dem_sha,
        dem_buffer_m    = buf,
        # Names the artefact this scenario was delineated FROM, so the merged file is a chain and
        # not three independent statements.
        network_layer   = streams_lyr,
        attribute_by    = cfg$attribute_by,
        subbasin_source = subbasin_source,
        crs_epsg        = sf::st_crs(streams)$epsg,
        flooded         = fp_pkg_stamp("flooded")),
      # What this scenario PRODUCED (#65) -- "did the answer change?", which `inputs_hash` cannot
      # answer and must not try to. Digested from the WRITTEN FILE rather than from `valleys` in
      # memory, deliberately and asymmetrically with the DEM above: the path form returns NA when
      # the file is absent or empty, so this doubles as evidence the artefact actually reached disk.
      # The vector layer is NOT digested here -- a GeoPackage layer has no guaranteed row order and
      # carries floating-point coordinates, which is #72.
      outputs = list(
        floodplain_raster         = basename(out_raster),
        floodplain_content_sha256 = fp_raster_content_sha256(out_raster),
        valley_cells              = n_valley),
      # The cache event (#122) is `run`, not `inputs`: Last-Modified and ETag can move with no change to
      # the cells, and dem_content_sha256 above already says whether the cells moved.
      run = fp_prov_run(toolchain = fp_toolchain(),
                        dem_cache = dem_cache[FP_DEM_CACHE_RECORD])))

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
