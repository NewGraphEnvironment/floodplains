# imagery_index-dated.R — which DATED high-resolution images cover each accuracy sample point (#103).
#
# The review project's Sentinel-2 chips are dated but 10 m; Esri/Google/Bing are sharp but undated.
# Two dated, sharper sources exist, and this records, per point, which of their epochs cover it:
#
#   orthophoto   our private orthophoto STAC. The endpoint is read from FP_ORTHO_STAC (~/.Renviron)
#                and is never written here, in a log, or in the output: this repo is public, and
#                that catalogue is not. The output carries the year and resolution only -- no href,
#                no item id. Year precision: the catalogue dates many items to 1 January.
#   airphoto     BC air photo centroids (DataBC), sized into footprints by fly::fly_footprint().
#                A DEM is passed because digital frames cannot be sized without one (NECR: 1,466 of
#                16,964 frames, every 2012 and 2015 frame). Coverage is footprint-in-point, by st_join;
#                fly needs no new function for this (#103, "Ownership").
#
# Writes reference/<area>/imagery.csv, one row per (point, source, year):
#   point_id, stratum, cell, map_class, source, year, date, gsd_m, media, scale, n_images, airp_id
# plus one row with an empty source for any point no dated image covers, so the file lists every point.
# gsd_m is the orthophoto's pixel size; for air photos it is empty (the catalogue has no metric GSD).
# where the image fields describe the frame whose centre is NEAREST the point (the least oblique
# view); date and airp_id are air photo only. stratum, cell and map_class are copied from the sample
# so a consumer can check the index against the design by content (a redraw reuses point ids).
# It is an index of what existed when it ran, and the catalogues change, so it is regenerated, never
# hand-edited -- and re-run after any redraw, because it is keyed by point_id (CLAUDE.md, "A point_id
# is not an identity").
#
# Prints, per source-year, how many points it covers and whether it earns a review theme
# (fp_acc_imagery_themes: >= 25% of points, and for air photos digital frames only -- film frames with
# a flight bearing need per-roll rotations that do not exist yet, fly#53, and fly_georef skips them).
#
# usage: Rscript scripts/landcover_accuracy/imagery_index-dated.R [area]

suppressMessages({library(sf)})
sf::sf_use_s2(FALSE)
source(here::here("scripts", "landcover_accuracy", "fp_accuracy.R"))

area <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(area)) area <- "necr"
cfg  <- fp_acc_area(area)

smp <- sf::st_read(file.path(cfg$dir_ref, "sample.gpkg"), layer = "sample", quiet = TRUE)
design <- sf::st_drop_geometry(smp)[, c("point_id", FP_ACC_DESIGN_KEY)]
smp <- smp[, "point_id"]
n_pts <- nrow(smp)

# --- orthophoto -------------------------------------------------------------------------------
bb <- as.numeric(sf::st_bbox(sf::st_transform(sf::st_buffer(smp, 100), 4326)))
ortho <- fp_acc_ortho_items(bb)
# Only COGs can be streamed into a review layer; a non-COG tile is not an image the reviewer can see.
ortho <- ortho[ortho$cog, ]
message(sprintf("orthophoto: %d COG items in the sample bbox", nrow(ortho)))
j_o <- sf::st_join(sf::st_transform(smp, 4326), ortho, join = sf::st_intersects, left = FALSE)
# An item's footprint is not its image: a tile's collar is zero-filled, and 25 of NECR's 229 footprint
# hits read 0,0,0 there. A point is covered only where a pixel read returns image data. One remote
# read per tile, URLs quieted; the href goes no further than this block.
if (nrow(j_o)) {
  j_o$has_data <- FALSE
  for (h in unique(j_o$href)) {
    k <- which(j_o$href == h)
    v <- fp_acc_quiet_urls({
      r <- terra::rast(paste0("/vsicurl/", h))
      terra::extract(r, terra::vect(sf::st_transform(j_o[k, ], terra::crs(r))), ID = FALSE)
    }, "an orthophoto pixel read")$value
    j_o$has_data[k] <- rowSums(as.matrix(v) > 0, na.rm = TRUE) > 0
  }
  message(sprintf("orthophoto: %d point-tile hits, %d on image data (the rest on a zero collar)",
                  nrow(j_o), sum(j_o$has_data)))
  j_o <- j_o[j_o$has_data, ]
}
j_o$href <- NULL
o_rows <- if (nrow(j_o)) {
  d <- sf::st_drop_geometry(j_o)
  do.call(rbind, lapply(split(d, list(d$point_id, d$year), drop = TRUE), function(g)
    data.frame(point_id = g$point_id[1], source = "orthophoto", year = g$year[1], date = NA_character_,
               gsd_m = min(g$gsd_m), media = NA_character_, scale = NA_character_,
               n_images = nrow(g), airp_id = NA_character_)))
}

# --- air photos -------------------------------------------------------------------------------
pts_ba <- sf::st_transform(smp, 3005)
bb_ba  <- sf::st_bbox(sf::st_buffer(pts_ba, 5000))   # a frame centred up to ~5 km away covers a point
ph <- bcdata::bcdc_query_geodata("WHSE_IMAGERY_AND_BASE_MAPS.AIMG_PHOTO_CENTROIDS_SP") |>
  bcdata::filter(bcdata::BBOX(!!bb_ba, crs = "EPSG:3005")) |> bcdata::collect()
names(ph) <- tolower(names(ph))
sf::st_geometry(ph) <- "geometry"
message(sprintf("airphoto: %d frames in the buffered sample bbox", nrow(ph)))
# Size from the frame's own metadata first, and bring in the DEM only for the frames that need it:
# terrain-sizing samples the DEM under every footprint, which over ~17k frames costs many minutes for
# frames (film, at a stated scale) it does not change materially.
fp <- fly::fly_footprint(ph)
need <- sf::st_is_empty(fp)
if (any(need)) {
  dem <- flooded::fl_dem_aoi(sf::st_as_sf(sf::st_as_sfc(bb_ba)))
  fp_dem <- fly::fly_footprint(ph[need, ], dem = dem)
  fp <- rbind(fp[!need, ], fp_dem[, names(fp)])
  message(sprintf("airphoto: %d frames sized with the DEM, %d still unsized (they cover nothing here)",
                  sum(need), sum(sf::st_is_empty(fp))))
}
fp <- fp[!sf::st_is_empty(fp), ]
j_a <- sf::st_join(pts_ba, fp[, c("airp_id", "photo_year", "photo_date", "scale", "media")],
                   join = sf::st_intersects, left = FALSE)
a_rows <- if (nrow(j_a)) {
  # the nearest CENTRE per (point, year): distance from the point to that frame's centroid
  cen <- sf::st_geometry(ph)[match(j_a$airp_id, ph$airp_id)]
  j_a$dist <- as.numeric(sf::st_distance(sf::st_geometry(j_a), cen, by_element = TRUE))
  d <- sf::st_drop_geometry(j_a)
  do.call(rbind, lapply(split(d, list(d$point_id, d$photo_year), drop = TRUE), function(g) {
    b <- g[order(g$dist, g$airp_id), ][1, ]
    data.frame(point_id = b$point_id, source = "airphoto", year = as.integer(b$photo_year),
               date = format(as.Date(b$photo_date), "%Y-%m-%d"),
               # BCDC's ground_sample_distance is not metres (31 on 1:20,000 film, 0 on every 2012
               # digital frame), so it is not written into a column that says metres
               gsd_m = NA_real_,
               media = b$media, scale = b$scale, n_images = nrow(g), airp_id = as.character(b$airp_id))
  }))
}

out <- rbind(o_rows, a_rows)
# One row at least for EVERY sample point -- an uncovered point gets an empty source and n_images 0 --
# so a consumer can test the index for completeness against the sample, not just for agreement on
# the rows it happens to hold (a stale index after pilot -> full would otherwise pass).
none <- setdiff(design$point_id, out$point_id)
if (length(none))
  out <- rbind(out, data.frame(point_id = none, source = NA_character_, year = NA_integer_,
                               date = NA_character_, gsd_m = NA_real_, media = NA_character_,
                               scale = NA_character_, n_images = 0L, airp_id = NA_character_))
out <- merge(design, out, by = "point_id", sort = FALSE)
out <- out[order(out$point_id, out$source, out$year, method = "radix"), ]
utils::write.csv(out, file.path(cfg$dir_ref, "imagery.csv"), row.names = FALSE, na = "")

# --- coverage per source-year, and which earn a theme (the rule imagery_build-dated.R builds from) --
cov <- fp_acc_imagery_themes(out, n_pts)
cov$share <- round(100 * cov$share, 1)
message(sprintf("\n%d rows -> %s\ncoverage of %d points, by source and year:", nrow(out),
                file.path(cfg$dir_ref, "imagery.csv"), n_pts))
print(cov, row.names = FALSE)
