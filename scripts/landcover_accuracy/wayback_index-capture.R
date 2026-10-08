# wayback_index-capture.R — per accuracy sample point, the Esri Wayback capture nearest each endpoint (#115).
#
# Esri's World Imagery is sub-metre where the review's other sharp sources are not dated or not near
# the endpoints (imagery_index-dated.R: a 2012 air photo thumbnail and a 2021 orthophoto). Its archive,
# Wayback, publishes the mosaic as it stood on each release date, but a release date is NOT a capture
# date: a release mosaics captures of many years (rtj research/esri_wayback.md; NECR point 1 is a 2013
# capture in the 2017-11-16 release and a 2017-06-11 one in the 2020-04-29 release). So this reads
# each release's capture metadata and picks, per point and endpoint, the CAPTURE nearest the endpoint
# (fp_acc_wayback_pick in fp_accuracy.R holds the rule).
#
# Method (measured in #115, planning findings):
#   - the release list is Esri's waybackconfig.json (release ids are not ordered by date);
#   - each release's metadata MapServer has one layer per scale band, and layer L describes tile zoom
#     23 - L. Layers 4-6 (zoom 19-17) are queried once each over the sample's bbox -- one envelope query
#     per release and layer, not one identify per point -- and the polygons are joined to the points
#     locally, in the service's own EPSG:3857;
#   - per point and release the DEEPEST layer covering the point gives both the capture and the zoom
#     the build fetches at. Over NECR that is zoom 17 (~0.7 m on the ground) everywhere probed.
# Metadata responses are cached under data/<area>/accuracy/wayback/meta/ (gitignored), keyed by release,
# layer and query bbox; FORCE=1 refetches.
#
# Writes reference/<area>/wayback.csv, one row per (point, endpoint) for EVERY sample point:
#   point_id, stratum, cell, map_class, endpoint, release_id, release_date, capture_date, src_res,
#   source, zoom, years_from_endpoint
# with an empty release where no capture covers the point. Regenerated, never hand-edited, and re-run
# after any redraw (keyed by point_id, design columns copied so consumers can check it by content).
#
# usage: Rscript scripts/landcover_accuracy/wayback_index-capture.R [area]

suppressMessages({library(sf)})
sf::sf_use_s2(FALSE)
source(here::here("scripts", "landcover_accuracy", "fp_accuracy.R"))

area <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(area)) area <- "necr"
cfg  <- fp_acc_area(area)
force <- identical(Sys.getenv("FORCE"), "1")

WB_CONFIG <- "https://s3-us-west-2.amazonaws.com/config.maptiles.arcgis.com/waybackconfig.json"
WB_LAYERS <- 4:6                       # metadata layer L <-> tile zoom 23 - L (19, 18, 17)

smp <- sf::st_read(file.path(cfg$dir_ref, "sample.gpkg"), layer = "sample", quiet = TRUE)
design <- sf::st_drop_geometry(smp)[, c("point_id", FP_ACC_DESIGN_KEY)]
pts <- sf::st_transform(smp[, "point_id"], 3857)
bb  <- as.numeric(sf::st_bbox(sf::st_transform(sf::st_buffer(smp, 200), 4326)))
# The cache is keyed by the bbox it was queried over: a grown or redrawn sample has another bbox, and a
# response cached for the old one would report its new points as "no capture" (drift#25's class).
bb_key <- substr(digest::digest(sprintf("%.5f", bb), algo = "md5"), 1, 10)
dir_meta <- file.path(cfg$dir_acc, "wayback", "meta")
dir.create(dir_meta, recursive = TRUE, showWarnings = FALSE)

# HTTP GET with the status read from curl itself, and one retry: a metadata service that answers 5xx
# once is common, and a missing release would silently narrow the candidate set.
fetch <- function(url) {
  for (i in 1:3) {
    r <- tryCatch(curl::curl_fetch_memory(url, handle = curl::new_handle(timeout = 120)), error = identity)
    if (!inherits(r, "error") && r$status_code == 200) return(rawToChar(r$content))
    Sys.sleep(2 * i)
  }
  stop("GET failed after 3 tries (", if (inherits(r, "error")) conditionMessage(r) else r$status_code, "): ", url,
       call. = FALSE)
}

cfg_wb <- jsonlite::fromJSON(fetch(WB_CONFIG), simplifyVector = FALSE)
rel <- data.frame(
  release_id   = names(cfg_wb),
  release_date = vapply(cfg_wb, function(r) sub(".*Wayback ([0-9-]{10}).*", "\\1", r$itemTitle), ""),
  meta_url     = vapply(cfg_wb, function(r) r$metadataLayerUrl %||% NA_character_, ""),
  stringsAsFactors = FALSE)
bad <- !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", rel$release_date) | is.na(rel$meta_url)
if (any(bad)) stop(sum(bad), " release(s) in waybackconfig.json without a parseable date or metadata URL: ",
                   paste(utils::head(rel$release_id[bad], 3), collapse = ", "), call. = FALSE)
rel <- rel[order(rel$release_date, method = "radix"), ]
message(sprintf("%d Wayback releases, %s to %s", nrow(rel), rel$release_date[1], rel$release_date[nrow(rel)]))

# One release-layer's capture polygons over the sample bbox, paged until the server says it is done.
meta_query <- function(url, layer) {
  q <- function(offset) paste0(url, "/", layer, "/query?", paste(
    c(paste0("geometry=", paste(bb, collapse = ",")), "geometryType=esriGeometryEnvelope", "inSR=4326",
      # geometryPrecision: some release-layers (2017_r12 layer 6) answer a full-precision geometry
      # request with HTTP 500 "Error performing query operation" every time, and answer at 0.1 m
      # (3857 units). 0.1 m does not move a point-in-polygon join that matters.
      "spatialRel=esriSpatialRelIntersects", "outSR=3857", "returnGeometry=true", "geometryPrecision=1", "f=json",
      "outFields=SRC_DATE,SRC_RES,SRC_DESC,NICE_DESC,MinMapLevel,MaxMapLevel,DrawOrder",
      paste0("resultOffset=", offset)), collapse = "&"))
  feats <- list(); offset <- 0L
  repeat {
    d <- jsonlite::fromJSON(fetch(q(offset)), simplifyVector = FALSE)
    if (!is.null(d$error)) stop("metadata query error at ", url, "/", layer, ": ", d$error$message, call. = FALSE)
    feats <- c(feats, d$features)
    if (!isTRUE(d$exceededTransferLimit)) break
    offset <- length(feats)
  }
  if (!length(feats)) return(NULL)
  rings <- lapply(feats, function(f) sf::st_polygon(lapply(f$geometry$rings, function(r)
    do.call(rbind, lapply(r, function(xy) as.numeric(unlist(xy)))))))
  # a JSON null arrives as NULL; unlist() then coerces the column to its values' type
  a <- function(k) unlist(lapply(feats, function(f) f$attributes[[k]] %||% NA), use.names = FALSE)
  sf::st_sf(src_date = as.character(a("SRC_DATE")), src_res = as.numeric(a("SRC_RES")),
            sensor = as.character(a("SRC_DESC")), provider = as.character(a("NICE_DESC")),
            max_level = as.integer(a("MaxMapLevel")), draw_order = as.integer(a("DrawOrder")),
            geometry = sf::st_sfc(rings, crs = 3857))
}

t0 <- Sys.time()
hits <- list()
for (i in seq_len(nrow(rel))) {
  for (L in WB_LAYERS) {
    f <- file.path(dir_meta, sprintf("%s_L%d_%s.rds", rel$release_id[i], L, bb_key))
    if (force || !file.exists(f)) saveRDS(meta_query(rel$meta_url[i], L), f)
    m <- readRDS(f)
    if (is.null(m) || !nrow(m)) next
    j <- sf::st_join(pts, sf::st_make_valid(m), join = sf::st_intersects, left = FALSE)
    if (!nrow(j)) next
    j <- sf::st_drop_geometry(j)
    j$release_id <- rel$release_id[i]; j$release_date <- rel$release_date[i]; j$layer <- L
    hits[[length(hits) + 1L]] <- j
  }
  if (i %% 25 == 0) message(sprintf("  %d/%d releases read (%.1f min)", i, nrow(rel),
                                    as.numeric(difftime(Sys.time(), t0, units = "mins"))))
}
hits <- do.call(rbind, hits)
if (is.null(hits) || !nrow(hits)) stop("no Wayback capture covers any sample point", call. = FALSE)

# Within one release and layer a point should sit in one capture polygon. Report any overlap rather
# than assume it away, and resolve it by the highest DrawOrder (drawn on top), then the finer source.
k <- paste(hits$point_id, hits$release_id, hits$layer)
n_ov <- sum(duplicated(k))
if (n_ov) message(sprintf("%d (point, release, layer) hit(s) fall in more than one capture polygon; the top DrawOrder wins",
                          n_ov))
hits <- hits[order(hits$point_id, hits$release_id, hits$layer, -hits$draw_order, hits$src_res, method = "radix"), ]
hits <- hits[!duplicated(paste(hits$point_id, hits$release_id, hits$layer)), ]
# the deepest layer covering the point in that release: its capture is what the deepest tiles show
hits <- hits[order(hits$point_id, hits$release_id, hits$layer, method = "radix"), ]
hits <- hits[!duplicated(paste(hits$point_id, hits$release_id)), ]
hits$zoom <- 23L - hits$layer
# A null SRC_DATE is a base layer (Earthstar etc.), not a capture.
cand <- data.frame(point_id = hits$point_id, release_id = hits$release_id, release_date = hits$release_date,
                   capture_date = ifelse(grepl("^[0-9]{8}$", hits$src_date),
                                         sub("^([0-9]{4})([0-9]{2})([0-9]{2})$", "\\1-\\2-\\3", hits$src_date),
                                         NA_character_),
                   src_res = hits$src_res, source = trimws(paste(hits$provider, hits$sensor)), zoom = hits$zoom,
                   stringsAsFactors = FALSE)
message(sprintf("%d (point, release) captures; %d distinct capture dates", nrow(cand),
                length(unique(stats::na.omit(cand$capture_date)))))

pick <- fp_acc_wayback_pick(cand, design$point_id, cfg$change_interval)
out  <- merge(design, pick, by = "point_id", sort = FALSE)
out  <- out[order(out$point_id, out$endpoint, method = "radix"),
            c("point_id", FP_ACC_DESIGN_KEY, setdiff(FP_ACC_WAYBACK_COLS, "point_id"))]
csv <- file.path(cfg$dir_ref, "wayback.csv")
utils::write.csv(out, csv, row.names = FALSE, na = "")
# read back through the consumers' guard, so a file the build would refuse is never left as current
invisible(fp_acc_wayback_read(csv, sf::st_drop_geometry(smp), cfg$change_interval))

# --- how far the nearest capture sits from each endpoint ----------------------------------------
d <- out$years_from_endpoint
band <- ifelse(is.na(d), "no capture", ifelse(d == 0, "same year", ifelse(abs(d) == 1, "+/-1 year",
               ifelse(abs(d) == 2, "+/-2 years", "further"))))
band <- factor(band, levels = c("same year", "+/-1 year", "+/-2 years", "further", "no capture"))
message(sprintf("\n%d rows -> %s (%.1f min)\ncapture distance from each endpoint (points):", nrow(out), csv,
                as.numeric(difftime(Sys.time(), t0, units = "mins"))))
print(table(endpoint = out$endpoint, band))
message("\nsigned years from endpoint:")
print(table(endpoint = out$endpoint, years = d, useNA = "ifany"))
# The nearest capture to both endpoints can be the SAME image (one capture is all a point has near
# either): the chip then dates one endpoint well and the other poorly, and its label says so.
o1 <- out[out$endpoint == min(out$endpoint), ]; o2 <- out[out$endpoint == max(out$endpoint), ]
same <- o1$capture_date == o2$capture_date[match(o1$point_id, o2$point_id)] & !is.na(o1$capture_date)
message(sprintf("\nsame capture at both endpoints: %d of %d points", sum(same), nrow(o1)))
message("\nzoom and resolution of the picked captures:")
print(table(zoom = out$zoom, src_res = out$src_res, useNA = "ifany"))
