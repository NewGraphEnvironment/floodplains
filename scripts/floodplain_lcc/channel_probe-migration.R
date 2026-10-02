# channel_probe-migration.R — does channel migration separate in IO's Water change? (#106)
#
# Applies rule v2, pre-registered in research/channel_migration.md, to one area's primary scenario
# on two patch sets:
#   unsieved  2017 -> 2023 re-derived from the on-disk endpoint rasters (patch_area_min = NULL)
#   sieved    the published transition.tif (1 ha sieve, step 3)
# Cells with exactly one Water endpoint get a role (erosion / deposition / other) and patches are
# 8-connected runs of one ROLE, so a bank eroding through mixed cover stays one strip. Per patch it
# measures what the rule names; drift::dft_transition_artifact() runs separately on transition-level
# patches for the misregistration report (sliver and exact-reciprocal shares).
#
# Two exact anchors stop the run before anything is measured: re-sieving the endpoints at 1 ha must
# reproduce transition.tif cell for cell, and (where reference/<area>/strata.csv exists) the
# unsieved total change must equal the strata's change + sieved area.
#
# READ-ONLY on everything step 3 publishes. It writes:
#   data/<area>/channel/probe_<set>.gpkg     per-patch metrics with geometry (gitignored; nominates
#                                            reaches for the dated-imagery follow-up). The publish
#                                            layer copies data/<area>/ files by explicit name, so
#                                            this never ships.
#   scripts/floodplain_lcc/logs/<yyyymmdd>_channel-migration_<area>.{csv,md}   rule + distributions
#
# Needs the full annual series (lulc_annual: true) and a database (libpq env from ~/.Renviron) for
# whse_basemapping.fwa_rivers_poly and fwa_lakes_poly.
#
# usage: Rscript scripts/floodplain_lcc/channel_probe-migration.R <area>

suppressMessages({library(sf); library(terra); library(DBI); library(RPostgres); library(yaml)})
sf::sf_use_s2(FALSE)
`%||%` <- function(a, b) if (is.null(a)) b else a
source(here::here("scripts", "landcover_accuracy", "fp_accuracy.R"))   # fp_acc_area, fp_acc_grid
source(here::here("scripts", "floodplain_lcc", "fp_channel.R"))
source(here::here("scripts", "fp_gpkg.R"))
fp_gpkg_pin_date()                                                        # #45

if (utils::packageVersion("drift") < "0.20.0")
  stop("drift >= 0.20.0 is required for dft_transition_artifact()", call. = FALSE)

area <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(area) || !grepl("^[a-z0-9_]+$", area))
  stop("usage: channel_probe-migration.R <area>", call. = FALSE)
cfg  <- fp_acc_area(area)
yrs  <- seq(cfg$change_interval[1], cfg$change_interval[2])
ends <- as.character(cfg$change_interval)
res_m <- NA_real_

# Refuse before reading anything: `sustained` needs every year, not just the endpoints.
need <- c(file.path(cfg$dir_rast, sprintf("classified_%d.tif", yrs)), file.path(cfg$dir_rast, "transition.tif"))
if (any(!file.exists(need)))
  stop("missing rasters (the probe needs lulc_annual: true outputs):\n  ",
       paste(need[!file.exists(need)], collapse = "\n  "), call. = FALSE)

message("== ", area, " / ", cfg$primary_scenario, " (", ends[1], " -> ", ends[2], ")")
g <- fp_acc_grid(cfg)   # raw codes, every year; stops if transition.tif is out of sync with them
res_m <- terra::res(g$from)[1]

raw <- function(r) { r <- terra::deepcopy(r); terra::set.cats(r, layer = 1, value = NULL); r }
n_diff <- function(a, b) terra::global((is.na(a) != is.na(b)) | (!is.na(a) & !is.na(b) & (a != b)),
                                       "sum", na.rm = TRUE)[[1]]

# --- the two transition rasters, and the anchors ---------------------------------------------------
cls_f <- stats::setNames(lapply(ends, function(y) terra::rast(file.path(cfg$dir_rast, sprintf("classified_%s.tif", y)))), ends)
tr_u <- drift::dft_rast_transition(cls_f, from = ends[1], to = ends[2], patch_area_min = NULL)$raster
tr_s <- terra::rast(file.path(cfg$dir_rast, "transition.tif"))
raw_u <- raw(tr_u)
raw_s <- raw(tr_s)

d_u <- n_diff(raw_u, g$from * 1000L + g$to)
if (d_u > 0) stop("ANCHOR FAIL: ", d_u, " unsieved transition cells disagree with the endpoint rasters", call. = FALSE)
resieved <- raw(drift::dft_rast_transition(cls_f, from = ends[1], to = ends[2], patch_area_min = 10000)$raster)
d_s <- n_diff(resieved, raw_s)
message("  anchor 1: re-sieved at 1 ha vs transition.tif: ", d_s, " differing cells")
if (d_s > 0) stop("ANCHOR FAIL: re-sieving does not reproduce transition.tif (", d_s, " cells)", call. = FALSE)
rm(resieved)

chg_ha <- terra::global(g$from != g$to, "sum", na.rm = TRUE)[[1]] * res_m^2 / 1e4
anchor2 <- NA_real_
st_csv <- file.path(cfg$dir_ref, "strata.csv")
if (file.exists(st_csv)) {
  st <- utils::read.csv(st_csv, stringsAsFactors = FALSE)
  anchor2 <- sum(st$area[st$kind %in% c("change", "sieved")])
  message(sprintf("  anchor 2: unsieved total change %.2f ha vs strata change + sieved %.2f ha", chg_ha, anchor2))
  if (abs(chg_ha - anchor2) > 0.01)
    stop("ANCHOR FAIL: unsieved total change does not match ", st_csv, call. = FALSE)
} else message("  anchor 2: no strata.csv for ", area, " -- skipped")

# --- per-cell layers shared by both sets ---------------------------------------------------------
win <- 2L * FP_CH_IO_ADJ_CELLS + 1L
adj_from <- terra::focal(g$from == FP_CH_WATER, w = win, fun = "max", na.rm = TRUE)
adj_to   <- terra::focal(g$to == FP_CH_WATER, w = win, fun = "max", na.rm = TRUE)
sustained <- fp_ch_sustained(terra::rast(g$cls), as.integer(names(g$cls)))
stable_w <- (g$from == FP_CH_WATER) & (g$to == FP_CH_WATER)
cells <- c(adj_from, adj_to, sustained)
names(cells) <- c("adj_from", "adj_to", "sustained")

# --- FWA channel geometry ------------------------------------------------------------------------
crs <- terra::crs(g$from)
streams <- sf::st_read(file.path(cfg$dir_out, "aquatic_network.gpkg"),
                       layer = sprintf("streams_%s%d", cfg$species, cfg$min_order), quiet = TRUE)
streams <- sf::st_transform(streams, crs)
up <- fp_ch_digitised_upstream(streams)
message(sprintf("  FWA digitised upstream: %.4f of consecutive features", up))
if (!isTRUE(up >= 0.99)) stop("streams are not digitised upstream -- station_m would be wrong", call. = FALSE)
seg <- fp_ch_segments(streams)
conn <- DBI::dbConnect(RPostgres::Postgres())
q_wsg <- function(tbl) sf::st_read(conn, query = DBI::sqlInterpolate(conn,
  paste0("SELECT geom FROM whse_basemapping.", tbl, " WHERE watershed_group_code = ?wsg"),
  wsg = toupper(cfg$watershed_group)), quiet = TRUE)
rivers <- sf::st_transform(q_wsg("fwa_rivers_poly"), crs)   # the rule: river polygons in the WSG
# Lakes by footprint, not by group: the rule's lake margin has no WSG limit, and a lake assigned to
# the neighbouring group can sit within 50 m of a patch at the group boundary.
fp_bb <- sf::st_bbox(sf::st_buffer(sf::st_as_sfc(sf::st_bbox(g$from)), FP_CH_LAKE_DIST))
fp_bb <- sf::st_bbox(sf::st_transform(sf::st_as_sfc(fp_bb), 3005))   # fwapg stores BC Albers
lakes <- sf::st_read(conn, query = DBI::sqlInterpolate(conn,
  "SELECT geom FROM whse_basemapping.fwa_lakes_poly WHERE geom && ST_MakeEnvelope(?x0, ?y0, ?x1, ?y1, 3005)",
  x0 = fp_bb[["xmin"]], y0 = fp_bb[["ymin"]], x1 = fp_bb[["xmax"]], y1 = fp_bb[["ymax"]]), quiet = TRUE)
lakes <- sf::st_transform(lakes, crs)
DBI::dbDisconnect(conn)
message("  FWA: ", nrow(seg), " stream segments, ", nrow(rivers), " river polygons, ", nrow(lakes), " lakes")

near_dist <- function(x, y) {
  if (!nrow(y)) return(rep(Inf, nrow(x)))
  as.numeric(sf::st_distance(x, y[sf::st_nearest_feature(x, y), ], by_element = TRUE))
}

# --- role patches ----------------------------------------------------------------------------------
role_patches <- function(rr) {
  out <- lapply(seq_along(FP_CH_ROLES), function(v) {
    pv <- terra::patches(terra::ifel(rr == v, 1L, NA), directions = 8)
    if (is.na(terra::global(pv, "max", na.rm = TRUE)[[1]])) return(NULL)
    p <- sf::st_as_sf(terra::as.polygons(pv))
    sf::st_sf(role = FP_CH_ROLES[v], geometry = sf::st_geometry(p))
  })
  do.call(rbind, out)
}

probe_set <- function(tr, tr_raw, set) {
  t0 <- Sys.time()
  p <- role_patches(fp_ch_role_raster(tr_raw))
  if (is.null(p) || !nrow(p)) stop(set, ": no Water-involving change", call. = FALSE)
  p$patch_id <- seq_len(nrow(p))
  p$area_ha <- as.numeric(sf::st_area(p)) / 1e4

  # per-patch cell values, cell centres inside the (cell-aligned) polygons
  ex <- terra::extract(c(tr_raw, cells), terra::vect(p))
  names(ex) <- c("ID", "code", "adj_from", "adj_to", "sustained")
  if (abs(nrow(ex) * res_m^2 / 1e4 - sum(p$area_ha)) > 0.01)
    stop(set, ": extracted cells do not cover the patches", call. = FALSE)
  by_id <- function(v, f) { o <- tapply(v, factor(ex$ID, levels = p$patch_id), f); unname(o) }
  p$code_dom   <- by_id(ex$code, fp_ch_modal)
  cc <- fp_ch_codes(p$code_dom)
  p$from_dom <- cc$from
  p$to_dom   <- cc$to
  af <- by_id(ex$adj_from, function(v) max(v, na.rm = TRUE))
  at <- by_id(ex$adj_to, function(v) max(v, na.rm = TRUE))
  p$io_adjacent <- ifelse(p$role == "deposition", at, af) %in% 1
  p$sustained <- by_id(as.numeric(ex$sustained), function(v) mean(v, na.rm = TRUE))

  p$width_px <- 2 * as.numeric(sf::st_area(p)) / fp_ch_perimeter(p) / res_m
  p$elong <- fp_ch_elong(p)
  m <- fp_ch_mrr(p)
  p$mrr_long_m <- m$long
  p$elong_mrr <- m$elong
  p$axis_deg <- m$axis_deg
  p$compact <- fp_ch_compact(p)

  pts <- sf::st_point_on_surface(sf::st_geometry(p))
  sd <- fp_ch_side(pts, seg)
  p$blk <- sd$blk
  p$side <- sd$side
  p$station_m <- sd$station_m
  p$align_deg <- fp_ch_align(p$axis_deg, sd$bearing_deg)

  d_poly <- near_dist(p, rivers)
  p$fwa_dist_m <- ifelse(d_poly <= FP_CH_POLY_REACH, d_poly, near_dist(p, seg))
  p$lake_margin <- near_dist(p, lakes) <= FP_CH_LAKE_DIST
  p$channel_adjacent <- fp_ch_channel_adjacent(p$io_adjacent, p$fwa_dist_m, p$lake_margin)
  p$candidate <- fp_ch_candidate(p)

  # pairs among candidates
  ci <- which(p$candidate)
  pr <- fp_ch_pairs(p[ci, ], p$role[ci], p$blk[ci], p$station_m[ci], p$mrr_long_m[ci] / 2)
  pr$i <- ci[pr$i]
  pr$j <- ci[pr$j]
  if (nrow(pr)) {
    xy <- sf::st_coordinates(pts)[, 1:2, drop = FALSE]
    ln <- sf::st_sfc(lapply(seq_len(nrow(pr)), function(k) sf::st_linestring(rbind(xy[pr$i[k], ], xy[pr$j[k], ]))), crs = crs)
    sx <- terra::extract(stable_w, terra::vect(ln))
    pr$crosses <- as.logical(tapply(sx[[2]] %in% TRUE, factor(sx$ID, levels = seq_len(nrow(pr))), any))
    pr$kind <- fp_ch_pair_kind(p$side[pr$i], p$side[pr$j], pr$crosses)
    pr$fwa_opposite <- p$side[pr$i] != p$side[pr$j]
    ero <- ifelse(p$role[pr$i] == "erosion", pr$i, pr$j)
    dep <- ifelse(p$role[pr$i] == "erosion", pr$j, pr$i)
    pr$exact_reverse <- p$from_dom[ero] == p$to_dom[dep]
    pr$ero <- ero
    pr$dep <- dep
  } else {
    pr <- cbind(pr, crosses = logical(0), kind = character(0), fwa_opposite = logical(0),
                exact_reverse = logical(0), ero = integer(0), dep = integer(0))
  }
  fl <- fp_ch_pair_flags(pr, nrow(p))
  p$paired_opp <- fl$opp
  p$paired_same <- fl$same
  o <- pr[pr$kind == "opposite", ]
  xy <- sf::st_coordinates(pts)[, 1:2, drop = FALSE]
  dir_r <- fp_ch_direction_r(xy[o$dep, , drop = FALSE], xy[o$ero, , drop = FALSE])

  rule <- fp_ch_rule(sf::st_drop_geometry(p), dir_r, nrow(o))
  # misregistration report on transition-level patches (drift's own unit)
  wv <- terra::mask(tr, terra::classify(tr_raw, fp_ch_role_rcl(terra::unique(tr_raw)[[1]]), others = NA))
  tv <- drift::dft_transition_vectors(wv, changes_only = TRUE)
  tv <- drift::dft_transition_artifact(tv, tr)
  tv_a <- sum(tv$area_ha)
  rule$sliver_share <- sum(tv$area_ha[tv$width_px < FP_CH_WIDTH_MIN_PX]) / tv_a
  rule$reciprocal_share <- sum(tv$area_ha[tv$flag_reciprocal %in% TRUE]) / tv_a
  rule$opp_exact_reverse <- if (nrow(o)) mean(o$exact_reverse) else NA_real_
  rule$opp_fwa_without_crossing <- if (nrow(pr)) sum(pr$fwa_opposite & !(pr$crosses %in% TRUE), na.rm = TRUE) else 0L
  rule$n_patches <- nrow(p)
  rule$n_candidates <- length(ci)

  message(sprintf("  %s: %d role patches, %.2f ha, %d candidates, %d opposite / %d same pairs (%s)",
                  set, nrow(p), sum(p$area_ha), length(ci), sum(pr$kind == "opposite"),
                  sum(pr$kind == "same"), format(round(Sys.time() - t0, 1))))
  list(p = p, pairs = pr, rule = rule)
}

sets <- list(unsieved = probe_set(tr_u, raw_u, "unsieved"), sieved = probe_set(tr_s, raw_s, "sieved"))

# --- outputs ---------------------------------------------------------------------------------------
out_dir <- file.path(cfg$dir_out, "channel")
dir.create(out_dir, showWarnings = FALSE)
for (nm in names(sets)) {
  f <- file.path(out_dir, sprintf("probe_%s.gpkg", nm))
  if (file.exists(f)) file.remove(f)
  sf::st_write(sets[[nm]]$p, f, layer = "patches", quiet = TRUE)
  if (nrow(sets[[nm]]$pairs)) {
    pr <- sets[[nm]]$pairs
    pt <- sf::st_coordinates(sf::st_point_on_surface(sf::st_geometry(sets[[nm]]$p)))[, 1:2]
    pl <- sf::st_sf(pr, geometry = sf::st_sfc(lapply(seq_len(nrow(pr)), function(k)
      sf::st_linestring(rbind(pt[pr$ero[k], ], pt[pr$dep[k], ]))), crs = crs))
    sf::st_write(pl, f, layer = "pairs", quiet = TRUE)
  }
}

rule <- do.call(rbind, lapply(names(sets), function(nm) cbind(area = area, set = nm, sets[[nm]]$rule)))
rule$separates <- vapply(seq_len(nrow(rule)), function(k) fp_ch_separates(rule[k, ]), logical(1))
rule$direction_holds <- vapply(seq_len(nrow(rule)), function(k) fp_ch_direction_holds(rule[k, ]), logical(1))
log_dir <- here::here("scripts", "floodplain_lcc", "logs")
stem <- file.path(log_dir, sprintf("%s_channel-migration_%s", format(Sys.Date(), "%Y%m%d"), area))
utils::write.csv(rule, paste0(stem, ".csv"), row.names = FALSE, na = "")

q <- function(v) paste(sprintf("%.2f", stats::quantile(v, c(.1, .25, .5, .75, .9), na.rm = TRUE)), collapse = " / ")
pct <- function(num, den) sprintf("%.1f%%", 100 * num / den)
md <- c(sprintf("# Channel-migration probe: %s (%s, %s -> %s)", area, cfg$primary_scenario, ends[1], ends[2]), "",
        sprintf("Produced by `scripts/floodplain_lcc/channel_probe-migration.R %s`, %s, drift %s, terra %s.", area,
                format(Sys.time(), "%Y-%m-%d %H:%M %Z"), utils::packageVersion("drift"), utils::packageVersion("terra")),
        "Rule: research/channel_migration.md (rule v2, pre-registered).", "",
        "Anchor 1: re-sieving the endpoints at 1 ha reproduces transition.tif (0 differing cells).",
        if (!is.na(anchor2)) sprintf("Anchor 2: unsieved total change %.2f ha = strata change + sieved %.2f ha.", chg_ha, anchor2) else
          sprintf("Anchor 2: no strata.csv; unsieved total change %.2f ha.", chg_ha), "")
for (nm in names(sets)) {
  s <- sets[[nm]]$p
  r <- rule[rule$set == nm, ]
  er <- s[s$role != "other", ]
  a  <- sum(er$area_ha)
  by_role <- tapply(s$area_ha, s$role, sum)
  md <- c(md, sprintf("## %s", nm), "",
          sprintf("- role patches %d, Water-involving %.2f ha (erosion %.2f, deposition %.2f, other %.2f)",
                  nrow(s), sum(s$area_ha), by_role["erosion"] %||% 0, by_role["deposition"] %||% 0, by_role["other"] %||% 0),
          sprintf("- misregistration (transition-level patches, drift): sliver %.1f%% of area, exact reciprocal %.1f%%",
                  100 * r$sliver_share, 100 * r$reciprocal_share),
          sprintf("- each condition alone, share of erosion + deposition area: width %s, elong %s, io_adjacent %s, FWA <= 50 m %s, not lake margin %s, aligned %s",
                  pct(sum(er$area_ha[er$width_px >= FP_CH_WIDTH_MIN_PX]), a), pct(sum(er$area_ha[er$elong >= FP_CH_ELONG_MIN]), a),
                  pct(sum(er$area_ha[er$io_adjacent]), a), pct(sum(er$area_ha[er$fwa_dist_m <= FP_CH_FWA_DIST_MAX]), a),
                  pct(sum(er$area_ha[!er$lake_margin]), a), pct(sum(er$area_ha[er$align_deg <= FP_CH_ALIGN_MAX], na.rm = TRUE), a)),
          sprintf("- width_px p10/25/50/75/90: %s", q(s$width_px)),
          sprintf("- elong (equivalent rectangle) p10/25/50/75/90: %s", q(s$elong)),
          sprintf("- elong (MRR) p10/25/50/75/90: %s", q(s$elong_mrr)),
          sprintf("- fwa_dist_m p10/25/50/75/90: %s", q(s$fwa_dist_m)),
          sprintf("- sustained p10/25/50/75/90: %s", q(s$sustained)),
          sprintf("- candidates %d; pairs: %d opposite (%.0f%% exact reverse), %d same-side; %d FWA-opposite pairs had no stable Water between them",
                  r$n_candidates, r$n_opp_pairs, 100 * r$opp_exact_reverse, sum(sets[[nm]]$pairs$kind == "same"),
                  r$opp_fwa_without_crossing),
          "",
          "| cand ha | share (A) | sustained cand / width-matched (B) | opposite / same (C) | R over opposite pairs (D) | A | B | C | D | separates | direction |",
          "|---|---|---|---|---|---|---|---|---|---|---|",
          sprintf("| %.2f | %.3f | %.3f / %.3f | %.3f / %.3f | %.3f (n = %d) | %s | %s | %s | %s | %s | %s |",
                  r$cand_ha, r$cand_share, r$sustained_cand, r$sustained_wm, r$paired_opp, r$paired_same,
                  r$dir_r, r$n_opp_pairs, r$A, r$B, r$C, r$D, r$separates, r$direction_holds), "")
}
writeLines(md, paste0(stem, ".md"))
message("  wrote ", stem, ".{csv,md} and ", out_dir, "/probe_{unsieved,sieved}.gpkg")
print(rule[, c("set", "water_ha", "cand_ha", "cand_share", "sustained_lead", "paired_opp", "paired_same",
               "dir_r", "n_opp_pairs", "A", "B", "C", "D", "separates", "direction_holds")])
message("DONE ", area)
