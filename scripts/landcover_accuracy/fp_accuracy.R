# fp_accuracy.R — helpers for measuring IO LULC accuracy inside a floodplain (#93).
#
# The sampler and estimators are drift's (dft_accuracy_*, drift#81). This file only resolves
# the area and builds what drift is handed. It must stay free of side effects when sourced:
# run_area.R cannot be sourced for fp_read_config() because it dispatches the pipeline at top
# level, so the minimum of area.yml this module needs is read here.

`%||%` <- function(a, b) if (is.null(a)) b else a

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
fp_acc_rasterize <- function(polys, template) {
  if (!nrow(polys)) return(terra::init(terra::rast(template), NA))
  polys <- sf::st_transform(polys, terra::crs(template))
  terra::rasterize(terra::vect(sf::st_geometry(polys)), terra::rast(template), field = 1L,
                   touches = FALSE, background = NA)
}

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

# The strata table for a given ordered set of cause names: causes 1..k, then the fixed strata.
fp_acc_strata_table <- function(causes) {
  rbind(data.frame(stratum = seq_along(causes), label = paste0("change: ", causes), kind = "change"),
        FP_ACC_STRATA_FIXED)
}

# from, to:  IO classified endpoints (raw codes). trans: published transition (NA = outside or sieved).
# causes:    NAMED list of 1/NA rasters, in precedence order (published patch flags, rasterised).
# wet:       1/NA raster of FWA wetland cells.
# Returns list(strata = factor SpatRaster, reported = the published map claim per cell, table).
fp_acc_strata <- function(from, to, trans, causes, wet) {
  if (is.null(names(causes)) || any(!nzchar(names(causes))))
    stop("`causes` must be a named list in precedence order", call. = FALSE)
  tb   <- fp_acc_strata_table(names(causes))
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
FP_ACC_IMAGERY    <- c("s2_composite", "esri", "google", "bing", "several")

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
