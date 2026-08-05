# gpkg_backfill-wsg.R — one-time migration for #30.
# Backfill the item key (wsg, species, scenario) into the published gpkg layers of areas that were
# generated before the pipeline wrote them. New runs carry the keys natively (02/03), so this is
# only for pre-existing outputs; it is idempotent, so re-running is harmless.
#
# Keys mirror the STAC item id (<wsg>_<species>_<scenario>) so a merged multi-area gpkg stays
# separable by attribute. Layer names are left exactly as they are.
#
#   floodplain.gpkg            layer = <scenario>                    (e.g. co_ff04)
#   floodplain_landcover.gpkg  layer = classified_<scenario>_<year>  |  transition_<scenario>_<span>
#
# usage: Rscript scripts/floodplain_lcc/gpkg_backfill-wsg.R <area>

suppressMessages({library(sf); library(yaml)})
sf::sf_use_s2(FALSE)

area <- commandArgs(TRUE)[1]
if (is.na(area)) stop("usage: Rscript gpkg_backfill-wsg.R <area>")

cfg_path <- here::here("config", area, "area.yml")
if (!file.exists(cfg_path)) stop("no config for area '", area, "': ", cfg_path)
cfg <- yaml::read_yaml(cfg_path)
wsg <- cfg$watershed_group
if (is.null(wsg) || !nzchar(wsg)) stop("area.yml has no watershed_group: ", cfg_path)

# scenario id is embedded in every layer name; species is its prefix (co_ff04 -> co).
# classified_<scenario>_<year> / transition_<scenario>_<from>_<to> / <scenario>
scenario_of <- function(lyr) {
  # EXTRACT the scenario rather than strip suffixes off the end. A scenario id is always
  # <species>_ff<NN>, so one rule covers every suffix a layer name can carry — year, transition
  # span, _disturbance, _fire, _patches, and anything added later. Stripping suffixes instead
  # means enumerating them, and any unlisted one silently yields a bogus scenario value.
  s <- sub("^classified_", "", sub("^transition_", "", lyr))
  m <- regmatches(s, regexpr("^[a-z]{2,4}_ff[0-9]+", s))
  if (length(m)) m else s
}

for (g in c("floodplain.gpkg", "floodplain_landcover.gpkg")) {
  path <- here::here("data", area, g)
  if (!file.exists(path)) { message("  skip (absent): ", g); next }

  for (lyr in sf::st_layers(path)$name) {
    x <- sf::st_read(path, layer = lyr, quiet = TRUE)
    scenario <- scenario_of(lyr)
    # Idempotent by VALUE, not by presence: always recompute and overwrite, so a re-run repairs a
    # layer that was keyed with a wrong value rather than skipping it.
    keyed <- all(c("wsg", "species", "scenario") %in% names(x)) &&
      identical(unique(x$wsg), wsg) && identical(unique(x$scenario), scenario)
    if (keyed) { message(sprintf("  %-42s already keyed", lyr)); next }

    species  <- sub("_.*$", "", scenario)
    n0 <- nrow(x)
    x$wsg      <- wsg
    x$species  <- species
    x$scenario <- scenario
    sf::st_write(x, path, layer = lyr, delete_layer = TRUE, quiet = TRUE)

    chk <- sf::st_read(path, layer = lyr, quiet = TRUE)
    if (nrow(chk) != n0) stop("FEATURE COUNT CHANGED for ", lyr, ": ", n0, " -> ", nrow(chk))
    message(sprintf("  %-42s + wsg=%s species=%s scenario=%s (%d features)",
                    lyr, wsg, species, scenario, nrow(chk)))
  }
}
message("Done: ", area)
