# channel_probe-check.R — assert the channel-migration probe helpers on synthetic geometry (#106).
#
# No database, no data/. Every helper in fp_channel.R that rule v2 (research/channel_migration.md)
# depends on is exercised against a fixture whose answer is known by construction, including the
# cases the rule exists to reject: a rigid registration shift (every pair pointing one way), the
# next bend of a meander (same side, different station), a same-bank pair, a pair on another
# blue_line_key, a one-pixel sliver, a lake margin, a raster staircase that would read as elongated,
# drought-year exposure, and flicker that returns to its first class.
#
# usage: Rscript scripts/floodplain_lcc/channel_probe-check.R

suppressMessages({library(sf); library(terra)})
sf::sf_use_s2(FALSE)
source(here::here("scripts", "floodplain_lcc", "fp_channel.R"))

n_fail <- 0L
check <- function(ok, what) {
  ok <- isTRUE(ok)
  if (!ok) n_fail <<- n_fail + 1L
  cat(if (ok) "  ok   " else "  FAIL ", what, "\n", sep = "")
}
crs <- 32610
rect <- function(x0, x1, y0, y1) sf::st_polygon(list(rbind(c(x0, y0), c(x1, y0), c(x1, y1), c(x0, y1), c(x0, y0))))
# rotate clockwise by `deg` (compass sense: north (0, 1) -> (sin, cos)); the ring is closed by
# copying the first vertex, never by recomputing it
rot <- function(g, deg) {
  a <- deg * pi / 180
  xy <- g[[1]][, 1:2] %*% matrix(c(cos(a), sin(a), -sin(a), cos(a)), 2, 2)   # row vectors: (x, y) %*% M
  xy[nrow(xy), ] <- xy[1, ]
  sf::st_polygon(list(xy))
}

cat("roles\n")
r <- fp_ch_role(c(2, 11, 8, 1, 1, 1, 9, 7, 2, 1), c(1, 1, 1, 8, 2, 5, 1, 1, 2, 1))
check(identical(r, c("erosion", "erosion", "erosion", "deposition", "deposition", "other", "other", "other", NA, NA)),
      "erosion / deposition / other / not Water-involving")
cc <- fp_ch_codes(c(2001, 1011))
check(identical(cc$from, c(2L, 1L)) && identical(cc$to, c(1L, 11L)), "codes split from * 1000 + to")
rcl <- fp_ch_role_rcl(c(2001, 1008, 1005, 2002, 2011, NA))
check(identical(unname(rcl[, 1]), c(1005L, 1008L, 2001L, 2002L, 2011L)) && identical(unname(rcl[, 2]), c(3L, 2L, 1L, NA, NA)),
      "reclass (sorted by code): Water->Crops 3, Water->Bare 2, Trees->Water 1, rest NA")
tr <- terra::rast(matrix(c(2001, 11001, 1002, 2011, 2002, 1001), 2, 3))
rr <- fp_ch_role_raster(tr)
check(identical(as.vector(terra::values(rr)), c(1, 2, NA, 1, NA, NA)), "role raster: erosion strip through mixed cover is one role")
check(fp_ch_modal(c(3, 1, 3, 1, 2)) == 1L && is.na(fp_ch_modal(c(NA, NA))), "modal: ties to the smallest, all-NA is NA")

cat("shape\n")
strip <- rect(-10, 10, -150, 150)                     # 20 m x 300 m, long axis north-south
for (deg in c(0, 30, 120, 165)) {
  m <- fp_ch_mrr(sf::st_sfc(rot(strip, deg), crs = crs))
  check(abs(m$elong - 15) < 1e-6 && abs(m$long - 300) < 1e-6, sprintf("MRR elongation 15 at %d deg", deg))
  check(fp_ch_align(m$axis_deg, deg) < 1e-6, sprintf("MRR long axis recovered at %d deg (got %.3f)", deg, m$axis_deg))
}
check(abs(fp_ch_elong_eq(300 * 20, 2 * (300 + 20)) - 15) < 1e-9, "equivalent rectangle recovers 300 x 20")
check(fp_ch_elong_eq(100, 40) == 1 && fp_ch_elong_eq(100, 30) == 1, "a square and anything more compact score 1")
# a 20 m wide quarter-ring (outside bend, centre radius 150 m): MRR ~3.6, equivalent rectangle ~11.8
arc <- sf::st_buffer(sf::st_linestring(t(sapply(seq(0, pi / 2, length.out = 60), function(t) 150 * c(cos(t), sin(t))))),
                     10, endCapStyle = "FLAT")
arc <- sf::st_sfc(arc, crs = crs)
check(fp_ch_mrr(arc)$elong < 5, "MRR understates a crescent (< 5)")
check(fp_ch_elong(arc) > 10, "equivalent-rectangle elongation sees the crescent as the strip it is (> 10)")
# a diamond (square rotated 45 deg) rasterised at 10 m: compact, but its staircase perimeter is
# ~4.8x long if used raw. The 1-cell simplify must bring it back to 1.
diamond <- sf::st_sfc(sf::st_polygon(list(rbind(c(0, -70.7), c(70.7, 0), c(0, 70.7), c(-70.7, 0), c(0, -70.7)))), crs = crs)
grid <- terra::rast(terra::ext(-100, 100, -100, 100), res = 10, crs = "EPSG:32610")
stair <- sf::st_as_sf(terra::as.polygons(terra::rasterize(terra::vect(diamond), grid)))
check(fp_ch_elong_eq(as.numeric(sf::st_area(stair)), fp_ch_perimeter(stair)) > 3,
      "must-fail arm: the raw staircase perimeter would call a rasterised diamond elongated")
check(fp_ch_elong(stair) < 1.5, "the simplified perimeter does not")
check(abs(fp_ch_elong(sf::st_sfc(rot(rect(0, 100, 0, 100), 45), crs = crs)) - 1) < 1e-6, "a rotated square stays at 1")
check(abs(fp_ch_compact(sf::st_sfc(rect(0, 10, 0, 10), crs = crs)) - pi / 4) < 1e-9, "compactness of a square is pi/4")
check(fp_ch_align(10, 170) == 20 && fp_ch_align(0, 90) == 90 && fp_ch_align(30, 210) == 0,
      "alignment folds orientations at 180 and caps at 90")

cat("streams: segments, side, station\n")
# blk 1 runs north along x = 0 in two features (measures 0 and 500) with a repeated vertex;
# blk 2 runs SOUTH along x = 2000, so its digitised direction is reversed and its sides mirrored.
streams <- sf::st_sf(blue_line_key = c(1L, 1L, 2L), downstream_route_measure = c(0, 500, 0),
                     geometry = sf::st_sfc(sf::st_linestring(rbind(c(0, 0), c(0, 250), c(0, 250), c(0, 500))),
                                           sf::st_linestring(rbind(c(0, 500), c(0, 1000))),
                                           sf::st_linestring(rbind(c(2000, 1000), c(2000, 0))), crs = crs))
check(fp_ch_digitised_upstream(streams) == 1, "blk 1 features chain end -> start: digitised upstream")
rev1 <- streams; rev1$geometry[2] <- sf::st_sfc(sf::st_linestring(rbind(c(0, 1000), c(0, 500))), crs = crs)
check(fp_ch_digitised_upstream(rev1) == 0, "must-fail arm: a reversed feature is caught")
seg <- fp_ch_segments(streams)
check(nrow(seg) == 4, "repeated vertex dropped (4 segments, not 5)")
check(all(abs(seg$bearing_deg) < 1e-9), "north-south segments have bearing 0 whichever way digitised")
pts <- sf::st_sfc(sf::st_point(c(50, 300)), sf::st_point(c(-50, 700)),
                  sf::st_point(c(2050, 300)), sf::st_point(c(1950, 300)), crs = crs)
sd <- fp_ch_side(pts, seg)
check(identical(sd$blk, c(1L, 1L, 2L, 2L)), "nearest blue_line_key")
check(sd$side[1] != sd$side[2] && sd$side[3] != sd$side[4], "east and west are opposite sides on both lines")
check(sd$side[1] == -sd$side[3], "digitised direction flips the sign, so sides are only compared within a blk")
check(all(abs(sd$station_m - c(300, 700, 0, 0) - c(0, 0, 700, 700)) < 1e-9),
      "station: measure + distance along the feature (blk 2 counts from its own start)")

cat("sustained\n")
# one cell per case, 2017..2023; first year is the 2017 class
yrs <- 2017:2023
mk <- function(v) terra::rast(lapply(v, function(x) terra::rast(matrix(x, 1, 1))))
sus <- function(v) as.vector(terra::values(fp_ch_sustained(mk(v), yrs)))
check(sus(c(2, 2, 1, 1, 1, 1, 1)) == 1, "erosion in 2019 that stays: sustained")
check(sus(c(1, 8, 11, 11, 2, 2, 2)) == 1, "succession Water -> Bare -> Rangeland -> Trees: sustained")
check(sus(c(2, 1, 2, 1, 1, 1, 1)) == 0, "flicker that returns to Trees: not sustained")
check(sus(c(1, 1, 1, 1, 1, 1, 8)) == 0, "a bar exposed only in the drought year 2023: not sustained")
check(sus(c(1, 1, 1, 1, 1, 8, 8)) == 0, "onset 2022 is after the 2021 cut-off: not sustained")
check(sus(c(1, 9, 1, 2, 2, 2, 2)) == 1, "a Snow/Ice year is missing: not an onset followed by a return")
check(sus(c(1, 10, 1, 2, 2, 2, 2)) == 1, "a Clouds year is missing: not an onset followed by a return")
check(sus(c(2, 1, NA, 1, 1, 1, 1)) == 1, "an NA year is missing, not a return")
check(is.na(sus(c(NA, 1, 1, 1, 1, 1, 1))), "no 2017 class: NA")
check(is.na(sus(c(9, 1, 1, 1, 1, 1, 1))) && is.na(sus(c(10, 1, 1, 1, 1, 1, 1))),
      "a Snow/Ice or Clouds 2017 class is missing too: NA, not sustained")

cat("pairs: station, side, null\n")
# A straight channel along x = 0 (blk 1, northward). Bend 1 at stations 0-200: erosion east,
# deposition west. Bend 2 at 250-450: erosion WEST, deposition EAST. Opposite banks at one station
# must pair; bend 1's erosion and bend 2's deposition are on the same side within 300 m and must
# NOT pair, because their stations do not overlap (this is what filled v1's same-side null).
geo <- sf::st_sfc(rect(40, 60, 0, 200), rect(-60, -40, 0, 200), rect(-60, -40, 250, 450), rect(40, 60, 250, 450),
                  rect(-60, -40, 1300, 1500), rect(-60, -40, 0, 200), crs = crs)
role <- c("erosion", "deposition", "erosion", "deposition", "deposition", "deposition")
blk  <- c(1L, 1L, 1L, 1L, 1L, 2L)
st   <- c(100, 100, 350, 350, 1400, 100)
hl   <- rep(100, 6)
pr <- fp_ch_pairs(geo, role, blk, st, hl)
key <- paste(pr$i, pr$j)
check(setequal(key, c("1 2", "3 4")), sprintf("only the two same-station pairs (got %s)", paste(key, collapse = ", ")))
pr300 <- fp_ch_pairs(geo, role, blk, st, rep(1e6, 6))
check("1 4" %in% paste(pr300$i, pr300$j), "must-fail arm: without the station test, bend 1 erosion pairs with bend 2 deposition")
check(!any(pr$j == 5 | pr$i == 5), "a deposition 1.1 km away does not pair")
check(!"1 5" %in% paste(pr300$i, pr300$j),
      "the 300 m edge-to-edge limit holds on its own (station test disabled)")
check(!any(pr$j == 6 | pr$i == 6), "a deposition on another blue_line_key does not pair")
check(nrow(fp_ch_pairs(geo[c(1, 3)], role[c(1, 3)], blk[c(1, 3)], st[c(1, 3)], c(1e6, 1e6))) == 0, "same role never pairs")
check(nrow(fp_ch_pairs(geo[0], character(0), integer(0), numeric(0), numeric(0))) == 0, "zero patches give zero pairs")
k <- fp_ch_pair_kind(c(-1, -1, -1, -1, 1), c(1, 1, -1, 0, NA), c(TRUE, FALSE, TRUE, TRUE, TRUE))
check(identical(k, c("opposite", "none", "same", "none", "none")),
      "kind: opposite needs IO stable Water between; same is FWA side only; side 0 or NA is none")
fl <- fp_ch_pair_flags(data.frame(i = c(1, 1), j = c(2, 3), kind = c("opposite", "same")), 4)
check(identical(fl$opp, c(TRUE, TRUE, FALSE, FALSE)) && identical(fl$same, c(TRUE, FALSE, TRUE, FALSE)),
      "a patch with both kinds of partner counts in both")

cat("direction (D)\n")
# migration: erosion alternates banks with the bends, so deposition->erosion vectors point both ways
dep <- rbind(c(-50, 100), c(50, 350), c(-50, 600), c(50, 850))
ero <- rbind(c(50, 100), c(-50, 350), c(50, 600), c(-50, 850))
check(fp_ch_direction_r(dep, ero) < 0.1, "alternating bends: R near 0")
# a rigid 2-px shift east between epochs: every reach erodes its east bank, whatever its bearing
th  <- c(0, 40, 80, 120, 160) * pi / 180
dep <- cbind(-20 * cos(0) + 1000 * sin(th), 1000 * cos(th))
ero <- dep + cbind(rep(40, 5), 0)
check(fp_ch_direction_r(dep, ero) > 0.99, "must-fail arm: a rigid shift points every pair one way (R ~ 1)")
check(is.na(fp_ch_direction_r(dep, dep)), "zero-length vectors carry no direction")

cat("candidate\n")
base <- data.frame(role = "erosion", width_px = 2, elong = 5, channel_adjacent = TRUE, align_deg = 10)
check(fp_ch_candidate(base), "a wide, long, adjacent, aligned erosion strip is a candidate")
check(!fp_ch_candidate(transform(base, width_px = 0.95)), "a one-pixel band (drift sliver) is not")
check(!fp_ch_candidate(transform(base, elong = 2.9)), "a stubby patch is not")
check(!fp_ch_candidate(transform(base, channel_adjacent = FALSE)), "a patch away from the channel is not")
check(!fp_ch_candidate(transform(base, align_deg = 31)), "a patch across the channel is not")
check(!fp_ch_candidate(transform(base, role = "other")), "Water -> Crops ('other') is not")
check(identical(fp_ch_channel_adjacent(c(TRUE, TRUE, FALSE, TRUE, TRUE), c(10, 60, 10, 10, NA), c(FALSE, FALSE, FALSE, TRUE, FALSE)),
                c(TRUE, FALSE, FALSE, FALSE, FALSE)),
      "channel_adjacent is IO AND FWA <= 50 m AND not a lake margin")

cat("rule\n")
x <- data.frame(area_ha = c(10, 10, 40, 40), candidate = c(TRUE, TRUE, FALSE, FALSE), width_px = c(2, 2, 2, 0.5),
                sustained = c(0.9, 0.9, 0.5, 0.0), paired_opp = c(TRUE, FALSE, FALSE, FALSE),
                paired_same = c(FALSE, FALSE, FALSE, FALSE))
r <- fp_ch_rule(x, dir_r = 0.2, n_opp = 12)
check(r$A && abs(r$cand_share - 0.2) < 1e-12, "A holds at exactly 20%")
check(r$B && abs(r$sustained_lead - 0.4) < 1e-12, "B compares with width-matched non-candidates only (lead 0.4)")
# a sliver (width 0.5) with sustained 0 sits beside a wide non-candidate at 0.5: the lead over the
# width-matched set is 0.1 (B fails); over all non-candidates it would be 0.35 (B would pass)
r_sl <- fp_ch_rule(transform(x, sustained = c(0.6, 0.6, 0.5, 0.0)), 0.2, 12)
check(!r_sl$B && abs(r_sl$sustained_lead - 0.1) < 1e-12,
      "must-fail arm: a lead the slivers would have manufactured is not counted")
check(r$C && r$D && fp_ch_separates(r), "C and D hold; the cluster separates")
check(!fp_ch_rule(transform(x, paired_same = c(FALSE, TRUE, FALSE, FALSE)), 0.2, 12)$C,
      "C fails when the opposite share is under 10 points above the same-side share")
check(!fp_ch_rule(x, dir_r = 0.6, n_opp = 12)$D, "D fails when pairs point one way")
check(!fp_ch_rule(x, dir_r = 0.2, n_opp = 9)$D, "D fails with fewer than 10 opposite pairs")
check(!fp_ch_rule(transform(x, candidate = FALSE), NA, 0)$A, "no candidates: nothing holds")

cat("verdict table\n")
check(fp_ch_verdict(TRUE, TRUE, TRUE) == "separates", "all hold: separates")
check(fp_ch_verdict(TRUE, FALSE, TRUE) == "separates below the sieve", "unsieved only: below the sieve")
check(fp_ch_verdict(TRUE, TRUE, FALSE) == "NECR only", "BULK direction fails: NECR only")
check(fp_ch_verdict(FALSE, TRUE, TRUE) == "does not separate", "sieved only: does not separate")

cat(if (n_fail) sprintf("\n%d FAILED\n", n_fail) else "\nall passed\n")
if (n_fail) quit(status = 1)
