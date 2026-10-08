# review_build-qgis.R — the QGIS project a reviewer labels the accuracy sample in (#93).
#
# Phase 6 of #93. Built with rfp (method in packages), as a restoration-template project holding:
#   Reference labels      the sample points + empty label fields, with the constrained form in
#                         reference/<area>/labels_form.qml (IO class codes only; "cannot label" is
#                         a status, never a class)
#   Sample cells          the 10 m cell each label is about (#111)
#   Change patches        the published transition layer, with its in_* flags -- IO's answer, so in
#                         its own "After labelling - change patches" theme only, never a labelling one
#   Reference imagery     one layer per window-year of dated Sentinel-2 chips, when chip_build-composite.R has run
#   Reference imagery - dated   one layer per themed orthophoto / digital air photo epoch (#103), when
#                         imagery_build-dated.R has run (sharper than the chips, and dated, unlike the basemaps)
#   FWA wetlands / rivers / lakes, and Esri / Google / Bing   context; the basemaps are UNDATED
#
# The reviewer edits labels.gpkg INSIDE the project -- a working copy. reference/<area>/sample.gpkg
# is the committed design record and is never edited; labels_export.R carries labels back out by
# point_id into reference/<area>/labels.csv, the committed record every number regenerates from.
#
# Re-running is safe: an existing project is kept, a labels.gpkg holding any label is never rewritten
# (one with none is: pre-#111 schema, or stale imagery coverage), and
# a sample that has grown (pilot -> full, same seed) only APPENDS the new points. Chip layers are
# added once per window-year.
#
# MAP THEMES (#103, #111), rewritten on every run so they always match the layers present, named so the
# drop-down reads in working order (see NAMES ARE THE INTERFACE below): "0 Start" (points, cells,
# boundary, lakes, Esri), one theme per reference imagery year, and "9 After labelling" (adds IO's change
# patches and FWA wetlands, which no labelling theme shows). An imagery theme is the base vectors plus that one image, with
# nothing else drawn under it. A theme hides a layer by
# ABSENCE (rfp's declared membership), so switching theme is how a reviewer flips between epochs.
#
# SECOND LABELLER (#111): REVIEWER=b builds a separate project, <area>_lulc_review_b, holding only the
# fixed subset (review_key.csv `second`) and none of labeller A's labels, so B labels blind to A as well
# as to the map. Its imagery is hard-linked from A's project (no extra disk; rfp needs the files inside).
#
# usage: Rscript scripts/landcover_accuracy/review_build-qgis.R [area]
#        REVIEWER=b Rscript scripts/landcover_accuracy/review_build-qgis.R [area]

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

reviewer <- Sys.getenv("REVIEWER", "a")
if (!reviewer %in% c("a", "b")) stop("REVIEWER must be a or b, got ", reviewer, call. = FALSE)
dir_proj_a <- fp_acc_review_dir(cfg)
dir_proj <- if (reviewer == "b") paste0(dir_proj_a, "_b") else dir_proj_a
qgs      <- file.path(dir_proj, paste0(basename(dir_proj), ".qgs"))
qml_form <- file.path(cfg$dir_ref, "labels_form.qml")
qml_rgb  <- here::here("scripts", "landcover_accuracy", "chip_rgb.qml")
qml_dated   <- here::here("scripts", "landcover_accuracy", "dated_rgb.qml")
qml_dated_a <- here::here("scripts", "landcover_accuracy", "dated_rgba.qml")
if (!file.exists(qml_form)) stop("no ", qml_form, call. = FALSE)

# NAMES ARE THE INTERFACE (#111). The reviewer works point by point: open it, judge the first year, judge
# the last year, fill the form, then (only then) look at what IO said. So:
#   - layer names say what a layer is FOR, not what file it came from;
#   - every theme name starts with a sort key, and QGIS lists themes alphabetically, so the drop-down
#     reads in working order: "0 Start", then each imagery year oldest to newest, then "9 After labelling";
#   - an imagery theme names its year, its source and (Sentinel-2) its composite months, and the two
#     endpoint years say FIRST YEAR / LAST YEAR, since those are the two labels the form asks for.
LYR_POINTS  <- "Points to label"
LYR_CELLS   <- "Cell being labelled (10 m)"
LYR_PATCHES <- "Change patches"
THEME_START <- "0 Start - Esri satellite (undated, for finding your way)"
FP_ACC_AFTER_THEME <- "9 After labelling - IO change patches and FWA wetlands"
ends <- sort(as.integer(cfg$change_interval))
endpoint_tag <- function(y) if (y == ends[1]) " - FIRST YEAR" else if (y == ends[2]) " - LAST YEAR" else ""
months_lab <- function(m) paste(month.abb[as.integer(strsplit(as.character(m), "-", fixed = TRUE)[[1]])],
                                collapse = "-")
win_csv <- file.path(cfg$dir_ref, "windows.csv")
wins <- if (file.exists(win_csv)) utils::read.csv(win_csv, stringsAsFactors = FALSE) else NULL
s2_name <- function(v) {                       # chips/<window>_<year>.vrt
  b <- sub("[.]vrt$", "", v); y <- as.integer(sub(".*_", "", b)); w <- sub("_[0-9]{4}$", "", b)
  m <- if (!is.null(wins)) wins$months[wins$window == w & wins$year == y] else character(0)
  sprintf("%d Sentinel-2%s%s", y, if (length(m)) paste0(", ", months_lab(m[1]), " composite") else "",
          endpoint_tag(y))
}
# dated/wayback_<year>.vrt (#115): per point, the Esri capture nearest that year, which varies by point
wb_name <- function(v) {
  y <- as.integer(sub("^wayback_([0-9]{4})[.]vrt$", "\\1", v))
  sprintf("%d Esri capture (nearest per point)%s", y, endpoint_tag(y))
}
WB_LAYER_RE <- "^[0-9]{4} Esri capture [(]nearest per point[)]"
dated_name <- function(v) {                    # dated/<source>_<year>.vrt
  p <- strsplit(sub("[.]vrt$", "", v), "_", fixed = TRUE)[[1]]
  sprintf("%s %s (dated)%s", p[2], c(orthophoto = "orthophoto", airphoto = "air photo")[[p[1]]],
          endpoint_tag(as.integer(p[2])))
}

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
if (reviewer == "b") {
  # B sees the same imagery as A. Built by chip_build-composite.R / imagery_build-dated.R into A's project.
  # Wayback chips (#115) are pruned too: wayback_build-chips.R removes a chip A no longer wants, and a
  # copy left in B would still sit under B's VRT directory.
  for (d in c("chips", "dated")) fp_acc_link_tree(file.path(dir_proj_a, d), file.path(dir_proj, d),
                                                  prune = if (d == "dated") "^wayback_" else NULL)
}
tree_names <- function() {
  q <- xml2::read_xml(qgs)
  xml2::xml_attr(xml2::xml_find_all(q, "//layer-tree-layer"), "name")
}

# --- labelling key (#111) -----------------------------------------------------------------------
# The pre-registered key, copied from research/landcover_accuracy.md on every run, so the project never
# carries a stale or hand-edited copy.
writeLines(fp_acc_labelling_key(), file.path(dir_proj, "labelling_key.md"))

# --- review key + blind labels working copy (#111) -------------------------------------------
# The reviewer labels an opaque review_id, never a point_id: drift's ids are `<stratum>_<k>`, so the id
# alone would tell the reviewer the stratum. reference/<area>/review_key.csv maps the id back, and the
# working copy carries no design column at all -- blind by construction, not by hidden fields.
FP_ACC_LABEL_FIELDS <- c("ref_from", "ref_to", "label_status", "confidence", "imagery", "note",
                         "reviewer", "labelled_on")
design <- jsonlite::read_json(file.path(cfg$dir_ref, "design.json"))
smp <- sf::st_transform(sf::st_read(file.path(cfg$dir_ref, "sample.gpkg"), layer = "sample", quiet = TRUE),
                       REVIEW_EPSG)
key_csv <- file.path(cfg$dir_ref, "review_key.csv")
key <- fp_acc_review_key(sf::st_drop_geometry(smp), design$seed, unlist(design$rng_kind),
                         fp_acc_review_key_read(key_csv))
key <- fp_acc_second_subset(key, design$seed, unlist(design$rng_kind))
utils::write.csv(key, key_csv, row.names = FALSE)
smp_design <- sf::st_drop_geometry(smp)   # the whole sample, for design checks, before any B subset
if (reviewer == "b") {
  smp <- smp[smp$point_id %in% key$point_id[key$second], ]   # B's project holds the subset only
  message("reviewer b: ", nrow(smp), " points (the second-labeller subset)")
}
key_here <- key[key$point_id %in% smp$point_id, ]

# Which dated imagery covers each point (imagery.csv, #103), so the reviewer knows which themes are
# worth opening. Only epochs the project actually carries a theme for (a dated/<source>_<year>.vrt):
# imagery.csv lists every epoch back to the 1970s, and naming one the reviewer cannot open is noise.
# Text only: source and year, never an href. Refreshed while the working copy holds no label; once
# labelling has started the working copy is never rewritten.
img_csv <- file.path(cfg$dir_ref, "imagery.csv")
cover <- stats::setNames(rep(NA_character_, nrow(smp)), smp$point_id)
avail <- sub("_", " ", sub("[.]vrt$", "", list.files(file.path(dir_proj, "dated"),
                                                      pattern = "^(orthophoto|airphoto)_[0-9]{4}[.]vrt$")))
if (file.exists(img_csv)) {
  im <- utils::read.csv(img_csv, colClasses = c(point_id = "character"), stringsAsFactors = FALSE)
  # Checked against the design before it is joined by point_id: after a redraw imagery.csv describes
  # other cells under the same ids, and their coverage would be baked into the working copy.
  fp_acc_design_check(im[!duplicated(im$point_id), ], smp_design, img_csv)
  im <- im[!is.na(im$source) & nzchar(im$source) & paste(im$source, im$year) %in% avail, ]
  if (nrow(im)) {
    lbl <- tapply(paste(im$source, im$year), im$point_id, function(v) paste(sort(unique(v)), collapse = "; "))
    cover[names(lbl)] <- lbl
  }
}
blind <- function(pts) fp_acc_blind_points(pts, key, cover)
lab_gpkg <- file.path(dir_proj, "labels.gpkg")
if (file.exists(lab_gpkg) && !"review_id" %in% names(sf::st_read(lab_gpkg, layer = "labels", quiet = TRUE))) {
  # Pre-#111 working copy: point_id and the design in plain sight. Replaced only if nobody has labelled
  # in it -- a label made seeing the map's answer is not a label this design can use, but it is still
  # somebody's work, and deleting it is a decision for a person.
  old <- sf::st_read(lab_gpkg, layer = "labels", quiet = TRUE)
  if (any(!is.na(old$label_status) & nzchar(trimws(old$label_status))))
    stop(lab_gpkg, " is a pre-#111 (unblinded) working copy holding labels; refusing to replace it. ",
         "Move it aside deliberately.", call. = FALSE)
  unlink(paste0(lab_gpkg, c("", "-wal", "-shm", "-journal")))
  for (nm in intersect(c("Reference labels", "Points to label"), tree_names())) rfp::rfp_qgs_layer_rm(qgs, nm)
  message("labels.gpkg: replaced the unlabelled pre-#111 working copy with the blind schema")
}
if (file.exists(lab_gpkg)) {
  have0 <- sf::st_read(lab_gpkg, layer = "labels", quiet = TRUE)
  unlabelled <- !any(!is.na(have0$label_status) & nzchar(trimws(have0$label_status)))
  stale_cover <- !identical(unname(cover[key$point_id[match(have0$review_id, key$review_id)]]),
                            as.character(have0$dated_imagery))
  if (unlabelled && stale_cover) {
    unlink(paste0(lab_gpkg, c("", "-wal", "-shm", "-journal")))
    message("labels.gpkg: no label yet and the dated-imagery coverage changed -- rewritten")
  }
}
if (!file.exists(lab_gpkg)) {
  sf::st_write(blind(smp), lab_gpkg, layer = "labels", quiet = TRUE)
  message("labels.gpkg: ", nrow(smp), " points, blind")
} else {
  have <- sf::st_read(lab_gpkg, layer = "labels", quiet = TRUE)
  if (!all(FP_ACC_LABEL_FIELDS %in% names(have)))
    stop(lab_gpkg, " is missing label fields; refusing to touch it", call. = FALSE)
  fp_acc_unblind(sf::st_drop_geometry(have), key)   # every id keyed, every cell the key's
  new <- smp[!key$review_id[match(smp$point_id, key$point_id)] %in% have$review_id, ]
  if (nrow(new)) {
    sf::st_write(blind(new)[, names(have)], lab_gpkg, layer = "labels", append = TRUE, quiet = TRUE)
    message("labels.gpkg: appended ", nrow(new), " new points (", nrow(have), " kept as they were)")
  } else message("labels.gpkg: unchanged (", nrow(have), " points)")
}
leak <- fp_acc_blind_leaks(names(sf::st_read(lab_gpkg, layer = "labels", quiet = TRUE)))
if (length(leak)) stop("labels.gpkg carries design column(s) ", paste(leak, collapse = ", "),
                       ": the review would not be blind", call. = FALSE)

# chips/manifest.csv maps point_id -> chip; it moved out of the project (chip_build-composite.R), and an
# old copy left in the folder would hand the reviewer the stratum of every point.
old_man <- file.path(dir_proj, "chips", "manifest.csv")
if (file.exists(old_man)) {
  new_man <- file.path(cfg$dir_acc, "chips_manifest.csv")
  if (!file.exists(new_man)) file.copy(old_man, new_man)
  unlink(old_man)
  message("chips/manifest.csv moved out of the project to ", new_man)
}

# --- sample cells (#111) ----------------------------------------------------------------------
# The label is about one 10 m cell, and a point on a 0.5 m orthophoto gives no sense of the square being
# judged. Each cell is rebuilt from its number on the design grid (design.json), keyed by review_id only,
# and drawn in the review CRS. Rewritten when the keyed set changes (a grown sample).
cells_gpkg <- file.path(dir_proj, "cells.gpkg")
grid <- terra::rast(nrows = design$dims[[1]], ncols = design$dims[[2]],
                    xmin = design$extent[[1]], xmax = design$extent[[2]],
                    ymin = design$extent[[3]], ymax = design$extent[[4]], crs = design$crs)
fp_acc_cell_squares <- function(key, grid) {
  xy <- terra::xyFromCell(grid, key$cell); h <- terra::res(grid) / 2
  sq <- lapply(seq_len(nrow(xy)), function(i) sf::st_polygon(list(rbind(
    c(xy[i, 1] - h[1], xy[i, 2] - h[2]), c(xy[i, 1] + h[1], xy[i, 2] - h[2]),
    c(xy[i, 1] + h[1], xy[i, 2] + h[2]), c(xy[i, 1] - h[1], xy[i, 2] + h[2]),
    c(xy[i, 1] - h[1], xy[i, 2] - h[2])))))
  sf::st_sf(review_id = key$review_id, geometry = sf::st_sfc(sq, crs = terra::crs(grid)))
}
# The Esri capture under each cell in each "<year> Esri capture" theme (#115), as read-only text the
# cells layer labels: capture_<year> = "2017-06-11, 0.31 m". Taken from what wayback_build-chips.R BUILT
# (its manifest, outside the project), so it describes the image on screen. The manifest is keyed by
# review_id and carries point_id; both are checked against the key before a column is written.
wb_ok <- function() {
  man <- file.path(cfg$dir_acc, "wayback", "built.csv")
  if (!file.exists(man) || !length(list.files(file.path(dir_proj, "dated"), pattern = "^wayback_[0-9]{4}[.]vrt$")))
    return(NULL)
  w <- tryCatch(fp_acc_wayback_read(file.path(cfg$dir_ref, "wayback.csv"), smp_design, cfg$change_interval),
                error = function(cnd) { message("Esri capture layers skipped: ", conditionMessage(cnd)); NULL })
  if (is.null(w)) return(NULL)
  b <- utils::read.csv(man, stringsAsFactors = FALSE, colClasses = c(release_id = "character", capture_date = "character"))
  # The manifest lists every point the build ran for. Voronoi clips depend on the whole point set, so a
  # build for an earlier sample has chips that cover the new points with a neighbour's capture.
  if (!"status" %in% names(b) || nrow(b) != nrow(w) ||
      !setequal(paste(b$point_id, b$endpoint), paste(w$point_id, w$endpoint))) {
    message("Esri capture layers skipped: ", man, " was not built for this sample -- re-run wayback_build-chips.R")
    return(NULL)
  }
  # ...and for this sample's CELLS: a redraw keeps the ids and moves the points (the manifest lives
  # outside the project, so it may carry the design columns)
  bad_design <- inherits(tryCatch(fp_acc_design_check(b, smp_design, man), error = identity), "error")
  k <- key$point_id[match(b$review_id, key$review_id)]
  if (bad_design || anyNA(k) || any(k != b$point_id)) {
    message("Esri capture layers skipped: ", man, " disagrees with the review key -- re-run wayback_build-chips.R")
    return(NULL)
  }
  wm <- w[match(paste(b$point_id, b$endpoint), paste(w$point_id, w$endpoint)), ]
  if (!identical(ifelse(is.na(wm$release_id), "", wm$release_id), ifelse(is.na(b$release_id), "", b$release_id))) {
    message("Esri capture layers skipped: the built chips are not wayback.csv's choice -- re-run wayback_build-chips.R")
    return(NULL)
  }
  b[b$status == "built", ]
}
wb_built <- wb_ok()
# `cell` rides along (labels.gpkg already carries it, so it is not a leak): the squares are built from it,
# and without it a redraw that kept every review_id would leave the old squares in place
cells_want <- fp_acc_cell_squares(key_here, grid)
cells_want$cell <- as.numeric(key_here$cell)
if (!is.null(wb_built))
  cells_want <- cbind(cells_want, fp_acc_capture_columns(wb_built, key_here$review_id, cfg$change_interval)[, -1, drop = FALSE])
cells_attr <- function(x) { x <- sf::st_drop_geometry(x); x <- x[order(x$review_id), sort(names(x)), drop = FALSE]
                            rownames(x) <- NULL; lapply(x, as.character) }
# cells.gpkg is read-only display: rewritten whenever its keyed set OR its capture columns differ
if (!file.exists(cells_gpkg) ||
    !identical(cells_attr(sf::st_read(cells_gpkg, layer = "cells", quiet = TRUE)), cells_attr(cells_want))) {
  unlink(paste0(cells_gpkg, c("", "-wal", "-shm", "-journal")))
  sf::st_write(sf::st_transform(cells_want, REVIEW_EPSG), cells_gpkg, layer = "cells", quiet = TRUE)
  message("cells.gpkg: ", nrow(key_here), " sample cells", if (!is.null(wb_built)) ", with Esri capture dates" else "")
}
cells_back <- sf::st_read(cells_gpkg, layer = "cells", quiet = TRUE)
leak <- fp_acc_blind_leaks(names(cells_back))
if (length(leak)) stop("cells.gpkg carries design column(s) ", paste(leak, collapse = ", "), call. = FALSE)
if (!identical(cells_attr(cells_back), cells_attr(cells_want)))
  stop("cells.gpkg does not read back as written", call. = FALSE)

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
# Layers named before the rename (#111) are dropped and re-added under the new names; their files are the
# same, so nothing labelled is touched.
old_names <- c("Reference labels", "Sample cells",
               grep("^S2 |^(Orthophoto|Air photo) [0-9]{4}$", have_lyrs, value = TRUE))
for (nm in intersect(old_names, have_lyrs)) rfp::rfp_qgs_layer_rm(qgs, nm)
have_lyrs <- tree_names()
if (!LYR_POINTS %in% have_lyrs)
  rfp::rfp_qgs_vector_add(qgs, gpkg = "labels.gpkg", table = "labels", name = LYR_POINTS,
                          qml = qml_form, geometry = "Point", group = "Project Specific",
                          position = "top")
if (!LYR_CELLS %in% have_lyrs)
  rfp::rfp_qgs_vector_add(qgs, gpkg = "cells.gpkg", table = "cells", name = LYR_CELLS,
                          qml = here::here("scripts", "landcover_accuracy", "cells_outline.qml"),
                          geometry = "Polygon", group = "Project Specific", position = "top")
# A layer is added once, so a later qml edit would never reach it: restyle from the committed qml on
# every run (rfp checks the qml's fields against the gpkg).
rfp::rfp_qgs_style_set(qgs, LYR_POINTS, qml_form, backup = FALSE)
rfp::rfp_qgs_style_set(qgs, LYR_CELLS, here::here("scripts", "landcover_accuracy", "cells_outline.qml"),
                       backup = FALSE)
# Change patches are IO's answer: hidden in the layer tree (a project opens with the tree's state, before
# anyone picks a theme) and in no theme but the after-labelling one. An existing project that has them
# checked gets them re-added hidden.
tree_checked <- function(name) {
  n <- xml2::xml_find_all(xml2::read_xml(qgs), sprintf("//layer-tree-layer[@name='%s']", name))
  length(n) > 0 && any(xml2::xml_attr(n, "checked") == "Qt::Checked")
}
if ("Change patches" %in% have_lyrs && tree_checked("Change patches")) rfp::rfp_qgs_layer_rm(qgs, "Change patches")
# The template's FWA Wetland layer is checked too, and rfp has no visibility setter: uncheck its tree node
# directly. Only the `checked` attribute of that one node changes.
if (tree_checked("Wetland")) {
  qx <- xml2::read_xml(qgs)
  for (n in xml2::xml_find_all(qx, "//layer-tree-layer[@name='Wetland']")) xml2::xml_set_attr(n, "checked", "Qt::Unchecked")
  xml2::write_xml(qx, qgs)
}
if (!"Change patches" %in% tree_names())
  rfp::rfp_qgs_vector_add(qgs, gpkg = "patches.gpkg", table = "patches", name = "Change patches",
                          geometry = "Polygon", group = "Project Specific", position = "bottom",
                          visible = FALSE, themes = character(0))

# --- reference imagery ------------------------------------------------------------------------
vrts <- list.files(file.path(dir_proj, "chips"), pattern = "\\.vrt$", full.names = FALSE)
for (v in sort(vrts)) {
  nm <- s2_name(v)
  if (nm %in% tree_names()) next
  rfp::rfp_qgs_raster_add(qgs, raster = file.path("chips", v), name = nm, qml = qml_rgb,
                          stretch = "none", group = "Reference imagery", visible = FALSE)
}
if (!length(vrts)) message("no chips yet: run chip_build-composite.R once reference/<area>/windows.csv exists (window_count-clear.R derive)")

# dated orthophoto / air photo epochs (#103): dated/<source>_<year>.vrt -> "Orthophoto 2021"
dated <- sort(list.files(file.path(dir_proj, "dated"), pattern = "^(orthophoto|airphoto)_[0-9]{4}[.]vrt$"))
# The dated VRTs were built for the points imagery.csv lists. After a redraw or a larger sample they
# describe other points, so they are not offered (and any already in the project are removed below)
# until imagery_index-dated.R and imagery_build-dated.R have been re-run. (img_csv: set above.)
if (length(dated) && (!file.exists(img_csv) ||
    !setequal(unique(utils::read.csv(img_csv, stringsAsFactors = FALSE)$point_id), smp_design$point_id))) {
  message("dated layers skipped: ", img_csv, " does not list exactly sample.gpkg's points -- re-run ",
          "imagery_index-dated.R and imagery_build-dated.R")
  dated <- character(0)
}
# Esri capture mosaics (#115), guarded on their own: a stale imagery.csv must not take them down, nor a
# stale wayback.csv the orthophotos (wb_built is NULL when wayback.csv or the build disagrees).
wb_vrts <- if (is.null(wb_built)) character(0) else
  sort(list.files(file.path(dir_proj, "dated"), pattern = "^wayback_[0-9]{4}[.]vrt$"))
# a dated layer whose VRT imagery_build-dated.R removed (its epoch no longer earns a theme) goes too
orphan <- c(setdiff(grep("^[0-9]{4} (orthophoto|air photo) [(]dated[)]", tree_names(), value = TRUE),
                    vapply(dated, dated_name, "")),
            setdiff(grep(WB_LAYER_RE, tree_names(), value = TRUE), vapply(wb_vrts, wb_name, "")))
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
# RGB with nodata 0 outside each point's Voronoi cell, so dated_rgb.qml draws the gaps transparent
for (v in wb_vrts) {
  nm <- wb_name(v)
  if (nm %in% tree_names()) next
  rfp::rfp_qgs_raster_add(qgs, raster = file.path("dated", v), name = nm, qml = qml_dated, stretch = "none",
                          group = "Reference imagery - dated", visible = FALSE)
}

# --- map themes -------------------------------------------------------------------------------
have  <- tree_names()
# Change patches show IO's own transition -- the map's answer -- so they are in NO labelling theme
# (#111). They get one theme of their own, picked from the theme drop-down after a point is labelled.
# FWA Wetland is a stratifier (stable wetland, wetland change): drawn under a point it hints at the
# stratum and anchors a Flooded Vegetation call, so it too waits for the after-labelling theme.
base  <- intersect(c(LYR_POINTS, LYR_CELLS, "Watershed group boundary", "Lake"), have)
imgs  <- c(vapply(sort(vrts), s2_name, ""), vapply(dated, dated_name, ""), vapply(wb_vrts, wb_name, ""))
imgs  <- intersect(imgs, have)
imgs  <- imgs[order(substr(imgs, 1, 4), imgs)]   # oldest year first, as the drop-down will show them
th <- rbind(data.frame(theme = THEME_START, layer = c(base, intersect("Esri Satellite", have))),
            do.call(rbind, lapply(imgs, function(l) data.frame(theme = l, layer = c(base, l)))),
            data.frame(theme = FP_ACC_AFTER_THEME,
                       layer = c(base, intersect(c(LYR_PATCHES, "Wetland", "Esri Satellite"), have))))
leaky <- setdiff(th$theme[th$layer == "Change patches"], FP_ACC_AFTER_THEME)
if (length(leaky)) stop("Change patches would show in labelling theme(s) ", paste(leaky, collapse = ", "),
                        call. = FALSE)
rfp::rfp_qgs_theme_set(qgs, th, on_missing_layer = "error", backup = FALSE)
# The template ships its own themes (crossings, tenure, fish models) and a newly added layer joins them,
# so they would show the change patches too. The review project carries only the themes defined here.
foreign <- setdiff(rfp::rfp_qgs_theme_names(qgs), unique(th$theme))
if (length(foreign)) rfp::rfp_qgs_theme_rm(qgs, themes = foreign, backup = FALSE)
# Checked on the WRITTEN project, every theme in it -- the guard above saw only the themes this script
# sets, which is how five template themes kept showing IO's answer.
tl <- rfp::rfp_qgs_themes(qgs)$layers
for (hidden in c("Change patches", "Wetland")) {
  shown <- unique(tl$theme[tl$layer == hidden & tl$visible])
  if (length(setdiff(shown, FP_ACC_AFTER_THEME)))
    stop(hidden, " is visible in theme(s) ", paste(setdiff(shown, FP_ACC_AFTER_THEME), collapse = ", "),
         " of the written project", call. = FALSE)
}
# ...and the rest of the written project's promises, read back rather than assumed (#111 review):
q  <- xml2::read_xml(qgs)
ml <- xml2::xml_find_first(q, sprintf("//maplayer[layername='%s']", LYR_POINTS))
for (hidden in c("Change patches", "Wetland"))
  if (tree_checked(hidden)) stop(hidden, " is checked in the layer tree: it draws on first open", call. = FALSE)
if (!identical(xml2::xml_attr(ml, "labelsEnabled"), "1"))
  stop(LYR_POINTS, " has labelsEnabled != 1: the review_id labels will not draw", call. = FALSE)
ro <- xml2::xml_attr(xml2::xml_find_all(ml, ".//editable/field[@name='review_id' or @name='cell' or @name='dated_imagery']"),
                     "editable")
if (length(ro) != 3 || any(ro != "0")) stop("review_id / cell / dated_imagery are not read-only in the form", call. = FALSE)
message("themes, in drop-down order:\n  ", paste(sort(unique(th$theme)), collapse = "\n  "))

message("project: ", qgs)
