# wayback_coverage-area.R — how near each change endpoint Esri Wayback can see an area's floodplain (#145).
#
# #145 step 1: before any sample is drawn or chip built for a new area, measure which Wayback captures
# exist over its floodplain and how near the endpoints they fall. That says where Wayback can date a change
# endpoint and where another dated source (Sentinel-2, an orthophoto or air photo) must. Metadata only: no
# tile is fetched.
#
# A seeded random point sample over the accuracy scenario's floodplain (fp_acc_area, #140) stands in
# for its area: a point gets the one capture drawn on top there (drift::dft_wayback_captures), which
# is the unit the accuracy sample uses too, and equal-probability points make each share an estimate of the share of floodplain AREA.
# Per point and endpoint, the capture nearest mid-season of that year (dft_wayback_pick), banded by whole
# years as labelling-key rule 5 is (+/-2 years supports high or medium confidence).
#
# usage: Rscript scripts/landcover_accuracy/wayback_coverage-area.R <area> [n_points]
# Output: data/<area>/accuracy/wayback_coverage.csv (per point and endpoint) and a summary on stdout.

suppressMessages({library(sf)})
sf::sf_use_s2(FALSE)
source(here::here("scripts", "landcover_accuracy", "fp_accuracy.R"))

a    <- commandArgs(trailingOnly = TRUE)
area <- if (!is.na(a[1])) a[1] else stop("usage: wayback_coverage-area.R <area> [n_points]", call. = FALSE)
n    <- if (!is.na(a[2])) as.integer(a[2]) else 1000L
cfg  <- fp_acc_area(area)
if (utils::packageVersion("drift") < "0.24.0") stop("drift >= 0.24.0 (dft_wayback_*) is required", call. = FALSE)

fp  <- sf::st_read(file.path(cfg$dir_out, "floodplain.gpkg"), layer = cfg$primary_scenario, quiet = TRUE)
fp  <- sf::st_union(sf::st_make_valid(fp))
set.seed(145L)
pts <- sf::st_sf(feature = seq_len(n), geometry = sf::st_sample(fp, n, type = "random", exact = TRUE))
if (nrow(pts) != n) stop("sampled ", nrow(pts), " points, not ", n, call. = FALSE)

ends <- as.integer(cfg$change_interval)
cap  <- drift::dft_wayback_captures(pts, zoom = 17:19)
pick <- drift::dft_wayback_pick(cap, as.Date(sprintf("%d-07-01", ends)))
pick$endpoint <- as.integer(format(as.Date(pick$date), "%Y"))
pick$years    <- as.integer(format(as.Date(pick$capture_date), "%Y")) - pick$endpoint

grid <- expand.grid(feature = pts$feature, endpoint = ends)
out  <- merge(grid, as.data.frame(pick)[, c("feature", "endpoint", "release_id", "capture_date", "res_m", "zoom", "years")],
              by = c("feature", "endpoint"), all.x = TRUE)
dir.create(cfg$dir_acc, showWarnings = FALSE, recursive = TRUE)
utils::write.csv(out, file.path(cfg$dir_acc, "wayback_coverage.csv"), row.names = FALSE, na = "")

band <- cut(abs(out$years), c(-Inf, 0, 1, 2, Inf), labels = c("same year", "+/-1 year", "+/-2 years", "further"))
band <- factor(ifelse(is.na(out$years), "no capture", as.character(band)),
               levels = c("same year", "+/-1 year", "+/-2 years", "further", "no capture"))
tab  <- table(out$endpoint, band)
cat(sprintf("%s: %d random floodplain points (%s), seed 145, drift %s\n\n", area, n, cfg$primary_scenario,
            utils::packageVersion("drift")))
print(tab)
cat("\nshare within +/-2 years (rule 5's high/medium ceiling):\n")
print(round(tapply(!is.na(out$years) & abs(out$years) <= 2, out$endpoint, mean), 3))
cat("\nnewest capture:", format(max(as.Date(cap$capture_date), na.rm = TRUE)), "\n")
cat("captures by year (picked, all endpoints):\n")
print(table(format(as.Date(out$capture_date), "%Y"), useNA = "ifany"))
