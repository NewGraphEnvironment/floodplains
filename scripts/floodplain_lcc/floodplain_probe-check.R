# floodplain_probe-check.R — assert the whole-FWA floodplain probe helpers offline (#110).
#
# No database, no data/. Every helper in fp_whole_fwa.R the probe's numbers depend on is exercised
# against a fixture whose answer is known by construction, including the shapes it exists to
# reject: an NA access or parent value that SQL would drop, an arm that does not nest, an arm code
# or species that would reach SQL unchecked, a segment key built from an NA, and two rasters on
# different grids.
#
# usage: Rscript scripts/floodplain_lcc/floodplain_probe-check.R

suppressMessages(library(terra))
source(here::here("scripts", "floodplain_lcc", "fp_whole_fwa.R"))

n_fail <- 0L
check <- function(ok, what) {
  ok <- isTRUE(ok)
  if (!ok) n_fail <<- n_fail + 1L
  cat(if (ok) "  ok   " else "  FAIL ", what, "\n", sep = "")
}
errs <- function(expr) inherits(tryCatch(expr, error = function(e) e), "error")

# One row per case that separates the arms, plus the NA cases SQL's three-valued logic drops.
df <- data.frame(
  stream_order        = c(1L, 1L, 1L, 2L, 3L, 3L, 5L, NA, 1L, 3L),
  stream_order_parent = c(2L, 5L, 6L, 3L, 4L, 4L, 6L, 3L, NA, NA),
  access              = c(0L, 1L, 1L, 1L, 0L, 1L, 2L, 1L, 1L, NA))

cat("arm predicates\n")
k <- lapply(1:5, function(a) fp_wf_keep(df, a))
check(identical(which(k[[1]]), c(1:7, 9:10)), "arm 1: every ordered segment; NA order dropped")
check(identical(which(k[[2]]), c(4:7, 10L)), "arm 2: order >= 2")
check(identical(which(k[[3]]), c(5:7, 10L)), "arm 3: order >= 3")
check(identical(which(k[[4]]), c(2:3, 5:7, 10L)), "arm 4: order >= 3 plus first-order with parent >= 5")
check(identical(which(k[[5]]), 6:7), "arm 5: access 1 or 2 at order >= 3; NA access dropped")
check(!k[[4]][9], "arm 4: a first-order segment with NA parent is dropped, as SQL drops it")
nests <- function(sup, sub) all(!sub | sup)
check(nests(k[[1]], k[[2]]) && nests(k[[2]], k[[3]]) && nests(k[[3]], k[[5]]) && nests(k[[4]], k[[3]]),
      "arms nest: 1 >= 2 >= 3 >= 5 and 4 >= 3")
check(!nests(k[[3]], k[[4]]), "must-fail arm: arm 4 is NOT inside arm 3 (the nesting test can fail)")
check(identical(which(fp_wf_keep(df, 5, min_order = 5L)), 7L), "arm 5 honours the scenario's min_order")
# The NA guard is what makes arm 5 match 01's SQL. Without it `access %in% c(1, 2)` alone is the
# same here, but `>=` on an NA order is NA, and `NA & FALSE` is FALSE while `NA | TRUE` is TRUE --
# so check the guard the switch uses directly, against the naive comparison it replaces.
check(identical(which(df$stream_order >= 1L), c(1:7, 9:10)) && anyNA(df$stream_order >= 1L),
      "must-fail arm: the naive comparison carries an NA the guard removes")

cat("closed shapes\n")
check(errs(fp_wf_keep(df, 6)) && errs(fp_wf_keep(df, 0)) && errs(fp_wf_keep(df, 2.5)) &&
        errs(fp_wf_keep(df, "2; DROP")) && errs(fp_wf_keep(df, NA)), "arm outside 1..5 is refused")
check(identical(fp_wf_check_arm("3"), 3L) && identical(fp_wf_check_arm(3), 3L), "arm as text or number")
check(errs(fp_wf_network_sql("fresh", "MORR", "co; DROP")) && errs(fp_wf_network_sql("fresh", "MORR", "CO")),
      "species outside ^[a-z]{2,4}$ is refused before it reaches SQL")
check(errs(fp_wf_network_sql("fresh x", "MORR", "co")) && errs(fp_wf_network_sql("fresh", "morr", "co")),
      "schema and watershed group are refused outside their shapes")
sql <- fp_wf_network_sql("fresh", "MORR", "co")
check(grepl("a.access_co AS access", sql, fixed = TRUE) &&
        grepl("WHERE s.watershed_group_code = 'MORR'$", sql) && !grepl("stream_order >=", sql, fixed = TRUE),
      "the SQL filters the group only; every arm is a filter in R")

cat("segment key\n")
check(identical(fp_wf_seg_key(c(360885316, 1), c(0, 1234.56789)), c("360885316:0.000", "1:1234.568")),
      "blk:drm at 3 decimals, no scientific notation on a 9-digit key")
check(errs(fp_wf_seg_key(c(1, NA), c(0, 1))) && errs(fp_wf_seg_key(1, NA)), "an NA half is refused")
op <- options(scipen = -9)
check(identical(fp_wf_seg_key(360885316, 0), "360885316:0.000"), "a scipen option cannot reach the key")
options(op)

cat("overlap\n")
a <- terra::rast(nrows = 2, ncols = 3, xmin = 0, xmax = 300, ymin = 0, ymax = 200, crs = "EPSG:3005",
                 vals = c(1, 1, 0, NA, 1, 0))
b <- terra::rast(a, vals = c(1, 0, 1, 1, NA, 0))
o <- fp_wf_overlap(a, b)
v <- setNames(o$cells, o$metric)
check(identical(unname(v), c(3, 3, 1, 2, 2)), "a, b, both, a_only, b_only; NA and 0 are both not-floodplain")
check(all.equal(o$ha[o$metric == "both"], 1), "100 m cells: one cell is 1 ha")
check(v[["both"]] + v[["a_only"]] == v[["a"]] && v[["both"]] + v[["b_only"]] == v[["b"]], "parts sum to totals")
shifted <- terra::shift(b, dx = 100)
check(errs(fp_wf_overlap(a, shifted)), "must-fail arm: two grids are refused, not resampled")

cat("peak RSS\n")
tl <- c("        6.28 real", "  1073741824  maximum resident set size", "  0  page reclaims")
check(identical(fp_wf_peak_rss_gb(tl), 1), "bytes -> GiB from /usr/bin/time -l")
check(is.na(fp_wf_peak_rss_gb(c("Error in foo", "Execution halted"))), "absent line is NA, not 0")

cat(if (n_fail) sprintf("\n%d FAILED\n", n_fail) else "\nall passed\n")
if (n_fail) quit(status = 1)
