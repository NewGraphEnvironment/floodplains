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
#   anchor   arm 5 on its OWN DEM, checked two ways. (1) Its network must digest equal to what step 1
#            recorded in provenance.json -- the SQL copy's guard. (2) Its floodplain must digest equal
#            to step 2 ITSELF: fp_floodplain() is replayed on the same day's DEM into
#            probe_whole_fwa/step2_replay/ (attribution off) and the two rasters compared. The DEM and
#            floodplain are also compared with the PUBLISHED record and reported, not enforced:
#            measured 2026-10-09, terra 1.9.50 (GDAL 3.13) reprojects MRDEM onto a grid ~1 m off the
#            one 1.9.34 (GDAL 3.8.5) produced, so the published floodplain is not reproducible on
#            this toolchain and a stop there would test the toolchain, not the probe.
#   dem      fetches MRDEM-30 over arm 1 (the widest network) once and writes dem_common.tif at
#            FLT8S, refusing unless the file digests equal to the object. Also asserts, on the live
#            read, that the arms nest (1 >= 2 >= 3 >= 5, 4 >= 3).
#   <k>      arm k on dem_common.tif, so all five compare cell for cell. Attributed by
#            blue_line_key, and once more from the COHO network alone as a single group with
#            complete = FALSE: the coho-reachable floodplain, which separates the boundary move
#            (#40: the flood surface is fitted from every seed) from area added by new seeds.
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
    !(mode %in% c("anchor", "dem", "seg", "report") || mode %in% as.character(FP_WF_ARMS$arm)))
  stop("usage: floodplain_probe-whole-fwa.R <area> <anchor|dem|1..5|seg|report> [scenario_id]", call. = FALSE)

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

# Versions recorded in every json, so `report` can refuse arms run across an upgrade. terra's GDAL is
# named separately from sf's: they differ on this machine (3.13.0 vs 3.8.5), and terra's is the one
# that reprojects the DEM.
vers <- function() list(flooded = as.character(packageVersion("flooded")),
                        terra = as.character(packageVersion("terra")), sf = as.character(packageVersion("sf")),
                        terra_gdal = terra::gdal(), sf_gdal = unname(sf::sf_extSoftVersion()[["GDAL"]]))

read_arm <- function(conn, arm, all = NULL) {
  if (is.null(all)) all <- fp_wf_read_network(conn, read_schema, wsg, species)
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
  message("  anchor 1 (network vs step 1's record): ", if (identical(got_net, rec_net)) "MATCH" else "DIFFERS")
  if (!identical(got_net, rec_net))
    stop("ANCHOR FAIL (network): arm 5 does not reproduce step 1's ", net_key, " network. Either '",
         read_schema, "' has been rebuilt since step 1 ran, or this script's copy of 01's SQL or ",
         "digest columns has drifted. recorded ", rec_net, ", got ", got_net, call. = FALSE)
  wb5 <- fp_wf_read_waterbodies(conn, s5)
  DBI::dbDisconnect(conn)

  # --- step 2 replayed: the real fp_floodplain() on today's DEM, into a scratch directory ---
  # It reads aquatic_network.gpkg from its own dir_out, so the published one is COPIED in (a byte copy
  # of a file nothing is writing; refuse if a SQLite sidecar says otherwise). Attribution is off: it
  # is not what the anchor tests and costs ~14 min on MORR.
  src_net <- file.path(dir_area, "aquatic_network.gpkg")
  if (any(file.exists(paste0(src_net, c("-journal", "-wal", "-shm")))))
    stop("aquatic_network.gpkg has a SQLite sidecar; something is writing it", call. = FALSE)
  replay_dir <- p_out("step2_replay")
  unlink(replay_dir, recursive = TRUE)
  fs::dir_create(replay_dir)
  file.copy(src_net, file.path(replay_dir, "aquatic_network.gpkg"))
  source(file.path(lcc, "fp_region.R"))              # fp_wsg_subbasin
  source(file.path(lcc, "02_floodplain_model.R"))    # fp_floodplain
  cfg2 <- list(name = cfg$name, watershed_group = wsg, species = species, min_order = min_order,
               dir_out = replay_dir, break_points = NULL, attribute_by = NULL,
               primary_scenario = scen_id,
               scenarios = readr::read_csv(file.path(cfg_dir, "flood_scenarios.csv"), show_col_types = FALSE))
  t0 <- Sys.time()
  fp_floodplain(cfg2, scenarios = scen_id)
  t_replay <- secs(t0)
  rp <- jsonlite::read_json(file.path(replay_dir, "provenance.json"))$floodplain[[scen_id]]
  replay_tif <- file.path(replay_dir, paste0("floodplain_", scen_id, ".tif"))
  replay_fp  <- fp_raster_content_sha256(replay_tif)
  if (!identical(replay_fp, rp$outputs$floodplain_content_sha256))
    stop("step 2 replay: its raster does not digest equal to its own provenance record", call. = FALSE)

  # --- the probe's own arm 5, on its own DEM ---
  t0 <- Sys.time()
  dem5 <- flooded::fl_dem_aoi(s5, buffer = buf, target_crs = sf::st_crs(s5))
  t_dem <- secs(t0)
  got_dem <- fp_raster_content_sha256(dem5)
  message("  DEM vs step 2 replay: ", if (identical(got_dem, rp$inputs$dem_content_sha256)) "MATCH" else "DIFFERS",
          "; vs published record: ", if (identical(got_dem, rec_dem)) "MATCH" else "DIFFERS", " (", t_dem, " s)")
  if (!identical(got_dem, rp$inputs$dem_content_sha256))
    stop("ANCHOR FAIL (DEM): the probe and step 2, run minutes apart on one machine, fetched different ",
         "DEMs for the same network", call. = FALSE)

  t0 <- Sys.time()
  v5 <- delineate(dem5, s5, wb5)
  t_delin <- secs(t0)
  f5 <- p_out("anchor_floodplain.tif")
  fp_rast_write(v5, f5, overwrite = TRUE, datatype = "FLT4S")   # 02's pinned type
  got_fp <- fp_raster_content_sha256(f5)
  pub_tif <- file.path(dir_area, paste0("floodplain_", scen_id, ".tif"))
  ondisk  <- fp_raster_content_sha256(pub_tif)
  cells <- function(f) { r <- terra::rast(f); sum(terra::values(r, mat = FALSE) == 1, na.rm = TRUE) * prod(terra::res(r)) / 1e4 }
  ha_pub <- cells(pub_tif); ha_rep <- cells(replay_tif)
  r_pub <- terra::rast(pub_tif); r_new <- terra::rast(f5)
  message("  anchor 2 (floodplain vs step 2 replay): ", if (identical(got_fp, replay_fp)) "MATCH" else "DIFFERS",
          " (", t_delin, " s)")
  message("  published record: floodplain ", if (identical(got_fp, rec_fp)) "MATCH" else "DIFFERS",
          sprintf("; %.1f ha published vs %.1f ha today (%+.3f%%)", ha_pub, ha_rep, 100 * (ha_rep - ha_pub) / ha_pub))
  write_json(list(mode = "anchor", scenario = scen_id, network = got_net, dem = got_dem, floodplain = got_fp,
                  network_match = identical(got_net, rec_net),
                  dem_match_replay = identical(got_dem, rp$inputs$dem_content_sha256),
                  floodplain_match_replay = identical(got_fp, replay_fp),
                  dem_match_published = identical(got_dem, rec_dem),
                  floodplain_match_published = identical(got_fp, rec_fp),
                  ondisk_matches_its_record = identical(ondisk, rec_fp),
                  published_ha = ha_pub, today_ha = ha_rep,
                  published_ext = sprintf("%.9f", as.vector(terra::ext(r_pub))),
                  today_ext = sprintf("%.9f", as.vector(terra::ext(r_new))),
                  published_res = sprintf("%.9f", terra::res(r_pub)[1]), today_res = sprintf("%.9f", terra::res(r_new)[1]),
                  t_replay_s = t_replay, t_dem_s = t_dem, t_delin_s = t_delin,
                  flooded = as.character(packageVersion("flooded")), terra = as.character(packageVersion("terra")),
                  terra_gdal = terra::gdal(), sf_gdal = unname(sf::sf_extSoftVersion()[["GDAL"]])),
             p_out("anchor.json"))
  if (!identical(got_fp, replay_fp))
    stop("ANCHOR FAIL (floodplain): same network, same DEM, and the probe's VCA call does not reproduce ",
         "step 2's. replay ", replay_fp, ", probe ", got_fp, call. = FALSE)
  message("PROBE_DONE anchor")
}

# =================================================================================================
if (mode == "dem") {
  conn <- DBI::dbConnect(RPostgres::Postgres())
  all <- fp_wf_read_network(conn, read_schema, wsg, species)
  DBI::dbDisconnect(conn)
  # Nesting on the LIVE read. The offline check proves the predicates nest; this proves the data
  # did not find a case the fixture missed.
  k <- lapply(FP_WF_ARMS$arm, function(a) fp_wf_keep(all, a, min_order))
  inside <- function(sup, sub) all(!k[[sub]] | k[[sup]])
  if (!(inside(1, 2) && inside(2, 3) && inside(3, 5) && inside(4, 3)))
    stop("arms do not nest on the live read", call. = FALSE)
  s1 <- all[k[[1]], ]
  t0 <- Sys.time()
  d <- flooded::fl_dem_aoi(s1, buffer = buf, target_crs = sf::st_crs(s1))
  t_dem <- secs(t0)
  sha_mem <- fp_raster_content_sha256(d)
  dem_path <- p_out("dem_common.tif")
  # FLT8S: the reprojected DEM is double in memory; a float write would round it and the arms would
  # then not be delineated on the DEM the digest describes.
  fp_rast_write(d, dem_path, overwrite = TRUE, datatype = "FLT8S")
  sha_file <- fp_raster_content_sha256(dem_path)
  if (!identical(sha_mem, sha_file)) stop("dem_common.tif does not round-trip the fetched DEM", call. = FALSE)
  r <- terra::rast(dem_path)
  if (sf::st_crs(terra::crs(r)) != sf::st_crs(s1)) stop("dem_common.tif CRS differs from the network's", call. = FALSE)
  n_na <- terra::global(is.na(r), "sum")[[1]]
  message("  DEM: ", terra::ncol(r), " x ", terra::nrow(r), ", ", n_na, " NA cells, ", t_dem, " s")
  write_json(c(list(mode = "dem", dem_content_sha256 = sha_file, ncol = terra::ncol(r), nrow = terra::nrow(r),
                    na_cells = n_na, res = sprintf("%.9f", terra::res(r)[1]),
                    ext = sprintf("%.9f", as.vector(terra::ext(r))), t_dem_s = t_dem,
                    arm_segments = vapply(k, sum, 0)), vers()), p_out("dem.json"))
  message("PROBE_DONE dem")
}

# =================================================================================================
if (mode %in% as.character(FP_WF_ARMS$arm)) {
  arm <- fp_wf_check_arm(mode)
  dem_path <- p_out("dem_common.tif")
  if (!file.exists(dem_path) || !file.exists(p_out("dem.json")))
    stop("dem_common.tif is absent: run the `dem` mode first, it defines the common grid", call. = FALSE)
  conn <- DBI::dbConnect(RPostgres::Postgres())
  all <- fp_wf_read_network(conn, read_schema, wsg, species)
  s  <- read_arm(conn, arm, all)
  s5 <- all[fp_wf_keep(all, 5L, min_order), ]
  wb <- fp_wf_read_waterbodies(conn, s)
  DBI::dbDisconnect(conn)

  dem <- terra::rast(dem_path)
  dem_sha <- fp_raster_content_sha256(dem)
  if (!identical(dem_sha, jsonlite::read_json(p_out("dem.json"))$dem_content_sha256))
    stop("dem_common.tif has changed since the `dem` mode wrote it", call. = FALSE)
  bb <- sf::st_bbox(s); de <- as.vector(terra::ext(dem))
  if (bb[["xmin"]] < de[["xmin"]] || bb[["xmax"]] > de[["xmax"]] || bb[["ymin"]] < de[["ymin"]] || bb[["ymax"]] > de[["ymax"]])
    stop("arm ", arm, "'s streams extend beyond dem_common.tif", call. = FALSE)

  t0 <- Sys.time()
  v <- delineate(dem, s, wb)
  t_delin <- secs(t0)
  vv <- terra::values(v, mat = FALSE)
  n_valley <- sum(vv == 1, na.rm = TRUE)
  fp_out <- p_out("arm", arm, "_floodplain.tif")
  fp_rast_write(v, fp_out, overwrite = TRUE, datatype = "FLT4S")
  message("  delineation: ", t_delin, " s, ", n_valley, " valley cells (",
          round(n_valley * prod(terra::res(v)) / 1e6, 1), " km2)")

  # Waterbody cells: flooded ORs every waterbody into the valley with no slope or distance filter,
  # so a floor that brings headwater lakes and wetlands adds area that says nothing about whether a
  # first-order valley is floodplain. Rasterized the way flooded burns them (field = 1, no touches).
  wb_r <- if (is.null(wb) || !nrow(wb)) terra::init(terra::rast(dem), 0) else
    terra::rasterize(terra::vect(sf::st_transform(wb, terra::crs(dem))), dem, field = 1, background = 0)
  fp_rast_write(wb_r, p_out("arm", arm, "_waterbody.tif"), overwrite = TRUE, datatype = "INT1U")
  n_valley_wb <- sum(vv == 1 & terra::values(wb_r, mat = FALSE) == 1, na.rm = TRUE)

  t0 <- Sys.time()
  a <- attribute(v, s, dem, "blue_line_key")
  t_attr <- secs(t0)
  a$x$arm <- arm
  sf::st_write(a$x, p_out("arm", arm, "_by_blk.gpkg"), layer = "by_blk", delete_dsn = TRUE, quiet = TRUE)
  message("  attribution by blue_line_key: ", t_attr, " s, ", nrow(a$x), " rows, ", a$n_warn, " warnings")

  # The coho-reachable floodplain under THIS arm's delineation: the coho network as ONE group,
  # complete = FALSE so cells reached only by the fallback stay out.
  s5$coho_net <- 1L
  t0 <- Sys.time()
  cr <- attribute(v, s5, dem, "coho_net")
  t_coho <- secs(t0)
  cr_x <- cr$x
  if (!is.null(cr_x) && nrow(cr_x)) cr_x$arm <- arm
  sf::st_write(cr_x, p_out("arm", arm, "_coho_reach.gpkg"), layer = "coho_reach", delete_dsn = TRUE, quiet = TRUE)
  message("  coho-reachable floodplain: ", round(sum(as.numeric(sf::st_area(cr_x))) / 1e4, 1), " ha, ", t_coho, " s")

  write_json(c(list(
    mode = "arm", arm = arm, label = FP_WF_ARMS$label[arm], scenario = scen_id,
    n_segments = nrow(s), km = round(sum(s$length_metre) / 1000, 3),
    n_blk = length(unique(s$blue_line_key)), n_waterbodies = if (is.null(wb)) 0L else nrow(wb),
    dem_ncol = terra::ncol(dem), dem_nrow = terra::nrow(dem), dem_content_sha256 = dem_sha,
    valley_cells = n_valley, valley_cells_waterbody = n_valley_wb, cell_m2 = prod(terra::res(v)),
    floodplain_content_sha256 = fp_raster_content_sha256(fp_out),
    t_delin_s = t_delin, t_attr_blk_s = t_attr, t_coho_reach_s = t_coho,
    attr_rows = nrow(a$x), attr_warnings = a$n_warn, attr_first_warning = a$first_warning,
    fallback_cells = attr(a$x, "fl_fallback_cells") %||% NA,
    coho_reach_ha = sum(as.numeric(sf::st_area(cr_x))) / 1e4,
    threads = terra::terraOptions(print = FALSE)$threads %||% NA), vers()),
    p_out("arm", arm, "_timing.json"))
  message("PROBE_DONE ", arm)
}

# =================================================================================================
if (mode == "seg") {
  arm <- 3L
  f3 <- p_out("arm3_floodplain.tif"); dem_path <- p_out("dem_common.tif")
  if (!file.exists(f3) || !file.exists(dem_path)) stop("run the `dem` mode and arm 3 first", call. = FALSE)
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
  write_json(c(list(mode = "seg", arm = arm, n_groups = nrow(s), t_attr_seg_s = t_attr, attr_rows = nrow(a$x),
                    attr_warnings = a$n_warn, attr_first_warning = a$first_warning,
                    fallback_cells = attr(a$x, "fl_fallback_cells") %||% NA), vers()), p_out("seg_timing.json"))
  message("PROBE_DONE seg")
}

# =================================================================================================
if (mode == "report") {
  source(file.path(lcc, "floodplain_probe-report.R"))
  fp_wf_report(area = area, dir_area = dir_area, dir_out = dir_out, scen_id = scen_id, species = species,
               min_order = min_order, wsg = wsg, read_schema = read_schema)
  message("PROBE_DONE report")
}
