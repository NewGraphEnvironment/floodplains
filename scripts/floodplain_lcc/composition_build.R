# composition_build.R — write an area's composition table from the rasters step 3 already wrote (#108).
#
# The backfill path for areas whose step 3 predates the composition table: the same
# fp_composition_build() step 3 now calls at its end, run on rasters/<scenario>/ with no ~30 min
# STAC fetch. Writes `composition_<scenario>_<from>_<to>` into floodplain_landcover.gpkg and the
# `composition` sibling of landcover[<scenario>] in provenance.json, which it refuses to do for a
# scenario step 3 has not recorded (the sibling describes rasters that entry vouches for).
#
# The item keys come from the scenario's transition layer when there is one -- what is already
# published for that scenario -- so a second species in the same area (morr ch_ff06) is keyed as
# its own rows were, not as area.yml's default species.
#
# Standalone CLI: does not source packages.R, so it pins the gpkg date itself (#45). Then run
# composition-check.R <area> [scenario].
#
# usage: Rscript scripts/floodplain_lcc/composition_build.R <area> [scenario]

suppressMessages({library(sf); library(terra); library(DBI); library(RPostgres); library(yaml)})
sf::sf_use_s2(FALSE)
lcc <- here::here("scripts", "floodplain_lcc")
source(here::here("scripts", "fp_gpkg.R"))
source(here::here("scripts", "fp_raster.R"))
source(file.path(lcc, "fp_provenance.R"))
source(file.path(lcc, "fp_disturbance.R"))
source(file.path(lcc, "fp_composition.R"))
fp_gpkg_pin_date()

a <- commandArgs(TRUE)
if (is.na(a[1])) stop("usage: composition_build.R <area> [scenario]", call. = FALSE)
area <- a[1]
if (!grepl("^[a-z0-9_]+$", area)) stop("area must be a config directory name, got: ", area, call. = FALSE)
cfg_dir <- here::here("config", area)
if (!dir.exists(cfg_dir)) stop("no config for area '", area, "' at ", cfg_dir, call. = FALSE)

cfg <- yaml::read_yaml(file.path(cfg_dir, "area.yml"))
cfg$area            <- area
cfg$dir_out         <- here::here("data", area)
cfg$change_interval <- cfg$change_interval %||% c(2017L, 2023L)
scen <- if (!is.na(a[2])) a[2] else cfg$primary_scenario %||% paste0(cfg$species, "_ff04")
if (!grepl("^[a-z0-9_]+$", scen)) stop("scenario must be a scenario id such as co_ff04, got: ", scen, call. = FALSE)
dst <- fp_disturbance_validate(yaml::read_yaml(here::here("config", "disturbance.yml")))
cfg$context_overlays <- dst[["context"]]

yrs  <- sort(cfg$change_interval)
gpkg <- file.path(cfg$dir_out, "floodplain_landcover.gpkg")
tlyr <- sprintf("transition_%s_%d_%d", scen, as.integer(yrs[1]), as.integer(yrs[2]))
if (file.exists(gpkg) && tlyr %in% sf::st_layers(gpkg)$name) {
  k <- sf::st_read(gpkg, query = sprintf('SELECT DISTINCT wsg, species FROM "%s"', tlyr), quiet = TRUE)
  if (inherits(k, "sf")) k <- sf::st_drop_geometry(k)
  if (nrow(k) != 1) stop(tlyr, " carries ", nrow(k), " (wsg, species) pairs; expected one", call. = FALSE)
  cfg$watershed_group <- k$wsg; cfg$species <- k$species
} else {
  # No transition layer (a zero-change run, or a step 3 that died before vectorising): the species
  # is the scenario's own prefix, never area.yml's default -- `morr ch_ff06` must not be keyed `co`.
  cfg$species <- sub("_.*$", "", scen)
}

message(sprintf("composition: area=%s scenario=%s wsg=%s species=%s context=%s", area, scen,
                cfg$watershed_group, cfg$species,
                paste(vapply(cfg$context_overlays, function(s) s$name, character(1)), collapse = ",")))
fp_composition_build(cfg, scen)
