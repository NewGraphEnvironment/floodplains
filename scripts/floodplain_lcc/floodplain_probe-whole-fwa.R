# floodplain_probe-whole-fwa.R — cost and difference of a whole-FWA floodplain (#110, gates #104)
#
# Delineates one area's floodplain from five networks with ONE scenario's VCA parameters, and times
# delineation and per-watercourse attribution separately:
#   arm 1  all FWA (order >= 1)          arm 4  order >= 3 + first-order with parent >= 5
#   arm 2  order >= 2                    arm 5  the species network (step 1's, the baseline)
#   arm 3  order >= 3
# The arms are filters of ONE whole-group read (fp_whole_fwa.R), so arm 3 contains arm 5 exactly.
#
# One mode per invocation, so floodplain_probe-run.sh can wrap each in /usr/bin/time -l and read a
# peak RSS per stage:
#   anchor   arm 5 on its OWN DEM. Stops unless the network, the DEM and the floodplain all digest
#            equal to what step 1 and step 2 recorded in provenance.json. This is what makes the
#            probe's copy of 01's SQL and 02's VCA call trustworthy without editing either.
#   <k>      arm k on the COMMON DEM (arm 1 fetches it and writes dem_common.tif; 2-5 refuse to run
#            without it), so all five compare cell for cell. Attributed by blue_line_key.
#   seg      arm 3's floodplain attributed by (blue_line_key, downstream_route_measure), timed.
#   report   tables, review layers and panels from the outputs above (needs the database for the
#            habitat-below-floor numbers). Writes the committed logs.
#
# READ-ONLY on steps 1-3: it never writes aquatic_network.gpkg, floodplain.gpkg, a floodplain_*.tif
# or provenance.json. Outputs go to data/<area>/probe_whole_fwa/ (gitignored; the publish layer
# copies data/<area>/ files by explicit name, so nothing here ships) and, from `report`,
# scripts/floodplain_lcc/logs/<yyyymmdd>_floodplain_probe-whole-fwa_<area>.{csv,md}.
#
# usage: Rscript scripts/floodplain_lcc/floodplain_probe-whole-fwa.R <area> <mode> [scenario_id]

suppressMessages({library(sf); library(terra); library(DBI); library(RPostgres); library(flooded)})
sf::sf_use_s2(FALSE)
terra::terraOptions(threads = 12, progress = 0)   # 02's thread setting
`%||%` <- function(a, b) if (is.null(a)) b else a
lcc <- here::here("scripts", "floodplain_lcc")
source(file.path(lcc, "fp_whole_fwa.R"))
source(file.path(lcc, "fp_provenance.R"))   # fp_raster_content_sha256, fp_table_content_sha256
source(here::here("scripts", "fp_raster.R"))   # fp_rast_write
source(here::here("scripts", "fp_gpkg.R"))
fp_gpkg_pin_date()                                                        # #45

args <- commandArgs(trailingOnly = TRUE)
area <- args[1]; mode <- args[2]
if (is.na(area) || !grepl("^[a-z0-9_]+$", area) || is.na(mode) ||
    !(mode %in% c("anchor", "seg", "report") || mode %in% as.character(FP_WF_ARMS$arm)))
  stop("usage: floodplain_probe-whole-fwa.R <area> <anchor|1..5|seg|report> [scenario_id]", call. = FALSE)

# --- config: read directly, not through run_area.R (which runs the pipeline when sourced) ---------
cfg_dir <- here::here("config", area)
cfg <- yaml::read_yaml(file.path(cfg_dir, "area.yml"))
scen_id <- if (length(args) >= 3L) args[3] else cfg$primary_scenario %||% paste0(cfg$species, "_ff04")
sc <- utils::read.csv(file.path(cfg_dir, "flood_scenarios.csv"), stringsAsFactors = FALSE)
sc <- sc[sc$scenario_id == scen_id, , drop = FALSE]
if (nrow(sc) != 1L) stop("scenario '", scen_id, "' not found once in config/", area, "/flood_scenarios.csv", call. = FALSE)
species   <- sc$species
min_order <- as.integer(sc$min_order)
fp_wf_check_species(species)
if (!is.null(cfg$subset)) stop("the probe is for whole-group areas; ", area, " has a subset", call. = FALSE)
read_schema <- if (!is.null(cfg$network_source) && nzchar(cfg$network_source)) cfg$network_source else cfg$schema
wsg <- cfg$watershed_group
buf <- 2000   # 02's DEM buffer

dir_area <- here::here("data", area)
dir_out  <- file.path(dir_area, "probe_whole_fwa")
fs::dir_create(dir_out)
p_out <- function(...) file.path(dir_out, paste0(...))

# 01's digest key and value columns, copied (they are locals of fp_network()). A copy that drifted
# from 01's would make anchor 1 fail, so the anchor guards this list as well as the SQL.
NETWORK_DIGEST_KEY <- c("blue_line_key", "downstream_route_measure")
NETWORK_DIGEST_VAL <- c("length_metre", "stream_order", "upstream_area_ha", "map_upstream",
                        "channel_width", "waterbody_key")

secs <- function(t0) round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
write_json <- function(x, path) jsonlite::write_json(x, path, auto_unbox = TRUE, pretty = TRUE, digits = NA)

read_arm <- function(conn, arm) {
  all <- fp_wf_read_network(conn, read_schema, wsg, species)
  s <- all[fp_wf_keep(all, arm, min_order), ]
  message("  arm ", arm, " (", FP_WF_ARMS$label[arm], "): ", nrow(s), " of ", nrow(all), " segments, ",
          round(sum(s$length_metre) / 1000, 1), " km, ", length(unique(s$blue_line_key)), " blue lines")
  s
}

# 02's VCA call, with the scenario row's parameters. `area_field` rather than 02's deprecated
# `field`: flooded 0.6.0 forwards one to the other and reproduces the same delineation exactly.
delineate <- function(dem, streams, waterbodies) {
  precip <- fl_stream_rasterize(streams, dem, field = "map_upstream")
  fl_valley_confine(dem, streams, area_field = "upstream_area_ha", slope = NULL,
                    slope_threshold = sc$slope_threshold, max_width = sc$max_width,
                    cost_threshold = sc$cost_threshold, flood_factor = sc$flood_factor,
                    precip = precip, waterbodies = waterbodies,
                    size_threshold = sc$size_threshold, hole_threshold = sc$hole_threshold)
}

# Attribution with its warnings counted rather than printed: a group with no valley cells is
# expected on a whole network (a first-order line in a confined valley), and the count is a result.
attribute <- function(valleys, streams, dem, group) {
  n_warn <- 0L; first <- NULL
  out <- withCallingHandlers(
    flooded::fl_valley_attribute(valleys, streams, group = group, dem = dem,
                                 max_width = sc$max_width, cost_threshold = sc$cost_threshold),
    warning = function(w) {
      n_warn <<- n_warn + 1L
      if (is.null(first)) first <<- substr(conditionMessage(w), 1, 300)
      invokeRestart("muffleWarning")
    })
  list(x = out, n_warn = n_warn, first_warning = first)
}

# =================================================================================================
if (mode == "anchor") {
  prov <- jsonlite::read_json(file.path(dir_area, "provenance.json"))
  net_key <- paste0(species, min_order)
  rec_net <- prov$network[[net_key]]$outputs$streams_content_sha256
  rec_dem <- prov$floodplain[[scen_id]]$inputs$dem_content_sha256
  rec_fp  <- prov$floodplain[[scen_id]]$outputs$floodplain_content_sha256
  if (is.null(rec_net) || is.null(rec_dem) || is.null(rec_fp))
    stop("provenance.json lacks network[", net_key, "] or floodplain[", scen_id, "] digests; ",
         "the anchor has nothing to compare against", call. = FALSE)

  conn <- DBI::dbConnect(RPostgres::Postgres())
  s5 <- read_arm(conn, 5)
  got_net <- fp_table_content_sha256(s5, NETWORK_DIGEST_KEY, NETWORK_DIGEST_VAL)
  message("  anchor 1 (network): ", if (identical(got_net, rec_net)) "MATCH" else "DIFFERS")
  if (!identical(got_net, rec_net))
    stop("ANCHOR FAIL (network): arm 5 does not reproduce step 1's ", net_key, " network. Either '",
         read_schema, "' has been rebuilt since step 1 ran, or this script's copy of 01's SQL or ",
         "digest columns has drifted. recorded ", rec_net, ", got ", got_net, call. = FALSE)
  wb5 <- fp_wf_read_waterbodies(conn, s5)
  DBI::dbDisconnect(conn)

  t0 <- Sys.time()
  dem5 <- flooded::fl_dem_aoi(s5, buffer = buf, target_crs = sf::st_crs(s5))
  t_dem <- secs(t0)
  got_dem <- fp_raster_content_sha256(dem5)
  message("  anchor 2 (DEM): ", if (identical(got_dem, rec_dem)) "MATCH" else "DIFFERS", " (", t_dem, " s)")
  if (!identical(got_dem, rec_dem))
    stop("ANCHOR FAIL (DEM): MRDEM-30 over arm 5 does not digest equal to step 2's DEM. NRCan may have ",
         "re-derived it, or the reprojection moved. recorded ", rec_dem, ", got ", got_dem, call. = FALSE)

  t0 <- Sys.time()
  v5 <- delineate(dem5, s5, wb5)
  t_delin <- secs(t0)
  f5 <- p_out("anchor_floodplain.tif")
  fp_rast_write(v5, f5, overwrite = TRUE, datatype = "FLT4S")   # 02's pinned type
  got_fp <- fp_raster_content_sha256(f5)
  ondisk <- fp_raster_content_sha256(file.path(dir_area, paste0("floodplain_", scen_id, ".tif")))
  message("  anchor 3 (floodplain): ", if (identical(got_fp, rec_fp)) "MATCH" else "DIFFERS",
          " (", t_delin, " s); on-disk raster ", if (identical(ondisk, rec_fp)) "matches" else "DIFFERS FROM",
          " its own record")
  write_json(list(mode = "anchor", scenario = scen_id, network = got_net, dem = got_dem, floodplain = got_fp,
                  network_match = identical(got_net, rec_net), dem_match = identical(got_dem, rec_dem),
                  floodplain_match = identical(got_fp, rec_fp), ondisk_match = identical(ondisk, rec_fp),
                  t_dem_s = t_dem, t_delin_s = t_delin, flooded = as.character(packageVersion("flooded")),
                  terra = as.character(packageVersion("terra"))), p_out("anchor.json"))
  if (!identical(got_fp, rec_fp))
    stop("ANCHOR FAIL (floodplain): same network and same DEM, different floodplain. The VCA call or ",
         "flooded (", as.character(packageVersion("flooded")), " here) has changed what step 2 does. ",
         "recorded ", rec_fp, ", got ", got_fp, call. = FALSE)
  message("PROBE_DONE anchor")
}

# =================================================================================================
if (mode %in% as.character(FP_WF_ARMS$arm)) {
  arm <- fp_wf_check_arm(mode)
  conn <- DBI::dbConnect(RPostgres::Postgres())
  s <- read_arm(conn, arm)
  wb <- fp_wf_read_waterbodies(conn, s)
  DBI::dbDisconnect(conn)

  dem_path <- p_out("dem_common.tif")
  t0 <- Sys.time()
  if (arm == 1L) {
    # FLT8S: the reprojected DEM is double in memory; a float write would round it and the arms
    # would then not be delineated on the DEM the digest describes.
    d <- flooded::fl_dem_aoi(s, buffer = buf, target_crs = sf::st_crs(s))
    fp_rast_write(d, dem_path, overwrite = TRUE, datatype = "FLT8S")
    rm(d)
  } else if (!file.exists(dem_path)) {
    stop("dem_common.tif is absent: run arm 1 first, it defines the common grid", call. = FALSE)
  }
  dem <- terra::rast(dem_path)
  t_dem <- secs(t0)
  dem_sha <- fp_raster_content_sha256(dem)
  # Every arm lies inside arm 1, so its streams must lie inside the common DEM. Refuse rather than
  # let the VCA silently drop seeds off the edge.
  bb <- sf::st_bbox(s); de <- as.vector(terra::ext(dem))
  if (bb[["xmin"]] < de[["xmin"]] || bb[["xmax"]] > de[["xmax"]] || bb[["ymin"]] < de[["ymin"]] || bb[["ymax"]] > de[["ymax"]])
    stop("arm ", arm, "'s streams extend beyond dem_common.tif", call. = FALSE)
  message("  DEM: ", terra::ncol(dem), " x ", terra::nrow(dem), " (", t_dem, " s)")

  t0 <- Sys.time()
  v <- delineate(dem, s, wb)
  t_delin <- secs(t0)
  n_valley <- sum(terra::values(v, mat = FALSE) == 1, na.rm = TRUE)
  fp_out <- p_out("arm", arm, "_floodplain.tif")
  fp_rast_write(v, fp_out, overwrite = TRUE, datatype = "FLT4S")
  message("  delineation: ", t_delin, " s, ", n_valley, " valley cells (",
          round(n_valley * prod(terra::res(v)) / 1e6, 1), " km2)")

  t0 <- Sys.time()
  a <- attribute(v, s, dem, "blue_line_key")
  t_attr <- secs(t0)
  a$x$arm <- arm
  sf::st_write(a$x, p_out("arm", arm, "_by_blk.gpkg"), layer = "by_blk", delete_dsn = TRUE, quiet = TRUE)
  message("  attribution by blue_line_key: ", t_attr, " s, ", nrow(a$x), " rows, ", a$n_warn, " warnings")

  write_json(list(
    mode = "arm", arm = arm, label = FP_WF_ARMS$label[arm], scenario = scen_id,
    n_segments = nrow(s), km = round(sum(s$length_metre) / 1000, 3),
    n_blk = length(unique(s$blue_line_key)), n_waterbodies = if (is.null(wb)) 0L else nrow(wb),
    dem_ncol = terra::ncol(dem), dem_nrow = terra::nrow(dem), dem_content_sha256 = dem_sha,
    valley_cells = n_valley, cell_m2 = prod(terra::res(v)),
    floodplain_content_sha256 = fp_raster_content_sha256(fp_out),
    t_dem_s = t_dem, t_delin_s = t_delin, t_attr_blk_s = t_attr,
    attr_rows = nrow(a$x), attr_warnings = a$n_warn, attr_first_warning = a$first_warning,
    fallback_cells = attr(a$x, "fl_fallback_cells") %||% NA,
    flooded = as.character(packageVersion("flooded")), terra = as.character(packageVersion("terra"))),
    p_out("arm", arm, "_timing.json"))
  message("PROBE_DONE ", arm)
}

# =================================================================================================
if (mode == "seg") {
  arm <- 3L
  f3 <- p_out("arm3_floodplain.tif"); dem_path <- p_out("dem_common.tif")
  if (!file.exists(f3) || !file.exists(dem_path)) stop("run arms 1 and 3 first", call. = FALSE)
  conn <- DBI::dbConnect(RPostgres::Postgres())
  s <- read_arm(conn, arm)
  DBI::dbDisconnect(conn)
  s$seg_key <- fp_wf_seg_key(s$blue_line_key, s$downstream_route_measure)
  if (anyDuplicated(s$seg_key)) stop(sum(duplicated(s$seg_key)), " duplicate segment keys in arm 3", call. = FALSE)
  v <- terra::rast(f3); dem <- terra::rast(dem_path)
  t0 <- Sys.time()
  a <- attribute(v, s, dem, "seg_key")
  t_attr <- secs(t0)
  a$x$arm <- arm
  sf::st_write(a$x, p_out("arm3_by_seg.gpkg"), layer = "by_seg", delete_dsn = TRUE, quiet = TRUE)
  message("  attribution by segment: ", t_attr, " s, ", nrow(a$x), " rows of ", nrow(s), " segments, ",
          a$n_warn, " warnings")
  write_json(list(mode = "seg", arm = arm, n_groups = nrow(s), t_attr_seg_s = t_attr, attr_rows = nrow(a$x),
                  attr_warnings = a$n_warn, attr_first_warning = a$first_warning,
                  fallback_cells = attr(a$x, "fl_fallback_cells") %||% NA), p_out("seg_timing.json"))
  message("PROBE_DONE seg")
}

# =================================================================================================
if (mode == "report") {
  source(file.path(lcc, "floodplain_probe-report.R"))
  fp_wf_report(area = area, dir_area = dir_area, dir_out = dir_out, scen_id = scen_id, species = species,
               min_order = min_order, wsg = wsg, read_schema = read_schema)
  message("PROBE_DONE report")
}
