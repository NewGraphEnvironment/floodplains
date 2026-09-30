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
  bad <- terra::global(!is.na(tr) & (tr != expect), "sum", na.rm = TRUE)[[1]]
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
