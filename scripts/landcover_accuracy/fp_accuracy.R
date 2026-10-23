# fp_accuracy.R — helpers for measuring IO LULC accuracy inside a floodplain (#93).
#
# The sampler and estimators are drift's (dft_accuracy_*, drift#81). This file only resolves
# the area and builds what drift is handed. It must stay free of side effects when sourced:
# run_area.R cannot be sourced for fp_read_config() because it dispatches the pipeline at top
# level, so the minimum of area.yml this module needs is read here.

`%||%` <- function(a, b) if (is.null(a)) b else a
source(here::here("scripts", "fp_raster.R"))   # fp_rast_cells; defines functions only

# area name -> the few facts the accuracy scripts need, with the same defaults run_area.R applies.
# The scenario and change interval are the DESIGN's once one is committed (#140): see fp_acc_scenario().
fp_acc_area <- function(area, scenario = NULL, redesign = FALSE) {
  cfg_dir <- here::here("config", area)
  if (!dir.exists(cfg_dir)) stop("no config for area '", area, "' at ", cfg_dir, call. = FALSE)
  cfg <- yaml::read_yaml(file.path(cfg_dir, "area.yml"))
  cfg$area    <- area
  cfg$dir_out <- here::here("data", area)
  cfg$dir_acc <- file.path(cfg$dir_out, "accuracy")
  cfg$dir_ref <- here::here("reference", area)
  sc  <- utils::read.csv(file.path(cfg_dir, "flood_scenarios.csv"), stringsAsFactors = FALSE)
  cfg <- fp_acc_scenario(cfg, fp_acc_design_scenario(file.path(cfg$dir_ref, "design.json")), sc,
                         scenario = scenario, redesign = redesign)
  cfg$dir_rast <- file.path(cfg$dir_out, "rasters", cfg$primary_scenario)
  cfg
}

# The population a committed design was drawn from (#140), parsed from design.json's
# `transition_layer` (`transition_<scenario>_<from>_<to>`), the one field the draw wrote it into.
# NULL when there is no design yet. design.json is never hand-edited, so it is parsed, not extended.
fp_acc_design_scenario <- function(path) {
  if (!file.exists(path)) return(NULL)
  d   <- jsonlite::read_json(path, simplifyVector = TRUE)
  lyr <- d$transition_layer
  m   <- if (is.character(lyr) && length(lyr) == 1)
    regmatches(lyr, regexec("^transition_([a-z]+_ff[0-9]+)_([0-9]{4})_([0-9]{4})$", lyr))[[1]]
  if (length(m) != 4)
    stop(path, ": transition_layer `", if (is.null(lyr)) "absent" else paste(lyr, collapse = ","),
         "` does not name a scenario and interval (transition_<sp>_ffNN_<from>_<to>)", call. = FALSE)
  list(scenario = m[2], change_interval = as.integer(m[3:4]), design = d)
}

# cfg (area.yml) + the design's scenario -> the scenario every accuracy stage reads (#140).
# A committed design wins: its sample, strata and labels describe one grid, and area.yml moves with
# the pipeline (#125 moved NECR to all_ff04 under a ch_ff04 sample, and every stage followed it).
# area.yml answers only before a first draw. An explicit `scenario` that differs from the design's is
# refused unless `redesign` (sample_draw-pilot.R under FORCE=1, which orphans every label anyway); a
# redesign also drops the design's grid, since a forced redraw is how a moved grid gets a new design.
# Species and min_order come from the scenario's row in flood_scenarios.csv (`scenarios`), as
# run_area.R resolves them, never from area.yml: #125 moved NECR to `all` at order 2, and the design's
# network is ch at order 3. cfg$design carries the design's grid for fp_acc_grid() to hold rasters to.
fp_acc_scenario <- function(cfg, des = NULL, scenarios, scenario = NULL, redesign = FALSE) {
  yml_scen <- cfg$primary_scenario %||% paste0(cfg$species, "_ff04")
  yml_int  <- cfg$change_interval %||% c(2017L, 2023L)
  if (is.null(des) || redesign) {
    cfg$primary_scenario <- scenario %||% des$scenario %||% yml_scen
    cfg$change_interval  <- if (identical(cfg$primary_scenario, des$scenario)) des$change_interval else yml_int
    cfg$scenario_source  <- if (!is.null(scenario)) "argument" else if (!is.null(des)) "design" else "area.yml"
    cfg$design           <- NULL
  } else {
    if (!is.null(scenario) && !identical(scenario, des$scenario))
      stop("scenario `", scenario, "` differs from the design's `", des$scenario, "` (reference/",
           cfg$area, "/design.json); only a redraw (sample_draw-pilot.R, FORCE=1) may move it", call. = FALSE)
    if (!identical(yml_scen, des$scenario) || !identical(as.integer(yml_int), des$change_interval))
      message("NOTE: area.yml names ", yml_scen, " ", paste(yml_int, collapse = "-"), "; the accuracy ",
              "design is on ", des$scenario, " ", paste(des$change_interval, collapse = "-"), ", which is read")
    cfg$primary_scenario <- des$scenario
    cfg$change_interval  <- des$change_interval
    cfg$scenario_source  <- "design"
    cfg$design           <- des$design
  }
  row <- scenarios[scenarios$scenario_id == cfg$primary_scenario, , drop = FALSE]
  if (nrow(row) != 1)
    stop("scenario `", cfg$primary_scenario, "` has ", nrow(row), " rows in config/", cfg$area,
         "/flood_scenarios.csv; its species and min_order cannot be resolved", call. = FALSE)
  cfg$species   <- row$species
  cfg$min_order <- as.integer(row$min_order)
  cfg
}

# The grid a design was drawn on, rebuilt from design.json (as review_build-qgis.R does for its cells)
fp_acc_design_grid <- function(d) {
  terra::rast(nrows = d$dims[[1]], ncols = d$dims[[2]], xmin = d$extent[[1]], xmax = d$extent[[2]],
              ymin = d$extent[[3]], ymax = d$extent[[4]], crs = d$crs)
}

# "EPSG:<code>" of a raster, for handing a grid's CRS to drift
fp_acc_epsg <- function(path) {
  code <- terra::crs(terra::rast(path), describe = TRUE)$code
  if (is.na(code) || !nzchar(code)) stop("no EPSG code for ", path, call. = FALSE)
  paste0("EPSG:", code)
}

FP_ACC_TREES <- 2L   # IO LULC class code for Trees

# The classified series + transition for the area's accuracy scenario (fp_acc_scenario), on one grid, checked.
# The transition is what step 3 published (1 ha sieve applied); the classified rasters are IO's own
# labels. Both are read from disk, and they must agree: a partial re-run of step 3 can rewrite one
# without the other, and every stratum and omission number assumes they describe the same map.
fp_acc_grid <- function(cfg, years = NULL) {
  yrs  <- years %||% seq(cfg$change_interval[1], cfg$change_interval[2])
  cls  <- lapply(yrs, function(y) terra::rast(file.path(cfg$dir_rast, sprintf("classified_%d.tif", y))))
  names(cls) <- yrs
  tr   <- terra::rast(file.path(cfg$dir_rast, "transition.tif"))
  # The sample's cells are numbered on the design grid, so any other grid puts every point on another
  # cell, whatever the scenario string says (#140).
  if (!is.null(cfg$design) && !terra::compareGeom(tr, fp_acc_design_grid(cfg$design), stopOnError = FALSE))
    stop(cfg$primary_scenario, "/transition.tif (", paste(dim(tr)[1:2], collapse = " x "), ") is not the grid ",
         "reference/", cfg$area, "/design.json was drawn on (", paste(cfg$design$dims, collapse = " x "),
         "); step 3 has moved the design's scenario", call. = FALSE)
  for (y in names(cls)) {
    if (!terra::compareGeom(cls[[y]], tr, stopOnError = FALSE))
      stop("classified_", y, ".tif is not on the transition grid", call. = FALSE)
  }
  ends <- as.character(cfg$change_interval)
  if (!all(ends %in% names(cls))) stop("endpoint years missing from the classified series", call. = FALSE)
  # raw codes: drop the category tables so arithmetic sees IO codes / from*1000+to
  cls <- lapply(cls, function(r) { r <- terra::deepcopy(r); terra::set.cats(r, layer = 1, value = NULL); r })
  tr  <- terra::deepcopy(tr); terra::set.cats(tr, layer = 1, value = NULL)
  expect <- cls[[ends[1]]] * 1000L + cls[[ends[2]]]
  # NA-safe: a published transition cell whose endpoint is NA is a disagreement too, and `tr != NA`
  # would be NA and dropped by na.rm.
  bad <- terra::global(!is.na(tr) & (is.na(expect) | (tr != expect)), "sum", na.rm = TRUE)[[1]]
  if (bad > 0) stop(bad, " transition cells disagree with classified_", ends[1], "*1000+classified_",
                    ends[2], " -- step 3 outputs are out of sync", call. = FALSE)
  list(cls = cls, trans = tr, from = cls[[ends[1]]], to = cls[[ends[2]]], years = yrs, ends = ends)
}

# 1 inside any polygon (cell centre), NA elsewhere, on `template`'s grid. Overlaps count once.
# Delegates to fp_rast_cells() (scripts/fp_raster.R), which the composition table (#108) uses too:
# one membership rule for both.
fp_acc_rasterize <- function(polys, template) fp_rast_cells(polys, template)

# Omission of tree loss inside reference-disturbance cells (criterion 4 and its published twin).
#   denominator: footprint cells in `inpoly` that IO labelled Trees at `from`
#   IO view:     of those, the ones IO labels non-Trees at `to` (unsieved)
#   published:   of those, the ones the published transition carries as Trees -> non-Trees
# `inpoly` is 1/NA. Areas in ha from the grid's cell size.
fp_acc_omission <- function(from, to, trans, inpoly) {
  ha   <- prod(terra::res(from)) / 1e4
  base <- !is.na(inpoly) & !is.na(from) & !is.na(to) & (from == FP_ACC_TREES)
  n    <- function(x) terra::global(x, "sum", na.rm = TRUE)[[1]]
  d    <- n(base)
  io   <- n(base & (to != FP_ACC_TREES))
  pub  <- n(base & !is.na(trans) & (trans %/% 1000L == FP_ACC_TREES) & (trans %% 1000L != FP_ACC_TREES))
  data.frame(denom_ha = d * ha, io_loss_ha = io * ha, published_loss_ha = pub * ha,
             omission_io = if (d) 1 - io / d else NA_real_,
             omission_published = if (d) 1 - pub / d else NA_real_)
}

# Criterion 4's input: harvest omission over the whole window, from reference_omission-disturbance.R.
# Refused unless it names the scenario the estimate is on (#140): a file from before a redraw, or from
# the #125 window when the module followed area.yml, would score the criterion on another floodplain.
fp_acc_omission_read <- function(path, scenario) {
  o <- utils::read.csv(path, stringsAsFactors = FALSE)
  if (!"scenario" %in% names(o) || !all(o$scenario == scenario))
    stop(path, " is on ", if ("scenario" %in% names(o)) paste(unique(o$scenario), collapse = ", ") else
           "an unrecorded scenario (predates #140)", ", not ", scenario,
         "; re-run reference_omission-disturbance.R", call. = FALSE)
  v <- o$omission_io[o$source == "harvest" & o$year == "all"]
  if (length(v) != 1) stop(path, " has ", length(v), " harvest/all rows", call. = FALSE)
  v
}

# The composite windows (reference/<area>/windows.csv) were counted over one floodplain. `derive` writes
# its scenario beside them (#148), and every reader refuses another or none: a redraw onto a new scenario
# would otherwise build its chips from the old floodplain's windows, with no message. months as
# character: an all-single-month file ("7") would otherwise read back as integer.
fp_acc_windows_read <- function(path, scenario) {
  w <- utils::read.csv(path, stringsAsFactors = FALSE, colClasses = c(months = "character"))
  if (!all(c("window", "year", "months") %in% names(w)))
    stop(path, " needs columns window, year, months (e.g. \"7-8\")", call. = FALSE)
  if (!"scenario" %in% names(w) || !nrow(w) || !all(w$scenario %in% scenario))
    stop(path, " is on ", if ("scenario" %in% names(w)) paste(unique(w$scenario), collapse = ", ") else
           "an unrecorded scenario (predates #148)", ", not ", scenario,
         "; re-run window_count-clear.R <area> run, then derive", call. = FALSE)
  if (anyDuplicated(w[, c("window", "year")])) stop("duplicate window x year in ", path, call. = FALSE)
  w
}

# `derive`'s input, the clear-day counts `run` cached (data/<area>/accuracy/windows_clear_obs.csv): the
# per-month rows at res 100, refused unless every row names this scenario. derive mixes them with direct
# counts over the current floodplain, so counts from another one would decide a committed file (#148).
fp_acc_window_obs_read <- function(path, scenario) {
  st <- utils::read.csv(path, stringsAsFactors = FALSE)
  if (!"scenario" %in% names(st) || !nrow(st) || !all(st$scenario %in% scenario))
    stop(path, " was counted on ", if ("scenario" %in% names(st)) paste(unique(st$scenario), collapse = ", ") else
           "an unrecorded scenario (predates #148)", ", not ", scenario,
         "; re-run window_count-clear.R <area> run", call. = FALSE)
  st <- st[st$res == 100 & grepl("^[0-9]+$", st$month), ]   # per-month rows only
  st$month <- as.integer(st$month)
  st
}

# --- Strata (phase 5) -------------------------------------------------------------------------
# One stratum per footprint cell, FIRST MATCH WINS in the order below (research/landcover_accuracy.md,
# "Strata"). Cause strata come first and are numbered 1..k in `sources:` order; the rest are fixed.
#   change   = the PUBLISHED transition says from != to
#   sieved   = IO changed the cell, the 1 ha sieve removed it: published says "no change"
#   stable   = IO itself says from == to
# The three kinds partition the footprint, so every cell lands in exactly one stratum.
FP_ACC_STRATA_FIXED <- data.frame(
  stratum = c(10L, 11L, 12L, 13L, 14L, 15L, 16L, 17L, 18L, 20L, 30L, 31L, 32L),
  label   = c("wetland change", "Trees -> Rangeland", "Rangeland -> Trees", "Crops <-> Rangeland",
              "Crops <-> Trees", "Snow/Ice -> any", "any <-> Water", "other tree loss",
              "other change", "sieved change (<1 ha)", "stable wetland", "stable Trees",
              "stable other"),
  kind    = c(rep("change", 9), "sieved", rep("stable", 3))
)

# Published change inside a fire from the `lookback:` years before the interval (#103). NOT a cause:
# it sits after every cause stratum, its label is not "change: <cause>" (which is how fp_acc_estimate
# finds cause strata), and its cells stay in criterion 2's unattributed loss. It exists so the labels
# can say whether change inside older burns is real -- the decision that would make it a cause. Drawn
# only for the lookback entry of this name; any other lookback has no stratum (sample_draw refuses it).
FP_ACC_PRIOR_NAME <- "fire_prior"
FP_ACC_STRATUM_PRIOR <- data.frame(stratum = 19L, label = "change in prior fire", kind = "change")

# The strata table for a given ordered set of cause names: causes 1..k, then the prior-fire stratum
# when one is drawn, then the fixed strata.
fp_acc_strata_table <- function(causes, prior = FALSE) {
  rbind(data.frame(stratum = seq_along(causes), label = paste0("change: ", causes), kind = "change"),
        if (prior) FP_ACC_STRATUM_PRIOR,
        FP_ACC_STRATA_FIXED)
}

# from, to:  IO classified endpoints (raw codes). trans: published transition (NA = outside or sieved).
# causes:    NAMED list of 1/NA rasters, in precedence order (published patch flags, rasterised).
# wet:       1/NA raster of FWA wetland cells.
# prior:     OPTIONAL 1/NA raster of cells inside a lookback fire (#103), at CELL level like `wet`:
#            the polygons cover stable and sieved land too, and only published change cells take the
#            stratum -- so there is no stray-cell guard here, unlike the patch-level cause flags.
# Returns list(strata = factor SpatRaster, reported = the published map claim per cell, table).
fp_acc_strata <- function(from, to, trans, causes, wet, prior = NULL) {
  if (is.null(names(causes)) || any(!nzchar(names(causes))))
    stop("`causes` must be a named list in precedence order", call. = FALSE)
  tb   <- fp_acc_strata_table(names(causes), prior = !is.null(prior))
  code <- function(lbl) tb$stratum[tb$label == lbl]
  foot <- !is.na(from) & !is.na(to)
  chg  <- foot & !is.na(trans) & ((trans %/% 1000L) != (trans %% 1000L))
  siev <- foot & is.na(trans) & (from != to)
  stab <- foot & (from == to)
  inw  <- !is.na(wet)
  f <- from; t <- to
  # A cause flag lives on a published change patch, so its cells must be published change cells.
  # A cell outside that set means the patches and transition.tif came from different runs.
  for (k in names(causes)) {
    stray <- terra::global(!is.na(causes[[k]]) & !chg, "sum", na.rm = TRUE)[[1]]
    if (stray > 0) stop(stray, " `", k, "` cells are not published change cells", call. = FALSE)
  }

  # lowest precedence first; each later ifel overrides, so the LAST assignment is the first match
  s <- terra::ifel(stab, code("stable other"), NA)
  s <- terra::ifel(stab & (f == FP_ACC_TREES), code("stable Trees"), s)
  # wetland is the same rule for stable and change land: FWA cell, or Flooded Vegetation (here both
  # endpoints are the same class, so one test)
  s <- terra::ifel(stab & (inw | (f == 4L)), code("stable wetland"), s)
  s <- terra::ifel(siev, code("sieved change (<1 ha)"), s)
  s <- terra::ifel(chg, code("other change"), s)
  s <- terra::ifel(chg & (f == FP_ACC_TREES), code("other tree loss"), s)
  s <- terra::ifel(chg & ((f == 1L) | (t == 1L)), code("any <-> Water"), s)
  s <- terra::ifel(chg & (f == 9L), code("Snow/Ice -> any"), s)
  s <- terra::ifel(chg & (((f == 5L) & (t == 2L)) | ((f == 2L) & (t == 5L))), code("Crops <-> Trees"), s)
  s <- terra::ifel(chg & (((f == 5L) & (t == 11L)) | ((f == 11L) & (t == 5L))), code("Crops <-> Rangeland"), s)
  s <- terra::ifel(chg & (f == 11L) & (t == 2L), code("Rangeland -> Trees"), s)
  s <- terra::ifel(chg & (f == 2L) & (t == 11L), code("Trees -> Rangeland"), s)
  s <- terra::ifel(chg & ((f == 4L) | (t == 4L) | inw), code("wetland change"), s)
  if (!is.null(prior)) s <- terra::ifel(chg & !is.na(prior), code(FP_ACC_STRATUM_PRIOR$label), s)
  for (k in rev(seq_along(causes))) {
    s <- terra::ifel(chg & !is.na(causes[[k]]), k, s)
  }
  names(s) <- "stratum"
  levels(s) <- data.frame(value = tb$stratum, stratum = tb$label)

  # What the published map claims at each cell: the transition where it has one, and "no change"
  # (from*1000+from) where the sieve removed IO's change.
  reported <- terra::ifel(siev, f * 1000L + f, trans)
  reported <- terra::mask(reported, s)
  names(reported) <- "reported"
  list(strata = s, reported = reported, table = tb)
}

# Patch-level cause flags (published) -> one 1/NA raster per cause, in `sources:` order.
fp_acc_cause_rasters <- function(patches, causes, template) {
  out <- lapply(causes, function(nm) {
    col <- paste0("in_", nm)
    if (!col %in% names(patches)) stop("transition layer has no `", col, "` column", call. = FALSE)
    fp_acc_rasterize(patches[patches[[col]] %in% c(TRUE, 1L), ], template)
  })
  stats::setNames(out, causes)
}

# Polygons of one disturbance.yml entry that touch the floodplain footprint `fp` (an sf in the grid
# CRS). fp_disturbance.R's padded-bbox query (sourced by the caller) fetches the bbox; this keeps
# only what touches the footprint, in the grid CRS.
fp_acc_fetch <- function(conn, src, fp, window) {
  p <- sf::st_transform(.dst_fetch(conn, src, fp, window), sf::st_crs(fp))
  p[lengths(sf::st_intersects(p, fp)) > 0, ]
}

# --- Review, labels and estimation (phases 6-7) ------------------------------------------------
FP_ACC_IO_CODES   <- c(1L, 2L, 4L, 5L, 7L, 8L, 9L, 11L)
FP_ACC_STATUS     <- c("labelled", "cannot_label")
FP_ACC_CONFIDENCE <- c("high", "medium", "low")
# `orthophoto` and `airphoto` are the DATED high-resolution sources (#103); which epoch covers a point
# is in reference/<area>/imagery.csv. `esri_dated` is the per-point Wayback capture nearest an endpoint
# (#115; reference/<area>/wayback.csv), kept apart from `esri`, the UNDATED basemap that labelling-key
# rule 5 caps at low confidence. labels_form.qml's value map must list exactly these.
FP_ACC_IMAGERY    <- c("s2_composite", "orthophoto", "airphoto", "esri_dated", "esri", "google", "bing",
                       "several")

# Which dated imagery epochs earn a review theme (#103), from reference/<area>/imagery.csv: a source-year
# covering >= 25% of the sample's points, and for air photos digital frames only -- fly_georef skips a
# film frame with a flight bearing until its roll's rotation is known (fly#53). One definition, read by
# imagery_index-dated.R (to report it) and imagery_build-dated.R (to build it), so the two cannot differ.
FP_ACC_THEME_MIN_SHARE <- 0.25
fp_acc_imagery_themes <- function(imagery, n_points) {
  imagery <- imagery[!is.na(imagery$source) & nzchar(imagery$source), ]   # rows for uncovered points
  if (!nrow(imagery)) return(data.frame(source = character(0), year = integer(0), points = integer(0),
                                        share = numeric(0), digital = logical(0), theme = logical(0)))
  key <- paste(imagery$source, imagery$year)
  out <- do.call(rbind, lapply(split(imagery, key), function(g) data.frame(
    source = g$source[1], year = as.integer(g$year[1]), points = length(unique(g$point_id)),
    digital = all(grepl("^Digital", g$media[g$source == "airphoto"])))))
  out$share <- out$points / n_points
  out$theme <- out$share >= FP_ACC_THEME_MIN_SHARE & (out$source == "orthophoto" | out$digital)
  out[order(out$source, out$year), c("source", "year", "points", "share", "digital", "theme")]
}

# --- Esri Wayback captures (#115) ---------------------------------------------------------------
# A Wayback release mosaics captures of many years, so the release date says nothing about when a
# point was imaged (rtj research/esri_wayback.md). wayback_index-capture.R reads each release's capture
# polygons and hands every (point, release) capture here; this picks, per point and endpoint, the
# capture nearest the endpoint. Ranked by whole years from the endpoint first, because the
# pre-registered labelling key sets confidence by whole years (+/-2 since #145); then by days from 1 July of the endpoint
# year (mid growing season); then finer resolution; then the later release, then the larger release id
# (a release serving the same capture as an earlier one redirects to its tiles, so either fetches it).
# Every point gets a row at every endpoint; one with no capture has an empty release.
FP_ACC_WAYBACK_COLS <- c("point_id", "endpoint", "release_id", "release_date", "capture_date", "src_res",
                         "source", "zoom", "years_from_endpoint")
fp_acc_wayback_pick <- function(cand, point_ids, endpoints) {
  cand <- cand[!is.na(cand$capture_date) & nzchar(cand$capture_date), ]   # empty is "no capture", as NA is
  cap  <- as.Date(cand$capture_date)
  out <- lapply(as.integer(endpoints), function(e) {
    yrs  <- as.integer(format(cap, "%Y")) - e
    days <- abs(as.numeric(cap - as.Date(sprintf("%d-07-01", e))))
    o <- order(cand$point_id, abs(yrs), days, cand$src_res, -as.numeric(as.Date(cand$release_date)),
               -as.numeric(cand$release_id), method = "radix")
    best <- cand[o, ][!duplicated(cand$point_id[o]), ]
    m <- match(point_ids, best$point_id)
    data.frame(point_id = point_ids, endpoint = e,
               release_id = best$release_id[m], release_date = as.character(best$release_date[m]),
               capture_date = format(as.Date(best$capture_date[m]), "%Y-%m-%d"),
               src_res = best$src_res[m], source = best$source[m], zoom = best$zoom[m],
               years_from_endpoint = as.integer(format(as.Date(best$capture_date[m]), "%Y")) - e,
               stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, out)
  out[order(out$point_id, out$endpoint, method = "radix"), FP_ACC_WAYBACK_COLS]
}

# What the reviewer reads beside a cell: "2017-06-11, 0.31 m", or "none" for no capture.
fp_acc_capture_label <- function(capture_date, src_res)
  ifelse(is.na(capture_date) | !nzchar(capture_date), "none", sprintf("%s, %s m", capture_date, src_res))

# A review-project file name for a point. Named by review_id ONLY: point_id encodes the stratum (#111),
# so a chip named by it would tell the reviewer the map's answer from the layer list.
fp_acc_point_id_like <- function(x) grepl("[0-9]+_[0-9]{5}", x)
fp_acc_chip_name <- function(review_id) {
  nm <- sprintf("%04d.tif", as.integer(review_id))
  if (anyNA(review_id) || any(fp_acc_point_id_like(nm))) stop("a chip name would carry a point_id", call. = FALSE)
  nm
}

# The cells.gpkg display columns for a set of keyed points: per review_id, capture_<endpoint> =
# "2017-06-11, 0.31 m" (or "none"). From the BUILT chips (manifest rows: review_id, endpoint,
# capture_date, src_res), so the label describes the image on screen, not an index the build has not
# caught up with. Read-only context for the reviewer; nothing of the design.
fp_acc_capture_columns <- function(built, review_ids, endpoints) {
  out <- data.frame(review_id = as.integer(review_ids))
  for (e in as.integer(endpoints)) {
    b <- built[built$endpoint == e, ]
    m <- match(out$review_id, b$review_id)
    out[[paste0("capture_", e)]] <- fp_acc_capture_label(b$capture_date[m], b$src_res[m])
  }
  out
}

# A GDAL WMS (TMS) description of one Wayback release at one zoom. GDAL follows the 301 a deduplicated
# tile answers with (QGIS does not: qgis/QGIS#54161), a 404 tile reads as zeros rather than aborting,
# and tiles land in `cache` so a re-run fetches nothing it already has. Written OUTSIDE the review
# project: rtj's compose refuses any non-image file under dated/.
fp_acc_wayback_wms_xml <- function(release_id, zoom, cache) {
  sprintf(paste0(
    '<GDAL_WMS>\n',
    '  <Service name="TMS"><ServerUrl>https://wayback.maptiles.arcgis.com/arcgis/rest/services/World_Imagery/',
    'WMTS/1.0.0/default028mm/MapServer/tile/%s/${z}/${y}/${x}</ServerUrl></Service>\n',
    '  <DataWindow><UpperLeftX>-20037508.34</UpperLeftX><UpperLeftY>20037508.34</UpperLeftY>',
    '<LowerRightX>20037508.34</LowerRightX><LowerRightY>-20037508.34</LowerRightY>',
    '<TileLevel>%d</TileLevel><TileCountX>1</TileCountX><TileCountY>1</TileCountY><YOrigin>top</YOrigin></DataWindow>\n',
    '  <Projection>EPSG:3857</Projection><BlockSizeX>256</BlockSizeX><BlockSizeY>256</BlockSizeY><BandsCount>3</BandsCount>\n',
    '  <ZeroBlockHttpCodes>204,404</ZeroBlockHttpCodes>\n',
    '  <Cache><Path>%s</Path></Cache>\n',
    '</GDAL_WMS>\n'), release_id, as.integer(zoom), cache)
}

# reference/<area>/wayback.csv, checked: exactly one row per sample point per endpoint, and the design
# columns agree with the sample (a redraw reuses point ids). Read by the build and by review_build-qgis.R.
fp_acc_wayback_read <- function(path, smp, endpoints) {
  if (!file.exists(path)) stop("no ", path, " -- run wayback_index-capture.R first", call. = FALSE)
  w <- utils::read.csv(path, stringsAsFactors = FALSE, na.strings = "",
                       colClasses = c(release_id = "character", capture_date = "character"))
  want <- expand.grid(point_id = smp$point_id, endpoint = as.integer(endpoints), stringsAsFactors = FALSE)
  if (nrow(w) != nrow(want) || anyDuplicated(paste(w$point_id, w$endpoint)) ||
      !setequal(paste(w$point_id, w$endpoint), paste(want$point_id, want$endpoint)))
    stop(path, " does not hold exactly one row per sample point per endpoint (", paste(endpoints, collapse = ", "),
         ") -- re-run wayback_index-capture.R", call. = FALSE)
  fp_acc_design_check(w, smp, paste(path, "(re-run wayback_index-capture.R after a redraw)"))
  w
}

# --- the private orthophoto catalogue (#103) ----------------------------------------------------
# This repo is PUBLIC and its run logs are committed, while the orthophoto catalogue is private: its
# endpoint lives only in FP_ORTHO_STAC. rstac and GDAL put URLs in their errors and warnings ("Can't
# open /vsicurl/https://...tif. Skipping it"), so every condition leaving these calls is caught and
# its URLs redacted before it can reach a console or a log. A URL is not the only form the host takes:
# curl names it bare and in brackets ("Could not resolve hostname [host]: ... host: host",
# "Timeout was reached [10.255.255.1]"), so the endpoint's own host, any bracketed token and any
# "host:" tail are redacted too.
fp_acc_redact <- function(x) {
  x <- gsub("https?://[^[:space:]'\"]+", "<url>", x)
  host <- sub("^[a-z]+://([^/:]+).*$", "\\1", Sys.getenv("FP_ORTHO_STAC"))
  if (nzchar(host)) x <- gsub(host, "<host>", x, fixed = TRUE)
  x <- gsub("\\[[^]]*\\]", "[<host>]", x)
  x <- gsub("[0-9]{1,3}([.][0-9]{1,3}){3}", "<ip>", x)
  gsub("(host:?)[[:space:]]+[^[:space:]]+", "\\1 <host>", x, ignore.case = TRUE)
}
fp_acc_quiet_urls <- function(expr, what) {
  warns <- character(0)
  value <- withCallingHandlers(
    tryCatch(expr, error = function(e)
      stop(what, " failed: ", fp_acc_redact(conditionMessage(e)), call. = FALSE)),
    warning = function(w) {
      warns <<- c(warns, fp_acc_redact(conditionMessage(w)))
      invokeRestart("muffleWarning")
    })
  list(value = value, warnings = warns)
}

# Every orthophoto item intersecting a lon/lat bbox: year, cog, gsd_m, epsg, href + footprint. The
# catalogue's one collection is discovered, never named here. `href` is for building a VRT inside the
# gitignored review project only -- no caller may write it to a committed file.
fp_acc_ortho_items <- function(bbox4326) {
  url <- Sys.getenv("FP_ORTHO_STAC")
  if (!nzchar(url)) stop("FP_ORTHO_STAC is unset; add it to ~/.Renviron (the value is not in this repo)",
                         call. = FALSE)
  it <- fp_acc_quiet_urls({
    s  <- rstac::stac(url)
    cl <- rstac::get_request(rstac::collections(s))$collections
    if (length(cl) != 1) stop("the catalogue holds ", length(cl), " collections; expected 1")
    rstac::stac_search(s, collections = cl[[1]]$id, bbox = bbox4326, limit = 500) |>
      rstac::post_request() |> rstac::items_fetch(progress = FALSE)
  }, "the orthophoto catalogue request")$value
  if (!length(it$features)) stop("the orthophoto search returned no items", call. = FALSE)
  # geometry from rstac's own converter; properties from the features (proj:transform is a list)
  p <- function(f, k) f$properties[[k]]
  sf::st_sf(
    year  = vapply(it$features, function(f) as.integer(substr(p(f, "datetime"), 1, 4)), 1L),
    cog   = vapply(it$features, function(f) isTRUE(p(f, "cog")), TRUE),
    gsd_m = vapply(it$features, function(f) abs(as.numeric(p(f, "proj:transform")[[1]] %||% NA)), 0),
    epsg  = vapply(it$features, function(f) as.integer(p(f, "proj:epsg") %||% NA), 1L),
    href  = vapply(it$features, function(f) f$assets$image$href %||% NA_character_, ""),
    geometry = sf::st_geometry(rstac::items_as_sf(it)))
}

# The review project directory (gitignored: chips are large and labels.gpkg is a working copy)
fp_acc_review_dir <- function(cfg) file.path(cfg$dir_acc, "review", paste0(cfg$area, "_lulc_review"))

# A point_id is NOT an identity on its own: drift names points <stratum>_<k>, so a redraw after any
# change to a stratum's cells (a re-run of step 3, a new cause, #100) keeps every id and moves every
# point. Labels are only valid against the design they were made on, so wherever labels meet the
# sample, the design columns they carry must agree with it. Refuse on any disagreement.
FP_ACC_DESIGN_KEY <- c("stratum", "cell", "map_class")
fp_acc_design_check <- function(x, smp, what) {
  cols <- intersect(FP_ACC_DESIGN_KEY, names(x))
  # all three are required: stratum is encoded in the id and map_class is shared by every point of a
  # transition stratum, so without `cell` a redraw that moved every point would still pass
  if (!all(FP_ACC_DESIGN_KEY %in% cols))
    stop(what, " lacks design column(s) ", paste(setdiff(FP_ACC_DESIGN_KEY, cols), collapse = ", "),
         " to check against the sample", call. = FALSE)
  m   <- match(x$point_id, smp$point_id)
  bad <- rep(FALSE, nrow(x))
  for (k in cols) {
    a <- suppressWarnings(as.numeric(x[[k]])); b <- suppressWarnings(as.numeric(smp[[k]][m]))
    bad <- bad | (!is.na(m) & ((is.na(a) != is.na(b)) | (!is.na(a) & !is.na(b) & a != b)))
  }
  if (any(bad)) stop(sum(bad), " point(s) in ", what, " disagree with sample.gpkg on ",
                     paste(cols, collapse = "/"), " (", paste(utils::head(x$point_id[bad], 3), collapse = ", "),
                     "): the sample was redrawn under the same point ids, so these labels describe other ",
                     "cells. Label against the design they were made on, or discard them deliberately.",
                     call. = FALSE)
  invisible(TRUE)
}

# Working-copy labels (one row per point with a label_status) + the committed design -> the
# labels.csv frame. Design columns come from `smp`; only the label fields from `wc`.
fp_acc_labels_frame <- function(wc, smp) {
  if (anyDuplicated(wc$point_id)) stop("duplicate point_id in the working copy", call. = FALSE)
  unk <- setdiff(wc$point_id, smp$point_id)
  if (length(unk)) stop(length(unk), " labelled point(s) are not in sample.gpkg: ",
                        paste(utils::head(unk, 3), collapse = ", "), call. = FALSE)
  fp_acc_design_check(wc, smp, "the label working copy")
  bad <- function(what, ok) if (any(!ok)) stop(sum(!ok), " row(s) with an invalid ", what, ": ",
                                              paste(utils::head(wc$point_id[!ok], 3), collapse = ", "),
                                              call. = FALSE)
  st <- as.character(wc$label_status)
  bad("label_status", st %in% FP_ACC_STATUS)
  lab <- st == "labelled"
  bad("ref_from/ref_to (a labelled point needs both, in IO class codes)",
      !lab | (wc$ref_from %in% FP_ACC_IO_CODES & wc$ref_to %in% FP_ACC_IO_CODES))
  bad("ref_from/ref_to (a cannot_label point must leave them blank)",
      lab | (is.na(wc$ref_from) & is.na(wc$ref_to)))
  bad("confidence", is.na(wc$confidence) | wc$confidence %in% FP_ACC_CONFIDENCE)
  bad("imagery", is.na(wc$imagery) | wc$imagery %in% FP_ACC_IMAGERY)
  d <- smp[match(wc$point_id, smp$point_id), c("point_id", "stratum", "stratum_label", "cell", "map_class", "use")]
  out <- data.frame(
    point_id = d$point_id, stratum = as.integer(d$stratum), stratum_label = d$stratum_label,
    cell = as.numeric(d$cell), map_class = as.integer(d$map_class),
    ref_from = as.integer(wc$ref_from), ref_to = as.integer(wc$ref_to),
    ref_class = ifelse(lab, as.integer(wc$ref_from) * 1000L + as.integer(wc$ref_to), NA_integer_),
    label_status = st, confidence = wc$confidence, imagery = wc$imagery, note = wc$note,
    reviewer = wc$reviewer, labelled_on = format(as.Date(wc$labelled_on), "%Y-%m-%d"),
    use = d$use, stringsAsFactors = FALSE)
  out[order(out$point_id, method = "radix"), , drop = FALSE]
}

# Made-up labels for exercising the pipeline: IO's own endpoints, with a share of ref_to replaced by
# another IO class, and the first point of the first two strata marked cannot_label. RNG restored.
fp_acc_synthetic_labels <- function(smp, p_flip = 0.2, seed = 1L) {
  had <- exists(".Random.seed", envir = globalenv())
  if (had) old <- get(".Random.seed", envir = globalenv())
  on.exit(if (had) assign(".Random.seed", old, envir = globalenv()) else
            rm(".Random.seed", envir = globalenv()), add = TRUE)
  set.seed(seed)
  n <- nrow(smp)
  ref_from <- as.integer(smp$map_2017); ref_to <- as.integer(smp$map_2023)
  flip <- stats::runif(n) < p_flip
  ref_to[flip] <- vapply(ref_to[flip], function(x) sample(setdiff(FP_ACC_IO_CODES, x), 1), 1L)
  status <- rep("labelled", n)
  first <- match(utils::head(sort(unique(smp$stratum)), 2), smp$stratum)
  status[first] <- "cannot_label"; ref_from[first] <- NA; ref_to[first] <- NA
  fp_acc_labels_frame(data.frame(point_id = smp$point_id, stratum = smp$stratum, cell = smp$cell,
                                 map_class = smp$map_class, ref_from = ref_from, ref_to = ref_to,
                                 label_status = status, confidence = NA_character_,
                                 imagery = NA_character_, note = NA_character_, reviewer = "synthetic",
                                 labelled_on = as.Date(NA), stringsAsFactors = FALSE), smp)
}

# Criterion 1 holds if FV producer's accuracy is < 0.5 at EITHER endpoint. Three-valued: a PA that
# drift cannot estimate (no reference FV that year) is NA, and it must not be replaced by the other
# endpoint's value -- that would turn "cannot evaluate" into a verdict.
fp_acc_crit1 <- function(pa17, pa23) {
  pa <- c(pa17, pa23)
  if (any(pa < 0.5, na.rm = TRUE)) TRUE else if (anyNA(pa)) NA else FALSE
}

# Everything research/landcover_accuracy.md defines, from labels.csv rows + the design.
fp_acc_estimate <- function(lab, smp, strata, causes, omission_harvest_io = NA_real_, level = 0.95) {
  z <- stats::qnorm(1 - (1 - level) / 2)
  if (!all(lab$point_id %in% smp$point_id)) stop("labels.csv names points that are not in sample.gpkg", call. = FALSE)
  fp_acc_design_check(lab, smp, "labels.csv")
  d <- merge(lab[, c("point_id", "ref_from", "ref_to", "label_status")], smp, by = "point_id", sort = FALSE)

  # nonresponse, explicitly: dropping it changes each stratum's n (drift refuses it silently)
  nr <- data.frame(stratum = sort(unique(smp$stratum)))
  nr$drawn        <- as.integer(table(factor(smp$stratum, nr$stratum)))
  nr$labelled     <- as.integer(table(factor(d$stratum[d$label_status == "labelled"], nr$stratum)))
  nr$cannot_label <- as.integer(table(factor(d$stratum[d$label_status == "cannot_label"], nr$stratum)))
  thin <- nr$stratum[nr$labelled < 2]
  if (length(thin)) stop("stratum ", paste(thin, collapse = ", "), " has fewer than 2 labelled points; ",
                         "label more (or extend the sample) before estimating", call. = FALSE)
  d <- d[d$label_status == "labelled", ]
  st <- strata[, c("stratum", "n_cells", "area")]

  est <- function(map, ref) drift::dft_accuracy_estimate(
    data.frame(point_id = d$point_id, stratum = d$stratum, map_class = map, ref_class = ref,
               use = d$use), st, level = level)
  acc <- function(e, measure, cls) {
    v <- e$accuracy$estimate[e$accuracy$measure == measure & e$accuracy$class == cls]
    if (length(v)) v else NA_real_
  }

  m_from <- d$map_class %/% 1000L; m_to <- d$map_class %% 1000L
  loss   <- function(f, t) f == FP_ACC_TREES & t != FP_ACC_TREES
  cause_st <- strata$stratum[strata$stratum_label %in% paste0("change: ", causes)]
  in_poly  <- Reduce(`|`, lapply(causes, function(k) as.logical(d[[paste0("in_", k, "_poly")]])))
  in_wet   <- as.logical(d$in_fwa_wetland)
  wetland  <- function(f, t) f != t & (f == 4L | t == 4L | in_wet)

  target <- function(name, m, r) {
    e <- est(ifelse(m, "target", "other"), ifelse(r, "target", "other"))
    a <- e$area[e$area$class == "target", ]
    s <- e$stratum[e$stratum$target == "target", ]
    list(row = data.frame(target = name,
                          area_ha = if (nrow(a)) a$area else 0, area_se = if (nrow(a)) a$area_se else 0,
                          lower = if (nrow(a)) a$lower else 0, upper = if (nrow(a)) a$upper else 0,
                          proportion = if (nrow(a)) a$proportion else 0,
                          proportion_se = if (nrow(a)) a$proportion_se else 0),
         stratum = s)
  }
  trans <- est(d$map_class, d$ref_from * 1000L + d$ref_to)
  t_loss  <- target("tree loss", loss(m_from, m_to), loss(d$ref_from, d$ref_to))
  t_unatt <- target("unattributed tree loss", loss(m_from, m_to) & !d$stratum %in% cause_st,
                    loss(d$ref_from, d$ref_to) & !in_poly)
  t_wet   <- target("wetland change", wetland(m_from, m_to), wetland(d$ref_from, d$ref_to))
  targets <- rbind(t_loss$row, t_unatt$row, t_wet$row)

  pa17 <- acc(est(as.integer(d$map_2017), d$ref_from), "producer", 4)
  pa23 <- acc(est(as.integer(d$map_2023), d$ref_to), "producer", 4)
  ua_tr <- acc(trans, "user", 2011)
  u <- t_unatt$row
  hw <- if (u$area_ha > 0) z * u$area_se / u$area_ha else NA_real_
  crit <- data.frame(
    criterion = 1:4,
    measure = c("Flooded Vegetation producer's accuracy, min of 2017 / 2023",
                "95% CI half-width / estimate, unattributed tree loss",
                "Trees -> Rangeland user's accuracy",
                "IO omission of qualifying harvest (free reference)"),
    value = c(if (anyNA(c(pa17, pa23))) NA_real_ else min(pa17, pa23), hw, ua_tr, omission_harvest_io),
    bar = c("< 0.5", "> 0.5", "< 0.6", "> 0.30"))
  crit$value[!is.finite(crit$value)] <- NA_real_
  crit$holds <- c(fp_acc_crit1(pa17, pa23), crit$value[2] > 0.5, crit$value[3] < 0.6, crit$value[4] > 0.30)
  crit$detail <- c(sprintf("2017 %s, 2023 %s", format(round(pa17, 3)), format(round(pa23, 3))), "", "", "")
  n_hold <- sum(crit$holds, na.rm = TRUE); n_na <- sum(is.na(crit$holds))
  verdict <- if (n_hold >= 2) "pilot a local classifier" else
    if (n_hold + n_na >= 2) "undetermined (a criterion could not be evaluated)" else
      "IO meets the pre-registered bar"

  # full-sample size for the unattributed tree-loss area (half-width 25% of the estimate)
  size <- NULL
  if (u$proportion > 0 && nrow(t_unatt$stratum)) {
    s_h <- t_unatt$stratum$sd[match(strata$stratum, t_unatt$stratum$stratum)]
    s_h[is.na(s_h)] <- 0
    # drift refuses all-zero SDs (a pilot that agreed everywhere is too small to plan from); say so
    # rather than abort every other number with it
    if (any(s_h > 0)) {
      w <- stats::setNames(strata$weight, strata$stratum)
      sz <- drift::dft_accuracy_size(w, se_target = 0.25 * u$proportion / z, s_h = s_h)
      size <- data.frame(stratum = names(sz$allocation), n_full = as.integer(sz$allocation))
      size$n_pilot <- nr$drawn[match(size$stratum, nr$stratum)]
    } else size <- data.frame(note = "every stratum SD is 0 for this target: the pilot cannot size a full sample")
  }
  list(transition = trans, targets = targets, criteria = crit, verdict = verdict,
       nonresponse = nr, size = size, level = level)
}

# --- composite windows (#93 phase 2) -----------------------------------------------------------
# The rule is pre-registered in research/landcover_accuracy.md ("Composite windows") and was
# committed before the counts ran. Pure: it reads window_count-clear.R's per-month stats and
# decides; the live half (a direct count of a widened window) is the script's.
FP_ACC_WIN_THR <- 0.95   # a month is clear everywhere when >= 95% of floodplain cells see a clear day

# stats: one row per year x month with `status` (ok | empty | failed) and `share_ge1`.
# -> list(pass = logical year x month matrix, share = numeric matrix)
# A missing, duplicated or failed month-year is refused: an unmeasured month is not a failed one,
# and treating it as either would move the span.
fp_acc_window_pass <- function(stats, years, months, thr = FP_ACC_WIN_THR) {
  key  <- paste(stats$year, stats$month)
  want <- paste(rep(years, each = length(months)), rep(months, length(years)))
  if (anyDuplicated(key)) stop("duplicate year x month in the window stats", call. = FALSE)
  miss <- setdiff(want, key)
  if (length(miss)) stop("window stats lack ", length(miss), " year x month(s): ",
                         paste(utils::head(miss, 5), collapse = ", "), call. = FALSE)
  s <- stats[match(want, key), ]
  bad <- s$status == "failed" | is.na(s$status) | is.na(s$share_ge1)
  if (any(bad)) stop(sum(bad), " month-year(s) failed or unmeasured (", paste(want[bad], collapse = ", "),
                     "): re-run window_count-clear.R before deriving windows", call. = FALSE)
  share <- matrix(s$share_ge1, nrow = length(years), byrow = TRUE,
                  dimnames = list(as.character(years), as.character(months)))
  list(pass = share >= thr, share = share)
}

# Longest run of contiguous months that passes in every one of `years`; ties go to the run with the
# higher minimum share over its cells, then to the earlier run. integer(0) when no month passes.
fp_acc_window_span <- function(wp, years = rownames(wp$pass)) {
  yrs    <- as.character(years)
  months <- as.integer(colnames(wp$pass))
  ok_m   <- apply(wp$pass[yrs, , drop = FALSE], 2, all)
  runs <- list(); cur <- integer(0)
  for (k in seq_along(months)) {
    contiguous <- length(cur) && months[k] == cur[length(cur)] + 1L
    if (ok_m[k]) cur <- if (contiguous) c(cur, months[k]) else months[k]
    else cur <- integer(0)
    if (ok_m[k]) runs[[length(runs) + 1]] <- cur
  }
  if (!length(runs)) return(integer(0))
  # keep only maximal runs (the loop records every prefix)
  runs <- runs[!vapply(seq_along(runs), function(i)
    i < length(runs) && all(runs[[i]] %in% runs[[i + 1]]), logical(1))]
  len  <- vapply(runs, length, integer(1))
  minv <- vapply(runs, function(r) min(wp$share[yrs, as.character(r), drop = FALSE]), numeric(1))
  first <- vapply(runs, `[`, integer(1), 1)
  runs[[order(-len, -minv, first)[1]]]
}

# The widening order for one year that fails the span: add the adjacent month (within `months`)
# with the higher share for that year, one at a time; a tie takes the earlier month. Returns the
# candidate windows, narrowest first, each one month wider. Which one is USED is decided by a
# direct count of the whole window -- a union of months cannot be read off per-month shares.
fp_acc_window_widen <- function(wp, year, span) {
  months <- as.integer(colnames(wp$pass))
  sh <- wp$share[as.character(year), ]
  out <- list(); cur <- span
  repeat {
    cand <- c(cur[1] - 1L, cur[length(cur)] + 1L)
    cand <- cand[cand %in% months]
    if (!length(cand)) break
    add <- cand[order(-sh[as.character(cand)], cand)[1]]
    cur <- sort(c(cur, add))
    out[[length(out) + 1]] <- cur
  }
  out
}

fp_acc_months_str <- function(m) if (length(m) == 1) as.character(m) else paste0(min(m), "-", max(m))

# The pre-registered labelling key (#111): the `## Labelling key` section of research/landcover_accuracy.md,
# up to the next `## ` heading. Extracted, never re-typed, so the reviewer reads the committed text and
# nothing else. Refuses a missing or empty section rather than shipping a project with no key.
fp_acc_labelling_key <- function(path = here::here("research", "landcover_accuracy.md")) {
  x <- readLines(path, warn = FALSE)
  i <- which(x == "## Labelling key")
  if (length(i) != 1) stop(path, " has ", length(i), " `## Labelling key` sections; expected one", call. = FALSE)
  nxt <- which(startsWith(x, "## ") & seq_along(x) > i)
  j <- if (length(nxt)) nxt[1] - 1L else length(x)
  out <- x[i:j]
  while (length(out) && !nzchar(trimws(out[length(out)]))) out <- out[-length(out)]
  if (length(out) < 5) stop("the labelling key in ", path, " is empty", call. = FALSE)
  out
}

# --- Blind review (#111) ----------------------------------------------------------------------------
# The reviewer must not see the map's answer: seeing it pulls a label toward agreement and inflates the
# very accuracy #93 measures. Hiding columns is not enough, because point_id ENCODES the stratum
# (`<stratum>_<k>`, drift's naming), so the working copy carries an opaque review_id instead. A
# committed key (reference/<area>/review_key.csv) maps it back to point_id and the design.
#
# The columns the review layer may NEVER carry: the id that encodes the stratum, the design, IO's
# map classes for every year, the cause and wetland flags, and the use tag.
fp_acc_blind_leaks <- function(nm) nm[nm %in% c("point_id", "stratum", "stratum_label", "map_class", "use") |
                                        grepl("^map_[0-9]{4}$|^in_", nm)]

# A seed for one named purpose, derived from the design seed so the review order and the second-labeller
# subset are reproducible from design.json alone. Hashed from a purpose string, drift's idiom
# (digest2int over "<namespace>:<seed>:<code>"): an arithmetic offset let two streams collide (the review
# order's append batch at n0 = 111 equalled the second-labeller seed).
FP_ACC_SEED_PURPOSES <- c("review_order", "second_labeller", "second_labeller_stable")
fp_acc_seed <- function(design_seed, purpose, n0 = 0L) {
  if (!purpose %in% FP_ACC_SEED_PURPOSES) stop("unknown seed purpose ", purpose, call. = FALSE)
  digest::digest2int(sprintf("floodplains-accuracy-review:%s:%s:%d", format(design_seed, scientific = FALSE),
                             purpose, as.integer(n0)))
}
# Draw under the design's own RNG kind, leaving the session's RNG state and kind exactly as found.
# Base R only (no withr: it is not a declared dependency, and m4 or a fresh machine may not have it).
fp_acc_with_seed <- function(seed, rng_kind, expr) {
  g <- globalenv()
  old_kind <- RNGkind()
  had <- exists(".Random.seed", envir = g, inherits = FALSE)
  if (had) old_seed <- get(".Random.seed", envir = g, inherits = FALSE)
  on.exit({
    suppressWarnings(RNGkind(old_kind[1], old_kind[2], old_kind[3]))
    if (had) assign(".Random.seed", old_seed, envir = g)
    else if (exists(".Random.seed", envir = g, inherits = FALSE)) rm(".Random.seed", envir = g)
  }, add = TRUE)
  suppressWarnings(RNGkind(rng_kind[[1]], rng_kind[[2]], rng_kind[[3]]))
  set.seed(seed)
  expr
}

# The key: review_id (a random permutation, which is also the review ORDER) -> point_id and the design
# columns. APPEND-ONLY: given the committed key (`have`), existing ids never change; points new to the
# sample (pilot -> full, same seed) take the next ids, shuffled among themselves with a seed that
# depends on how many were already keyed, so the append is reproducible too.
fp_acc_review_key <- function(smp, design_seed, rng_kind, have = NULL) {
  d <- as.data.frame(smp)[, c("point_id", "cell", "stratum", "map_class")]
  d <- d[order(d$point_id, method = "radix"), , drop = FALSE]
  n0 <- 0L
  if (!is.null(have) && nrow(have)) {
    if (anyDuplicated(have$review_id) || anyDuplicated(have$point_id))
      stop("review_key has duplicate review_id or point_id", call. = FALSE)
    gone <- setdiff(have$point_id, d$point_id)
    if (length(gone)) stop(length(gone), " keyed point(s) are not in sample.gpkg (",
                           paste(utils::head(gone, 3), collapse = ", "), "): the sample was redrawn; ",
                           "a key from another draw would send labels to the wrong cells", call. = FALSE)
    fp_acc_design_check(have, d, "review_key.csv")
    if (!identical(sort(as.integer(have$review_id)), seq_len(nrow(have))))
      stop("review_key.csv ids are not 1..", nrow(have), call. = FALSE)
    n0 <- nrow(have)
  }
  new <- d[!d$point_id %in% (if (n0) have$point_id else character(0)), , drop = FALSE]
  if (nrow(new)) {
    perm <- fp_acc_with_seed(fp_acc_seed(design_seed, "review_order", n0), rng_kind, sample.int(nrow(new)))
    new$review_id <- n0 + perm
  } else new$review_id <- integer(0)
  # `batch` records WHEN a point was keyed: 1 for the first draw, +1 for each growth. It is what lets a
  # working copy made before a growth be told apart from one that lost its last rows (both hold a run of
  # low ids; only the first holds exactly whole batches).
  if (n0 && !"batch" %in% names(have)) have$batch <- 1L
  new$batch <- rep(if (n0) max(have$batch) + 1L else 1L, nrow(new))
  cols <- c("review_id", "point_id", "cell", "stratum", "map_class", "batch")
  if (n0 && "second" %in% names(have)) {
    cols <- c(cols, "second"); new$second <- rep(FALSE, nrow(new))
  }
  out <- rbind(if (n0) have[, cols], new[, cols])
  out$review_id <- as.integer(out$review_id)
  out[order(out$review_id), , drop = FALSE]
}
fp_acc_review_key_read <- function(path) {
  if (!file.exists(path)) return(NULL)
  k <- utils::read.csv(path, colClasses = c(review_id = "integer", point_id = "character", cell = "numeric",
                                            stratum = "integer", map_class = "integer"))
  if ("second" %in% names(k)) k$second <- as.logical(k$second)
  if ("batch" %in% names(k)) k$batch <- as.integer(k$batch)
  k
}

# Working copy -> the frame fp_acc_labels_frame() takes: review_id mapped back to point_id, the design
# columns taken from the KEY (never from the working copy, which does not carry them), and the working
# copy's own `cell` checked against the key so a working copy from another draw is refused here too.
fp_acc_unblind <- function(wc, key) {
  if (is.null(key)) stop("no review_key.csv: the labels cannot be mapped to points", call. = FALSE)
  if (anyDuplicated(wc$review_id)) stop("duplicate review_id in the working copy", call. = FALSE)
  m <- match(wc$review_id, key$review_id)
  if (anyNA(m)) stop(sum(is.na(m)), " review_id(s) not in review_key.csv: ",
                     paste(utils::head(wc$review_id[is.na(m)], 3), collapse = ", "), call. = FALSE)
  bad <- is.na(wc$cell) | as.numeric(wc$cell) != key$cell[m]
  if (any(bad)) stop(sum(bad), " working-copy row(s) whose cell disagrees with review_key.csv (review_id ",
                     paste(utils::head(wc$review_id[bad], 3), collapse = ", "), "): labels from another ",
                     "draw or another key", call. = FALSE)
  wc$point_id  <- key$point_id[m]
  wc$stratum   <- key$stratum[m]
  wc$map_class <- key$map_class[m]
  wc
}

# --- Second labeller (#111) -------------------------------------------------------------------------
# A fixed subset labelled again, blind to the first labeller, so IO's "error" can be separated from
# imagery that is genuinely ambiguous: if two people disagree on a cell, IO disagreeing with either is
# not evidence against IO. n_per points per stratum, drawn once from the design seed's own stream and
# recorded in review_key.csv (`second`). Points added when the sample grows are never added to it.
fp_acc_second_subset <- function(key, design_seed, rng_kind, n_per = 3L) {
  if ("second" %in% names(key) && any(key$second %in% TRUE)) {
    key$second <- key$second %in% TRUE
    return(key)
  }
  k <- key[order(key$point_id, method = "radix"), ]
  pick <- fp_acc_with_seed(fp_acc_seed(design_seed, "second_labeller"), rng_kind, {
    unlist(lapply(sort(unique(k$stratum)), function(st) {
      ids <- k$point_id[k$stratum == st]
      ids[sample.int(length(ids), min(n_per, length(ids)))]
    }))
  })
  key$second <- key$point_id %in% pick
  key
}

# The one growth of the second-labeller subset (#145, pre-registered before any label): n_add more points
# in each STABLE stratum, which hold most of the area and had 3 audit points each, so the audit can see a
# labeller inventing change in stable land. Drawn from its own seed stream among points not already in
# the subset. Idempotent by count: a stable stratum already holding n_per + n_add is left alone, so a
# re-run of the build never draws again.
fp_acc_second_stable <- function(key, design_seed, rng_kind, strata, n_per = 3L, n_add = 9L) {
  if (!"second" %in% names(key)) stop("the key has no second-labeller subset to grow", call. = FALSE)
  key$second <- key$second %in% TRUE
  stable <- sort(strata$stratum[strata$kind == "stable"])
  if (!length(stable)) stop("strata.csv names no stable stratum", call. = FALSE)
  k <- key[order(key$point_id, method = "radix"), ]
  pick <- fp_acc_with_seed(fp_acc_seed(design_seed, "second_labeller_stable"), rng_kind, {
    unlist(lapply(stable, function(st) {
      have <- sum(k$second & k$stratum == st)
      want <- min(n_per + n_add, sum(k$stratum == st)) - have
      ids  <- k$point_id[k$stratum == st & !k$second]
      if (want <= 0 || !length(ids)) character(0) else ids[sample.int(length(ids), min(want, length(ids)))]
    }))
  })
  key$second <- key$second | key$point_id %in% pick
  key
}

# Agreement between the two labellers, by the rules pre-registered in research/landcover_accuracy.md
# ("Second labeller"): class agreement and Cohen's kappa per endpoint over the points BOTH labelled, and
# the cannot_label disagreements counted apart (one labeller could read the cell, the other could not).
# INFORMATION about the reference, never an input to the estimates.
fp_acc_agreement <- function(a, b) {
  both <- merge(a[, c("point_id", "label_status")], b[, c("point_id", "label_status")], by = "point_id")
  cant <- c(both_cannot = sum(both$label_status.x == "cannot_label" & both$label_status.y == "cannot_label"),
            a_only_cannot = sum(both$label_status.x == "cannot_label" & both$label_status.y == "labelled"),
            b_only_cannot = sum(both$label_status.x == "labelled" & both$label_status.y == "cannot_label"))
  m <- merge(a[a$label_status == "labelled", c("point_id", "ref_from", "ref_to")],
             b[b$label_status == "labelled", c("point_id", "ref_from", "ref_to")], by = "point_id")
  kappa <- function(x, y) {
    lv <- sort(unique(c(x, y))); t <- table(factor(x, lv), factor(y, lv)) / length(x)
    po <- sum(diag(t)); pe <- sum(rowSums(t) * colSums(t))
    if (isTRUE(all.equal(pe, 1))) NA_real_ else (po - pe) / (1 - pe)
  }
  # #145: the change call (ref_from != ref_to) is a third row; for a model labeller it gates the estimate
  chg_a <- m$ref_from.x != m$ref_to.x; chg_b <- m$ref_from.y != m$ref_to.y
  out <- data.frame(endpoint = c("first year (ref_from)", "last year (ref_to)", "change (ref_from != ref_to)"),
                    n = nrow(m),
                    agree = c(mean(m$ref_from.x == m$ref_from.y), mean(m$ref_to.x == m$ref_to.y), mean(chg_a == chg_b)),
                    kappa = c(kappa(m$ref_from.x, m$ref_from.y), kappa(m$ref_to.x, m$ref_to.y), kappa(chg_a, chg_b)))
  # 95% intervals, printed and never gating (pre-registered): Wald for agreement, and for kappa the
  # large-sample SE sqrt(po (1 - po) / (n (1 - pe)^2)) from the observed and chance agreement
  pe <- function(x, y) { lv <- sort(unique(c(x, y))); t <- table(factor(x, lv), factor(y, lv)) / length(x)
                         sum(rowSums(t) * colSums(t)) }
  pes <- c(pe(m$ref_from.x, m$ref_from.y), pe(m$ref_to.x, m$ref_to.y), pe(chg_a, chg_b))
  se_a <- sqrt(out$agree * (1 - out$agree) / pmax(out$n, 1))
  se_k <- sqrt(out$agree * (1 - out$agree) / (pmax(out$n, 1) * (1 - pes)^2))
  out$agree_lo <- pmax(0, out$agree - 1.96 * se_a); out$agree_hi <- pmin(1, out$agree + 1.96 * se_a)
  out$kappa_lo <- out$kappa - 1.96 * se_k; out$kappa_hi <- pmin(1, out$kappa + 1.96 * se_k)
  attr(out, "cannot_label") <- cant
  out
}

# The model-labeller gate (#145, research/landcover_accuracy.md "Model labeller"): A's labels feed the
# estimate only if kappa >= FP_ACC_MODEL_KAPPA on both endpoints, change agreement >= FP_ACC_MODEL_CHANGE,
# and A abstained (cannot_label) on at most FP_ACC_MODEL_ABSTAIN of the points B labelled. Point
# estimates; the intervals ride along in `agreement`.
FP_ACC_MODEL_ABSTAIN <- 0.10
# B's labels must be the WHOLE second-labeller subset (labelled or cannot_label): an export taken midway
# through labelling holds only the rows done so far, and agreement on any subset can pass the gate.
fp_acc_b_complete <- function(b, key) {
  want <- key$point_id[key$second %in% TRUE]
  if (!length(want)) stop("review_key.csv names no second-labeller subset", call. = FALSE)
  if (!setequal(b$point_id, want) || anyDuplicated(b$point_id))
    stop("labels_b.csv holds ", length(unique(b$point_id)), " of the ", length(want), " second-labeller points (",
         length(setdiff(want, b$point_id)), " missing, ", length(setdiff(b$point_id, want)), " not in the subset): ",
         "finish labelling and export again", call. = FALSE)
  invisible(TRUE)
}

fp_acc_model_gate <- function(a, b) {
  ag <- fp_acc_agreement(a, b)
  b_lab <- b$point_id[b$label_status == "labelled"]
  abstain <- mean(a$label_status[match(b_lab, a$point_id)] %in% "cannot_label")
  checks <- c(kappa_from = isTRUE(ag$kappa[1] >= FP_ACC_MODEL_KAPPA),
              kappa_to   = isTRUE(ag$kappa[2] >= FP_ACC_MODEL_KAPPA),
              change     = isTRUE(ag$agree[3] >= FP_ACC_MODEL_CHANGE),
              abstain    = length(b_lab) > 0 && abstain <= FP_ACC_MODEL_ABSTAIN)
  list(pass = all(checks), checks = checks, abstain = abstain, agreement = ag)
}

# Agreement per stratum, for the refusal message (never a rule: 3 points per change stratum, see research)
fp_acc_agreement_by_stratum <- function(a, b, smp) {
  m <- merge(a[a$label_status == "labelled", c("point_id", "ref_from", "ref_to")],
             b[b$label_status == "labelled", c("point_id", "ref_from", "ref_to")], by = "point_id")
  m$stratum <- smp$stratum[match(m$point_id, smp$point_id)]
  do.call(rbind, lapply(split(m, m$stratum), function(d) data.frame(
    stratum = d$stratum[1], n = nrow(d), agree_from = mean(d$ref_from.x == d$ref_from.y),
    agree_to = mean(d$ref_to.x == d$ref_to.y),
    agree_change = mean((d$ref_from.x != d$ref_to.x) == (d$ref_from.y != d$ref_to.y)))))
}

# Hard-link every file under `from` into `to` (same filesystem: no extra disk, and the links are real
# files INSIDE `to`, which rfp requires of a project's rasters -- a symlink resolves outside it). A file
# already linked is left alone; a rewritten source (new inode) is relinked.
# `prune`: a regex on the relative path; a file in `to` matching it that `from` no longer holds is
# removed, so a layer a builder retired in A does not live on in B (only what the regex names: B's own
# files are never touched).
fp_acc_link_tree <- function(from, to, prune = NULL) {
  if (!dir.exists(from)) return(invisible(0L))
  f <- list.files(from, recursive = TRUE, all.files = FALSE)
  if (!is.null(prune) && dir.exists(to)) {
    gone <- setdiff(grep(prune, list.files(to, recursive = TRUE), value = TRUE), f)
    if (length(gone)) { unlink(file.path(to, gone)); message("pruned from ", to, ": ", length(gone), " file(s)") }
  }
  n <- 0L
  for (x in f) {
    src <- file.path(from, x); dst <- file.path(to, x)
    dir.create(dirname(dst), recursive = TRUE, showWarnings = FALSE)
    # base file.info() has no inode column (file.info(x)$ino is NULL, so identical() was always TRUE and
    # a rewritten source was never relinked -- #115 round 3): read it from fs
    if (file.exists(dst) && identical(fs::file_info(dst)$inode, fs::file_info(src)$inode)) next
    if (file.exists(dst)) unlink(dst)
    if (!file.link(src, dst)) stop("could not hard-link ", src, " -> ", dst, call. = FALSE)
    n <- n + 1L
  }
  invisible(n)
}

# The blind working-copy rows for `pts` (sample points, sf, in the review CRS): review_id from the key,
# the cell, the dated imagery covering the point, and empty label fields -- nothing of the design. The
# geometry column is `geom`, what a GeoPackage hands back on read, so rows built here append to an
# existing working copy by name (with `geometry` they did not: "undefined columns selected").
fp_acc_blind_points <- function(pts, key, cover) {
  m <- match(pts$point_id, key$point_id)
  if (anyNA(m)) stop(sum(is.na(m)), " point(s) are not in the review key", call. = FALSE)
  x <- sf::st_sf(review_id = key$review_id[m], cell = as.numeric(pts$cell),
                 dated_imagery = unname(cover[pts$point_id]), geom = sf::st_geometry(pts))
  x$ref_from <- NA_integer_; x$ref_to <- NA_integer_
  x$label_status <- NA_character_; x$confidence <- NA_character_; x$imagery <- NA_character_
  x$note <- NA_character_; x$reviewer <- NA_character_; x$labelled_on <- as.Date(NA)
  x[order(x$review_id), ]   # feature order = review order, so the attribute table opens in it
}

# Which labeller a working copy belongs to, from WHAT IT HOLDS rather than from a flag someone has to
# remember: labeller A's copy holds every keyed point, B's exactly the second-labeller subset. Anything
# else is refused, so B's 48 labels can never be exported as the record of 480.
fp_acc_working_copy_role <- function(ids, key) {
  if (setequal(ids, key$review_id)) return("a")
  # A copy made before the sample grew holds exactly the points of batches 1..j (growth appends whole
  # batches) and its labels are valid -- the Mergin working copy is this, since it is never overwritten.
  # A run of low ids that is NOT whole batches is a copy that lost rows, and is refused: exporting it
  # would silently drop labels that were never exported.
  if ("batch" %in% names(key)) {
    for (j in sort(unique(key$batch))) {
      if (j < max(key$batch) && setequal(ids, key$review_id[key$batch <= j])) return("a")
    }
  }
  if ("second" %in% names(key) && any(key$second %in% TRUE) && setequal(ids, key$review_id[key$second %in% TRUE]))
    return("b")
  stop("the working copy holds ", length(unique(ids)), " point(s): neither the whole keyed sample (",
       nrow(key), ") nor the second-labeller subset (", sum(key$second %in% TRUE), ")", call. = FALSE)
}

# --- Model labeller (#145) --------------------------------------------------------------------------
# A blind model agent labels every point from one PNG contact sheet per point (review_render-sheets.R);
# a person labels the second-labeller subset; agreement gates the estimate. Pre-registered in
# research/landcover_accuracy.md, "Model labeller", before any label existed -- these constants are
# that text and move only with it.
FP_ACC_MODEL_KAPPA  <- 0.7    # Cohen's kappa on ref_from AND on ref_to
FP_ACC_MODEL_CHANGE <- 0.85   # agreement on change vs no change (ref_from != ref_to)
FP_ACC_MODEL_PREFIX <- "model:"

# The shipped name of a sheet. A plain counter over a fresh shuffle: never the review_id, which is
# drawn in review order and so would carry the batch hint (#113), and never anything of the design.
fp_acc_sheet_name <- function(k) sprintf("sheet_%03d.png", as.integer(k))
FP_ACC_SHEET_RE <- "^sheet_[0-9]{3}[.]png$"

# review_ids -> data.frame(sheet, review_id, batch): a shuffle drawn from `seed`, cut into batches of
# n_batch sheets in shuffled order. The map stays outside the batch directories.
fp_acc_sheet_plan <- function(review_ids, n_batch = 40L, seed) {
  if (anyDuplicated(review_ids)) stop("duplicate review_id handed to the sheet plan", call. = FALSE)
  o <- fp_acc_with_seed(seed, c("Mersenne-Twister", "Inversion", "Rejection"), sample.int(length(review_ids)))
  k <- seq_along(review_ids)
  data.frame(sheet = fp_acc_sheet_name(k), review_id = as.integer(review_ids[o]),
             batch = as.integer((k - 1L) %/% n_batch + 1L), stringsAsFactors = FALSE)
}

# A panel title may say what the image is and when it was taken, and nothing else: a fixed vocabulary
# of sources, dates, months and resolutions. Anything outside it is refused before it is drawn.
fp_acc_sheet_title_ok <- function(x) grepl(paste0(
  "^(Sentinel-2 [0-9]{4} (Aug|Aug-Sep) composite, 10 m|",
  "Esri Wayback captured [0-9]{4}-[0-9]{2}-[0-9]{2}, [0-9.]+ m|Esri Wayback: no capture|",
  "Orthophoto [0-9]{4}|Air photo [0-9]{4}|",
  "Label the outlined 10 m cell in 2017 and in 2023)$"), x)

# PNG text chunks (tEXt, zTXt, iTXt) in a file: a sheet carries none, so nothing rides in metadata.
fp_acc_png_text_chunks <- function(path) {
  b <- readBin(path, "raw", file.size(path))
  if (!identical(b[1:8], as.raw(c(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a))))
    stop(path, " is not a PNG", call. = FALSE)
  i <- 9L; out <- character(0)
  while (i + 7L <= length(b)) {
    len  <- sum(as.numeric(b[i:(i + 3L)]) * 256^(3:0))
    type <- rawToChar(b[(i + 4L):(i + 7L)])
    if (type %in% c("tEXt", "zTXt", "iTXt")) out <- c(out, type)
    if (type == "IEND") break
    i <- i + 12L + as.integer(len)
  }
  out
}

# What an agent is handed: batch_<NN>/ holding sheets only, and key.md beside them. Refuses any other
# file, any sheet name outside the counter, and any PNG carrying text.
fp_acc_sheet_dir_check <- function(dir_model) {
  b <- list.dirs(dir_model, recursive = FALSE)
  b <- b[grepl("^batch_[0-9]{2}$", basename(b))]
  if (!length(b)) stop("no batch_<NN> directory under ", dir_model, call. = FALSE)
  for (d in b) {
    f <- list.files(d, all.files = TRUE, no.. = TRUE)
    bad <- f[!grepl(FP_ACC_SHEET_RE, f)]
    if (length(bad)) stop(d, " holds file(s) other than sheets: ", paste(utils::head(bad, 3), collapse = ", "),
                          call. = FALSE)
    for (x in f) {
      t <- fp_acc_png_text_chunks(file.path(d, x))
      if (length(t)) stop(file.path(d, x), " carries PNG text chunk(s) ", paste(t, collapse = ", "), call. = FALSE)
    }
  }
  invisible(length(b))
}

# The CSV block of a model batch reply -> a character data.frame. The LAST ```csv fence in the reply:
# a reply quoting the contract before answering must not be read as the answer.
FP_ACC_MODEL_COLS <- c("sheet", "ref_from", "ref_to", "label_status", "confidence", "imagery", "note")
fp_acc_model_csv <- function(reply) {
  x <- strsplit(reply, "\n", fixed = TRUE)[[1]]
  open <- which(trimws(x) == "```csv"); close <- which(trimws(x) == "```")
  if (!length(open)) stop("the reply holds no ```csv block", call. = FALSE)
  i <- max(open); j <- close[close > i][1]
  if (is.na(j)) stop("the reply's ```csv block is not closed", call. = FALSE)
  d <- utils::read.csv(text = paste(x[(i + 1L):(j - 1L)], collapse = "\n"), colClasses = "character",
                       na.strings = "", strip.white = TRUE)
  if (!identical(names(d), FP_ACC_MODEL_COLS))
    stop("the reply's columns are ", paste(names(d), collapse = ","), ", not ",
         paste(FP_ACC_MODEL_COLS, collapse = ","), call. = FALSE)
  d
}

# An agent's tool calls (data.frame: name, path) against what it may touch: Read of its own batch's
# sheets and of the key. Returns the violations; any one discards the batch.
fp_acc_transcript_audit <- function(calls, batch_dir, key_path) {
  ok_path <- function(p) !is.na(p) & (normalizePath(p, mustWork = FALSE) == normalizePath(key_path, mustWork = FALSE) |
    (dirname(normalizePath(p, mustWork = FALSE)) == normalizePath(batch_dir, mustWork = FALSE) &
       grepl(FP_ACC_SHEET_RE, basename(p))))
  calls[!(calls$name == "Read" & ok_path(calls$path)), , drop = FALSE]
}

# What the agent did NOT read: the key, and each sheet of its batch. A reply can label a sheet the agent
# never opened (it skipped it, or ran out of context), and the audit above only sees reads it should not
# have made, never reads it failed to make.
# A Read counts only when its tool_result came back without an error (`calls$ok`, from extract): a Read
# that failed showed the agent nothing, so a label for that sheet was made blind of it.
fp_acc_unread <- function(calls, batch_dir, key_path, want) {
  if (!"ok" %in% names(calls)) stop("calls carry no `ok` column: match each Read to its tool_result first", call. = FALSE)
  rd <- calls$path[calls$name == "Read" & !is.na(calls$path) & calls$ok %in% TRUE]
  rd <- normalizePath(rd, mustWork = FALSE)
  in_batch <- basename(rd)[dirname(rd) == normalizePath(batch_dir, mustWork = FALSE)]
  c(if (!normalizePath(key_path, mustWork = FALSE) %in% rd) "key.md", setdiff(want, in_batch))
}

# All batches' rows + the frozen sheet map -> the working-copy frame labels_export uses (review_id, cell,
# label fields). Every sheet exactly once, no sheet the map does not hold.
fp_acc_model_wc <- function(rows, sheet_map, reviewer, labelled_on) {
  dup <- rows$sheet[duplicated(rows$sheet)]
  if (length(dup)) stop(length(dup), " sheet(s) labelled more than once: ", paste(utils::head(dup, 3), collapse = ", "),
                        call. = FALSE)
  unk <- setdiff(rows$sheet, sheet_map$sheet)
  if (length(unk)) stop(length(unk), " labelled sheet(s) not in sheet_map.csv: ", paste(utils::head(unk, 3), collapse = ", "),
                        call. = FALSE)
  miss <- setdiff(sheet_map$sheet, rows$sheet)
  if (length(miss)) stop(length(miss), " sheet(s) have no label: ", paste(utils::head(miss, 3), collapse = ", "),
                         call. = FALSE)
  if (!startsWith(reviewer, FP_ACC_MODEL_PREFIX)) stop("a model reviewer reads ", FP_ACC_MODEL_PREFIX, "<id>", call. = FALSE)
  m <- match(rows$sheet, sheet_map$sheet)
  # as.integer("2.5") is 2 with no warning, so a fractional code would pass as a valid class: read as a
  # number and refuse anything that is not a whole one
  num <- function(v) { v <- trimws(v); x <- suppressWarnings(as.numeric(v)); x[is.na(v) | !nzchar(v)] <- NA
                       x[!is.na(x) & x != round(x)] <- NaN; out <- as.integer(x); out[is.nan(x)] <- NA; out }
  bad <- !is.na(rows$ref_from) & is.na(num(rows$ref_from)) | !is.na(rows$ref_to) & is.na(num(rows$ref_to))
  if (any(bad)) stop(sum(bad), " row(s) with a class that is not an integer code: ",
                     paste(utils::head(rows$sheet[bad], 3), collapse = ", "), call. = FALSE)
  data.frame(review_id = as.integer(sheet_map$review_id[m]), cell = as.numeric(sheet_map$cell[m]),
             ref_from = num(rows$ref_from), ref_to = num(rows$ref_to), label_status = rows$label_status,
             confidence = rows$confidence, imagery = rows$imagery, note = rows$note,
             reviewer = reviewer, labelled_on = labelled_on, stringsAsFactors = FALSE)
}

# Freeze a fact by hash: write `<sha>  <name>` when the file is absent, pass when it already holds this sha,
# and refuse when it holds another. A freeze that a re-run can overwrite freezes nothing (#145 code-check).
fp_acc_freeze <- function(path, sha, name) {
  if (file.exists(path)) {
    have <- strsplit(readLines(path, n = 1), "  ", fixed = TRUE)[[1]][1]
    if (!identical(have, sha)) stop(path, " already freezes ", name, " at ", substr(have, 1, 12), "; it now reads ",
                                    substr(sha, 1, 12), ". Refusing to re-freeze an edited file.", call. = FALSE)
    return(invisible(FALSE))
  }
  writeLines(sprintf("%s  %s", sha, name), path)
  invisible(TRUE)
}

# Is the image a Read returned (a transcript's `source`: media_type + base64) the sheet on disk? It binds a
# label to the picture the agent saw, not to a file name every render reuses. The Read tool passes a small
# PNG through byte for byte and re-encodes a large one to JPEG, so: identical bytes, or the same size with a
# mean absolute RGB difference within `tol`. Measured on NECR batch 1: a re-encoded sheet sits 0.0031-0.0040
# from its own PNG and 0.038-0.139 from any other sheet, so 0.01 separates them about tenfold.
FP_ACC_IMAGE_TOL <- 0.01
fp_acc_b64_sha256 <- function(b64) digest::digest(jsonlite::base64_dec(b64), algo = "sha256", serialize = FALSE)
fp_acc_image_matches <- function(src, png_path, tol = FP_ACC_IMAGE_TOL) {
  if (is.null(src$data) || is.null(src$media_type)) return(FALSE)
  raw <- jsonlite::base64_dec(src$data)
  if (identical(digest::digest(raw, algo = "sha256", serialize = FALSE), digest::digest(file = png_path, algo = "sha256")))
    return(TRUE)
  seen <- switch(src$media_type, "image/png" = png::readPNG(raw), "image/jpeg" = jpeg::readJPEG(raw), NULL)
  disk <- png::readPNG(png_path)
  if (is.null(seen) || length(dim(seen)) != 3 || !identical(dim(seen)[1:2], dim(disk)[1:2])) return(FALSE)
  mean(abs(seen[, , 1:3] - disk[, , 1:3])) <= tol
}

# --- Model-labeller guards as functions (#145 code-check round 4) ------------------------------------------
# Each refusal the scripts rely on lives here, so accuracy-check.R can exercise it and go red when it is removed.

# the sha in a `<sha>  <name>` file
fp_acc_sha_file <- function(path) strsplit(readLines(path, n = 1, warn = FALSE), "  ", fixed = TRUE)[[1]][1]

# git, from R, on one repository; NULL output on failure
fp_acc_git <- function(repo, ..., status = FALSE) {
  if (status) return(system2("git", c("-C", shQuote(repo), ...), stdout = FALSE, stderr = FALSE) == 0)
  suppressWarnings(system2("git", c("-C", shQuote(repo), ...), stdout = TRUE, stderr = FALSE))
}
# Tracked and identical to HEAD: what a freeze or a hash must be before anything relies on it. A file that
# is merely on disk can be deleted by a clean or missing on another checkout, and then reads as "never set".
fp_acc_git_committed <- function(repo, path)
  fp_acc_git(repo, "ls-files", "--error-unmatch", shQuote(path), status = TRUE) &&
  fp_acc_git(repo, "diff", "--quiet", "HEAD", "--", shQuote(path), status = TRUE)
# The last commit touching `first` is a strict ancestor of the commit that first added `then`.
fp_acc_git_committed_before <- function(repo, first, then) {
  c1 <- fp_acc_git(repo, "log", "-1", "--format=%H", "--", shQuote(first))
  c2 <- utils::tail(fp_acc_git(repo, "log", "--diff-filter=A", "--format=%H", "--", shQuote(then)), 1)
  length(c1) == 1 && length(c2) == 1 && c1 != c2 &&
    fp_acc_git(repo, "merge-base", "--is-ancestor", c1, c2, status = TRUE)
}

# labels.csv must be the model's labels as hashed, wherever a committed model hash exists. TRUE when the
# labels are the model's (so the gate applies), FALSE when there is no model hash at all.
fp_acc_labels_hashed <- function(labels_csv, sha_file) {
  if (!file.exists(sha_file)) return(FALSE)
  if (!identical(digest::digest(file = labels_csv, algo = "sha256"), fp_acc_sha_file(sha_file)))
    stop(labels_csv, " is not the model's labels as hashed in ", basename(sha_file), call. = FALSE)
  TRUE
}
# Every commit, on any local branch, that ever touched `path`.
# A stash's index commit is not history anyone committed, so stashes are excluded (`--exclude` must precede
# `--all`): staging the freeze, stashing and applying it would otherwise count it twice.
fp_acc_git_commits <- function(repo, path)
  fp_acc_git(repo, "log", "--exclude=refs/stash", "--all", "--format=%H", "--", shQuote(path))
fp_acc_git_commit_refs <- function(repo, path)
  paste(fp_acc_git(repo, "log", "--exclude=refs/stash", "--all", "--format=%h%d", "--", shQuote(path)), collapse = "; ")

# B as frozen, decided by HISTORY, never by what is on disk (rounds 3-5 each defeated a disk-based freeze: a
# re-run rewrote it, its absence read as "not frozen yet", a clean made a re-run look like a first one):
#   - the freeze is committed, and exactly ONE commit has ever touched its path, so it was never re-frozen;
#   - it matches labels_b.csv as it stands;
#   - when labels.csv is given, that one commit is an ancestor of the commit that first added labels.csv,
#     so B was fixed in history before the model's labels were in the tree to be seen.
# Out of reach of any local check, and stated as such in research/landcover_accuracy.md: history rewritten
# on purpose, and a freeze made on another machine and never pushed.
fp_acc_b_frozen <- function(repo, labels_b, freeze, labels_csv = NULL) {
  if (!file.exists(freeze) || !fp_acc_git_committed(repo, freeze))
    stop(freeze, " is missing or not committed: B's labels are not frozen", call. = FALSE)
  n <- length(fp_acc_git_commits(repo, freeze))
  if (n != 1) stop(freeze, " has been committed ", n, " times (", fp_acc_git_commit_refs(repo, freeze), "). Either B was ",
                   "re-frozen, so the freeze proves nothing, or the branch was squash-merged while the original still ",
                   "exists: this work merges with a merge commit, never a squash.", call. = FALSE)
  if (!identical(digest::digest(file = labels_b, algo = "sha256"), fp_acc_sha_file(freeze)))
    stop(labels_b, " is not the one frozen when the model's labels were published", call. = FALSE)
  if (!is.null(labels_csv) && !fp_acc_git_committed_before(repo, freeze, labels_csv))
    stop(basename(freeze), " was not committed before labels.csv was", call. = FALSE)
  invisible(TRUE)
}
# The model's labels as published, decided by history like B's freeze: the hash committed and last touched
# before B's labels were first added, and labels.csv committed exactly once (a re-import with FORCE=1 and a
# hand copy, committed later, would otherwise pass: the estimate compared labels.csv with the hash on disk).
fp_acc_model_published <- function(repo, sha_file, labels_b, labels_csv) {
  if (!fp_acc_git_committed(repo, sha_file)) stop(sha_file, " is not committed as it stands", call. = FALSE)
  if (!fp_acc_git_committed_before(repo, sha_file, labels_b))
    stop(basename(sha_file), "'s last commit does not precede the commit that added ", basename(labels_b), call. = FALSE)
  n <- length(fp_acc_git_commits(repo, labels_csv))
  if (n != 1) stop(labels_csv, " has been committed ", n, " times (", fp_acc_git_commit_refs(repo, labels_csv),
                   "): the model's labels were published once", call. = FALSE)
  invisible(TRUE)
}
# A path history has never seen, on any branch: what makes a freeze or a publish a FIRST one.
fp_acc_git_never <- function(repo, paths) {
  seen <- paths[vapply(paths, function(p) length(fp_acc_git_commits(repo, p)) > 0, TRUE)]
  if (length(seen)) stop(paste(basename(seen), collapse = " and "), " already in history: not a first freeze or publish",
                         call. = FALSE)
  invisible(TRUE)
}

# An extracted batch against its audit: the csv as written, the key it was read under, the sheets it saw.
fp_acc_batch_verify <- function(audit, csv, key_md, batch_dir) {
  sha <- function(f) digest::digest(file = f, algo = "sha256")
  if (is.null(audit$csv_sha256) || !identical(sha(csv), audit$csv_sha256))
    stop(csv, " is not the csv its audit recorded: extract it again", call. = FALSE)
  if (!identical(audit$key_sha256, sha(key_md))) stop("batch ", audit$batch, " was read under another key.md", call. = FALSE)
  now <- vapply(names(audit$sheet_sha256), function(s) sha(file.path(batch_dir, s)), "")
  if (!identical(unname(now), unname(unlist(audit$sheet_sha256))))
    stop("batch ", audit$batch, "'s sheets on disk are not the ones it labelled: the render moved under it", call. = FALSE)
  invisible(TRUE)
}
# The key text a Read returned (`N<TAB>line` per line) -> the lines the agent read, for comparison with
# fp_acc_labelling_key(): the transcript says what the agent saw, key.md only what is on disk now.
fp_acc_read_text <- function(txt) {
  x <- strsplit(txt, "\n", fixed = FALSE)[[1]]
  x <- sub("^[0-9]+\t", "", x)
  while (length(x) && !nzchar(x[length(x)])) x <- x[-length(x)]
  x
}
