# reference_composition-wetland.R — what IO calls a mapped wetland, year by year (#93).
#
# Phase 4 of #93, the free reference: FWA wetlands (1:20,000) are a mapped-wetland reference that
# is independent of IO. The per-year IO class composition inside them says how IO labels a known
# wetland (Flooded Vegetation, Rangeland, Trees, ...) regardless of change, and how much that
# label moves between years with no change on the ground to move it.
#
# Read from the CLASSIFIED rasters, not from #95's `in_wetland`: that flag sits on changed patches
# only (step 3 vectorizes changes_only = TRUE), so it cannot describe stable land. Membership is
# per cell centre, the same rule the strata use.
#
# usage: Rscript scripts/landcover_accuracy/reference_composition-wetland.R [area]
# Output: data/<area>/accuracy/wetland_composition.csv (year x zone x class: ha, share)

suppressMessages({library(sf); library(terra); library(DBI); library(RPostgres); library(yaml)})
sf::sf_use_s2(FALSE)
source(here::here("scripts", "floodplain_lcc", "fp_disturbance.R"))
source(here::here("scripts", "landcover_accuracy", "fp_accuracy.R"))

area <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(area)) area <- "necr"
cfg  <- fp_acc_area(area)
g    <- fp_acc_grid(cfg)

dst <- fp_disturbance_validate(yaml::read_yaml(here::here("config", "disturbance.yml")))
wet_src <- Filter(function(s) identical(s$name, "wetland"), dst$context)
if (length(wet_src) != 1) stop("config/disturbance.yml has no `wetland` context entry", call. = FALSE)

fp <- sf::st_read(file.path(cfg$dir_out, "floodplain.gpkg"), layer = cfg$primary_scenario, quiet = TRUE)
fp <- sf::st_transform(fp, terra::crs(g$trans))
conn <- DBI::dbConnect(RPostgres::Postgres())
wet  <- .dst_fetch(conn, wet_src[[1]], fp, cfg$change_interval)
DBI::dbDisconnect(conn)
wet  <- wet[lengths(sf::st_intersects(sf::st_transform(wet, sf::st_crs(fp)), fp)) > 0, ]  # bbox -> footprint
wet_r <- fp_acc_rasterize(wet, g$trans)

class_names <- c(`1` = "Water", `2` = "Trees", `4` = "Flooded Vegetation", `5` = "Crops",
                 `7` = "Built Area", `8` = "Bare Ground", `9` = "Snow/Ice", `11` = "Rangeland")
ha <- prod(terra::res(g$trans)) / 1e4

tab <- function(r, zone) {
  f <- terra::freq(r)
  f <- f[!is.na(f$value), c("value", "count")]
  data.frame(zone = zone, class_code = f$value, class = unname(class_names[as.character(f$value)]),
             ha = f$count * ha, share = f$count / sum(f$count))
}

rows <- list()
for (y in names(g$cls)) {
  r <- g$cls[[y]]
  rows[[length(rows) + 1]] <- cbind(year = as.integer(y), tab(terra::mask(r, wet_r), "fwa_wetland"))
  rows[[length(rows) + 1]] <- cbind(year = as.integer(y), tab(r, "floodplain"))
}
out <- do.call(rbind, rows)
out$ha <- round(out$ha, 2); out$share <- round(out$share, 4)

dir.create(cfg$dir_acc, showWarnings = FALSE, recursive = TRUE)
utils::write.csv(out, file.path(cfg$dir_acc, "wetland_composition.csv"), row.names = FALSE, na = "")

wide <- stats::reshape(out[out$zone == "fwa_wetland", c("year", "class", "share")],
                       idvar = "class", timevar = "year", direction = "wide")
names(wide) <- sub("^share\\.", "", names(wide))
cat(sprintf("FWA wetland polygons touching the floodplain: %d; cells inside them: %.1f ha\n",
            nrow(wet), sum(out$ha[out$zone == "fwa_wetland" & out$year == min(out$year)])))
cat("IO class share inside FWA wetlands, by year:\n")
print(wide[order(-wide[[2]]), ], row.names = FALSE)
