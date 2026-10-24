# review_render-sheets.R — one blind PNG contact sheet per sample point, for the model labeller (#145).
#
# The model labeller (research/landcover_accuracy.md, "Model labeller", pre-registered before any label)
# reads each point from a sheet rather than a QGIS project. A sheet shows the outlined 10 m cell in the
# DATED imagery the pre-registration lets the model see, and nothing else:
#   row 1  the Sentinel-2 same-season composites (chips_manifest.csv), 310 m around the cell, one fixed
#          stretch, 0-0.25 reflectance under a square root (forest sits near 0.03 and is black on a linear
#          one), so a brightness difference between years is a real one; pixels drawn unsmoothed, so the
#          10 m grid shows; the dashed square is row 2's window
#   row 2  the Esri Wayback capture nearest each endpoint, 120 m around the cell, warped from the build's
#          tile cache (wayback/built.csv: release, zoom, capture date), and the air photo epochs
#          (dated/airphoto_<year>.vrt) where they cover the point
# NOT the review project's Wayback chips: they are clipped to each point's Voronoi cell, so the nodata
# wedges would show where neighbouring sample points are, and change strata cluster. NOT the orthophoto:
# it comes from a private endpoint and stays out of what is sent to the model (decided at #145's gate).
# Panel titles pass fp_acc_sheet_title_ok(): source, date, resolution, nothing of the design.
#
# Blind by construction: sheets are named sheet_<k>.png over a fresh shuffle (never the review_id,
# which is in review order and carries the batch hint, #113), in batch_<NN>/ directories holding sheets
# only. The map back, sheet_map.csv (sheet, review_id, cell, batch), sits beside the batches, never
# inside one, and is FROZEN once labels exist: this script refuses to render over a raw/ that holds any.
# The labelling key is written beside the batches as key.md. Output is under
# data/<area>/accuracy/model/ (gitignored). RENDER_SEED pins the shuffle (default from the clock;
# recorded in render.json either way).
#
# usage: Rscript scripts/landcover_accuracy/review_render-sheets.R [area] [n_batch]
#        SHEETS_ONLY=5 ... renders the first 5 sheets into model_test/ to look at, and writes no map

suppressMessages({library(sf); library(terra)})
sf::sf_use_s2(FALSE)
source(here::here("scripts", "landcover_accuracy", "fp_accuracy.R"))

a       <- commandArgs(trailingOnly = TRUE)
area    <- if (!is.na(a[1])) a[1] else "necr"
n_batch <- if (!is.na(a[2])) as.integer(a[2]) else 40L
cfg     <- fp_acc_area(area)

dir_proj  <- fp_acc_review_dir(cfg)
n_only    <- as.integer(Sys.getenv("SHEETS_ONLY", NA))
dir_model <- file.path(cfg$dir_acc, if (is.na(n_only)) "model" else "model_test")
if (length(list.files(file.path(dir_model, c("raw", "transcripts")))))
  stop(dir_model, " holds model labels or transcripts: a re-render reshuffles the sheets, so they would point ",
       "at other points. (extract and import also refuse sheets that are not the images the agent saw.)",
       call. = FALSE)

key   <- fp_acc_review_key_read(file.path(cfg$dir_ref, "review_key.csv"))
if (is.null(key)) stop("no review_key.csv for ", area, call. = FALSE)
cells <- terra::vect(file.path(dir_proj, "cells.gpkg"))
if (!setequal(cells$review_id, key$review_id))
  stop("cells.gpkg and review_key.csv hold different review_ids: rebuild the review project", call. = FALSE)
m <- match(cells$review_id, key$review_id)
if (any(as.numeric(cells$cell) != key$cell[m])) stop("cells.gpkg disagrees with review_key.csv on cell", call. = FALSE)

# Sentinel-2: point_id-keyed manifest (kept outside the project, #111), read here and never shipped
man  <- utils::read.csv(file.path(cfg$dir_acc, "chips_manifest.csv"), stringsAsFactors = FALSE)
wins <- fp_acc_windows_read(file.path(cfg$dir_ref, "windows.csv"), cfg$primary_scenario)
s2_years  <- sort(unique(man$year[man$window == "same_season"]))
# Any measured window, not only NECR's first ones ("8", "8-9"): a redraw re-measures them (#148)
month_lab <- function(mo) paste(month.abb[as.integer(strsplit(mo, "-", fixed = TRUE)[[1]])], collapse = "-")
s2_title  <- function(y) sprintf("Sentinel-2 %d %s composite, 10 m", y,
                                 month_lab(wins$months[wins$window == "same_season" & wins$year == y]))

# Wayback: the release and zoom the build picked per point and endpoint (the BUILT manifest, which is what
# cells.gpkg's capture columns describe), fetched again unclipped through the build's own tile cache
dir_wb <- file.path(cfg$dir_acc, "wayback")
wb <- utils::read.csv(file.path(dir_wb, "built.csv"), stringsAsFactors = FALSE,
                      colClasses = c(release_id = "character"))
wb <- wb[wb$status == "built", ]
fp_acc_design_check(wb[!duplicated(wb$point_id), ], key, "wayback/built.csv")
wb_years <- sort(unique(wb$endpoint))
dir.create(file.path(dir_wb, "wms"), showWarnings = FALSE)
wb_panel <- function(r, e) {
  xml <- file.path(dir_wb, "wms", sprintf("%s_z%d.xml", r$release_id, r$zoom))
  writeLines(fp_acc_wayback_wms_xml(r$release_id, r$zoom, file.path(dir_wb, "tiles")), xml)
  tmp <- tempfile(fileext = ".tif"); on.exit(unlink(tmp), add = TRUE)
  suppressWarnings(sf::gdal_utils("warp", source = xml, destination = tmp,
                                  options = c("-t_srs", "EPSG:3005", "-te", as.vector(e)[c(1, 3, 2, 4)],
                                              "-ts", "480", "480", "-r", "bilinear", "-overwrite")))
  if (!file.exists(tmp)) return(NULL)
  x <- terra::rast(tmp)
  if (mean(rowSums(terra::values(x[[1:3]])) == 0) > 0.05) return(NULL)   # 404 tiles: no imagery here
  x[[1:3]] * 1   # arithmetic puts it in memory before the tempfile goes; terra::rast(x) would be an empty template
}

dated   <- sort(list.files(file.path(dir_proj, "dated"), pattern = "^airphoto_[0-9]{4}[.]vrt$"))
dated_r <- setNames(lapply(file.path(dir_proj, "dated", dated), terra::rast), dated)
dated_title <- function(f) sprintf("Air photo %s", sub("^airphoto_([0-9]{4})[.]vrt$", "\\1", f))

# 8-bit display of a crop; NULL when the window misses the raster or holds no data
crop_byte <- function(r, e, max_val, gamma = 1) {
  if (!terra::relate(terra::ext(r), e, "intersects")) return(NULL)
  x <- terra::crop(r, e, snap = "out")[[1:3]]
  v <- terra::values(x[[1]], mat = FALSE)
  if (all(is.na(v) | v == 0)) return(NULL)
  terra::clamp(x / max_val, 0, 1)^gamma * 255
}
draw_cell <- function(cell_v, lwd = 2) {
  terra::lines(cell_v, col = "white", lwd = lwd + 2)
  terra::lines(cell_v, col = "#FF2D2D", lwd = lwd)
}
panel <- function(img, title, e, cell_v, frame = NULL) {
  stopifnot(fp_acc_sheet_title_ok(title))
  if (is.null(img)) {
    plot.new(); plot.window(c(0, 1), c(0, 1)); rect(0, 0, 1, 1, col = "grey85", border = NA)
    text(0.5, 0.5, "no coverage", col = "grey30", cex = 1.3)
  } else {
    terra::plotRGB(img, r = 1, g = 2, b = 3, scale = 255, ext = e, mar = NA, axes = FALSE, colNA = "grey85",
                   smooth = FALSE)
    if (!is.null(frame)) terra::lines(frame, col = "white", lty = 2, lwd = 1)
    draw_cell(cell_v)
  }
  u <- par("usr")
  rect(u[1], u[4] - 0.12 * (u[4] - u[3]), u[2], u[4], col = grDevices::adjustcolor("black", 0.7), border = NA)
  text(u[1] + 0.02 * (u[2] - u[1]), u[4] - 0.06 * (u[4] - u[3]), title, adj = c(0, 0.5), col = "white",
       cex = 1.45, font = 2)
}

n_hi <- length(wb_years) + length(dated)
if (length(s2_years) > 4 || n_hi > 4) stop("a sheet holds 4 panels per row: ", length(s2_years),
                                          " Sentinel-2 and ", n_hi, " high-resolution sources", call. = FALSE)

seed <- as.integer(Sys.getenv("RENDER_SEED", as.integer(Sys.time()) %% 2147483647L))
plan <- fp_acc_sheet_plan(key$review_id, n_batch, seed)
plan$cell <- as.numeric(cells$cell[match(plan$review_id, cells$review_id)])   # the project's, checked against the key above
# The map, key and render record of any earlier render go BEFORE the first sheet is drawn: sheet names and
# batches depend only on the counter, so an aborted re-render would leave the old map beside new sheets
# and every check by name would still pass.
unlink(file.path(dir_model, c("sheet_map.csv", "render.json", "key.md")))
unlink(list.files(dir_model, pattern = "^batch_[0-9]{2}$", full.names = TRUE), recursive = TRUE)
dir.create(dir_model, recursive = TRUE, showWarnings = FALSE)
for (b in unique(plan$batch)) dir.create(file.path(dir_model, sprintf("batch_%02d", b)))

S2_HALF <- 155; HI_HALF <- 60
hdr <- "Label the outlined 10 m cell in 2017 and in 2023"
stopifnot(fp_acc_sheet_title_ok(hdr))
t0 <- Sys.time()
for (i in seq_len(if (is.na(n_only)) nrow(plan) else min(n_only, nrow(plan)))) {
  rid   <- plan$review_id[i]
  pid   <- key$point_id[key$review_id == rid]
  cv    <- cells[cells$review_id == rid]
  ctr   <- terra::geom(terra::centroids(cv))[1, c("x", "y")]
  e_s2  <- terra::ext(ctr[1] - S2_HALF, ctr[1] + S2_HALF, ctr[2] - S2_HALF, ctr[2] + S2_HALF)
  e_hi  <- terra::ext(ctr[1] - HI_HALF, ctr[1] + HI_HALF, ctr[2] - HI_HALF, ctr[2] + HI_HALF)
  frame <- terra::as.polygons(e_hi, crs = terra::crs(cv))

  s2 <- lapply(s2_years, function(y) {
    row <- man[man$point_id == pid & man$window == "same_season" & man$year == y, ]
    if (nrow(row) != 1) return(NULL)
    crop_byte(terra::rast(file.path(dir_proj, row$file)), e_s2, 0.25, gamma = 0.5)
  })
  hi <- lapply(wb_years, function(y) {
    r <- wb[wb$point_id == pid & wb$endpoint == y, ]
    if (nrow(r) != 1) return(list(NULL, "Esri Wayback: no capture"))
    img <- wb_panel(r, e_hi)
    list(if (!is.null(img)) terra::clamp(img, 0, 255),
         if (is.null(img)) "Esri Wayback: no capture" else
           paste("Esri Wayback captured", fp_acc_capture_label(r$capture_date, r$src_res)))
  })
  hi <- c(hi, lapply(dated, function(d) list(crop_byte(dated_r[[d]], e_hi, 255), dated_title(d))))

  f <- file.path(dir_model, sprintf("batch_%02d", plan$batch[i]), plan$sheet[i])
  grDevices::png(f, width = 1600, height = 860, bg = "white")
  layout(rbind(c(1, 1, 1, 1), 2:5, 6:9), heights = c(0.06, 0.47, 0.47))
  par(mar = c(0, 0, 0, 0)); plot.new()
  text(0.005, 0.5, hdr, adj = c(0, 0.5), cex = 1.5, font = 2)
  par(mar = c(0.3, 0.3, 0.3, 0.3))
  for (k in seq_along(s2_years)) panel(s2[[k]], s2_title(s2_years[k]), e_s2, cv, frame)
  for (k in seq_len(4 - length(s2_years))) plot.new()
  for (h in hi) panel(h[[1]], h[[2]], e_hi, cv)
  for (k in seq_len(4 - length(hi))) plot.new()
  grDevices::dev.off()
  if (i %% 50 == 0) message(sprintf("%d / %d sheets, %.1f min", i, nrow(plan),
                                    as.numeric(difftime(Sys.time(), t0, units = "mins"))))
}

if (!is.na(n_only)) { message("SHEETS_ONLY: ", n_only, " sheets in ", dir_model, ", no map written"); quit(save = "no") }
writeLines(fp_acc_labelling_key(), file.path(dir_model, "key.md"))
utils::write.csv(plan, file.path(dir_model, "sheet_map.csv"), row.names = FALSE)
fp_acc_sheet_dir_check(dir_model)
jsonlite::write_json(list(area = area, seed = seed, n_batch = n_batch, n_sheets = nrow(plan),
                          s2_years = s2_years, wayback_years = wb_years, dated = dated,
                          rendered_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")),
                     file.path(dir_model, "render.json"), auto_unbox = TRUE, pretty = TRUE)
message(sprintf("%d sheets in %d batches under %s (seed %d), %.1f min", nrow(plan), max(plan$batch),
                dir_model, seed, as.numeric(difftime(Sys.time(), t0, units = "mins"))))
