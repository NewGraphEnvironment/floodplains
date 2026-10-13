# dem_cache-check.R — assert the step-2 DEM cache (#122).
#
# Offline (default): every key ingredient moves the key hash and an unchanged input keeps it; a hit
# needs the key AND the file's digest; a tampered file, a lost sidecar or a moved key re-fetches;
# FP_DEM_SOURCE still equals flooded's own default. The fetch and the HEAD request are replaced by
# counting fakes, so no network and no DEM are needed.
#
# LIVE=1 adds a real round trip on a tiny AOI in a temp directory: a miss, then a hit with no fetch,
# both digesting the same.
#
# usage: Rscript scripts/floodplain_lcc/dem_cache-check.R
#        LIVE=1 Rscript scripts/floodplain_lcc/dem_cache-check.R

suppressMessages({library(sf); library(terra)})
source(here::here("scripts", "fp_raster.R"))
source(here::here("scripts", "floodplain_lcc", "fp_provenance.R"))
source(here::here("scripts", "floodplain_lcc", "fp_dem.R"))

n_fail <- 0L
check <- function(ok, what) {
  ok <- isTRUE(ok)
  if (!ok) n_fail <<- n_fail + 1L
  cat(if (ok) "  ok   " else "  FAIL ", what, "\n", sep = "")
}
errs <- function(expr) inherits(tryCatch(expr, error = function(e) e), "error")

crs <- sf::st_crs(3005)
streams <- sf::st_sf(id = 1:2, geometry = sf::st_sfc(
  sf::st_linestring(rbind(c(1000000, 1000000), c(1001000, 1000500))),
  sf::st_linestring(rbind(c(1001000, 1000500), c(1002000, 1000200))), crs = crs))
ver <- list(last_modified = "Wed, 24 Jun 2026 15:08:08 GMT", etag = "1bf0-9997")
tc  <- list(gdal_terra = "3.13.0", proj_terra = "9.8.1", proj = "9.5.1")
k0  <- fp_dem_key(streams, 2000, crs, FP_DEM_SOURCE, ver, flooded = "0.7.0", toolchain = tc)
h0  <- fp_dem_key_hash(k0)

cat("the key\n")
check(identical(h0, fp_dem_key_hash(fp_dem_key(streams, 2000, crs, FP_DEM_SOURCE, ver,
                                               flooded = "0.7.0", toolchain = tc))),
      "an unchanged input keeps the key hash")
check(identical(h0, fp_dem_key_hash(fp_dem_key(streams, 2000L, crs, FP_DEM_SOURCE, ver,
                                               flooded = "0.7.0", toolchain = tc))),
      "an integer buffer hashes like the double (step 2's 2000 vs a CSV's max_width)")
moved <- list(
  "the AOI geometry" = function() {
    s <- streams; sf::st_geometry(s)[[2]] <- sf::st_linestring(rbind(c(1001000, 1000500), c(1002000, 1000201)))
    fp_dem_key(s, 2000, crs, FP_DEM_SOURCE, ver, flooded = "0.7.0", toolchain = tc) },
  "the AOI row order" = function()
    fp_dem_key(streams[2:1, ], 2000, crs, FP_DEM_SOURCE, ver, flooded = "0.7.0", toolchain = tc),
  "a dropped feature" = function()
    fp_dem_key(streams[1, ], 2000, crs, FP_DEM_SOURCE, ver, flooded = "0.7.0", toolchain = tc),
  "the buffer" = function()
    fp_dem_key(streams, 1500, crs, FP_DEM_SOURCE, ver, flooded = "0.7.0", toolchain = tc),
  "the target CRS" = function()
    fp_dem_key(streams, 2000, sf::st_crs(3157), FP_DEM_SOURCE, ver, flooded = "0.7.0", toolchain = tc),
  "the source URL" = function()
    fp_dem_key(streams, 2000, crs, sub("mrdem-30-dtm", "mrdem-30-dsm", FP_DEM_SOURCE), ver,
               flooded = "0.7.0", toolchain = tc),
  "Last-Modified" = function()
    fp_dem_key(streams, 2000, crs, FP_DEM_SOURCE, modifyList(ver, list(last_modified = "Thu, 25 Jun 2026")),
               flooded = "0.7.0", toolchain = tc),
  "the ETag" = function()
    fp_dem_key(streams, 2000, crs, FP_DEM_SOURCE, modifyList(ver, list(etag = "1bf1-9997")),
               flooded = "0.7.0", toolchain = tc),
  "the flooded version" = function()
    fp_dem_key(streams, 2000, crs, FP_DEM_SOURCE, ver, flooded = "0.7.1", toolchain = tc),
  "terra's GDAL" = function()
    fp_dem_key(streams, 2000, crs, FP_DEM_SOURCE, ver, flooded = "0.7.0",
               toolchain = modifyList(tc, list(gdal_terra = "3.13.1"))),
  "terra's PROJ" = function()
    fp_dem_key(streams, 2000, crs, FP_DEM_SOURCE, ver, flooded = "0.7.0",
               toolchain = modifyList(tc, list(proj_terra = "9.8.2"))),
  "sf's PROJ (flooded#78)" = function()
    fp_dem_key(streams, 2000, crs, FP_DEM_SOURCE, ver, flooded = "0.7.0",
               toolchain = modifyList(tc, list(proj = "9.8.1"))))
for (nm in names(moved)) {
  check(!identical(h0, fp_dem_key_hash(moved[[nm]]())), paste0("must-fail: changing ", nm, " moves the key"))
}
check(errs(fp_dem_key_hash(modifyList(k0, list(proj_sf = NA_character_)))),
      "must-fail: an NA ingredient is refused rather than hashed as \"NA\"")
check(errs(fp_dem_key_hash(c(k0, list(extra = character(0))))),
      "must-fail: an empty ingredient is refused")
check(identical(fp_dem_key_diff(k0, moved[["the buffer"]]()), "buffer_m"),
      "the miss message names the ingredient that moved")

cat("\nthe source agrees with flooded's default\n")
# Parsed from flooded's body rather than restated: a flooded release changing its default is then a
# FAIL here, which is the prompt to decide whether FP_DEM_SOURCE should follow.
fl_body <- paste(deparse(body(flooded::fl_dem_aoi)), collapse = "")
fl_default <- tryCatch(eval(parse(text = regmatches(
  fl_body, regexpr("paste0\\(\"/vsicurl/[^)]*\\)", fl_body)))), error = function(e) NA_character_)
check(identical(fl_default, FP_DEM_SOURCE),
      sprintf("FP_DEM_SOURCE equals flooded %s's default (%s)",
              as.character(utils::packageVersion("flooded")), fl_default))

cat("\nhit and miss, with a counting fake for the fetch and the HEAD request\n")
n_fetch <- 0L
fake_dem <- function(streams, source, buffer, target_crs) {
  n_fetch <<- n_fetch + 1L
  r <- terra::rast(nrows = 20, ncols = 30, xmin = 998000, xmax = 1004000, ymin = 998000,
                   ymax = 1002000, crs = target_crs$wkt)
  terra::values(r) <- seq_len(terra::ncell(r)) / 7   # doubles a float write would round
  r[1:5] <- NA
  r
}
fp_dem_object_version <- function(source, ...) ver   # mask the HEAD request; the key is still real
d <- file.path(tempdir(), "dem_cache_check"); unlink(d, recursive = TRUE); dir.create(d)
tif <- file.path(d, "dem_co3.tif"); js <- file.path(d, "dem_co3.json")
call_cache <- function(buffer = 2000) suppressMessages(
  fp_dem_cached(streams, buffer, crs, d, "co3", fetch = fake_dem))

a <- call_cache()
check(n_fetch == 1L && identical(attr(a, "fp_dem_cache")$status, "miss"), "a cold call fetches once (miss)")
check(file.exists(tif) && file.exists(js), "the miss writes the tif and its sidecar")
check(identical(fp_raster_content_sha256(tif), fp_raster_content_sha256(fake_dem(streams, NULL, 0, crs))),
      "the cached tif digests like the fetched object (FLT8S, no rounding)")
n_fetch <- 0L
check(length(list.files(d, pattern = "^dem_.*[.](tif|json)$")) == 2L, "no temp files left behind")

b <- call_cache()
check(n_fetch == 0L && identical(attr(b, "fp_dem_cache")$status, "hit"), "a warm call does not fetch (hit)")
check(identical(attr(a, "fp_dem_cache")$dem_content_sha256, attr(b, "fp_dem_cache")$dem_content_sha256),
      "hit and miss record the same digest")
check(identical(attr(b, "fp_dem_cache")$key_sha256, jsonlite::read_json(js)$key_sha256),
      "the returned key is the sidecar's")
check(!terra::inMemory(a) && !terra::inMemory(b), "both paths return a file-backed raster")

n_fetch <- 0L
c1 <- call_cache(buffer = 1500)
check(n_fetch == 1L && identical(attr(c1, "fp_dem_cache")$status, "miss"),
      "must-fail: a moved key re-fetches")
invisible(call_cache(buffer = 2000))  # restore the 2000 m cache
n_fetch <- 0L
r <- terra::rast(tif); v <- terra::values(r); v[100] <- v[100] + 1
r2 <- terra::rast(r); terra::values(r2) <- v
terra::writeRaster(r2, file.path(d, "t.tif"), datatype = "FLT8S", overwrite = TRUE); rm(r)
invisible(file.rename(file.path(d, "t.tif"), tif))
t1 <- call_cache()
check(n_fetch == 1L && identical(attr(t1, "fp_dem_cache")$status, "miss"),
      "must-fail: a tampered tif under a matching key re-fetches, not hits")
n_fetch <- 0L
invisible(file.remove(js))
t2 <- call_cache()
check(n_fetch == 1L, "must-fail: a tif with no sidecar re-fetches")
n_fetch <- 0L
writeLines("{not json", js)
t3 <- call_cache()
check(n_fetch == 1L, "must-fail: an unreadable sidecar re-fetches")
n_fetch <- 0L
check(identical(attr(call_cache(), "fp_dem_cache")$status, "hit"), "and the repaired cache hits again")

cat("\nthe HEAD request fails closed\n")
rm(fp_dem_object_version)                 # back to the real one
check(errs(fp_dem_object_version("/data/local/dem.tif")), "must-fail: a non-/vsicurl/ source is refused")
check(errs(fp_dem_object_version("/vsicurl/https://canelevation-dem.s3.ca-central-1.amazonaws.com/no-such-key.tif",
                                 timeout = 20)),
      "must-fail: a 403/404 is an error, not an empty version (needs network; an outage fails too)")

if (identical(Sys.getenv("LIVE"), "1")) {
  cat("\nlive: a real round trip on a tiny AOI\n")
  dl <- file.path(tempdir(), "dem_cache_live"); unlink(dl, recursive = TRUE); dir.create(dl)
  tiny <- streams[1, ]
  t0 <- Sys.time()
  m <- fp_dem_cached(tiny, 500, crs, dl, "co3")
  t_miss <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  t0 <- Sys.time()
  h <- fp_dem_cached(tiny, 500, crs, dl, "co3")
  t_hit <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  cat(sprintf("  miss %.1f s, hit %.1f s, %d x %d cells\n", t_miss, t_hit, terra::ncol(h), terra::nrow(h)))
  check(identical(attr(m, "fp_dem_cache")$status, "miss") && identical(attr(h, "fp_dem_cache")$status, "hit"),
        "live: miss then hit")
  check(identical(attr(m, "fp_dem_cache")$dem_content_sha256, attr(h, "fp_dem_cache")$dem_content_sha256),
        "live: both digest the same")
  direct <- flooded::fl_dem_aoi(tiny, buffer = 500, target_crs = crs)
  check(identical(fp_raster_content_sha256(direct), attr(h, "fp_dem_cache")$dem_content_sha256),
        "live: the cache equals flooded's own default fetch")
}

cat(sprintf("\n%s (%d failure%s)\n", if (n_fail) "FAIL" else "PASS", n_fail, if (n_fail == 1) "" else "s"))
quit(status = if (n_fail) 1L else 0L)
