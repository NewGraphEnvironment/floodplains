# fp_accuracy.R — helpers for measuring IO LULC accuracy inside a floodplain (#93).
#
# The sampler and estimators are drift's (dft_accuracy_*, drift#81). This file only resolves
# the area and builds what drift is handed. It must stay free of side effects when sourced:
# run_area.R cannot be sourced for fp_read_config() because it dispatches the pipeline at top
# level, so the minimum of area.yml this module needs is read here.

`%||%` <- function(a, b) if (is.null(a)) b else a
source(here::here("scripts", "fp_raster.R"))   # fp_rast_cells; defines functions only

# area name -> the few facts the accuracy scripts need, with the same defaults run_area.R applies
fp_acc_area <- function(area) {
  cfg_dir <- here::here("config", area)
  if (!dir.exists(cfg_dir)) stop("no config for area '", area, "' at ", cfg_dir, call. = FALSE)
  cfg <- yaml::read_yaml(file.path(cfg_dir, "area.yml"))
  cfg$area             <- area
  cfg$dir_out          <- here::here("data", area)
  cfg$primary_scenario <- cfg$primary_scenario %||% paste0(cfg$species, "_ff04")
  cfg$change_interval  <- cfg$change_interval %||% c(2017L, 2023L)
  cfg$dir_rast         <- file.path(cfg$dir_out, "rasters", cfg$primary_scenario)
  cfg$dir_acc          <- file.path(cfg$dir_out, "accuracy")
  cfg$dir_ref          <- here::here("reference", area)
  cfg
}

# "EPSG:<code>" of a raster, for handing a grid's CRS to drift
fp_acc_epsg <- function(path) {
  code <- terra::crs(terra::rast(path), describe = TRUE)$code
  if (is.na(code) || !nzchar(code)) stop("no EPSG code for ", path, call. = FALSE)
  paste0("EPSG:", code)
}

FP_ACC_TREES <- 2L   # IO LULC class code for Trees

# The classified series + transition for an area's primary scenario, on one grid, checked.
# The transition is what step 3 published (1 ha sieve applied); the classified rasters are IO's own
# labels. Both are read from disk, and they must agree: a partial re-run of step 3 can rewrite one
# without the other, and every stratum and omission number assumes they describe the same map.
fp_acc_grid <- function(cfg, years = NULL) {
  yrs  <- years %||% seq(cfg$change_interval[1], cfg$change_interval[2])
  cls  <- lapply(yrs, function(y) terra::rast(file.path(cfg$dir_rast, sprintf("classified_%d.tif", y))))
  names(cls) <- yrs
  tr   <- terra::rast(file.path(cfg$dir_rast, "transition.tif"))
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
# is in reference/<area>/imagery.csv. labels_form.qml's value map must list exactly these.
FP_ACC_IMAGERY    <- c("s2_composite", "orthophoto", "airphoto", "esri", "google", "bing", "several")

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
FP_ACC_SEED_PURPOSES <- c("review_order", "second_labeller")
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
  cols <- c("review_id", "point_id", "cell", "stratum", "map_class")
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

# Agreement between the two labellers on the points both labelled, per endpoint: share agreeing and
# Cohen's kappa. INFORMATION about the reference, never an input to the estimates.
fp_acc_agreement <- function(a, b) {
  m <- merge(a[a$label_status == "labelled", c("point_id", "ref_from", "ref_to")],
             b[b$label_status == "labelled", c("point_id", "ref_from", "ref_to")], by = "point_id")
  kappa <- function(x, y) {
    lv <- sort(unique(c(x, y))); t <- table(factor(x, lv), factor(y, lv)) / length(x)
    po <- sum(diag(t)); pe <- sum(rowSums(t) * colSums(t))
    if (isTRUE(all.equal(pe, 1))) NA_real_ else (po - pe) / (1 - pe)
  }
  data.frame(endpoint = c("first year (ref_from)", "last year (ref_to)"), n = nrow(m),
             agree = c(mean(m$ref_from.x == m$ref_from.y), mean(m$ref_to.x == m$ref_to.y)),
             kappa = c(kappa(m$ref_from.x, m$ref_from.y), kappa(m$ref_to.x, m$ref_to.y)))
}

# Hard-link every file under `from` into `to` (same filesystem: no extra disk, and the links are real
# files INSIDE `to`, which rfp requires of a project's rasters -- a symlink resolves outside it). A file
# already linked is left alone; a rewritten source (new inode) is relinked.
fp_acc_link_tree <- function(from, to) {
  if (!dir.exists(from)) return(invisible(0L))
  f <- list.files(from, recursive = TRUE, all.files = FALSE)
  n <- 0L
  for (x in f) {
    src <- file.path(from, x); dst <- file.path(to, x)
    dir.create(dirname(dst), recursive = TRUE, showWarnings = FALSE)
    if (file.exists(dst) && identical(file.info(dst)$ino, file.info(src)$ino)) next
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
  if ("second" %in% names(key) && any(key$second %in% TRUE) && setequal(ids, key$review_id[key$second %in% TRUE]))
    return("b")
  stop("the working copy holds ", length(unique(ids)), " point(s): neither the whole keyed sample (",
       nrow(key), ") nor the second-labeller subset (", sum(key$second %in% TRUE), ")", call. = FALSE)
}
