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
