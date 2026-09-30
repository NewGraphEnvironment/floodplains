# window_count-clear.R — clear Sentinel-2 observations per month over an area's floodplain (#93).
#
# Phase 2 of #93: the composite windows for reference imagery are MEASURED, not chosen by hand.
# For each month and year, drift::dft_stac_composite(aggregation = "count") returns, per pixel,
# how many clear observations fall in that window. The SCL mask is applied before aggregation, so
# a cloudy pixel does not count. `cloud_cover_max` is the chips' own value (drift's default, 20),
# so the counts describe the scenes a review chip will actually be built from.
#
#   validate  one month, two checks before trusting the coarse run:
#             (a) res 100 vs res 20 over a small sub-AOI -- the coarse grid must not move the count
#             (b) the per-pixel count vs an INDEPENDENT rstac item query (bbox, not drift's
#                 `intersects` path): no pixel can see more clear scenes than there are scenes
#   run       months 4-10 x 2017-2023 over the whole primary floodplain at res 100
#
# Output: data/<area>/accuracy/windows_clear_obs.csv (per month/year stats). The curated copy and
# the log go to scripts/landcover_accuracy/logs/ by hand, with the date prefix.
#
# usage: Rscript scripts/landcover_accuracy/window_count-clear.R <area> validate|run
#        caffeinate -s Rscript scripts/landcover_accuracy/window_count-clear.R necr run

suppressMessages({library(sf); library(terra)})
sf::sf_use_s2(FALSE)
source(here::here("scripts", "landcover_accuracy", "fp_accuracy.R"))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2 || !args[2] %in% c("validate", "run"))
  stop("usage: window_count-clear.R <area> validate|run", call. = FALSE)
area <- args[1]; mode <- args[2]

cfg  <- fp_acc_area(area)
fp   <- sf::st_read(file.path(cfg$dir_out, "floodplain.gpkg"), layer = cfg$primary_scenario,
                    quiet = TRUE)
# The transition grid's CRS, so a window's pixels line up with the map being assessed.
crs_grid <- fp_acc_epsg(file.path(cfg$dir_rast, "transition.tif"))
fp   <- sf::st_transform(fp, as.integer(sub("EPSG:", "", crs_grid)))

YEARS  <- 2017:2023
MONTHS <- 4:10
CC_MAX <- 20   # drift's composite default; the chips use the same

count_stats <- function(r, month, year, res) {
  v <- terra::values(r[[1]], mat = FALSE)
  v <- v[!is.na(v)]
  data.frame(year = year, month = month, res = res, n_cells = length(v),
             median = if (length(v)) stats::median(v) else NA_real_,
             p10 = if (length(v)) unname(stats::quantile(v, 0.10)) else NA_real_,
             max = if (length(v)) max(v) else NA_real_,
             share_ge1 = if (length(v)) mean(v >= 1) else NA_real_,
             share_ge3 = if (length(v)) mean(v >= 3) else NA_real_)
}

clear_count <- function(aoi, year, month, res) {
  out <- tryCatch(
    drift::dft_stac_composite(aoi, years = year, months = month, bands = "red",
                              aggregation = "count", res = res, crs = crs_grid, clip = TRUE,
                              cloud_cover_max = CC_MAX),
    error = function(e) { message("  ", year, "-", month, ": ", conditionMessage(e)); NULL })
  if (is.null(out) || !length(out)) return(NULL)
  # A count is a whole number. drift 0.19.0 passes `aggregation` straight to gdalcubes'
  # cube_view(), which has no "count", and returns reflectance without complaint (drift#92) --
  # values near 0.03 that read as "almost no clear scenes" if nobody checks. Refuse them.
  v <- terra::values(out[[1]], mat = FALSE)
  v <- v[!is.na(v)]
  if (length(v) && any(abs(v - round(v)) > 1e-6))
    stop(sprintf("%d-%02d: aggregation = \"count\" returned non-integer values (max %.4f); ",
                 year, month, max(v)),
         "this drift does not count clear observations (drift#92)", call. = FALSE)
  out[[1]]
}

if (mode == "validate") {
  year <- 2021; month <- 7
  # Sub-AOI: a 6 km square on the floodplain's largest part, clipped to the floodplain.
  parts  <- sf::st_cast(sf::st_union(fp), "POLYGON")
  anchor <- sf::st_point_on_surface(parts[which.max(sf::st_area(parts))])
  box    <- sf::st_as_sfc(sf::st_bbox(sf::st_buffer(anchor, 3000)))
  sub    <- sf::st_sf(geometry = sf::st_intersection(sf::st_union(fp), box))

  r100 <- clear_count(sub, year, month, 100)
  r20  <- clear_count(sub, year, month, 20)
  if (is.null(r100) || is.null(r20)) stop("validation composite failed", call. = FALSE)
  s <- rbind(count_stats(r100, month, year, 100), count_stats(r20, month, year, 20))
  print(s)

  # (b) independent item query over the sub-AOI's bbox
  bb <- sf::st_bbox(sf::st_transform(sub, 4326))
  it <- rstac::stac("https://planetarycomputer.microsoft.com/api/stac/v1") |>
    rstac::stac_search(collections = "sentinel-2-l2a", bbox = as.numeric(bb),
                       datetime = sprintf("%d-%02d-01T00:00:00Z/%d-%02d-%02dT23:59:59Z", year, month,
                                          year, month, 31L), limit = 500) |>
    rstac::ext_filter(`eo:cloud_cover` <= {{CC_MAX}}) |>
    rstac::post_request() |> rstac::items_fetch()
  dts   <- vapply(it$features, function(f) substr(f$properties$datetime, 1, 10), "")
  tiles <- vapply(it$features, function(f) f$properties$`s2:mgrs_tile` %||% NA_character_, "")
  cat(sprintf("\nitems (cloud <= %d): %d over %d distinct dates; tiles: %s\n", CC_MAX,
              length(dts), length(unique(dts)), paste(sort(unique(tiles)), collapse = ",")))
  cat(sprintf("max per-pixel clear count: res100 %s, res20 %s (must be <= items %d)\n",
              s$max[1], s$max[2], length(dts)))
  if (max(s$max) > length(dts)) stop("a pixel saw more clear scenes than there are scenes",
                                     call. = FALSE)
} else {
  rows <- list()
  for (yr in YEARS) for (m in MONTHS) {
    t0 <- Sys.time()
    r  <- clear_count(fp, yr, m, 100)
    if (is.null(r)) {
      rows[[length(rows) + 1]] <- data.frame(year = yr, month = m, res = 100, n_cells = 0,
                                             median = 0, p10 = 0, max = 0, share_ge1 = 0,
                                             share_ge3 = 0)
    } else rows[[length(rows) + 1]] <- count_stats(r, m, yr, 100)
    message(sprintf("%d-%02d done in %.1f min", yr, m,
                    as.numeric(difftime(Sys.time(), t0, units = "mins"))))
  }
  res <- do.call(rbind, rows)
  dir.create(cfg$dir_acc, showWarnings = FALSE)
  f <- file.path(cfg$dir_acc, "windows_clear_obs.csv")
  utils::write.csv(res, f, row.names = FALSE, na = "")
  print(res)
  cat("wrote", f, "\n")
}
