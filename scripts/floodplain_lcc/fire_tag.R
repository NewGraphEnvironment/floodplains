# fire_tag.R — thin CLI wrapper over fp_disturbance_tag (#19).
# Re-tag an already-produced transition layer with the configured disturbance sources
# (config/disturbance.yml) WITHOUT re-running step 3's ~30-min STAC fetch. Writes a
# `transition_<scenario>_2017_2023_disturbance` layer (original transition layer untouched) and
# reports the Trees->non-Trees loss split by source + residual. Also the parity harness for #19:
# with fire the only configured source it must reproduce the fire_tag numbers
# (BULK 103.2 ha, MORR co 27.1, MORR ch 29.4).
#
# usage: Rscript scripts/floodplain_lcc/fire_tag.R <area> [scenario]

suppressMessages({library(sf); library(DBI); library(RPostgres); library(yaml)})
sf::sf_use_s2(FALSE)
source(here::here("scripts", "floodplain_lcc", "fp_disturbance.R"))
source(here::here("scripts", "fp_gpkg.R"))       # standalone CLI: not covered by run_area.R
fp_gpkg_pin_date()                                # #45

a     <- commandArgs(TRUE)
area  <- a[1]
if (is.na(area)) stop("usage: Rscript fire_tag.R <area> [scenario]")

gpkg <- here::here("data", area, "floodplain_landcover.gpkg")
if (!file.exists(gpkg)) stop("no gpkg: ", gpkg)

lyrs <- sf::st_layers(gpkg)$name
tlyr <- if (!is.na(a[2])) {
  grep(sprintf("^transition_%s_.*[0-9]$", a[2]), lyrs, value = TRUE)[1]  # [0-9]$ excludes *_disturbance
} else {
  grep("^transition_.*[0-9]$", lyrs, value = TRUE)[1]   # exclude any *_disturbance layer
}
if (is.na(tlyr)) stop("no transition_ layer in ", gpkg)

sources <- yaml::read_yaml(here::here("config", "disturbance.yml"))$sources
cat(sprintf("area=%s  layer=%s  sources=%s\n", area, tlyr,
            paste(vapply(sources, function(s) s$name, character(1)), collapse = ",")))

tr   <- sf::st_read(gpkg, layer = tlyr, quiet = TRUE)
conn <- dbConnect(Postgres()); on.exit(dbDisconnect(conn), add = TRUE)

tagged  <- fp_disturbance_tag(tr, sources, conn, window = c(2017, 2023))
out_lyr <- paste0(tlyr, "_disturbance")
sf::st_write(tagged, gpkg, layer = out_lyr, delete_layer = TRUE, quiet = TRUE)
cat(sprintf("wrote layer: %s (%d patches)\n", out_lyr, nrow(tagged)))

fp_disturbance_report(tagged, sources, area)
