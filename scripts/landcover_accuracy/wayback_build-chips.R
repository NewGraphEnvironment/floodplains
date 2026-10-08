# wayback_build-chips.R — per review point, a local chip of the Esri Wayback capture nearest each endpoint (#115).
#
# Reads reference/<area>/wayback.csv (wayback_index-capture.R) and builds, inside the review project
# (rfp refuses a raster outside it):
#
#   <project>/dated/wayback_<year>/<review_id>.tif   one chip per point that has a capture: the chosen
#                                                     release at the capture's zoom, +/-150 m around the
#                                                     point, at the tiles' own ground resolution, in BC Albers
#   <project>/dated/wayback_<year>.vrt               a mosaic over that year's chips
#
# Local rasters, so labelling needs no network, and they draw in QGIS, which a Wayback service does not
# (qgis/QGIS#54161: a deduplicated tile 301-redirects with a relative Location QGIS cannot follow;
# GDAL can).
#
# Three rules that are easy to break:
#   - NAMED BY review_id, NEVER point_id (fp_acc_chip_name). point_id encodes the stratum (#111). The
#     manifest that maps one to the other, built.csv, lives in data/<area>/accuracy/wayback/, outside the
#     project, as do the WMS descriptions and the tile cache: rtj's compose refuses any non-image file
#     under dated/, and GDAL_PAM_ENABLED=NO keeps .aux.xml sidecars from being written beside the chips.
#   - EACH PIXEL BELONGS TO ITS NEAREST POINT. 176 of NECR's 480 points have a neighbour within 300 m,
#     so +/-150 m chips overlap, and neighbours are usually different captures. A chip is clipped to its
#     point's Voronoi cell (over the whole sample, so reviewer B's hard-linked copy is identical), and
#     the outside is nodata 0 (a real 0 is nudged to 1). A VRT skips a source's NODATA when it composites
#     but NOT a source's mask band -- measured in #115: with JPEG + mask chips, the source listed last
#     overwrote its neighbour at the neighbour's own point. Hence lossless DEFLATE and nodata, not JPEG.
#   - A KEPT CHIP MUST STILL BE THE CHOSEN ONE. A re-index can pick another release for the same point
#     (Esri publishes new releases), and a grown sample moves the Voronoi cells. A chip is rebuilt
#     unless built.csv records the same release, zoom and cell for it.
#
# A chip fails, and is not written, when more than 5% of its cell came back empty (a 404 tile reads as
# zeros). A FLAT cell is not a failure: the first build refused three as possible placeholder tiles, and
# all three were open lake, which is Water and needs its chip. Failures and points with no capture are
# reported separately. After the build the pixel under EVERY point is read back from the VRT and compared with
# its own chip.
#
# usage: Rscript scripts/landcover_accuracy/wayback_build-chips.R [area]      FORCE=1 rebuilds every chip

suppressMessages({library(sf); library(terra)})
sf::sf_use_s2(FALSE)
Sys.setenv(GDAL_PAM_ENABLED = "NO")
source(here::here("scripts", "landcover_accuracy", "fp_accuracy.R"))

area <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(area)) area <- "necr"
cfg  <- fp_acc_area(area)
force <- identical(Sys.getenv("FORCE"), "1")
HALF  <- 150          # metres either side of the point
t0 <- Sys.time()

dir_proj <- fp_acc_review_dir(cfg)
if (!file.exists(file.path(dir_proj, paste0(basename(dir_proj), ".qgs"))))
  stop("no review project at ", dir_proj, " -- run review_build-qgis.R first", call. = FALSE)
dir_dated <- file.path(dir_proj, "dated")
dir.create(dir_dated, showWarnings = FALSE)
dir_wb  <- file.path(cfg$dir_acc, "wayback")
dir_wms <- file.path(dir_wb, "wms"); dir_tiles <- file.path(dir_wb, "tiles")
dir.create(dir_wms, recursive = TRUE, showWarnings = FALSE)
man_csv <- file.path(dir_wb, "built.csv")

smp <- sf::st_read(file.path(cfg$dir_ref, "sample.gpkg"), layer = "sample", quiet = TRUE)
smp_d <- sf::st_drop_geometry(smp)
ends <- as.integer(cfg$change_interval)
way <- fp_acc_wayback_read(file.path(cfg$dir_ref, "wayback.csv"), smp_d, ends)
key_csv <- file.path(cfg$dir_ref, "review_key.csv")
key <- fp_acc_review_key_read(key_csv)
if (is.null(key)) stop("no ", key_csv, " -- run review_build-qgis.R first", call. = FALSE)
if (length(setdiff(smp$point_id, key$point_id)))
  stop(length(setdiff(smp$point_id, key$point_id)), " sample point(s) have no review_id -- re-run ",
       "review_build-qgis.R (it appends them to the key) before building chips", call. = FALSE)
fp_acc_design_check(key, smp_d, key_csv)

# --- each point's own ground: its +/-150 m square inside its Voronoi cell -------------------------
pts <- sf::st_transform(smp[, "point_id"], 3005)
vor <- sf::st_collection_extract(sf::st_voronoi(sf::st_union(pts),
         envelope = sf::st_as_sfc(sf::st_bbox(sf::st_buffer(pts, 5 * HALF))), point_order = FALSE), "POLYGON")
hit <- sf::st_intersects(pts, vor)
if (any(lengths(hit) != 1)) stop("a sample point does not sit in exactly one Voronoi cell", call. = FALSE)
own <- sf::st_sfc(lapply(seq_len(nrow(pts)), function(i)
  sf::st_intersection(sf::st_buffer(sf::st_geometry(pts)[i], HALF, endCapStyle = "SQUARE"),
                      sf::st_geometry(vor)[hit[[i]]])[[1]]), crs = 3005)
# The clip itself, not its bbox: a Voronoi edge that cuts only a corner of the square leaves the bbox
# unchanged, and a chip kept on that key would overlap its new neighbour. Rounded to the centimetre, so
# GEOS's last bits do not force a rebuild.
own_key <- vapply(seq_along(own), function(i)
  paste(sprintf("%.2f", sf::st_coordinates(own[i])[, 1:2]), collapse = ","), "")
names(own) <- names(own_key) <- pts$point_id

# The tiles' ground resolution at the sample's latitude: Web Mercator stretches by 1/cos(lat), so a
# zoom-17 tile pixel is ~0.70 m on the ground at 54 N. Resampling finer would only inflate the files.
lat <- mean(sf::st_coordinates(sf::st_transform(smp, 4326))[, 2])
ground_res <- function(z) round(156543.03392 / 2^z * cos(lat * pi / 180) / 0.05) * 0.05

man_old <- if (file.exists(man_csv)) utils::read.csv(man_csv, stringsAsFactors = FALSE,
                                                    colClasses = c(release_id = "character")) else NULL
# The manifest is the build's certificate: review_build-qgis.R adds the Esri capture layers only when it
# lists every sample point at every endpoint. So it is removed now and rewritten only after every guard
# below has passed -- a build that aborts, or that a guard refuses, leaves no manifest, and the layers
# are not offered over a mosaic nobody vouched for.
if (!is.null(man_old)) {
  if (!"status" %in% names(man_old)) man_old$status <- "built"   # a manifest from before it listed failures
  man_old <- man_old[man_old$status == "built", ]
  unlink(man_csv)
}
built <- list(); fails <- list()

build_chip <- function(r, f) {
  xml <- file.path(dir_wms, sprintf("%s_z%d.xml", r$release_id, r$zoom))
  # rewritten every time: its content is the template and the cache path, not just its name
  writeLines(fp_acc_wayback_wms_xml(r$release_id, r$zoom, dir_tiles), xml)
  g <- own[[r$point_id]]
  b <- sf::st_bbox(g); tr <- ground_res(r$zoom)
  tmp <- tempfile(fileext = ".tif"); on.exit(unlink(tmp), add = TRUE)
  w <- character(0)
  withCallingHandlers(
    sf::gdal_utils("warp", source = xml, destination = tmp,
                   options = c("-t_srs", "EPSG:3005", "-te", b, "-tr", tr, tr, "-tap", "-r", "bilinear",
                               "-overwrite")),
    warning = function(cnd) { w <<- c(w, conditionMessage(cnd)); invokeRestart("muffleWarning") })
  if (!file.exists(tmp)) stop("gdalwarp wrote nothing")
  x <- terra::rast(tmp)
  inside <- terra::rasterize(terra::vect(sf::st_sfc(g, crs = 3005)), x[[1]], touches = FALSE)
  v <- terra::values(c(x, inside))
  v <- v[!is.na(v[, 4]), 1:3, drop = FALSE]
  if (!nrow(v)) stop("the point's cell covers no pixel")
  empty <- mean(rowSums(v) == 0)
  if (empty > 0.05) stop(sprintf("%.0f%% of the cell came back empty (404 tiles: no imagery at zoom %d)",
                                 100 * empty, r$zoom))
  x <- terra::classify(x, cbind(0, 1))                       # a real 0 is not nodata
  x <- terra::mask(x, terra::vect(sf::st_sfc(g, crs = 3005)), updatevalue = 0, touches = FALSE)
  terra::writeRaster(x, f, datatype = "INT1U", NAflag = 0, overwrite = TRUE,
                     gdal = c("COMPRESS=DEFLATE", "PREDICTOR=2", "TILED=YES"))
  length(w)
}

for (e in ends) {
  d <- file.path(dir_dated, sprintf("wayback_%d", e))
  dir.create(d, showWarnings = FALSE)
  w <- way[way$endpoint == e & !is.na(way$release_id) & nzchar(way$release_id), ]
  w$review_id <- key$review_id[match(w$point_id, key$point_id)]
  w$file <- fp_acc_chip_name(w$review_id)
  w$own_key <- own_key[w$point_id]
  n_new <- 0L; n_kept <- 0L
  for (i in seq_len(nrow(w))) {
    r <- w[i, ]; f <- file.path(d, r$file)
    prev <- if (!is.null(man_old)) man_old[man_old$endpoint == e & man_old$review_id == r$review_id, ] else NULL
    same <- !force && file.exists(f) && !is.null(prev) && nrow(prev) == 1 &&
      identical(prev$release_id, r$release_id) && identical(as.integer(prev$zoom), as.integer(r$zoom)) &&
      identical(prev$own_key, r$own_key) && identical(prev$point_id, r$point_id)
    if (same) { n_kept <- n_kept + 1L }
    else {
      unlink(f)
      res <- tryCatch(build_chip(r, f), error = function(cnd) cnd)
      if (inherits(res, "error")) {
        unlink(f)
        fails[[length(fails) + 1L]] <- data.frame(endpoint = e, review_id = r$review_id,
                                                  release_id = r$release_id, why = conditionMessage(res))
        next
      }
      n_new <- n_new + 1L
    }
    built[[length(built) + 1L]] <- r[, c("review_id", "point_id", "endpoint", "release_id", "release_date",
                                         "capture_date", "src_res", "zoom", "own_key", "file")]
    if ((n_new + n_kept) %% 50 == 0)
      message(sprintf("  %d: %d chips (%d fetched, %d kept), %.1f min", e, n_new + n_kept, n_new, n_kept,
                      as.numeric(difftime(Sys.time(), t0, units = "mins"))))
  }
  # a chip no longer wanted (a point that lost its capture, a redrawn sample) is removed
  have <- list.files(d, pattern = "[.]tif$")
  keep <- vapply(built, function(b) if (b$endpoint == e) b$file else NA_character_, "")
  stale <- setdiff(have, keep)
  if (length(stale)) { unlink(file.path(d, stale)); message(sprintf("  %d: removed %d stale chip(s)", e, length(stale))) }
  chips <- sort(setdiff(have, stale))
  vrt <- file.path(dir_dated, sprintf("wayback_%d.vrt", e))
  if (!length(chips)) { unlink(vrt); message(e, ": no chips"); next }
  # relative paths (the chips sit under the VRT's directory), so the project can move to Mergin
  owd <- setwd(dir_dated)
  sf::gdal_utils("buildvrt", source = file.path(basename(d), chips), destination = basename(vrt),
                 options = c("-overwrite", "-resolution", "highest"))
  setwd(owd)
  n_in <- length(unique(xml2::xml_text(xml2::xml_find_all(xml2::read_xml(vrt), "//SourceFilename"))))
  if (n_in != length(chips)) stop(e, ": the VRT holds ", n_in, " of ", length(chips), " chips", call. = FALSE)
  message(sprintf("%d: %d chips (%d fetched, %d kept), %d with no capture, %d failed -> %s", e,
                  length(chips), n_new, n_kept, sum(way$endpoint == e & (is.na(way$release_id) | !nzchar(way$release_id))),
                  sum(vapply(fails, function(x) x$endpoint == e, TRUE)), basename(vrt)))
}
# an endpoint the config no longer has
for (v in setdiff(list.files(dir_dated, pattern = "^wayback_[0-9]{4}[.]vrt$"), sprintf("wayback_%d.vrt", ends))) {
  unlink(c(file.path(dir_dated, v), file.path(dir_dated, sub("[.]vrt$", "", v))), recursive = TRUE)
  message("removed stale ", v)
}

built <- do.call(rbind, built)
if (is.null(built)) stop("no chip was built or kept for any point -- see the failures above", call. = FALSE)
fails <- if (length(fails)) do.call(rbind, fails) else NULL
if (!is.null(fails)) {
  message("\nfailed chips (", nrow(fails), "):")
  print(utils::head(fails[order(fails$why), ], 20), row.names = FALSE)
  print(table(sub(" \\(.*", "", sub("^[0-9]+% ", "N% ", fails$why))))
}

# --- what the project now holds --------------------------------------------------------------
# pattern = would match basenames only and skip every chip under wayback_<year>/: filter the relative path
wb_files <- grep("^wayback_", list.files(dir_dated, recursive = TRUE), value = TRUE)
odd <- wb_files[!grepl("[.](tif|vrt)$", wb_files)]
if (length(odd)) stop("non-image file(s) under dated/: ", paste(utils::head(odd, 3), collapse = ", "),
                      " (rtj's compose refuses them)", call. = FALSE)
if (any(fp_acc_point_id_like(wb_files))) stop("a wayback file name carries a point_id", call. = FALSE)
src <- unlist(lapply(file.path(dir_dated, sprintf("wayback_%d.vrt", ends)), function(v)
  if (file.exists(v)) xml2::xml_text(xml2::xml_find_all(xml2::read_xml(v), "//SourceFilename"))))
if (any(fp_acc_point_id_like(src))) stop("a wayback VRT names a point_id", call. = FALSE)

# The pixel under every point, read from the mosaic, must be its own chip's: the guard on the Voronoi
# clip and on the VRT's compositing (a neighbour's chip winning would show another capture).
pts_ba <- sf::st_transform(smp[, "point_id"], 3005)
n_bad <- 0L
for (e in ends) {
  b <- built[built$endpoint == e, ]
  if (!nrow(b)) next
  p <- pts_ba[match(b$point_id, pts_ba$point_id), ]
  mos <- terra::extract(terra::rast(file.path(dir_dated, sprintf("wayback_%d.vrt", e))), terra::vect(p), ID = FALSE)
  own_v <- t(vapply(seq_len(nrow(b)), function(i)
    unlist(terra::extract(terra::rast(file.path(dir_dated, sprintf("wayback_%d", e), b$file[i])),
                          terra::vect(p[i, ]), ID = FALSE)), numeric(3)))
  bad <- rowSums(abs(as.matrix(mos) - own_v) > 0, na.rm = TRUE) > 0 | is.na(rowSums(as.matrix(mos)))
  if (any(bad)) message(sprintf("%d: %d point(s) read another chip's pixel (review_id %s)", e, sum(bad),
                                paste(utils::head(b$review_id[bad], 5), collapse = ", ")))
  n_bad <- n_bad + sum(bad)
}
if (n_bad) stop(n_bad, " point(s) do not read their own chip from the mosaic", call. = FALSE)

# Every guard passed: write the manifest, one row per sample point per endpoint, so a reader can tell a
# build for THIS sample (every point listed) from one for an earlier sample, and "no capture" and
# "failed" from "not built". Voronoi cells are a function of the whole point set, so the point set is
# what makes the chips current.
all_rows <- way[, c("point_id", FP_ACC_DESIGN_KEY, "endpoint", "release_id", "release_date", "capture_date",
                   "src_res", "zoom")]
all_rows$review_id <- key$review_id[match(all_rows$point_id, key$point_id)]
bk <- paste(built$point_id, built$endpoint)
fk <- if (is.null(fails)) character(0) else paste(key$point_id[match(fails$review_id, key$review_id)], fails$endpoint)
ak <- paste(all_rows$point_id, all_rows$endpoint)
all_rows$status <- ifelse(ak %in% bk, "built", ifelse(ak %in% fk, "failed", "no_capture"))
m <- match(ak, bk)
all_rows$own_key <- built$own_key[m]; all_rows$file <- built$file[m]
all_rows <- all_rows[order(all_rows$point_id, all_rows$endpoint, method = "radix"),
                     c("review_id", "point_id", FP_ACC_DESIGN_KEY, "endpoint", "status", "release_id",
                       "release_date", "capture_date",
                       "src_res", "zoom", "own_key", "file")]
utils::write.csv(all_rows, man_csv, row.names = FALSE, na = "")
message(sprintf("manifest -> %s: %s", man_csv, paste(names(table(all_rows$status)), table(all_rows$status),
                                                      collapse = ", ")))

mb <- sum(file.size(file.path(dir_dated, wb_files))) / 1e6
message(sprintf("\nevery point reads its own chip; dated/wayback_* = %d files, %.0f MB; %.1f min",
                length(wb_files), mb, as.numeric(difftime(Sys.time(), t0, units = "mins"))))
# point 1 of the issue, as a number rather than a picture
p1 <- built[built$review_id == 1 & built$endpoint == ends[1], c("review_id", "endpoint", "release_id",
                                                                 "release_date", "capture_date", "src_res")]
if (nrow(p1)) { message("review_id 1, first endpoint:"); print(p1, row.names = FALSE) }
