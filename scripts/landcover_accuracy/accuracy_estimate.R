# accuracy_estimate.R — error-adjusted areas and the classify-ourselves verdict from the labels (#93).
#
# Phase 7 of #93 once labels exist; wired and exercised now. Reads the committed record only:
#   reference/<area>/labels.csv   reviewer labels (labels_export.R)
#   reference/<area>/sample.gpkg  the design: stratum, map classes per year, cell-level cause/wetland flags
#   reference/<area>/strata.csv   stratum sizes and weights
# and computes, with drift::dft_accuracy_estimate() (Stehman 2014 / Olofsson 2014):
#   - accuracy and error-adjusted area of the published transition map
#   - error-adjusted area with CIs for three targets, recode-then-estimate:
#       tree loss, UNATTRIBUTED tree loss, wetland change
#   - the four pre-registered criteria, exactly as research/landcover_accuracy.md defines them
#   - the full-sample size from the pilot's per-stratum SD (dft_accuracy_size)
#
# Nonresponse ("cannot_label") is dropped EXPLICITLY and counted per stratum -- drift refuses a blank
# ref_class rather than dropping it silently, because dropping it changes the stratum's n.
#
# SYNTHETIC=1 runs the same pipeline on made-up labels (the map with a fraction flipped) so the
# wiring can be exercised before anyone labels. It never reads or writes labels.csv, and every line
# it prints is prefixed SYNTHETIC.
#
# usage: Rscript scripts/landcover_accuracy/accuracy_estimate.R [area]
#        SYNTHETIC=1 Rscript scripts/landcover_accuracy/accuracy_estimate.R necr
# Output: data/<area>/accuracy/estimate[_synthetic].rds + criteria[_synthetic].csv

suppressMessages({library(sf); library(yaml)})
source(here::here("scripts", "landcover_accuracy", "fp_accuracy.R"))

area <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(area)) area <- "necr"
synthetic <- identical(Sys.getenv("SYNTHETIC"), "1")
tag <- if (synthetic) "SYNTHETIC " else ""
cfg <- fp_acc_area(area)

smp    <- sf::st_drop_geometry(sf::st_read(file.path(cfg$dir_ref, "sample.gpkg"), layer = "sample", quiet = TRUE))
strata <- utils::read.csv(file.path(cfg$dir_ref, "strata.csv"))
# Causes come from the DESIGN, not today's disturbance.yml: they define the cause strata the sample
# was drawn with. A yml that has changed since the draw is refused rather than silently redefining
# criterion 2 on both sides.
design <- jsonlite::read_json(file.path(cfg$dir_ref, "design.json"), simplifyVector = TRUE)
causes <- design$causes
dst    <- yaml::read_yaml(here::here("config", "disturbance.yml"))
if (!identical(causes, vapply(dst$sources, `[[`, "", "name")))
  stop("config/disturbance.yml sources (", paste(vapply(dst$sources, `[[`, "", "name"), collapse = ", "),
       ") differ from the design's causes (", paste(causes, collapse = ", "), "); redraw the sample ",
       "before estimating with new causes", call. = FALSE)
# Same rule for the prior-fire stratum (#103): it exists in the design only if the lookback did.
lb_cfg <- Filter(function(s) identical(s$name, FP_ACC_PRIOR_NAME), dst$lookback)
lb_now <- if (length(lb_cfg)) as.integer(lb_cfg[[1]]$lookback) else NULL
lb_was <- if (!is.null(design$lookback)) as.integer(design$lookback$lookback) else NULL
if (!identical(lb_now, lb_was))
  stop("config/disturbance.yml lookback `", FP_ACC_PRIOR_NAME, "` (", if (is.null(lb_now)) "absent" else lb_now,
       ") differs from the design's (", if (is.null(lb_was)) "absent" else lb_was, "); redraw the sample ",
       "before estimating", call. = FALSE)

lab <- if (synthetic) {
  fp_acc_synthetic_labels(smp, p_flip = 0.2, seed = 1L)
} else {
  f <- file.path(cfg$dir_ref, "labels.csv")
  if (!file.exists(f)) stop("no ", f, " -- nothing labelled yet (SYNTHETIC=1 exercises the wiring)", call. = FALSE)
  utils::read.csv(f, stringsAsFactors = FALSE, na.strings = "")
}

om_f <- file.path(cfg$dir_acc, "omission_disturbance.csv")
omission <- if (file.exists(om_f)) {
  o <- utils::read.csv(om_f); o$omission_io[o$source == "harvest" & o$year == "all"]
} else NA_real_

res <- fp_acc_estimate(lab, smp, strata, causes, omission_harvest_io = omission)

cat(tag, "Nonresponse dropped per stratum:\n", sep = "")
print(res$nonresponse, row.names = FALSE)
cat("\n", tag, "Error-adjusted area (ha), 95% CI:\n", sep = "")
print(res$targets, row.names = FALSE)
cat("\n", tag, "Pre-registered criteria (any two => pilot a local classifier):\n", sep = "")
print(res$criteria, row.names = FALSE)
cat(sprintf("\n%sCriteria holding: %d of %d evaluable -> %s\n", tag, sum(res$criteria$holds, na.rm = TRUE),
            sum(!is.na(res$criteria$holds)), res$verdict))
cat("\n", tag, "Full-sample size for the unattributed tree-loss target (se = 25% of the estimate / 1.96):\n", sep = "")
print(res$size, row.names = FALSE)

dir.create(cfg$dir_acc, showWarnings = FALSE, recursive = TRUE)
sfx <- if (synthetic) "_synthetic" else ""
saveRDS(res, file.path(cfg$dir_acc, paste0("estimate", sfx, ".rds")))
utils::write.csv(res$criteria, file.path(cfg$dir_acc, paste0("criteria", sfx, ".csv")), row.names = FALSE, na = "")
