# accuracy-check.R — assert the accuracy strata, omission and label rules on toy grids (#93).
#
# No database, no network, no area data. Every rule is checked against a grid built to contain the
# case, and the rules that a plausible refactor would break carry a must-fail arm: the same check
# run against the broken form, which must come out differently. A check that passes on the broken
# form cannot see the defect.
#
# Two of the arms exist because the first plan had the defect (#93's plan review):
#   - the population was `transition.tif`, which drops cells the 1 ha sieve removed (18% of NECR's
#     IO change), so omission of the published map could not be measured;
#   - wetland was the patch-level `in_wetland`, which is any-touch and would have moved 78% of
#     Trees->Rangeland into the wetland stratum.
#
# usage: Rscript scripts/landcover_accuracy/accuracy-check.R

suppressMessages({library(terra)})
source(here::here("scripts", "landcover_accuracy", "fp_accuracy.R"))

fails <- 0L
ok <- function(label, cond, detail = "") {
  if (isTRUE(cond)) message("  PASS  ", label, if (nzchar(detail)) paste0("  (", detail, ")") else "")
  else { fails <<- fails + 1L
         message("  FAIL  ", label, if (nzchar(detail)) paste0("  (", detail, ")") else "") }
}

# --- toy grid: one cell per rule --------------------------------------------------------------
# cols: from, to, published transition (NA = sieved/outside), fire, harvest, FWA wetland, expected
cases <- read.table(header = TRUE, text = "
case                        from to trans  fire harvest wet expect
fire_beats_wetland_and_TR     2  11  2011     1   NA     1   'change: fire'
fire_beats_harvest            2   8  2008     1    1    NA   'change: fire'
harvest                       2   5  2005    NA    1    NA   'change: harvest'
wetland_cell_TR               2  11  2011    NA   NA     1   'wetland change'
TR                            2  11  2011    NA   NA    NA   'Trees -> Rangeland'
FV_endpoint                   4  11  4011    NA   NA    NA   'wetland change'
RT                           11   2 11002    NA   NA    NA   'Rangeland -> Trees'
crops_range                   5  11  5011    NA   NA    NA   'Crops <-> Rangeland'
trees_crops                   2   5  2005    NA   NA    NA   'Crops <-> Trees'
snow                          9  11  9011    NA   NA    NA   'Snow/Ice -> any'
trees_water                   2   1  2001    NA   NA    NA   'any <-> Water'
trees_bare                    2   8  2008    NA   NA    NA   'other tree loss'
bare_built                    8   7  8007    NA   NA    NA   'other change'
sieved                        2  11    NA    NA   NA    NA   'sieved change (<1 ha)'
stable_trees_wet              2   2  2002    NA   NA     1   'stable wetland'
stable_FV_not_fwa             4   4  4004    NA   NA    NA   'stable wetland'
stable_trees                  2   2  2002    NA   NA    NA   'stable Trees'
stable_crops                  5   5  5005    NA   NA    NA   'stable other'
outside                      NA  NA    NA    NA   NA    NA   NA
", stringsAsFactors = FALSE)

grid <- function(v) terra::rast(nrows = 1, ncols = length(v), xmin = 0, xmax = 10 * length(v),
                                ymin = 0, ymax = 10, crs = "EPSG:32610", vals = v)
from <- grid(cases$from); to <- grid(cases$to); trans <- grid(cases$trans)
causes <- list(fire = grid(cases$fire), harvest = grid(cases$harvest))
wet <- grid(cases$wet)

got_labels <- function(res) {
  v  <- terra::values(res$strata, mat = FALSE)
  res$table$label[match(v, res$table$stratum)]
}

res <- fp_acc_strata(from, to, trans, causes, wet)
got <- got_labels(res)
message("Strata precedence (one cell per rule):")
for (i in seq_len(nrow(cases))) {
  ok(sprintf("%-26s -> %s", cases$case[i], ifelse(is.na(cases$expect[i]), "NA", cases$expect[i])),
     identical(got[i], cases$expect[i]), paste("got", got[i]))
}

message("Population and the published map claim:")
foot <- sum(!is.na(cases$from) & !is.na(cases$to))
ok("every footprint cell has exactly one stratum", sum(!is.na(got)) == foot,
   sprintf("%d of %d", sum(!is.na(got)), foot))
rep_v <- terra::values(res$reported, mat = FALSE)
ok("a sieved cell's map claim is 'no change' (from*1000+from)",
   identical(as.integer(rep_v[cases$case == "sieved"]), 2002L))
ok("elsewhere the map claim is the published transition",
   identical(as.integer(rep_v[cases$case == "TR"]), 2011L))
ok("strata raster carries labels for drift's stratum_label", !is.null(terra::cats(res$strata)[[1]]))

message("Must-fail arms:")
# (a) the first plan's population: transition.tif. Sieved cells fall outside every stratum.
g_trans_pop <- got
g_trans_pop[is.na(cases$trans)] <- NA
ok("must-fail arm: masking to transition.tif loses the sieved cell",
   sum(!is.na(g_trans_pop)) < foot)
# (b) the first plan's wetland: patch-level any-touch. Here: a wetland flag on the T->R patch that
#     only touches a wetland moves it out of the Trees->Rangeland stratum.
wet_patch <- wet; terra::values(wet_patch)[cases$case == "TR"] <- 1
g_patch <- got_labels(fp_acc_strata(from, to, trans, causes, wet_patch))
ok("must-fail arm: patch-level wetland empties the Trees -> Rangeland cell",
   !identical(g_patch[cases$case == "TR"], "Trees -> Rangeland"))
# (c) cause order is the yml's: reversed, the fire+harvest cell becomes harvest.
g_rev <- got_labels(fp_acc_strata(from, to, trans, rev(causes), wet))
ok("must-fail arm: reversing sources: order changes the fire+harvest cell",
   identical(g_rev[cases$case == "fire_beats_harvest"], "change: harvest"))
# (d) context is never a cause: filed as a cause, the wetland cell leaves 'wetland change'.
wet_chg <- wet; terra::values(wet_chg)[cases$case == "stable_trees_wet"] <- NA  # a patch flag: change cells only
g_ctx <- got_labels(fp_acc_strata(from, to, trans, c(causes, list(wetland = wet_chg)), wet))
ok("must-fail arm: a context layer filed as a cause becomes a cause stratum",
   identical(g_ctx[cases$case == "wetland_cell_TR"], "change: wetland"))
# (e) a cause cell on a non-change cell is refused (patches and transition from different runs)
bad <- causes; terra::values(bad$fire)[cases$case == "stable_trees"] <- 1
ok("a cause flag on a stable cell is refused",
   inherits(tryCatch(fp_acc_strata(from, to, trans, bad, wet), error = function(e) e), "error"))

message("Prior-fire stratum (#103):")
# The lookback polygons are CELL level, so they reach stable and sieved land; only published change
# takes stratum 19, a cause still wins, and 19 wins over every transition-class stratum.
pc <- read.table(header = TRUE, text = "
case                 from to trans  fire wet prior expect
prior_regrowth        11   2 11002    NA  NA     1  'change in prior fire'
prior_beats_wetland    2  11  2011    NA   1     1  'change in prior fire'
fire_beats_prior       2  11  2011     1  NA     1  'change: fire'
prior_stable           2   2  2002    NA  NA     1  'stable Trees'
prior_sieved           2  11    NA    NA  NA     1  'sieved change (<1 ha)'
no_prior_RT           11   2 11002    NA  NA    NA  'Rangeland -> Trees'
", stringsAsFactors = FALSE)
p_res <- fp_acc_strata(grid(pc$from), grid(pc$to), grid(pc$trans),
                       list(fire = grid(pc$fire), harvest = grid(rep(NA, nrow(pc)))), grid(pc$wet),
                       prior = grid(pc$prior))
p_got <- got_labels(p_res)
for (i in seq_len(nrow(pc)))
  ok(sprintf("%-22s -> %s", pc$case[i], pc$expect[i]), identical(p_got[i], pc$expect[i]), paste("got", p_got[i]))
ok("stratum 19 is in the table only when `prior` is given",
   19L %in% p_res$table$stratum && !19L %in% res$table$stratum)
ok("stratum 19's label is not a cause label (fp_acc_estimate finds causes by 'change: <name>')",
   !startsWith(p_res$table$label[p_res$table$stratum == 19L], "change: "))
p_none <- got_labels(fp_acc_strata(grid(pc$from), grid(pc$to), grid(pc$trans),
                                   list(fire = grid(pc$fire), harvest = grid(rep(NA, nrow(pc)))),
                                   grid(pc$wet)))
ok("must-fail arm: without `prior` the regrowth cell is plain Rangeland -> Trees",
   identical(p_none[pc$case == "prior_regrowth"], "Rangeland -> Trees"))

message("Review form imagery values (#103):")
# The form's value map and FP_ACC_IMAGERY are two lists of one fact; labels_export refuses any value
# outside FP_ACC_IMAGERY, so a form offering a value the list lacks makes a reviewer's choice unexportable.
form_values <- function(qml) {
  x <- xml2::read_xml(qml)
  xml2::xml_attr(xml2::xml_find_all(x, "//field[@name='imagery']//Option[@value]"), "value")
}
for (q in Sys.glob(here::here("reference", "*", "labels_form.qml"))) {
  ok(sprintf("%s imagery values == FP_ACC_IMAGERY", basename(dirname(q))),
     setequal(form_values(q), FP_ACC_IMAGERY),
     paste(sort(union(setdiff(form_values(q), FP_ACC_IMAGERY), setdiff(FP_ACC_IMAGERY, form_values(q)))),
           collapse = ","))
}
ok("must-fail arm: a form missing `orthophoto` is caught",
   !setequal(setdiff(form_values(Sys.glob(here::here("reference", "*", "labels_form.qml"))[1]),
                     "orthophoto"), FP_ACC_IMAGERY))

message("Omission:")
# 4 Trees cells in a harvest polygon; IO keeps 1 as Trees; the published map sieved 1 of the 3 losses.
om <- fp_acc_omission(from = grid(c(2, 2, 2, 2, 5)), to = grid(c(2, 11, 11, 8, 11)),
                      trans = grid(c(2002, 2011, NA, 2008, 5011)), inpoly = grid(c(1, 1, 1, 1, 1)))
cell_ha <- 0.01
ok("denominator is Trees-at-first-date cells only", isTRUE(all.equal(om$denom_ha, 4 * cell_ha)))
ok("IO omission counts IO's own labels (unsieved)", isTRUE(all.equal(om$omission_io, 1 - 3 / 4)))
ok("published omission counts the sieve as missed", isTRUE(all.equal(om$omission_published, 1 - 2 / 4)))

message("Labels contract (labels_export.R):")
refused <- function(expr) inherits(tryCatch(expr, error = function(e) e), "error")
smp <- data.frame(point_id = c("1_00001", "1_00002", "17_00001", "17_00002", "31_00001", "31_00002"),
                  stratum = c(1, 1, 17, 17, 31, 31), stratum_label = "x",
                  map_class = c(2011, 2011, 2008, 2008, 2002, 2002), use = "accuracy",
                  map_2017 = 2, map_2023 = c(11, 11, 8, 8, 2, 2),
                  in_fire_poly = c(TRUE, TRUE, FALSE, FALSE, FALSE, FALSE), in_fwa_wetland = FALSE)
wc <- data.frame(point_id = smp$point_id, ref_from = 2L, ref_to = c(11L, 11L, 8L, 8L, 2L, 2L),
                 label_status = "labelled", confidence = NA, imagery = NA, note = NA,
                 reviewer = "check", labelled_on = as.Date("2026-09-29"), map_class = 9999)
wc$stratum <- smp$stratum; wc$map_class <- smp$map_class; wc$cell <- seq_len(nrow(smp))
smp$cell <- seq_len(nrow(smp))
lf <- fp_acc_labels_frame(wc, smp)
ok("labels.csv carries the design's cell, stratum and map_class", identical(lf$cell[lf$point_id == "1_00001"], 1))
moved <- wc; moved$cell[1] <- 999
ok("must-fail arm: a working copy made on a redrawn sample (same id, other cell) is refused",
   refused(fp_acc_labels_frame(moved, smp)))
moved_cls <- wc; moved_cls$map_class[1] <- 2002
ok("must-fail arm: a working copy whose map_class disagrees with the design is refused",
   refused(fp_acc_labels_frame(moved_cls, smp)))
ok("ref_class = ref_from * 1000 + ref_to", identical(lf$ref_class[lf$point_id == "1_00001"], 2011L))
w2 <- wc; w2$ref_to[1] <- 3L
ok("a reference class outside IO's legend is refused", refused(fp_acc_labels_frame(w2, smp)))
w3 <- wc; w3$label_status[1] <- "cannot_label"
ok("cannot_label with reference classes filled is refused", refused(fp_acc_labels_frame(w3, smp)))
w4 <- wc; w4$point_id[1] <- "99_00001"
ok("a point not in the sample is refused", refused(fp_acc_labels_frame(w4, smp)))

message("Blind review (#111):")
# 16 strata x 30 points named the way drift names them, so the id carries the stratum
bsmp <- do.call(rbind, lapply(1:16, function(st) data.frame(
  point_id = sprintf("%d_%05d", st, 1:30), cell = st * 1000 + 1:30, stratum = st, map_class = st * 1000L + 2L)))
rk <- c("Mersenne-Twister", "Inversion", "Rejection")
k1 <- fp_acc_review_key(bsmp, 930093, rk)
ok("review_id is a permutation of 1..n", identical(sort(k1$review_id), seq_len(nrow(bsmp))))
ok("the key is reproducible from the design seed", identical(k1, fp_acc_review_key(bsmp, 930093, rk)))
rho <- stats::cor(k1$review_id, k1$stratum, method = "spearman")
ok("review order is not stratum order (|rho| < 0.2)", abs(rho) < 0.2, sprintf("rho %.3f", rho))
sorted <- bsmp[order(bsmp$point_id, method = "radix"), ]
ok("must-fail arm: ordering by point_id IS stratum order (the leak the shuffle removes)",
   abs(stats::cor(seq_len(nrow(sorted)), sorted$stratum, method = "spearman")) > 0.2)
set.seed(7); r0 <- runif(1); set.seed(7); invisible(fp_acc_review_key(bsmp, 930093, rk))
ok("drawing the key leaves the session RNG untouched", identical(runif(1), r0))
pilot <- bsmp[as.integer(sub(".*_", "", bsmp$point_id)) <= 20, ]
kp <- fp_acc_review_key(pilot, 930093, rk)
kg <- fp_acc_review_key(bsmp, 930093, rk, have = kp)
ok("growing the sample keeps every pilot id", identical(kg$review_id[match(kp$point_id, kg$point_id)], kp$review_id))
ok("new points take the next ids", setequal(kg$review_id[!kg$point_id %in% kp$point_id], (nrow(kp) + 1):nrow(bsmp)))
ok("a key from another draw (a point the sample lacks) is refused",
   refused(fp_acc_review_key(bsmp[-1, ], 930093, rk, have = k1)))
kc <- k1; kc$cell[1] <- -1
ok("must-fail arm: a key whose cell disagrees with the sample is refused",
   refused(fp_acc_review_key(bsmp, 930093, rk, have = kc)))
schema <- c("review_id", "cell", "dated_imagery", "ref_from", "ref_to", "label_status", "confidence",
            "imagery", "note", "reviewer", "labelled_on", "geom")
ok("the blind working-copy schema carries no design column", !length(fp_acc_blind_leaks(schema)))
ok("must-fail arm: point_id, a map year, a cause flag and the stratum are each caught",
   setequal(fp_acc_blind_leaks(c(schema, "point_id", "map_2017", "in_fire_poly", "stratum_label")),
            c("point_id", "map_2017", "in_fire_poly", "stratum_label")))
bw <- data.frame(review_id = k1$review_id[1:3], cell = k1$cell[1:3], ref_from = 2L, ref_to = 11L,
                 label_status = "labelled", confidence = NA, imagery = NA, note = NA, reviewer = "check",
                 labelled_on = as.Date("2026-10-06"))
ub <- fp_acc_unblind(bw, k1)
ok("unblinding maps review_id back to the keyed point_id and design",
   identical(ub$point_id, k1$point_id[1:3]) && identical(ub$stratum, k1$stratum[1:3]))
bsmp2 <- transform(bsmp, stratum_label = "x", use = "accuracy")
ok("an unblinded working copy passes the labels contract", !refused(fp_acc_labels_frame(ub, bsmp2)))
bu <- bw; bu$review_id[1] <- 9999L
ok("must-fail arm: an unknown review_id is refused", refused(fp_acc_unblind(bu, k1)))
bcell <- bw; bcell$cell[2] <- 1
ok("must-fail arm: a working-copy cell that disagrees with the key is refused", refused(fp_acc_unblind(bcell, k1)))
ok("no key, no export", refused(fp_acc_unblind(bw, NULL)))

message("Recode-then-estimate targets (perfect labels reproduce mapped areas):")
strata <- data.frame(stratum = c(1, 17, 31), stratum_label = c("change: fire", "other tree loss", "stable Trees"),
                     n_cells = c(1000, 500, 8500), area = c(10, 5, 85), weight = c(0.10, 0.05, 0.85))
est <- suppressMessages(fp_acc_estimate(lf, smp, strata, causes = "fire"))
tv <- function(e, nm) e$targets$area_ha[e$targets$target == nm]
ok("tree loss = both loss strata (15 ha)", isTRUE(all.equal(tv(est, "tree loss"), 15)))
ok("unattributed tree loss = the non-cause loss stratum (5 ha)",
   isTRUE(all.equal(tv(est, "unattributed tree loss"), 5)))
smp_nopoly <- smp; smp_nopoly$in_fire_poly <- FALSE
est2 <- suppressMessages(fp_acc_estimate(lf, smp_nopoly, strata, causes = "fire"))
ok("must-fail arm: without cell-level cause polygons the reference counts the fire loss as unattributed",
   isTRUE(all.equal(tv(est2, "unattributed tree loss"), 15)))
lf_nr <- lf; lf_nr$label_status[3] <- "cannot_label"; lf_nr$ref_from[3] <- NA; lf_nr$ref_to[3] <- NA
ok("a stratum left with < 2 labelled points is refused, not estimated",
   refused(suppressMessages(fp_acc_estimate(lf_nr, smp, strata, causes = "fire"))))

lab_moved <- lf; lab_moved$cell[lab_moved$point_id == "17_00001"] <- 12345
ok("estimation refuses labels.csv rows whose cell disagrees with sample.gpkg",
   refused(suppressMessages(fp_acc_estimate(lab_moved, smp, strata, causes = "fire"))))

nocell <- wc; nocell$cell <- NULL
ok("must-fail arm: a working copy without `cell` is refused (map_class alone cannot tell a redraw)",
   refused(fp_acc_labels_frame(nocell, smp)))

message("Criterion 1 is three-valued:")
ok("holds when either endpoint is < 0.5, even with the other NA", isTRUE(fp_acc_crit1(NA, 0.3)))
ok("NA when one endpoint cannot be evaluated and the other passes", is.na(fp_acc_crit1(NA, 0.8)))
ok("must-fail arm: min(na.rm = TRUE) would have said 'does not hold' there",
   !(suppressWarnings(min(NA, 0.8, na.rm = TRUE)) < 0.5))
ok("FALSE only when both endpoints are evaluated and >= 0.5", identical(fp_acc_crit1(0.7, 0.8), FALSE))

message("Composite windows (the pre-registered rule):")
yrs <- 2017:2019; mos <- 5:9
# every cell clear except the ones set below
wst <- expand.grid(month = mos, year = yrs)[, c("year", "month")]
wst$status <- "ok"; wst$share_ge1 <- 0.99
setw <- function(d, y, m, v) { d$share_ge1[d$year == y & d$month == m] <- v; d }
wst <- setw(wst, 2018, 5, 0.50)          # May fails in one year
wst <- setw(wst, 2019, 9, 0.94)          # just under the bar
wp <- fp_acc_window_pass(wst, yrs, mos)
ok("span = longest run clear in EVERY year (6-8: May fails 2018, Sep fails 2019 at 0.94)",
   identical(fp_acc_window_span(wp), 6:8))
ok("must-fail arm: a mean-over-years rule would have kept September (mean 0.973)",
   colMeans(wp$share)[["9"]] >= FP_ACC_WIN_THR && !9L %in% fp_acc_window_span(wp))
wst2 <- setw(wst, 2018, 7, 0.10)         # splits the span into 6 and 8
wp2 <- fp_acc_window_pass(wst2, yrs, mos)
ok("a month failing in one year breaks the run; the tie goes to the higher minimum share",
   identical(fp_acc_window_span(setw(wst2, 2017, 6, 0.96) |> fp_acc_window_pass(yrs, mos)), 8L))
ok("a tie on length and minimum share goes to the earlier run", identical(fp_acc_window_span(wp2), 6L))
wf <- wst; wf$status[wf$year == 2017 & wf$month == 7] <- "failed"; wf$share_ge1[wf$year == 2017 & wf$month == 7] <- NA
ok("a failed month-year is refused, never read as clear or as zero",
   inherits(tryCatch(fp_acc_window_pass(wf, yrs, mos), error = identity), "error"))
ok("a missing month-year is refused",
   inherits(tryCatch(fp_acc_window_pass(wst[-1, ], yrs, mos), error = identity), "error"))
we <- wst; we$status[we$year == 2017 & we$month == 7] <- "empty"; we$share_ge1[we$year == 2017 & we$month == 7] <- 0
ok("an empty month (a real zero) is measured, and fails the bar",
   !fp_acc_window_pass(we, yrs, mos)$pass["2017", "7"])
w17 <- setw(setw(setw(wst, 2017, 6, 0.60), 2017, 7, 0.60), 2017, 8, 0.60)   # 2017 alone fails 6-8
wp17 <- fp_acc_window_pass(w17, yrs, mos)
ok("no span in all years when 2017 alone fails the middle; without 2017 it is 6-8",
   !length(fp_acc_window_span(wp17)) && identical(fp_acc_window_span(wp17, c("2018", "2019")), 6:8))
wid <- fp_acc_window_widen(wp17, 2017, 6:8)
ok("widening adds the adjacent month with the higher share, one at a time; a tie takes the earlier month",
   identical(wid[[1]], 5:8) && identical(wid[[length(wid)]], 5:9))
ok("widening prefers the higher-share neighbour",
   identical(fp_acc_window_widen(fp_acc_window_pass(setw(w17, 2017, 5, 0.30), yrs, mos), 2017, 6:8)[[1]], 6:9))
ok("months string", identical(fp_acc_months_str(7L), "7") && identical(fp_acc_months_str(6:8), "6-8"))

message(if (fails) sprintf("\n%d FAIL", fails) else "\nALL PASS")
quit(status = if (fails) 1L else 0L)
