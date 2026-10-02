# imagery_build-dated.R — the dated high-resolution review layers, one per themed epoch (#103).
#
# Reads reference/<area>/imagery.csv (imagery_index-dated.R) and builds a layer for every source-year
# that fp_acc_imagery_themes() says earns a theme, into the review project (rfp refuses a raster
# outside it):
#
#   <project>/dated/orthophoto_<year>.vrt   a VRT over the orthophoto COGs touching the sample points,
#                                            read remotely (/vsicurl/) and warped on read to BC Albers
#                                            (the tiles are UTM; _native.vrt is the unwarped mosaic).
#                                            Nothing is copied: the reviewer's
#                                            QGIS streams the tiles it draws, so it needs the network.
#                                            The VRT holds the private catalogue's hrefs, which is why it
#                                            lives in the gitignored project and never in reference/.
#   <project>/dated/airphoto_<year>/        per point, the nearest-centre covering frame that
#                                            georeferences: fetched as a thumbnail (fly_fetch),
#                                            georeferenced (fly_georef, with a DEM -- the digital frames
#                                            are sized by it), plus airphoto_<year>.vrt over them. A
#                                            point whose frame fails falls back to its next-nearest, and
#                                            the run reports download failures, georeference skips and
#                                            points left with none.
#
# fly_georef is given the year's FULL frame set, not the frames being fetched. A frame's rotation
# comes from its roll neighbours (frame +/-1, fly_bearing()); passed alone, a frame has no bearing,
# is drawn landscape against a portrait thumbnail, and fly's stretch guard skips it. The first build
# passed the fetched sample only and lost 87 of 250 frames that way -- and hid fly's warning saying
# so behind suppressWarnings() (fly#88, withdrawn as a caller error). fly's warnings print.
#
# Prints each layer's ground resolution: a thumbnail coarser than Sentinel-2's 10 m would add a date
# and nothing else, and that is worth knowing before a reviewer relies on it.
#
# Re-runnable: VRTs and georeferenced frames are rebuilt; fetched thumbnails are kept (fly's
# overwrite = FALSE on the download). review_build-qgis.R adds the layers and their map themes afterwards.
#
# usage: Rscript scripts/landcover_accuracy/imagery_build-dated.R [area]

suppressMessages({library(sf); library(terra)})
sf::sf_use_s2(FALSE)
source(here::here("scripts", "landcover_accuracy", "fp_accuracy.R"))

area <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(area)) area <- "necr"
cfg  <- fp_acc_area(area)

dir_proj <- fp_acc_review_dir(cfg)
if (!file.exists(file.path(dir_proj, paste0(basename(dir_proj), ".qgs"))))
  stop("no review project at ", dir_proj, " -- run review_build-qgis.R first", call. = FALSE)
dir_dated <- file.path(dir_proj, "dated")
dir.create(dir_dated, showWarnings = FALSE)

smp <- sf::st_read(file.path(cfg$dir_ref, "sample.gpkg"), layer = "sample", quiet = TRUE)
img_csv <- file.path(cfg$dir_ref, "imagery.csv")
if (!file.exists(img_csv)) stop("no ", img_csv, " -- run imagery_index-dated.R first", call. = FALSE)
img <- utils::read.csv(img_csv, stringsAsFactors = FALSE, colClasses = c(airp_id = "character"))
# imagery.csv is keyed by point_id, which a redraw reuses for other cells, so it carries the design
# key and is checked against the sample BY CONTENT (never by mtime, which git does not keep).
# imagery.csv lists every sample point (an uncovered one with an empty source), so the point SET is
# checked as well as the content: a stale index after pilot -> full holds agreeing rows and too few.
if (!setequal(unique(img$point_id), smp$point_id))
  stop(img_csv, " does not list exactly sample.gpkg's points -- re-run imagery_index-dated.R", call. = FALSE)
fp_acc_design_check(img[!duplicated(img$point_id), ], sf::st_drop_geometry(smp),
                    paste(img_csv, "(re-run imagery_index-dated.R after a redraw)"))
themes <- fp_acc_imagery_themes(img, nrow(smp))
themes <- themes[themes$theme, ]
# A layer built for an epoch that no longer earns a theme (a redraw, a larger sample) would otherwise
# stay on disk and in the project; review_build-qgis.R drops a dated layer whose VRT is gone.
want  <- sprintf("%s_%d", themes$source, themes$year)
stale <- list.files(dir_dated, pattern = "^(orthophoto|airphoto)_[0-9]{4}(_native)?[.]vrt$")
stale <- stale[!sub("(_native)?[.]vrt$", "", stale) %in% want]
if (length(stale)) { unlink(file.path(dir_dated, stale)); message("removed stale: ", paste(stale, collapse = ", ")) }
if (!nrow(themes)) { message("no dated epoch earns a theme; nothing to build"); quit(status = 0L) }
print(themes, row.names = FALSE)

# Ground resolution of a built layer, in metres (the VRT's own pixel size). Opening the orthophoto VRT
# opens its remote tiles, so the read goes through the URL quieting like every other remote call.
res_m <- function(vrt) round(mean(fp_acc_quiet_urls(terra::res(terra::rast(vrt)), "reading a VRT")$value), 2)

# --- orthophotos ------------------------------------------------------------------------------
if (any(themes$source == "orthophoto")) {
  # 300 m around each point, the chips' footprint: only the tiles a reviewer looks at
  boxes <- sf::st_transform(sf::st_buffer(sf::st_transform(smp, 3005), 300, endCapStyle = "SQUARE"), 4326)
  feat  <- fp_acc_ortho_items(as.numeric(sf::st_bbox(boxes)))
  feat <- feat[feat$cog & !is.na(feat$href) & lengths(sf::st_intersects(feat, boxes)) > 0, ]
  for (y in themes$year[themes$source == "orthophoto"]) {
    f <- feat[feat$year == y, ]
    # One VRT needs one CRS; the catalogue stores each tile in its UTM zone.
    if (length(unique(f$epsg)) != 1)
      stop("orthophoto ", y, " tiles span EPSG ", paste(unique(f$epsg), collapse = ", "),
           "; one VRT per zone is not built yet", call. = FALSE)
    # The tiles are in their UTM zone and rfp refuses a raster in a CRS no project layer uses, so the
    # mosaic (native CRS) is wrapped in a WARPED VRT to BC Albers: still remote, still nothing copied,
    # reprojected on read at the tiles' own 0.15 m.
    src <- file.path(dir_dated, sprintf("orthophoto_%d_native.vrt", y))
    out <- file.path(dir_dated, sprintf("orthophoto_%d.vrt", y))
    # gdalbuildvrt SKIPS a tile it cannot open, returns TRUE, and names the tile's URL in a warning:
    # quiet the URLs, then count what the VRT actually holds rather than what was asked for.
    bv <- fp_acc_quiet_urls(sf::gdal_utils("buildvrt", source = paste0("/vsicurl/", sort(f$href)),
                                           destination = src, options = c("-overwrite")),
                            "gdalbuildvrt (orthophoto)")
    if (length(bv$warnings)) message("  ", length(bv$warnings), " buildvrt warning(s), URLs redacted: ",
                                     paste(utils::head(unique(bv$warnings), 3), collapse = " | "))
    n_in <- length(unique(xml2::xml_text(xml2::xml_find_all(xml2::read_xml(src), "//SourceFilename"))))
    if (n_in != nrow(f)) stop("orthophoto ", y, ": the VRT holds ", n_in, " of ", nrow(f),
                              " tiles; the rest could not be opened", call. = FALSE)
    if (file.exists(out)) unlink(out)
    fp_acc_quiet_urls(sf::gdal_utils("warp", source = src, destination = out,
                                     options = c("-of", "VRT", "-t_srs", "EPSG:3005", "-r", "bilinear",
                                                 "-tr", "0.15", "0.15", "-tap")),
                      "gdalwarp (orthophoto)")
    if (!file.exists(out)) stop("gdalwarp wrote no ", out, call. = FALSE)
    message(sprintf("orthophoto %d: %d tiles -> %s (%.2f m)", y, nrow(f), basename(out), res_m(out)))
  }
}

# --- digital air photos -----------------------------------------------------------------------
if (any(themes$source == "airphoto")) {
  pts_ba <- sf::st_transform(smp, 3005)
  bb_ba  <- sf::st_bbox(sf::st_buffer(pts_ba, 5000))   # the index's query, so every airp_id is in it
  ph <- bcdata::bcdc_query_geodata("WHSE_IMAGERY_AND_BASE_MAPS.AIMG_PHOTO_CENTROIDS_SP") |>
    bcdata::filter(bcdata::BBOX(!!bb_ba, crs = "EPSG:3005")) |> bcdata::collect()
  names(ph) <- tolower(names(ph))
  sf::st_geometry(ph) <- "geometry"
  ph$airp_id <- as.character(ph$airp_id)
  dem <- flooded::fl_dem_aoi(sf::st_as_sf(sf::st_as_sfc(bb_ba)))
  for (y in themes$year[themes$source == "airphoto"]) {
    # every covering frame per point, nearest centre first: the index records only the nearest
    phy <- ph[ph$photo_year == y, ]
    fp  <- fly::fly_footprint(phy, dem = dem)
    fp  <- fp[!sf::st_is_empty(fp), ]
    cov <- sf::st_join(pts_ba[, "point_id"], fp[, "airp_id"], join = sf::st_intersects, left = FALSE)
    cov$dist <- as.numeric(sf::st_distance(sf::st_geometry(cov),
                                           sf::st_geometry(phy)[match(cov$airp_id, phy$airp_id)],
                                           by_element = TRUE))
    cov <- sf::st_drop_geometry(cov)
    cov <- cov[order(cov$point_id, cov$dist, cov$airp_id), ]
    d   <- file.path(dir_dated, sprintf("airphoto_%d", y))
    good <- character(0); tried <- character(0); dest <- character(0); n_dl_fail <- 0L
    repeat {
      # each point still without a georeferenced frame takes its nearest frame not yet tried
      open_pts <- setdiff(unique(cov$point_id), cov$point_id[cov$airp_id %in% good])
      nxt <- cov[cov$point_id %in% open_pts & !cov$airp_id %in% tried, ]
      nxt <- unique(nxt$airp_id[!duplicated(nxt$point_id)])
      if (!length(nxt)) break
      sel <- phy[phy$airp_id %in% nxt, ]
      fet <- fly::fly_fetch(sel, type = "thumbnail", dest_dir = file.path(d, "thumbnail"), workers = 4)
      n_dl_fail <- n_dl_fail + sum(!fet$success %in% TRUE)
      # photos_sf = the whole year, so every fetched frame has its roll neighbours for a bearing
      # overwrite = TRUE: fly keys its cache on the file name, so a frame georeferenced under another
      # neighbour set, DEM or fly version would otherwise come back as a success, unchanged
      geo <- fly::fly_georef(fet[fet$success %in% TRUE, ], phy, dest_dir = file.path(d, "georef"), dem = dem,
                             overwrite = TRUE)
      tried <- c(tried, nxt)
      okg   <- geo$success %in% TRUE & !is.na(geo$dest) & file.exists(geo$dest)
      good  <- c(good, geo$airp_id[okg]); dest <- c(dest, geo$dest[okg])
    }
    n_none <- length(setdiff(unique(cov$point_id), cov$point_id[cov$airp_id %in% good]))
    message(sprintf("airphoto %d: %d frames georeferenced, %d not (%d of them failed to download); %d of %d covered points have none",
                    y, length(good), length(setdiff(tried, good)), n_dl_fail, n_none, length(unique(cov$point_id))))
    if (!length(dest)) next
    out <- file.path(dir_dated, sprintf("airphoto_%d.vrt", y))
    # terra::vrt drops a file with a different band count or CRS with only a warning; count what it holds
    terra::vrt(sort(unique(dest)), filename = out, overwrite = TRUE)
    n_in <- length(unique(xml2::xml_text(xml2::xml_find_all(xml2::read_xml(out), "//SourceFilename"))))
    if (n_in != length(unique(dest))) stop("airphoto ", y, ": the VRT holds ", n_in, " of ",
                                          length(unique(dest)), " georeferenced frames", call. = FALSE)
    message(sprintf("airphoto %d -> %s (%.2f m)", y, basename(out), res_m(out)))
  }
}
