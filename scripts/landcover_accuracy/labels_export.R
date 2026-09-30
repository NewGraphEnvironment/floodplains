# labels_export.R — carry reviewer labels out of the QGIS working copy into the committed record (#93).
#
# Phase 6 of #93. reference/<area>/labels.csv is the record every accuracy number regenerates from.
# It is written from the review project's labels.gpkg (review_build-qgis.R), keyed by point_id, and
# joined back to the committed design (sample.gpkg) rather than trusting the working copy's copy of
# the design columns: stratum and map_class come from the design, only the label fields from the
# reviewer.
#
# Rows written: every point the reviewer has given a label_status. "cannot_label" rows are KEPT in
# the csv (nonresponse is part of the record) with blank ref_* -- accuracy_estimate.R drops them
# explicitly and reports how many, per stratum, as drift requires.
#
# Refuses (FORCE=1 overrides) to drop a point already in labels.csv or to change its label: a
# working copy from another machine, or a stale one, would otherwise overwrite committed labels.
#
# usage: Rscript scripts/landcover_accuracy/labels_export.R [area]

suppressMessages({library(sf)})
source(here::here("scripts", "landcover_accuracy", "fp_accuracy.R"))

area  <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(area)) area <- "necr"
force <- identical(Sys.getenv("FORCE"), "1")
cfg   <- fp_acc_area(area)

lab_gpkg <- file.path(fp_acc_review_dir(cfg), "labels.gpkg")
if (!file.exists(lab_gpkg)) stop("no working copy at ", lab_gpkg, " -- run review_build-qgis.R", call. = FALSE)
wc  <- sf::st_drop_geometry(sf::st_read(lab_gpkg, layer = "labels", quiet = TRUE))
smp <- sf::st_drop_geometry(sf::st_read(file.path(cfg$dir_ref, "sample.gpkg"), layer = "sample", quiet = TRUE))

wc <- wc[!is.na(wc$label_status) & nzchar(trimws(wc$label_status)), ]
out <- fp_acc_labels_frame(wc, smp)

f <- file.path(cfg$dir_ref, "labels.csv")
if (file.exists(f) && !force) {
  old <- utils::read.csv(f, colClasses = "character", na.strings = "")
  new <- utils::read.csv(text = paste(utils::capture.output(
    utils::write.csv(out, row.names = FALSE, na = "")), collapse = "\n"),
    colClasses = "character", na.strings = "")
  lost <- setdiff(old$point_id, new$point_id)
  keyc <- c("ref_from", "ref_to", "label_status")
  both <- merge(old[, c("point_id", keyc)], new[, c("point_id", keyc)], by = "point_id")
  moved <- both$point_id[!mapply(function(a, b) identical(a, b),
                                 do.call(paste, both[paste0(keyc, ".x")]),
                                 do.call(paste, both[paste0(keyc, ".y")]))]
  if (length(lost) || length(moved))
    stop(sprintf("refusing to rewrite %s: %d labelled point(s) would be dropped and %d relabelled (%s). ",
                 f, length(lost), length(moved), paste(utils::head(c(lost, moved), 5), collapse = ", ")),
         "Export from the working copy that holds them, or FORCE=1 if the change is intended.",
         call. = FALSE)
}
utils::write.csv(out, f, row.names = FALSE, na = "")
message(sprintf("%s: %d labelled, %d cannot label, of %d sample points", f,
                sum(out$label_status == "labelled"), sum(out$label_status == "cannot_label"), nrow(smp)))
