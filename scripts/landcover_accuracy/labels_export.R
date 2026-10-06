# labels_export.R — carry reviewer labels out of the QGIS working copy into the committed record (#93).
#
# Phase 6 of #93. reference/<area>/labels.csv is the record every accuracy number regenerates from.
# It is written from the review project's labels.gpkg (review_build-qgis.R), which is BLIND (#111): it
# carries an opaque review_id and no design column. reference/<area>/review_key.csv maps the id back
# to point_id, stratum and map_class, and the working copy's cell is checked against the key before
# anything is joined to the committed design (sample.gpkg). Only the label fields come from the
# reviewer.
#
# Rows written: every point the reviewer has given a label_status. "cannot_label" rows are KEPT in
# the csv (nonresponse is part of the record) with blank ref_* -- accuracy_estimate.R drops them
# explicitly and reports how many, per stratum, as drift requires.
#
# Refuses (FORCE=1 overrides) to drop a point already in labels.csv or to change its label: a
# working copy from another machine, or a stale one, would otherwise overwrite committed labels.
#
# usage: Rscript scripts/landcover_accuracy/labels_export.R [area] [labels.gpkg]
#   labels.gpkg defaults to the local review project; pass the Mergin working copy's path to export
#   from there (rtj#367).
#   WHICH record is written follows from the working copy itself: a copy holding every keyed point, or
#   exactly the points of the key's first batches (made before the sample grew), is labeller A's
#   (labels.csv); one holding exactly the second-labeller subset is B's (labels_b.csv); anything else
#   -- a copy that lost rows, say -- is refused -- so B's labels can never become the record by a forgotten flag.
#   REVIEWER=b only picks B's default path (<area>_lulc_review_b) when no path is given.

suppressMessages({library(sf)})
source(here::here("scripts", "landcover_accuracy", "fp_accuracy.R"))

args  <- commandArgs(trailingOnly = TRUE)
area  <- if (!is.na(args[1])) args[1] else "necr"
force <- identical(Sys.getenv("FORCE"), "1")
cfg   <- fp_acc_area(area)

reviewer <- Sys.getenv("REVIEWER", "a")
if (!reviewer %in% c("a", "b")) stop("REVIEWER must be a or b, got ", reviewer, call. = FALSE)
lab_gpkg <- if (!is.na(args[2])) args[2] else
  file.path(paste0(fp_acc_review_dir(cfg), if (reviewer == "b") "_b" else ""), "labels.gpkg")
if (!file.exists(lab_gpkg)) stop("no working copy at ", lab_gpkg, " -- run review_build-qgis.R", call. = FALSE)
wc  <- sf::st_drop_geometry(sf::st_read(lab_gpkg, layer = "labels", quiet = TRUE))
key <- fp_acc_review_key_read(file.path(cfg$dir_ref, "review_key.csv"))
role <- fp_acc_working_copy_role(wc$review_id, key)
message(lab_gpkg, ": labeller ", role, "'s working copy")
smp <- sf::st_drop_geometry(sf::st_read(file.path(cfg$dir_ref, "sample.gpkg"), layer = "sample", quiet = TRUE))

wc <- wc[!is.na(wc$label_status) & nzchar(trimws(wc$label_status)), ]
wc <- fp_acc_unblind(wc, key)
out <- fp_acc_labels_frame(wc, smp)

f <- file.path(cfg$dir_ref, if (role == "b") "labels_b.csv" else "labels.csv")
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
