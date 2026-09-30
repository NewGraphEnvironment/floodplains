# chip_build-composite.R — dated Sentinel-2 reference chips around every sample point (#93).
#
# Phase 6 of #93. The reviewer decides each point's reference class from imagery whose DATE we
# know, which is what the Esri/Google/Bing basemaps cannot give. drift::dft_stac_composite() is
# called ONCE PER BUFFERED POINT per window, as drift documents: a floodplain-wide composite streams
# the whole bbox (drift#88), while a chip streams only the COG blocks under it and is cached on its
# own, so extending the pilot to the full sample fetches only the new points.
#
# Windows come from reference/<area>/windows.csv (columns: window, year, months), which phase 2
# writes once the windows are MEASURED (`window_count-clear.R <area> derive`), so this script refuses
# to run without the file rather than guess; `WINDOWS=<csv>` points it at another file (a timing run).
#
# Output, all inside the review project so rfp can reference it (rfp stops on a raster outside the
# project directory):
#   <project>/chips/cache/      drift's COG cache (cache_dir)
#   <project>/chips/manifest.csv  point_id x window x year -> file
#   <project>/chips/<window>_<year>.vrt  one mosaic per window-year: the layers the reviewer toggles
#
# usage: Rscript scripts/landcover_accuracy/chip_build-composite.R [area] [n_points]
#        caffeinate -s Rscript scripts/landcover_accuracy/chip_build-composite.R necr
#        (n_points: first n per stratum, for a timing run; default all)

suppressMessages({library(sf); library(terra)})
sf::sf_use_s2(FALSE)
source(here::here("scripts", "landcover_accuracy", "fp_accuracy.R"))

a    <- commandArgs(trailingOnly = TRUE)
area <- if (!is.na(a[1])) a[1] else "necr"
nmax <- if (!is.na(a[2])) as.integer(a[2]) else NA_integer_
cfg  <- fp_acc_area(area)

BUFFER_M <- 300   # half-width of a chip: 600 m square, 60 x 60 cells at 10 m
win_file <- Sys.getenv("WINDOWS", file.path(cfg$dir_ref, "windows.csv"))
if (!file.exists(win_file))
  stop("no ", win_file, ": the composite windows are measured first -- run window_count-clear.R <area> run, then derive",
       call. = FALSE)
# months as character: an all-single-month file ("7") would otherwise read back as integer
wins <- utils::read.csv(win_file, stringsAsFactors = FALSE, colClasses = c(months = "character"))
if (!all(c("window", "year", "months") %in% names(wins)))
  stop(win_file, " needs columns window, year, months (e.g. \"7-8\")", call. = FALSE)
if (anyDuplicated(wins[, c("window", "year")])) stop("duplicate window x year in ", win_file, call. = FALSE)

pts <- sf::st_read(file.path(cfg$dir_ref, "sample.gpkg"), layer = "sample", quiet = TRUE)
if (!is.na(nmax)) pts <- do.call(rbind, lapply(split(pts, pts$stratum), utils::head, nmax))
# Chips are built in BC Albers: they are display layers in the rfp project, whose templates carry
# EPSG:3005 (rfp refuses a raster in a CRS no project layer uses).
crs_grid <- 3005L

dir_proj  <- fp_acc_review_dir(cfg)
if (!file.exists(file.path(dir_proj, paste0(basename(dir_proj), ".qgs"))))
  stop("no review project at ", dir_proj, " -- run review_build-qgis.R first (rfp refuses to create ",
       "a project in a directory that already exists)", call. = FALSE)
dir_chips <- file.path(dir_proj, "chips")
dir_cache <- file.path(dir_chips, "cache")
dir.create(dir_cache, recursive = TRUE, showWarnings = FALSE)

months_of <- function(s) {
  r <- as.integer(strsplit(s, "-", fixed = TRUE)[[1]])
  if (length(r) == 1) r else seq(r[1], r[2])
}

rows <- list()
t0 <- Sys.time()
for (i in seq_len(nrow(pts))) {
  box <- sf::st_as_sf(sf::st_as_sfc(sf::st_bbox(sf::st_buffer(sf::st_geometry(pts[i, ]), BUFFER_M))))
  for (j in seq_len(nrow(wins))) {
    w <- wins[j, ]
    r <- tryCatch(
      drift::dft_stac_composite(box, years = w$year, months = months_of(w$months),
                                crs = paste0("EPSG:", crs_grid), cache_dir = dir_cache),
      error = function(e) { message("  ", pts$point_id[i], " ", w$window, " ", w$year, ": ",
                                    conditionMessage(e)); NULL })
    f <- if (length(r)) terra::sources(r[[1]])[1] else NA_character_
    rows[[length(rows) + 1]] <- data.frame(point_id = pts$point_id[i], window = w$window,
                                           year = w$year, file = f)
  }
  if (i %% 10 == 0 || i == nrow(pts))
    message(sprintf("%d / %d points, %.1f min", i, nrow(pts),
                    as.numeric(difftime(Sys.time(), t0, units = "mins"))))
}
man <- do.call(rbind, rows)
# paths relative to the project, so the project moves as one directory
man$file <- ifelse(is.na(man$file), NA_character_,
                   sub(paste0("^", normalizePath(dir_proj), "/"), "", normalizePath(man$file, mustWork = FALSE)))
utils::write.csv(man, file.path(dir_chips, "manifest.csv"), row.names = FALSE, na = "")

for (k in unique(paste(man$window, man$year))) {
  sel <- man[paste(man$window, man$year) == k & !is.na(man$file), ]
  if (!nrow(sel)) next
  out <- file.path(dir_chips, paste0(sub(" ", "_", k), ".vrt"))
  terra::vrt(file.path(dir_proj, sel$file), filename = out, overwrite = TRUE)
}
n_miss <- sum(is.na(man$file))
message(sprintf("%d chips (%d missing) for %d points x %d windows in %.1f min -> %s",
                nrow(man) - n_miss, n_miss, nrow(pts), nrow(wins),
                as.numeric(difftime(Sys.time(), t0, units = "mins")), dir_chips))
