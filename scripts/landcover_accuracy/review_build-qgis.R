# review_build-qgis.R — the QGIS project a reviewer labels the accuracy sample in (#93).
#
# Phase 6 of #93. Built with rfp (method in packages), as a restoration-template project holding:
#   Reference labels      the sample points + empty label fields, with the constrained form in
#                         reference/<area>/labels_form.qml (IO class codes only; "cannot label" is
#                         a status, never a class)
#   Change patches        the published transition layer, with its in_* flags
#   Reference imagery     one layer per window-year of dated Sentinel-2 chips, when chip_build-composite.R has run
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
if (!file.exists(pat_gpkg)) {
  p <- sf::st_read(file.path(cfg$dir_out, "floodplain_landcover.gpkg"), layer = lyr, quiet = TRUE,
                   promote_to_multi = FALSE)
  sf::st_write(sf::st_transform(p, REVIEW_EPSG), pat_gpkg, layer = "patches", quiet = TRUE)
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
if (!length(vrts)) message("no chips yet: run chip_build-composite.R once the windows are measured (drift#92)")

message("project: ", qgs)
