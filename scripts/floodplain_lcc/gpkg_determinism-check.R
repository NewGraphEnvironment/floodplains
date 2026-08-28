# gpkg_determinism-check.R — assert a full GeoPackage rebuild is byte-reproducible (#45).
#
# GDAL stamps gpkg_contents.last_change at write time, so two writes of identical data differ unless
# OGR_CURRENT_DATE is pinned (scripts/fp_gpkg.R). #45 asks for this assertion explicitly, so that a
# future regression — a new write path that bypasses the pin, a GDAL upgrade that stops honouring
# the env var — is loud rather than silent churn in the published checksums.
#
# WHAT IS ASSERTED: replaying an existing gpkg's layers into a FRESH file, twice, produces identical
# bytes. That mirrors the pipeline's own write shape (append = file.exists + delete_layer = TRUE,
# the #23 multi-species pattern), so it exercises the real path and not a toy fixture.
#
# WHAT IS NOT ASSERTED, and cannot be: rewriting ONE layer into an EXISTING gpkg. SQLite reuses
# free pages differently after a delete than on a fresh insert, so a partial rerun (step 3 alone
# over an area whose step 2 output is already there) is NOT byte-stable even with the stamp pinned.
# The check reports that case as INFO so the limit stays visible rather than being quietly assumed
# away. Answering "did this output actually change?" across a partial rerun needs a content hash,
# not byte equality — see the plan notes on bcgov/FIT_changedetector.
#
# usage: Rscript scripts/floodplain_lcc/gpkg_determinism-check.R [area] [gpkg]
#   defaults: morr floodplain.gpkg   (floodplain_landcover.gpkg is the heavier check)
#   FP_GPKG_NO_PIN=1   skip the pin. The check MUST then FAIL — that is the cold-path test proving
#                      the guard actually guards, rather than passing for some unrelated reason.

suppressMessages({library(sf)})
sf::sf_use_s2(FALSE)

a     <- commandArgs(TRUE)
area  <- if (!is.na(a[1])) a[1] else "morr"
gpkg  <- if (!is.na(a[2])) a[2] else "floodplain.gpkg"
src   <- here::here("data", area, gpkg)
if (!file.exists(src)) stop("no such gpkg: ", src, call. = FALSE)

no_pin <- nzchar(Sys.getenv("FP_GPKG_NO_PIN", ""))
if (no_pin) {
  # Unset explicitly: run_region.R pins the env for its children, so an inherited value would
  # leave the cold path silently testing the pinned case and claiming a meaningless pass.
  Sys.unsetenv("OGR_CURRENT_DATE")
  message("FP_GPKG_NO_PIN set — running WITHOUT the pin; this check is expected to FAIL.")
} else {
  source(here::here("scripts", "fp_gpkg.R"))
  fp_gpkg_pin_date(quiet = FALSE)
}

lyrs <- sf::st_layers(src)$name
message("Source: ", src, " (", length(lyrs), " layers, ",
        round(file.size(src) / 1e6, 1), " MB)")
dat <- lapply(lyrs, function(l) sf::st_read(src, layer = l, quiet = TRUE))

# Replay the pipeline's own write shape into a fresh file.
replay <- function(path) {
  unlink(path)
  for (i in seq_along(lyrs)) {
    sf::st_write(dat[[i]], path, layer = lyrs[i],
                 append = file.exists(path), delete_layer = TRUE, quiet = TRUE)
  }
  unname(tools::md5sum(path))
}

tmp <- tempfile("gpkgdet_")
p1  <- paste0(tmp, "_1.gpkg"); p2 <- paste0(tmp, "_2.gpkg"); p3 <- paste0(tmp, "_3.gpkg")
on.exit(unlink(c(p1, p2, p3)), add = TRUE)

h1 <- replay(p1)
# The unpinned stamp has 1 ms resolution but is written per layer; a full second of separation makes
# a false PASS from a same-instant write impossible, so a pass means the pin, not luck.
Sys.sleep(1.2)
h2 <- replay(p2)

message("\n  rebuild 1: ", h1, "\n  rebuild 2: ", h2)
same <- identical(h1, h2)

# INFO only: the documented limit. Rewrite the last layer into a copy of an existing file.
invisible(file.copy(p1, p3, overwrite = TRUE))
Sys.sleep(1.2)
sf::st_write(dat[[length(lyrs)]], p3, layer = lyrs[length(lyrs)],
             append = TRUE, delete_layer = TRUE, quiet = TRUE)
partial_same <- identical(unname(tools::md5sum(p3)), h1)
message("  partial rerun of 1 layer into an existing file reproduces: ", partial_same,
        "  (INFO — documented limit, not asserted)")

if (no_pin) {
  if (same) stop("UNEXPECTED: rebuilds matched with the pin disabled. The check is not ",
                 "exercising what it claims — investigate before trusting a pass.", call. = FALSE)
  message("\nPASS (cold path): without the pin the rebuilds differ, as expected.")
} else {
  if (!same) stop("gpkg rebuild is NOT byte-reproducible for ", area, "/", gpkg,
                  " — the pin is not reaching this write path (#45).", call. = FALSE)
  message("\nPASS: a full rebuild of ", area, "/", gpkg, " is byte-reproducible.")
}
