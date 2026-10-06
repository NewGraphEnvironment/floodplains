# review_build-qgis.R — the QGIS project a reviewer labels the accuracy sample in (#93).
#
# Phase 6 of #93. Built with rfp (method in packages), as a restoration-template project holding:
#   Reference labels      the sample points + empty label fields, with the constrained form in
#                         reference/<area>/labels_form.qml (IO class codes only; "cannot label" is
#                         a status, never a class)
#   Change patches        the published transition layer, with its in_* flags
#   Reference imagery     one layer per window-year of dated Sentinel-2 chips, when chip_build-composite.R has run
#   Reference imagery - dated   one layer per themed orthophoto / digital air photo epoch (#103), when
#                         imagery_build-dated.R has run (sharper than the chips, and dated, unlike the basemaps)
#   FWA wetlands / rivers / lakes, and Esri / Google / Bing   context; the basemaps are UNDATED
#
# The reviewer edits labels.gpkg INSIDE the project -- a working copy. reference/<area>/sample.gpkg
# is the committed design record and is never edited; labels_export.R carries labels back out by
# point_id into reference/<area>/labels.csv, the committed record every number regenerates from.
#
# Re-running is safe: an existing project is kept, an existing labels.gpkg is never rewritten, and
# a sample that has grown (pilot -> full, same seed) only APPENDS the new points. Chip layers are
# added once per window-year.
#
# MAP THEMES (#103), rewritten on every run so they always match the layers present: "Review" (the
# labels, the change patches, FWA context, Esri), and one theme per reference imagery layer -- the
# base vectors plus that one image, with nothing else drawn under it. A theme hides a layer by
# ABSENCE (rfp's declared membership), so switching theme is how a reviewer flips between epochs.
#
# usage: Rscript scripts/landcover_accuracy/review_build-qgis.R [area]

suppressMessages({library(sf)})
sf::sf_use_s2(FALSE)
source(here::here("scripts", "landcover_accuracy", "fp_accuracy.R"))

# The review layers are DISPLAY copies in BC Albers: rfp's templates carry EPSG:3005 and 3857 only, and
# rfp refuses a layer whose CRS no project layer uses (it cannot copy the <srs> block). The design
# stays on the transition grid in sample.gpkg; identity is checked on stratum/cell/map_class, never
# on geometry, so reprojecting the working copy loses nothing.
REVIEW_EPSG <- 3005L

area <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(area)) area <- "necr"
cfg  <- fp_acc_area(area)

dir_proj <- fp_acc_review_dir(cfg)
qgs      <- file.path(dir_proj, paste0(basename(dir_proj), ".qgs"))
qml_form <- file.path(cfg$dir_ref, "labels_form.qml")
qml_rgb  <- here::here("scripts", "landcover_accuracy", "chip_rgb.qml")
qml_dated   <- here::here("scripts", "landcover_accuracy", "dated_rgb.qml")
qml_dated_a <- here::here("scripts", "landcover_accuracy", "dated_rgba.qml")
if (!file.exists(qml_form)) stop("no ", qml_form, call. = FALSE)

# --- project ----------------------------------------------------------------------------------
if (!file.exists(qgs) && dir.exists(dir_proj))
  stop(dir_proj, " exists but holds no project (rfp_project_create refuses an existing directory). ",
       "Move it aside and re-run; chips are built after the project, into it.", call. = FALSE)
if (!file.exists(qgs)) {
  lyrs <- rfp::rfp_project_layers("bcrestoration_mobile")
  ctx  <- lyrs[lyrs$source_layer %in% c("whse_basemapping.fwa_wetlands_poly",
                                         "whse_basemapping.fwa_rivers_poly",
                                         "whse_basemapping.fwa_lakes_poly"), ]
  rfp::rfp_project_create(basename(dir_proj), watershed_groups = cfg$watershed_group,
                          template = "bcrestoration_mobile", path_out = dirname(dir_proj),
                          layer_config = ctx, forms = character(0), themes = character(0),
                          services = c("esri_satellite", "google_satellite", "bing_aerial"))
}
tree_names <- function() {
  q <- xml2::read_xml(qgs)
  xml2::xml_attr(xml2::xml_find_all(q, "//layer-tree-layer"), "name")
}

# --- labelling key (#111) -----------------------------------------------------------------------
# The pre-registered key, copied from research/landcover_accuracy.md on every run, so the project never
# carries a stale or hand-edited copy.
writeLines(fp_acc_labelling_key(), file.path(dir_proj, "labelling_key.md"))

# --- labels working copy ----------------------------------------------------------------------
FP_ACC_LABEL_FIELDS <- c("ref_from", "ref_to", "label_status", "confidence", "imagery", "note",
                         "reviewer", "labelled_on")
smp <- sf::st_transform(sf::st_read(file.path(cfg$dir_ref, "sample.gpkg"), layer = "sample", quiet = TRUE),
                       REVIEW_EPSG)
blank <- function(x) {
  x$ref_from <- NA_integer_; x$ref_to <- NA_integer_
  x$label_status <- NA_character_; x$confidence <- NA_character_; x$imagery <- NA_character_
  x$note <- NA_character_; x$reviewer <- NA_character_; x$labelled_on <- as.Date(NA)
  x
}
lab_gpkg <- file.path(dir_proj, "labels.gpkg")
if (!file.exists(lab_gpkg)) {
  sf::st_write(blank(smp), lab_gpkg, layer = "labels", quiet = TRUE)
  message("labels.gpkg: ", nrow(smp), " points")
} else {
  have <- sf::st_read(lab_gpkg, layer = "labels", quiet = TRUE)
  if (!all(FP_ACC_LABEL_FIELDS %in% names(have)))
    stop(lab_gpkg, " is missing label fields; refusing to touch it", call. = FALSE)
  gone <- setdiff(have$point_id, smp$point_id)
  if (length(gone)) stop(length(gone), " labelled points are not in sample.gpkg (",
                         paste(utils::head(gone, 3), collapse = ", "), "): the sample was redrawn ",
                         "with a different seed or grid; labels would be scored against the wrong map",
                         call. = FALSE)
  fp_acc_design_check(have, smp, lab_gpkg)
  new <- smp[!smp$point_id %in% have$point_id, ]
  if (nrow(new)) {
    sf::st_write(blank(new)[, names(have)], lab_gpkg, layer = "labels", append = TRUE, quiet = TRUE)
    message("labels.gpkg: appended ", nrow(new), " new points (", nrow(have), " kept as they were)")
  } else message("labels.gpkg: unchanged (", nrow(have), " points)")
}

# --- change patches ---------------------------------------------------------------------------
pat_gpkg <- file.path(dir_proj, "patches.gpkg")
lyr <- sprintf("transition_%s_%d_%d", cfg$primary_scenario, cfg$change_interval[1], cfg$change_interval[2])
src_gpkg <- file.path(cfg$dir_out, "floodplain_landcover.gpkg")
# A display copy, rebuilt whenever its attributes differ from the published layer's -- a re-tag
# (fire_tag.R: in_wetland #95, in_fire_prior #103) or a step 3 re-run changes what the reviewer should
# see. Compared by content, keyed (name_basin, patch_id). The project references the file by path, so
# replacing it keeps the layer; QGIS holds a gpkg in WAL mode, so the sidecars go with it.
attr_table <- function(gpkg, layer) {
  x <- sf::st_drop_geometry(sf::st_read(gpkg, layer = layer, quiet = TRUE, promote_to_multi = FALSE))
  x <- x[order(x[["name_basin"]], x[["patch_id"]]), sort(names(x)), drop = FALSE]
  rownames(x) <- NULL
  lapply(x, as.character)
}
p <- sf::st_read(src_gpkg, layer = lyr, quiet = TRUE, promote_to_multi = FALSE)
if (!file.exists(pat_gpkg) || !identical(attr_table(src_gpkg, lyr), attr_table(pat_gpkg, "patches"))) {
  unlink(paste0(pat_gpkg, c("", "-wal", "-shm", "-journal")))
  sf::st_write(sf::st_transform(p, REVIEW_EPSG), pat_gpkg, layer = "patches", quiet = TRUE)
  message("patches.gpkg: written from ", lyr, " (", ncol(p) - 1L, " columns)")
}

have_lyrs <- tree_names()
if (!"Reference labels" %in% have_lyrs)
  rfp::rfp_qgs_vector_add(qgs, gpkg = "labels.gpkg", table = "labels", name = "Reference labels",
                          qml = qml_form, geometry = "Point", group = "Project Specific",
                          position = "top")
if (!"Change patches" %in% have_lyrs)
  rfp::rfp_qgs_vector_add(qgs, gpkg = "patches.gpkg", table = "patches", name = "Change patches",
                          geometry = "Polygon", group = "Project Specific", position = "bottom")

# --- reference imagery ------------------------------------------------------------------------
vrts <- list.files(file.path(dir_proj, "chips"), pattern = "\\.vrt$", full.names = FALSE)
for (v in sort(vrts)) {
  nm <- paste("S2", sub("\\.vrt$", "", sub("_", " ", v)))
  if (nm %in% tree_names()) next
  rfp::rfp_qgs_raster_add(qgs, raster = file.path("chips", v), name = nm, qml = qml_rgb,
                          stretch = "none", group = "Reference imagery", visible = FALSE)
}
if (!length(vrts)) message("no chips yet: run chip_build-composite.R once reference/<area>/windows.csv exists (window_count-clear.R derive)")

# dated orthophoto / air photo epochs (#103): dated/<source>_<year>.vrt -> "Orthophoto 2021"
dated <- sort(list.files(file.path(dir_proj, "dated"), pattern = "^(orthophoto|airphoto)_[0-9]{4}[.]vrt$"))
# The dated VRTs were built for the points imagery.csv lists. After a redraw or a larger sample they
# describe other points, so they are not offered (and any already in the project are removed below)
# until imagery_index-dated.R and imagery_build-dated.R have been re-run.
img_csv <- file.path(cfg$dir_ref, "imagery.csv")
if (length(dated) && (!file.exists(img_csv) ||
    !setequal(unique(utils::read.csv(img_csv, stringsAsFactors = FALSE)$point_id), smp$point_id))) {
  message("dated layers skipped: ", img_csv, " does not list exactly sample.gpkg's points -- re-run ",
          "imagery_index-dated.R and imagery_build-dated.R")
  dated <- character(0)
}
dated_name <- function(v) {
  p <- strsplit(sub("[.]vrt$", "", v), "_", fixed = TRUE)[[1]]
  paste(c(orthophoto = "Orthophoto", airphoto = "Air photo")[[p[1]]], p[2])
}
# a dated layer whose VRT imagery_build-dated.R removed (its epoch no longer earns a theme) goes too
orphan <- setdiff(grep("^(Orthophoto|Air photo) [0-9]{4}$", tree_names(), value = TRUE),
                vapply(dated, dated_name, ""))
# the layer AND its theme: rfp_qgs_theme_set replaces the themes it is given and leaves the rest
for (nm in orphan) {
  rfp::rfp_qgs_layer_rm(qgs, nm)
  if (nm %in% rfp::rfp_qgs_theme_names(qgs)) rfp::rfp_qgs_theme_rm(qgs, themes = nm)
}
for (v in dated) {
  nm <- dated_name(v)
  if (nm %in% tree_names()) next
  # air photos are RGBA (fly_georef masks the frame border); orthophotos are RGB. rfp opens the raster,
  # and the orthophoto VRT's sources are the private catalogue's remote tiles: URLs quieted.
  fp_acc_quiet_urls(
    rfp::rfp_qgs_raster_add(qgs, raster = file.path("dated", v), name = nm,
                            qml = if (startsWith(v, "airphoto")) qml_dated_a else qml_dated,
                            stretch = "none", group = "Reference imagery - dated", visible = FALSE),
    paste("adding", nm))
}

# --- map themes -------------------------------------------------------------------------------
have  <- tree_names()
base  <- intersect(c("Reference labels", "Change patches", "Watershed group boundary", "Wetland", "Lake"), have)
imgs  <- c(paste("S2", sub("\\.vrt$", "", sub("_", " ", sort(vrts)))), vapply(dated, dated_name, ""))
imgs  <- intersect(imgs, have)
th <- rbind(data.frame(theme = "Review", layer = c(base, intersect("Esri Satellite", have))),
            do.call(rbind, lapply(imgs, function(l) data.frame(theme = l, layer = c(base, l)))))
rfp::rfp_qgs_theme_set(qgs, th, on_missing_layer = "error", backup = FALSE)
message("themes: Review + ", length(imgs), " imagery (", paste(imgs, collapse = ", "), ")")

message("project: ", qgs)
