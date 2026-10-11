# habitat_join-demo.R — #104's habitat join, demonstrated on MORR: link chinook spawning and rearing
# joined to the whole-network floodplain attributed by blue_line_key, with no re-delineation.
#
# Three joins, all from the probe's attributed layers (floodplain_probe-whole-fwa.R output):
#   blk     a blue line's whole floodplain polygon takes any habitat on that blue line
#   range   each floodplain cell takes the flags of the NEAREST segment on its own blue line
#           (straight-line distance, standing in for #104's join on route measure; the two can differ
#           across a meander neck), so habitat on part of a blue line covers part of its floodplain.
#           A cell several blue lines' floodplains share is resolved two ways (decided 2026-10-11):
#             nearest  the nearest of those blue lines' nearest segments, one owner per cell: the
#                      default for areas, since per-reach areas then add up to the floodplain
#                      (ties go to the lowest blue_line_key, and are counted in the log). Only the
#                      claiming blue lines compete: the nearest segment anywhere is, for about a
#                      quarter of cells, an order-1 line the floor left out (logged below)
#             any      habitat if any of them says so: the "connected to habitat" view
#   segment segment-grain attribution (arm 3 only, keyed by fp_wf_seg_key()), as the reference the
#           range join is checked against
# and two link builds (`fresh`, `morr`), whose chinook habitat on MORR differs (the log has by how much).
#
# Read-only on data/morr/probe_whole_fwa and the database. Writes data/morr/habitat_join_demo/
# (class rasters, a gpkg of both builds' habitat) and the committed log + figures named below.
#
# usage (after floodplain_probe-run.sh morr ... has produced arms 2 and 3):
#   Rscript scripts/floodplain_lcc/habitat_join-demo.R
t0 <- Sys.time()
suppressMessages({library(sf); library(terra); library(DBI); library(RPostgres); library(ggplot2); library(patchwork)})
sf::sf_use_s2(FALSE)
terra::terraOptions(threads = 4, memfrac = 0.3, progress = 0)
lcc <- here::here("scripts", "floodplain_lcc")
source(file.path(lcc, "fp_whole_fwa.R"))   # fp_wf_seg_key

wsg <- "MORR"; species <- "ch"; builds <- c("fresh", "morr")
dir_in  <- here::here("data", "morr", "probe_whole_fwa")
dir_out <- here::here("data", "morr", "habitat_join_demo")
stem <- file.path(lcc, "logs", "20261011_habitat_join-demo_morr")
# Shea Creek: in the morr build, rearing-only reaches sit between its spawning runs (in fresh, 11 of
# those 12 reaches are neither), so blk and range joins differ along one blue line.
fig_blk_key <- 360880257
p <- function(f) file.path(dir_in, f)
need <- p(c("arm2_floodplain.tif", "arm2_by_blk.gpkg", "arm3_floodplain.tif", "arm3_by_blk.gpkg",
            "arm3_by_seg.gpkg", "dem_common.tif"))
if (any(!file.exists(need))) stop("missing: ", paste(basename(need[!file.exists(need)]), collapse = ", "), call. = FALSE)
fp_wf_check_species(species)
# Scenario and toolchain come from the arms' own records, not from this session.
tmj <- lapply(c(2, 3), function(k) jsonlite::read_json(p(paste0("arm", k, "_timing.json")), simplifyVector = TRUE))
for (t in tmj) for (f in c("scenario", "flooded", "terra")) {
  if (!is.character(t[[f]]) || length(t[[f]]) != 1L || is.na(t[[f]]) || !nzchar(t[[f]]))
    stop("an arm's timing.json has no usable `", f, "`", call. = FALSE)
}
arm_sig <- vapply(tmj, function(t) paste(t$scenario, t$flooded, t$terra, sep = "/"), "")
if (length(unique(arm_sig)) != 1L) stop("arms 2 and 3 differ in scenario or toolchain: ", paste(arm_sig, collapse = " | "), call. = FALSE)
dir.create(dir_out, showWarnings = FALSE)

# --- habitat per build: segments with their flags --------------------------------------------
con <- dbConnect(Postgres())
read_hab <- function(b) {
  if (!grepl("^[a-z_]+$", b)) stop("bad schema name: ", b, call. = FALSE)
  x <- st_read(con, quiet = TRUE, query = sprintf("
    SELECT s.blue_line_key, s.downstream_route_measure AS drm, s.length_metre, s.stream_order,
           coalesce(h.spawning, false) AS spawning, coalesce(h.rearing, false) AS rearing, s.geom
      FROM %1$s.streams s JOIN %1$s.streams_habitat_%2$s h USING (id_segment, watershed_group_code)
     WHERE s.watershed_group_code = '%3$s'", b, species, wsg))
  if (!nrow(x)) stop("build ", b, " has no ", species, " habitat for ", wsg, call. = FALSE)
  x <- st_zm(x, drop = TRUE)
  x$blue_line_key <- as.numeric(x$blue_line_key)
  x
}
hab <- setNames(lapply(builds, read_hab), builds)
dbDisconnect(con)

# --- floodplain cells per group, and the integrity check: every floodplain cell attributed, ------
# --- nothing outside it ---------------------------------------------------------------------------
grid_cells <- function(tif, gpkg, key) {
  r <- rast(p(tif)); v <- st_read(p(gpkg), quiet = TRUE)
  # The range join puts the raster's cell centres beside the habitat lines, so all three share a CRS.
  if (st_crs(v) != st_crs(hab[[1]]) || st_crs(terra::crs(r)) != st_crs(hab[[1]]))
    stop(tif, ", ", gpkg, " and the habitat are not all in one CRS", call. = FALSE)
  cb <- terra::cells(r, vect(v))
  out <- data.frame(key = v[[key]][cb[, "ID"]], cell = cb[, "cell"])
  fpc <- which(values(r, mat = FALSE) == 1L)
  chk <- c(floodplain_cells = length(fpc), attributed_cells = length(unique(out$cell)),
           missing = length(setdiff(fpc, out$cell)), extra = length(setdiff(out$cell, fpc)))
  list(r = r, cells = out, check = chk)
}
a2 <- grid_cells("arm2_floodplain.tif", "arm2_by_blk.gpkg", "blue_line_key")
a3 <- grid_cells("arm3_floodplain.tif", "arm3_by_blk.gpkg", "blue_line_key")
s3 <- grid_cells("arm3_floodplain.tif", "arm3_by_seg.gpkg", "seg_key")
if (!compareGeom(a2$r, a3$r, stopOnError = FALSE)) stop("arms 2 and 3 are not on one grid", call. = FALSE)
ck <- rbind(arm2_blk = a2$check, arm3_blk = a3$check, arm3_seg = s3$check)
if (any(ck[, c("missing", "extra")] != 0)) {
  print(ck); stop("integrity check failed: floodplain and attribution disagree; nothing written", call. = FALSE)
}
cell_ha <- prod(res(a2$r)) / 1e4

# --- the joins: per-claim flags, then OR over the groups that claim a cell ----------------------
or_by_cell <- function(cell, sp, re) {
  s <- tapply(sp, cell, any); r <- tapply(re, cell, any)
  data.frame(cell = as.numeric(names(s)), spawning = as.logical(s), rearing = as.logical(r[names(s)]))
}
join_blk <- function(cells, h) {
  f <- aggregate(cbind(spawning, rearing) ~ blue_line_key, data = st_drop_geometry(h), FUN = any)
  m <- match(cells$key, f$blue_line_key)
  or_by_cell(cells$cell, !is.na(m) & f$spawning[m], !is.na(m) & f$rearing[m])
}
join_range <- function(cells, h, r) {
  out <- list(); no_seg <- 0; hk <- split(seq_len(nrow(h)), sprintf("%.0f", h$blue_line_key))
  for (b in unique(cells$key)) {
    cc <- cells$cell[cells$key == b]; idx <- hk[[sprintf("%.0f", b)]]
    if (is.null(idx)) {   # the blue line has no segment in this build: no habitat, and no distance
      no_seg <- no_seg + 1  # to compete with, so it never owns a cell under `nearest`
      out[[length(out) + 1]] <- data.frame(cell = cc, blk = b, dist = Inf, spawning = FALSE, rearing = FALSE); next
    }
    pts <- st_as_sf(as.data.frame(xyFromCell(r, cc)), coords = c("x", "y"), crs = st_crs(h))
    nn <- idx[st_nearest_feature(pts, h[idx, ])]
    out[[length(out) + 1]] <- data.frame(cell = cc, blk = b,
      dist = as.numeric(st_distance(pts, h[nn, ], by_element = TRUE)),
      spawning = h$spawning[nn], rearing = h$rearing[nn])
  }
  o <- do.call(rbind, out)
  any_ <- or_by_cell(o$cell, o$spawning, o$rearing)
  o <- o[order(o$cell, o$dist, o$blk), ]
  first <- !duplicated(o$cell)
  ties <- sum(!first & is.finite(o$dist) & o$dist == c(NA, o$dist[-nrow(o)]) & o$cell == c(NA, o$cell[-nrow(o)]) &
                c(FALSE, first[-length(first)]), na.rm = TRUE)
  near <- data.frame(cell = o$cell[first], spawning = o$spawning[first], rearing = o$rearing[first])
  attr(near, "ties") <- ties
  attr(any_, "blk_without_segments") <- attr(near, "blk_without_segments") <- no_seg
  list(nearest = near, any = any_)
}
join_seg <- function(cells, h) {
  m <- match(cells$key, fp_wf_seg_key(h$blue_line_key, h$drm))
  f <- or_by_cell(cells$cell, !is.na(m) & h$spawning[m], !is.na(m) & h$rearing[m])
  attr(f, "key_match") <- mean(!is.na(m[!duplicated(cells$key)])); f
}
summ <- function(f, label, build) {
  data.frame(join = label, build = build,
             spawning_ha = sum(f$spawning) * cell_ha, rearing_ha = sum(f$rearing) * cell_ha,
             both_ha = sum(f$spawning & f$rearing) * cell_ha,
             spawn_only_ha = sum(f$spawning & !f$rearing) * cell_ha,
             rear_only_ha = sum(!f$spawning & f$rearing) * cell_ha)
}

res2 <- list(); res3 <- list(); keep <- list(); km <- list()
for (b in builds) {
  h <- hab[[b]]
  fb <- join_blk(a2$cells, h); fr <- join_range(a2$cells, h, a2$r)
  res2[[b]] <- rbind(summ(fb, "blk", b), summ(fr$nearest, "range, nearest", b), summ(fr$any, "range, any", b))
  res2[[b]]$blk_without_segments <- c(NA, attr(fr$nearest, "blk_without_segments"), attr(fr$any, "blk_without_segments"))
  res2[[b]]$tied_cells <- c(NA, attr(fr$nearest, "ties"), NA)
  keep[[b]] <- list(blk = fb, nearest = fr$nearest, any = fr$any)
  r3 <- join_range(a3$cells, h, a3$r); sg <- join_seg(s3$cells, h)
  res3[[b]] <- rbind(summ(r3$nearest, "range, nearest (arm 3 blk)", b), summ(r3$any, "range, any (arm 3 blk)", b),
                     summ(sg, "segment (arm 3 seg)", b))
  res3[[b]]$seg_key_match <- c(NA, NA, attr(sg, "key_match"))
  agree <- function(x, field) { mm <- merge(x, sg, by = "cell", suffixes = c(".rng", ".seg"))
    mean(mm[[paste0(field, ".rng")]] == mm[[paste0(field, ".seg")]]) }
  res3[[b]]$agree_spawning <- c(agree(r3$nearest, "spawning"), agree(r3$any, "spawning"), NA)
  res3[[b]]$agree_rearing  <- c(agree(r3$nearest, "rearing"), agree(r3$any, "rearing"), NA)
  # habitat km, and how much sits on a blue line that has a floodplain polygon (by its max order)
  hk <- st_drop_geometry(h); on <- hk$blue_line_key %in% a2$cells$key
  blk_key <- sprintf("%.0f", hk$blue_line_key)
  blk_max <- tapply(hk$stream_order, blk_key, max)[blk_key]
  km[[b]] <- data.frame(build = b,
    spawning_km = sum(hk$length_metre[hk$spawning]) / 1e3,
    spawning_km_on_fp_blk = sum(hk$length_metre[hk$spawning & on]) / 1e3,
    rearing_km = sum(hk$length_metre[hk$rearing]) / 1e3,
    rearing_km_on_fp_blk = sum(hk$length_metre[hk$rearing & on]) / 1e3,
    habitat_km_off_fp_blk_order1 = sum(hk$length_metre[(hk$spawning | hk$rearing) & !on & blk_max == 1]) / 1e3,
    habitat_km_off_fp_blk_order2plus = sum(hk$length_metre[(hk$spawning | hk$rearing) & !on & blk_max >= 2]) / 1e3)
}
diff_builds <- function(rule) {
  d <- merge(keep$fresh[[rule]], keep$morr[[rule]], by = "cell", suffixes = c(".fresh", ".morr"))
  list(d = d, tab = data.frame(rule = rule,
    rearing_fresh_ha = sum(d$rearing.fresh) * cell_ha, rearing_morr_ha = sum(d$rearing.morr) * cell_ha,
    morr_only_ha = sum(d$rearing.morr & !d$rearing.fresh) * cell_ha,
    fresh_only_ha = sum(d$rearing.fresh & !d$rearing.morr) * cell_ha,
    spawning_changed_ha = sum(d$spawning.morr != d$spawning.fresh) * cell_ha))
}
bd <- lapply(c(nearest = "nearest", any = "any"), diff_builds)
build_diff <- rbind(bd$nearest$tab, bd$any$tab)
# How far the "any claimer" rule reaches: claims per floodplain cell on arm 2, and how far the cells
# whose rearing changed sit from the segments whose rearing changed.
n_claim <- tabulate(match(a2$cells$cell, unique(a2$cells$cell)))
shared <- data.frame(cells = length(n_claim), share_claimed_by_2plus = mean(n_claim >= 2), mean_claims = mean(n_claim))
# Why `nearest` competes only among claiming blue lines: where is each cell's nearest segment anywhere?
uc <- unique(a2$cells$cell)
nn_all <- st_nearest_feature(st_as_sf(as.data.frame(xyFromCell(a2$r, uc)), coords = c("x", "y"),
                                      crs = st_crs(hab$morr)), hab$morr)
own <- paste(uc, sprintf("%.0f", hab$morr$blue_line_key[nn_all])) %in%
  paste(a2$cells$cell, sprintf("%.0f", a2$cells$key))
off_net <- !hab$morr$blue_line_key[nn_all] %in% a2$cells$key
nearest_anywhere <- data.frame(
  share_nearest_on_claiming_blk = mean(own),
  share_nearest_on_blk_without_floodplain = mean(!own & off_net),
  share_nearest_on_nonclaiming_blk_in_floodplain = mean(!own & !off_net),
  order1_share_of_nonclaiming = if (any(!own)) mean(hab$morr$stream_order[nn_all][!own] == 1) else NA_real_)
kf <- fp_wf_seg_key(hab$fresh$blue_line_key, hab$fresh$drm); km_ <- fp_wf_seg_key(hab$morr$blue_line_key, hab$morr$drm)
mf <- match(km_, kf)
unmatched <- sum(is.na(mf))   # segments re-broken between builds; reported in the log, not dropped silently
chg <- hab$morr[!is.na(mf) & hab$morr$rearing != hab$fresh$rearing[mf], ]
reach <- do.call(rbind, lapply(names(bd), function(rule) {
  d <- bd[[rule]]$d; mo <- d$cell[d$rearing.morr & !d$rearing.fresh]
  out <- data.frame(rule = rule, changed_segments = nrow(chg), unmatched_morr_segments = unmatched,
                    morr_only_cells = length(mo), median_m = NA_real_, max_m = NA_real_)
  if (length(mo) && nrow(chg)) {
    pts <- st_as_sf(as.data.frame(xyFromCell(a2$r, mo)), coords = c("x", "y"), crs = st_crs(chg))
    dd <- as.numeric(st_distance(pts, chg[st_nearest_feature(pts, chg), ], by_element = TRUE))
    out$median_m <- median(dd); out$max_m <- max(dd)
  }
  out
}))

# --- class rasters (for QGIS and the figures) ---------------------------------------------------
cls <- function(f, r) {   # 1 spawning only, 2 rearing only, 3 both, 4 floodplain with neither
  out <- rast(r); v <- rep(NA_integer_, ncell(r)); v[which(values(r, mat = FALSE) == 1L)] <- 4L
  v[f$cell] <- ifelse(f$spawning & f$rearing, 3L, ifelse(f$spawning, 1L, ifelse(f$rearing, 2L, 4L)))
  values(out) <- v; out
}
cl <- list(blk_morr = cls(keep$morr$blk, a2$r), nearest_morr = cls(keep$morr$nearest, a2$r),
           any_morr = cls(keep$morr$any, a2$r), nearest_fresh = cls(keep$fresh$nearest, a2$r),
           any_fresh = cls(keep$fresh$any, a2$r))
# figure 2 shows the build change under `any`, the rule under which it reaches furthest
v_f <- values(cl$any_fresh, mat = FALSE); v_m <- values(cl$any_morr, mat = FALSE)
rf <- v_f %in% c(2, 3); rm_ <- v_m %in% c(2, 3)
dv <- rep(NA_integer_, length(v_m)); dv[!is.na(v_m)] <- 4L
dv[rf & rm_] <- 1L; dv[rm_ & !rf] <- 2L; dv[rf & !rm_] <- 3L
cl$rearing_build_diff <- rast(a2$r); values(cl$rearing_build_diff) <- dv

# Figure windows, checked before anything is written so a failure leaves no half-updated outputs.
pad_ext <- function(xmin, xmax, ymin, ymax, pad) ext(xmin - pad, xmax + pad, ymin - pad, ymax + pad)
s1 <- hab$morr[hab$morr$blue_line_key == fig_blk_key & hab$morr$rearing, ]
if (!nrow(s1)) stop("figure 1 blue line ", fig_blk_key, " has no rearing in the morr build", call. = FALSE)
b1 <- st_bbox(s1); e1 <- pad_ext(b1[["xmin"]], b1[["xmax"]], b1[["ymin"]], b1[["ymax"]], 1500)
pc <- patches(classify(cl$rearing_build_diff, cbind(c(1, 3, 4), NA)), directions = 8)
pv <- values(pc, mat = FALSE)
if (all(is.na(pv))) stop("no rearing differs between the builds; figure 2 has nothing to show", call. = FALSE)
big <- as.integer(names(which.max(table(pv))))
xy <- xyFromCell(pc, which(pv == big))
e2 <- pad_ext(min(xy[, 1]), max(xy[, 1]), min(xy[, 2]), max(xy[, 2]), 2500)
for (n in names(cl)) writeRaster(cl[[n]], file.path(dir_out, paste0(species, "_", n, ".tif")),
                                 overwrite = TRUE, datatype = "INT1U", NAflag = 255)
gp <- file.path(dir_out, "habitat_join_demo.gpkg")
for (b in builds) st_write(hab[[b]], gp, layer = paste0(species, "_habitat_", b), delete_layer = TRUE, quiet = TRUE)

# --- figures ------------------------------------------------------------------------------------
dem <- rast(p("dem_common.tif"))
hs_df <- function(e) {
  dd <- crop(dem, e); hs <- shade(terrain(dd, "slope", unit = "radians"), terrain(dd, "aspect", unit = "radians"))
  setNames(as.data.frame(hs, xy = TRUE), c("x", "y", "hs"))
}
cls_df <- function(r, e, labs) {
  dd <- setNames(as.data.frame(crop(r, e), xy = TRUE), c("x", "y", "v"))
  dd$class <- factor(labs[as.character(dd$v)], levels = unname(labs)); dd
}
lines_in <- function(h, e) {
  e <- as.vector(e)
  h <- suppressWarnings(st_crop(h, st_bbox(c(xmin = e[[1]], xmax = e[[2]], ymin = e[[3]], ymax = e[[4]]), crs = st_crs(h))))
  h$habitat <- factor(ifelse(h$spawning & h$rearing, "spawning + rearing",
                             ifelse(h$spawning, "spawning only", ifelse(h$rearing, "rearing only", "neither"))),
                      levels = c("spawning + rearing", "spawning only", "rearing only", "neither"))
  h
}
labs_fp <- c("1" = "spawning only", "2" = "rearing only", "3" = "spawning + rearing", "4" = "floodplain, no chinook habitat")
pal_fp  <- c("spawning only" = "#d7301f", "rearing only" = "#3182bd", "spawning + rearing" = "#8856a7",
             "floodplain, no chinook habitat" = "#bdbdbd")
labs_d  <- c("1" = "rearing in both builds", "2" = "rearing in morr build only", "3" = "rearing in fresh build only",
             "4" = "floodplain, no rearing")
pal_d   <- c("rearing in both builds" = "#3182bd", "rearing in morr build only" = "#e6550d",
             "rearing in fresh build only" = "#31a354", "floodplain, no rearing" = "#bdbdbd")
pal_ln  <- c("spawning + rearing" = "#67000d", "spawning only" = "#d7301f", "rearing only" = "#08306b",
             "neither" = "grey65")
panel <- function(r, e, h, title, labs = labs_fp, pal = pal_fp) {
  ggplot() +
    geom_raster(data = hs_df(e), aes(x, y, alpha = hs), fill = "grey10", show.legend = FALSE) +
    scale_alpha(range = c(0.35, 0)) +
    geom_raster(data = cls_df(r, e, labs), aes(x, y, fill = class), alpha = 0.75) +
    scale_fill_manual(values = pal, name = "Floodplain cell", drop = TRUE) +
    geom_sf(data = lines_in(h, e), aes(colour = habitat, linewidth = habitat), key_glyph = "path") +
    scale_colour_manual(values = pal_ln, name = paste0("link segment (", species, ")"), drop = TRUE) +
    scale_linewidth_manual(values = c(0.9, 0.9, 0.9, 0.35), guide = "none", drop = FALSE) +
    coord_sf(xlim = as.vector(e)[1:2], ylim = as.vector(e)[3:4], expand = FALSE, datum = NA) +
    labs(title = title) + theme_void(base_size = 12) +
    theme(plot.title = element_text(size = 12, face = "bold"), legend.direction = "vertical")
}
# Figure 1: the fig_blk_key blue line's rearing reach, padded (e1)
f1 <- (panel(cl$blk_morr, e1, hab$morr, "A. morr build, join by blue line: the whole\npolygon takes any habitat on its blue line") |
       panel(cl$nearest_morr, e1, hab$morr, "B. morr build, join by position: each cell takes\nthe nearest segment (nearest rule)")) +
  plot_layout(guides = "collect") & theme(legend.position = "bottom")
ggsave(paste0(stem, "_fig1.png"), f1, width = 12, height = 8, dpi = 110, bg = "white")
# Figure 2: window on the largest connected patch of morr-only rearing (e2)
f2 <- (panel(cl$any_fresh, e2, hab$fresh, "A. fresh build (any rule)") |
       panel(cl$rearing_build_diff, e2, hab$morr, "B. morr build vs fresh (any rule): same floodplain\nand join, new habitat", labs_d, pal_d)) &
  theme(legend.position = "bottom")
ggsave(paste0(stem, "_fig2.png"), f2, width = 12, height = 8.5, dpi = 110, bg = "white")
# Figure 3: the two rules for shared ground, morr build, same window as figure 2
f3 <- (panel(cl$nearest_morr, e2, hab$morr, "A. morr build, nearest rule (areas):\none owner per cell") |
       panel(cl$any_morr, e2, hab$morr, "B. morr build, any rule (connected to habitat):\nhabitat if any claiming blue line says so")) +
  plot_layout(guides = "collect") & theme(legend.position = "bottom")
ggsave(paste0(stem, "_fig3.png"), f3, width = 12, height = 8.5, dpi = 110, bg = "white")

# --- the log ------------------------------------------------------------------------------------
fmt <- function(x, rn = FALSE) paste(utils::capture.output(print(x, digits = 6, row.names = rn)), collapse = "\n")
log <- c(
  sprintf("# Habitat join on the attributed floodplain, %s %s (#104)", wsg, species), "",
  sprintf("Produced by `scripts/floodplain_lcc/habitat_join-demo.R`, %s. Floodplains: the probe's arm 2 (order >= 2) and arm 3 (order >= 3), `%s` flood surface, attributed by `blue_line_key` (arm 3 also by segment), with flooded %s and terra %s (from the arms' `timing.json`). Habitat: link builds %s, `streams_habitat_%s`.",
          format(Sys.time(), "%Y-%m-%d %H:%M %Z"), tmj[[1]]$scenario, tmj[[1]]$flooded, tmj[[1]]$terra,
          paste0("`", builds, "`", collapse = " and "), species), "",
  "Joins: **blk**, a blue line's whole floodplain takes any habitat on that blue line; **range**, each floodplain cell takes the nearest segment (straight-line) on its own blue line; **segment**, segment-grain attribution. A cell several blue lines' floodplains share is resolved by **nearest** (the nearest of those blue lines' nearest segments; one owner per cell; the default for areas) or **any** (habitat if any of them says so; the connected-to-habitat view).", "",
  "## Integrity: every floodplain cell attributed, nothing outside it", "", "```", fmt(as.data.frame(ck), rn = TRUE), "```", "",
  "## Habitat km on a blue line that has floodplain (arm 2)", "", "```", fmt(do.call(rbind, km)), "```", "",
  "## Arm 2: spawning vs rearing floodplain, ha", "", "```", fmt(do.call(rbind, res2)), "```", "",
  "## Arm 3: range join vs segment grain, ha and per-cell agreement", "", "```", fmt(do.call(rbind, res3)), "```", "",
  "## Build diff, range join on arm 2, under each rule", "", "```", fmt(build_diff), "```", "",
  "Distance from the cells whose rearing changed to the nearest segment whose rearing changed:", "",
  "```", fmt(reach), "```", "",
  "## Shared ground: floodplain cells by number of blue lines claiming them (arm 2)", "",
  "```", fmt(shared), "```", "",
  "Each cell's nearest segment anywhere in the `morr` build, by the blue line it is on:", "",
  "```", fmt(nearest_anywhere), "```", "",
  sprintf("Figures: `%s_fig1.png` (morr build, blk vs range under the nearest rule, blue line %.0f), `%s_fig2.png` (fresh vs morr rearing, any rule), `%s_fig3.png` (morr build, nearest vs any).",
          basename(stem), fig_blk_key, basename(stem), basename(stem)), "",
  sprintf("Run time: %.0f s.", as.numeric(difftime(Sys.time(), t0, units = "secs"))))
writeLines(log, paste0(stem, ".md"))
cat(log, sep = "\n")
