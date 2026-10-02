# fp_channel.R — channel-migration probe helpers (#106).
#
# The rule they implement is pre-registered in research/channel_migration.md (rule v2). The
# thresholds below are copied from it and must not be tuned to a result. Everything here except
# fp_ch_sustained() and fp_ch_role_raster() (terra algebra) is pure R/sf over small inputs, so
# channel_probe-check.R asserts all of it offline.

FP_CH_WATER         <- 1L
# IO LULC codes: 2 Trees, 4 Flooded Vegetation, 5 Crops, 8 Bare Ground, 9 Snow/Ice, 10 Clouds, 11 Rangeland
FP_CH_EROSION_FROM  <- c(2L, 4L, 5L, 8L, 11L)   # X -> Water
FP_CH_DEPOSITION_TO <- c(2L, 4L, 8L, 11L)       # Water -> Y
FP_CH_MISSING       <- c(9L, 10L)               # a year in these is missing, not a switch
FP_CH_ROLES         <- c("erosion", "deposition", "other")   # raster codes 1, 2, 3

# Pre-registered thresholds (research/channel_migration.md, rule v2)
FP_CH_WIDTH_MIN_PX  <- 1.5    # not a drift sliver
FP_CH_ELONG_MIN     <- 3
FP_CH_SIMPLIFY_M    <- 10     # one cell: removes raster staircase before the perimeter is used for elong
FP_CH_IO_ADJ_CELLS  <- 3      # endpoint Water within 3 cells
FP_CH_FWA_DIST_MAX  <- 50     # m, allows for 1:20k offset
FP_CH_POLY_REACH    <- 500    # m, beyond this the stream line stands in for fwa_rivers_poly
FP_CH_LAKE_DIST     <- 50     # m from fwa_lakes_poly = lake margin
FP_CH_ALIGN_MAX     <- 30     # degrees
FP_CH_PAIR_DIST     <- 300    # m, edge to edge
FP_CH_ONSET_MAX     <- 2021L  # sustained: first year away from the 2017 class
FP_CH_RULE_A        <- 0.20   # candidate share of Water-involving area
FP_CH_RULE_B        <- 0.15   # sustained lead over width-matched non-candidates
FP_CH_RULE_C        <- 0.25   # opposite-paired share of candidate area
FP_CH_RULE_C_MARGIN <- 0.10   # opposite share over same-side share
FP_CH_RULE_D        <- 0.5    # mean resultant length of pair directions must be below this
FP_CH_RULE_D_MIN    <- 10L    # opposite pairs needed for D to be decidable

# --- classes and roles -----------------------------------------------------------------------------

# from/to class codes from a transition id (from * 1000 + to)
fp_ch_codes <- function(id) {
  id <- as.integer(id)
  data.frame(from = id %/% 1000L, to = id %% 1000L)
}

# "erosion" / "deposition" / "other" for Water-involving transitions, NA for the rest
fp_ch_role <- function(from, to) {
  w_from <- from == FP_CH_WATER
  w_to   <- to == FP_CH_WATER
  out <- ifelse(xor(w_from, w_to), "other", NA_character_)
  out[w_to & from %in% FP_CH_EROSION_FROM]  <- "erosion"
  out[w_from & to %in% FP_CH_DEPOSITION_TO] <- "deposition"
  out
}

# Reclassification matrix: transition code -> role code (1/2/3); non-Water-involving codes -> NA
fp_ch_role_rcl <- function(codes) {
  codes <- sort(unique(as.integer(codes[!is.na(codes)])))
  cc <- fp_ch_codes(codes)
  cbind(codes, match(fp_ch_role(cc$from, cc$to), FP_CH_ROLES))
}

# Role raster from a raw-code transition raster (no category table)
fp_ch_role_raster <- function(tr_raw) {
  codes <- terra::unique(tr_raw)[[1]]
  terra::classify(tr_raw, fp_ch_role_rcl(codes), others = NA)
}

# Most frequent value; ties to the smallest (deterministic)
fp_ch_modal <- function(v) {
  v <- v[!is.na(v)]
  if (!length(v)) return(NA_integer_)
  tb <- table(v)
  as.integer(names(tb)[tb == max(tb)][1])
}

# --- shape -------------------------------------------------------------------------------------------

# Minimum rotated rectangle per geometry: long and short side (m) and the long axis as a line
# orientation in degrees from north, folded to [0, 180).
fp_ch_mrr <- function(geom) {
  m <- sf::st_minimum_rotated_rectangle(sf::st_geometry(geom))
  out <- vapply(seq_along(m), function(i) {
    xy <- unname(sf::st_coordinates(m[i])[, 1:2, drop = FALSE])   # named elements would rename c()'s entries
    e1 <- xy[2, ] - xy[1, ]
    e2 <- xy[3, ] - xy[2, ]
    l1 <- sqrt(sum(e1^2))
    l2 <- sqrt(sum(e2^2))
    lng <- if (l1 >= l2) e1 else e2
    c(long = max(l1, l2), short = min(l1, l2),
      axis_deg = (atan2(lng[1], lng[2]) * 180 / pi) %% 180)
  }, numeric(3))
  data.frame(long = out["long", ], short = out["short", ], axis_deg = out["axis_deg", ],
             elong = out["long", ] / out["short", ])
}

# Perimeter (m). st_boundary, not st_perimeter: the latter needs lwgeom on projected data.
fp_ch_perimeter <- function(geom) as.numeric(sf::st_length(sf::st_boundary(sf::st_geometry(geom))))

# Equivalent-rectangle long/short ratio from area and perimeter: the L x W rectangle with the same
# A and P has L, W = P/4 +- sqrt(P^2/16 - A). Bending a strip changes neither, so a crescent scores
# as the strip it is. 1 when no such rectangle exists (more compact than a square).
fp_ch_elong_eq <- function(area, perim) {
  disc <- perim^2 / 16 - area
  out <- rep(1, length(area))
  ok <- disc > 0
  r <- sqrt(disc[ok])
  out[ok] <- (perim[ok] / 4 + r) / (perim[ok] / 4 - r)
  out
}

# Bend-invariant elongation, with the raster staircase removed from the perimeter first
fp_ch_elong <- function(geom, simplify_m = FP_CH_SIMPLIFY_M) {
  g <- sf::st_geometry(geom)
  p <- fp_ch_perimeter(sf::st_simplify(g, preserveTopology = TRUE, dTolerance = simplify_m))
  fp_ch_elong_eq(as.numeric(sf::st_area(g)), p)
}

# 4 pi A / P^2: 1 for a circle, pi/4 for a square, towards 0 for a strip
fp_ch_compact <- function(geom) 4 * pi * as.numeric(sf::st_area(geom)) / fp_ch_perimeter(geom)^2

# Angle between two line orientations (degrees, any range), folded to [0, 90]
fp_ch_align <- function(a, b) {
  d <- abs(a - b) %% 180
  pmin(d, 180 - d)
}

# --- stream geometry ---------------------------------------------------------------------------------

# Share of consecutive features on a blue_line_key (ordered by downstream_route_measure) whose END
# meets the next one's START. 1 means digitised upstream, the direction station_m assumes.
fp_ch_digitised_upstream <- function(streams) {
  s <- sf::st_cast(streams, "LINESTRING", warn = FALSE)
  s <- s[order(s$blue_line_key, s$downstream_route_measure), ]
  n <- nrow(s)
  if (n < 2) return(NA_real_)
  st <- sf::st_coordinates(sf::st_line_sample(sf::st_geometry(s), sample = 0))[, 1:2, drop = FALSE]
  en <- sf::st_coordinates(sf::st_line_sample(sf::st_geometry(s), sample = 1))[, 1:2, drop = FALSE]
  same <- s$blue_line_key[-1] == s$blue_line_key[-n]
  if (!any(same)) return(NA_real_)
  d <- sqrt(rowSums((en[-n, , drop = FALSE] - st[-1, , drop = FALSE])^2))
  mean(d[same] < 1)
}

# Explode stream lines into two-vertex segments carrying blue_line_key, the digitised direction
# (dx, dy), the line orientation (degrees from north, [0, 180)), and s0: the along-stream station
# of the segment start (downstream_route_measure + distance along the feature).
fp_ch_segments <- function(streams) {
  need <- c("blue_line_key", "downstream_route_measure")
  if (!all(need %in% names(streams))) stop("streams need ", paste(need, collapse = " + "), call. = FALSE)
  s <- streams[, need]
  s$feat <- seq_len(nrow(s))
  ls <- sf::st_cast(sf::st_cast(s, "MULTILINESTRING", warn = FALSE), "LINESTRING", warn = FALSE)
  xy <- sf::st_coordinates(ls)
  n  <- nrow(xy)
  k  <- which(xy[-1, "L1"] == xy[-n, "L1"])
  part <- xy[k, "L1"]
  x0 <- xy[k, "X"]; y0 <- xy[k, "Y"]; x1 <- xy[k + 1, "X"]; y1 <- xy[k + 1, "Y"]
  len <- sqrt((x1 - x0)^2 + (y1 - y0)^2)
  # distance along the ORIGINAL feature at each segment start, across its parts in order
  feat <- ls$feat[part]
  s0 <- ls$downstream_route_measure[part] + stats::ave(len, feat, FUN = function(v) cumsum(v) - v)
  keep <- len > 0                                       # a repeated vertex has no direction
  g <- sf::st_sfc(lapply(which(keep), function(i) sf::st_linestring(rbind(c(x0[i], y0[i]), c(x1[i], y1[i])))),
                  crs = sf::st_crs(streams))
  sf::st_sf(blue_line_key = ls$blue_line_key[part][keep],
            x0 = x0[keep], y0 = y0[keep], dx = (x1 - x0)[keep], dy = (y1 - y0)[keep],
            len = len[keep], s0 = s0[keep],
            bearing_deg = (atan2(x1 - x0, y1 - y0)[keep] * 180 / pi) %% 180,
            geometry = g)
}

# For each point: the nearest segment's blue_line_key and bearing, which side of the segment's
# digitised direction the point lies on (+1 left, -1 right, 0 on the line), and its station.
fp_ch_side <- function(pts, seg) {
  i  <- sf::st_nearest_feature(pts, seg)
  xy <- sf::st_coordinates(pts)
  px <- xy[, "X"] - seg$x0[i]
  py <- xy[, "Y"] - seg$y0[i]
  cr <- seg$dx[i] * py - seg$dy[i] * px
  t  <- pmin(pmax((px * seg$dx[i] + py * seg$dy[i]) / seg$len[i]^2, 0), 1)
  data.frame(blk = seg$blue_line_key[i], bearing_deg = seg$bearing_deg[i], side = sign(cr),
             station_m = seg$s0[i] + t * seg$len[i])
}

# --- persistence -------------------------------------------------------------------------------------

# Per cell over an ordered annual stack of raw IO codes: 1 when the cell left its FIRST-year class
# once and never returned, with the first year away no later than `onset_max`; else 0. Years in
# FP_CH_MISSING or NA are skipped, neither away nor back. NA where the first year is NA or missing.
fp_ch_sustained <- function(stack, years, onset_max = FP_CH_ONSET_MAX) {
  n <- terra::nlyr(stack)
  if (n < 2 || length(years) != n) stop("need >= 2 layers, one per year", call. = FALSE)
  rcl <- cbind(FP_CH_MISSING, NA)
  f <- terra::classify(stack[[1]], rcl)                  # a missing first year is NA, not a class
  away_ever <- returned <- f * 0                         # 0 inside the footprint, NA outside
  onset_ok <- f * 0
  for (k in 2:n) {
    c_k  <- terra::classify(stack[[k]], rcl)
    away <- terra::ifel(is.na(c_k), 0, c_k != f)
    back <- terra::ifel(is.na(c_k), 0, c_k == f)
    returned  <- returned | (away_ever & back)
    away_ever <- away_ever | away
    if (years[k] <= onset_max) onset_ok <- away_ever
  }
  onset_ok & !returned
}

# --- pairs -------------------------------------------------------------------------------------------

# Candidate pairs (i < j): opposite role, same blk, within dist_max edge to edge, and overlapping
# station intervals (station_m +- half_len). Indices refer to the rows given.
fp_ch_pairs <- function(geom, role, blk, station, half_len, dist_max = FP_CH_PAIR_DIST) {
  none <- data.frame(i = integer(0), j = integer(0))
  if (length(role) < 2) return(none)
  nb <- sf::st_is_within_distance(sf::st_geometry(geom), sf::st_geometry(geom), dist = dist_max)
  out <- lapply(seq_along(nb), function(i) {
    j <- nb[[i]]
    j <- j[j > i & role[j] != role[i] & !is.na(blk[j]) & !is.na(blk[i]) & blk[j] == blk[i] &
             abs(station[j] - station[i]) <= half_len[i] + half_len[j]]
    if (length(j)) data.frame(i = i, j = j) else NULL
  })
  out <- do.call(rbind, out)
  if (is.null(out)) none else out
}

# Pair kind: "opposite" (FWA sides differ AND the line between crosses IO stable water),
# "same" (FWA sides equal), else "none"
fp_ch_pair_kind <- function(side_i, side_j, crosses) {
  ok <- !is.na(side_i) & !is.na(side_j) & side_i != 0 & side_j != 0
  ifelse(ok & side_i != side_j & crosses %in% TRUE, "opposite",
         ifelse(ok & side_i == side_j, "same", "none"))
}

# Per-patch flags from a pair table with a `kind` column; a patch can be both
fp_ch_pair_flags <- function(pairs, n) {
  opp <- same <- logical(n)
  o <- pairs[pairs$kind == "opposite", ]
  s <- pairs[pairs$kind == "same", ]
  opp[c(o$i, o$j)] <- TRUE
  same[c(s$i, s$j)] <- TRUE
  data.frame(opp = opp, same = same)
}

# Mean resultant length of the unit vectors from each deposition point to its erosion partner
fp_ch_direction_r <- function(dep_xy, ero_xy) {
  v <- ero_xy - dep_xy
  l <- sqrt(rowSums(v^2))
  v <- v[l > 0, , drop = FALSE] / l[l > 0]
  if (!nrow(v)) return(NA_real_)
  sqrt(sum(v[, 1])^2 + sum(v[, 2])^2) / nrow(v)
}

# --- candidate and rule ------------------------------------------------------------------------------

fp_ch_channel_adjacent <- function(io_adjacent, fwa_dist_m, lake_margin) {
  io_adjacent %in% TRUE & !is.na(fwa_dist_m) & fwa_dist_m <= FP_CH_FWA_DIST_MAX & !(lake_margin %in% TRUE)
}

fp_ch_candidate <- function(x) {
  !is.na(x$role) & x$role %in% c("erosion", "deposition") &
    x$width_px >= FP_CH_WIDTH_MIN_PX &
    x$elong >= FP_CH_ELONG_MIN &
    x$channel_adjacent &
    !is.na(x$align_deg) & x$align_deg <= FP_CH_ALIGN_MAX
}

# The pre-registered separation rule over one patch set. `x` needs area_ha, candidate, width_px,
# sustained, paired_opp, paired_same; `dir_r` and `n_opp` come from the opposite pairs.
fp_ch_rule <- function(x, dir_r, n_opp) {
  aw <- function(v, w) {
    k <- !is.na(v)
    if (sum(w[k]) > 0) sum(v[k] * w[k]) / sum(w[k]) else NA_real_
  }
  cand  <- x$candidate
  wm    <- !cand & x$width_px >= FP_CH_WIDTH_MIN_PX         # width-matched non-candidates
  a_all <- sum(x$area_ha)
  a_c   <- sum(x$area_ha[cand])
  ss_c  <- aw(x$sustained[cand], x$area_ha[cand])
  ss_w  <- aw(x$sustained[wm], x$area_ha[wm])
  pr_o  <- if (a_c > 0) sum(x$area_ha[cand & x$paired_opp]) / a_c else NA_real_
  pr_s  <- if (a_c > 0) sum(x$area_ha[cand & x$paired_same]) / a_c else NA_real_
  d_ok  <- n_opp >= FP_CH_RULE_D_MIN && isTRUE(dir_r < FP_CH_RULE_D)
  data.frame(
    water_ha = a_all, cand_ha = a_c, cand_share = if (a_all > 0) a_c / a_all else NA_real_,
    sustained_cand = ss_c, sustained_wm = ss_w, sustained_lead = ss_c - ss_w,
    paired_opp = pr_o, paired_same = pr_s, n_opp_pairs = n_opp, dir_r = dir_r,
    A = isTRUE(a_c / a_all >= FP_CH_RULE_A),
    B = isTRUE(ss_c - ss_w >= FP_CH_RULE_B),
    C = isTRUE(pr_o >= FP_CH_RULE_C) && isTRUE(pr_o - pr_s >= FP_CH_RULE_C_MARGIN),
    D = d_ok,
    B_dir = isTRUE(ss_c - ss_w > 0),
    C_dir = isTRUE(pr_o > pr_s),
    D_dir = d_ok
  )
}

fp_ch_separates <- function(r) r$A && r$B && r$C && r$D
fp_ch_direction_holds <- function(r) r$B_dir && r$C_dir && r$D_dir

# The pre-registered outcome table (research/channel_migration.md, "Outcomes, decided in advance")
fp_ch_verdict <- function(necr_unsieved, necr_sieved, bulk_dir) {
  if (!necr_unsieved) return("does not separate")
  if (!bulk_dir) return("NECR only")
  if (necr_sieved) "separates" else "separates below the sieve"
}
