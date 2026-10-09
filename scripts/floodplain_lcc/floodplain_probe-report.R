# floodplain_probe-report.R — tables, rule evaluation, review layers and panels (#110)
#
# Sourced by floodplain_probe-whole-fwa.R in `report` mode; defines fp_wf_report(). Reads only what
# the earlier modes wrote to data/<area>/probe_whole_fwa/ plus, for the habitat table,
# fresh.streams_vw_bcfp. Writes:
#   data/<area>/probe_whole_fwa/report.csv              the long table (the driver's done-marker)
#   data/<area>/probe_whole_fwa/review.gpkg             added-valley patches per floor, for review
#   data/<area>/probe_whole_fwa/panel_<n>.png           hillshade panels on order-1 additions
#   scripts/floodplain_lcc/logs/<yyyymmdd>_floodplain_probe-whole-fwa_<area>.{csv,md}
#
# The decision rule it evaluates is the one pre-registered in research/whole_fwa_floodplain.md; its
# thresholds are restated here as constants so a change to either is visible in a diff of both.

FP_WF_RULE <- list(max_min = 60, max_rss_gb = 32, min_added_share = 0.05, min_outside_wb = 0.50,
                   supersede_share = 0.02)

fp_wf_report <- function(area, dir_area, dir_out, scen_id, species, min_order, wsg, read_schema) {
  p_out <- function(...) file.path(dir_out, paste0(...))
  rd <- function(f) jsonlite::read_json(f, simplifyVector = TRUE)
  need <- c(p_out("anchor.json"), p_out("dem.json"), p_out("dem_common.tif"),
            p_out("arm", 1:5, "_timing.json"), p_out("arm", 1:5, "_floodplain.tif"),
            p_out("arm", 1:5, "_waterbody.tif"), p_out("arm", 1:5, "_by_blk.gpkg"),
            p_out("arm", 1:5, "_coho_reach.gpkg"), p_out("reach.json"))
  if (any(!file.exists(need))) stop("missing probe outputs:\n  ", paste(need[!file.exists(need)], collapse = "\n  "),
                                    call. = FALSE)
  # A log's RSS counts only if THAT log recorded the mode finishing and is no older than the json the
  # numbers come from. /usr/bin/time prints RSS for a run that died, so a failed driver attempt
  # followed by a direct Rscript re-run would otherwise lend the failed attempt's small figure to the
  # successful run -- and pass the memory gate unmeasured.
  mode_json <- function(mode) switch(as.character(mode), dem = p_out("dem.json"), reach = p_out("reach.json"),
                                     seg = p_out("seg_timing.json"), p_out("arm", mode, "_timing.json"))
  rss <- function(mode) {
    f <- file.path(dir_out, "logs", paste0(mode, ".log")); j <- mode_json(mode)
    if (!file.exists(f) || !file.exists(j)) return(NA_real_)
    lines <- readLines(f, warn = FALSE)
    if (!any(lines == paste("PROBE_DONE", mode)) || file.mtime(f) < file.mtime(j)) return(NA_real_)
    fp_wf_peak_rss_gb(lines)
  }
  rows <- list()
  put <- function(section, arm, metric, value) {
    rows[[length(rows) + 1L]] <<- data.frame(section = section, arm = as.character(arm), metric = metric,
                                             value = as.numeric(value), stringsAsFactors = FALSE)
  }

  # --- 0. completeness: one DEM, one toolchain ----------------------------------------------------
  anc <- rd(p_out("anchor.json"))
  dmj <- rd(p_out("dem.json"))
  tm  <- lapply(1:5, function(k) rd(p_out("arm", k, "_timing.json")))
  seg <- if (file.exists(p_out("seg_timing.json"))) rd(p_out("seg_timing.json")) else NULL
  if (length(unique(c(dmj$dem_content_sha256, vapply(tm, `[[`, "", "dem_content_sha256")))) != 1L)
    stop("arms were delineated on different DEMs", call. = FALSE)
  vkeys <- c("flooded", "terra", "sf", "terra_gdal", "sf_gdal")
  vsig <- function(x) paste(vapply(vkeys, function(k) as.character(x[[k]]), ""), collapse = "/")
  rch <- rd(p_out("reach.json"))
  sigs <- unique(c(vsig(dmj), vapply(tm, vsig, ""), vsig(rch), if (!is.null(seg)) vsig(seg)))
  if (length(sigs) != 1L) stop("arms ran on different toolchains: ", paste(sigs, collapse = " | "), call. = FALSE)
  # Each output tied to the floodplain it came from, by CONTENT: every mode re-reads the network and
  # any arm can be re-run alone, so file presence says nothing about which run produced what.
  for (k in 1:5) {
    if (!identical(fp_raster_content_sha256(p_out("arm", k, "_floodplain.tif")), tm[[k]]$floodplain_content_sha256))
      stop("arm", k, "_floodplain.tif no longer matches arm", k, "_timing.json: re-run that arm", call. = FALSE)
    if (!identical(as.numeric(dmj$arm_segments[k]), as.numeric(tm[[k]]$n_segments)))
      stop("arm ", k, " read ", tm[[k]]$n_segments, " segments but the `dem` mode counted ", dmj$arm_segments[k],
           ": the network changed between modes", call. = FALSE)
    if (k == 3L && !is.null(seg) && !identical(as.numeric(seg$n_groups), as.numeric(dmj$arm_segments[3])))
      stop("`seg` read ", seg$n_groups, " arm-3 segments but the `dem` mode counted ", dmj$arm_segments[3],
           ": the network changed between modes", call. = FALSE)
    rk <- rch$arms[rch$arms$arm == k, , drop = FALSE]
    if (nrow(rk) != 1L || rk$valley_cells != tm[[k]]$valley_cells)
      stop("reach.json does not describe arm ", k, "'s current floodplain: re-run `reach`", call. = FALSE)
    # The arm mode writes floodplain.tif, then waterbody.tif, then by_blk.gpkg, then timing.json, in
    # one process. A sibling outside that window is left over from another run. The by_blk row count
    # is the content half of the same tie.
    mt <- file.mtime(p_out("arm", k, c("_floodplain.tif", "_waterbody.tif", "_by_blk.gpkg", "_timing.json")))
    if (is.unsorted(mt)) stop("arm ", k, "'s outputs are not from one run (mtimes out of order): re-run that arm",
                              call. = FALSE)
    nb <- nrow(sf::st_read(p_out("arm", k, "_by_blk.gpkg"), quiet = TRUE))
    if (nb != tm[[k]]$attr_rows) stop("arm", k, "_by_blk.gpkg has ", nb, " rows, its timing json ", tm[[k]]$attr_rows,
                                      call. = FALSE)
  }
  if (!identical(fp_raster_content_sha256(p_out("dem_common.tif")), dmj$dem_content_sha256))
    stop("dem_common.tif no longer matches dem.json", call. = FALSE)
  if (!identical(fp_raster_content_sha256(p_out("anchor_floodplain.tif")), anc$floodplain))
    stop("anchor_floodplain.tif no longer matches anchor.json: re-run the anchor", call. = FALSE)

  # The network every mode re-read: link writes a new fresh.log row on every rebuild, so the newest
  # MORR row still being the one step 1's record names means no mode -- `reach` included, which
  # records no segment count -- read a rebuilt network. Ties broken on run_id so the pick is not an
  # arbitrary row.
  if (!grepl("^[a-z_][a-z0-9_]*$", read_schema)) stop("bad schema name: ", read_schema, call. = FALSE)
  conn0 <- DBI::dbConnect(RPostgres::Postgres())
  uid_now <- DBI::dbGetQuery(conn0, sprintf(
    "SELECT run_uid FROM %s.log WHERE watershed_group_code = '%s' ORDER BY date_end DESC NULLS LAST, run_id DESC LIMIT 1",
    read_schema, wsg))$run_uid
  DBI::dbDisconnect(conn0)
  uid_rec <- jsonlite::read_json(file.path(dir_area, "provenance.json"))$network[[paste0(species, min_order)]]$link_log$run_uid
  if (length(uid_now) != 1L || is.null(uid_rec) || !identical(as.character(uid_now), as.character(uid_rec)))
    stop("the newest ", read_schema, ".log row for ", wsg, " (", format(uid_now), ") is not the run step 1 recorded (",
         format(uid_rec), "): the network may have been rebuilt during the probe", call. = FALSE)

  # --- 1. cost and size per arm -------------------------------------------------------------------
  ha_cell <- tm[[1]]$cell_m2 / 1e4
  arm_tab <- do.call(rbind, lapply(tm, function(t) data.frame(
    arm = t$arm, label = FP_WF_ARMS$label[t$arm], segments = t$n_segments, km = t$km, blue_lines = t$n_blk,
    waterbodies = t$n_waterbodies, floodplain_km2 = t$valley_cells * ha_cell / 100,
    waterbody_share = t$valley_cells_waterbody / t$valley_cells,
    t_delin_min = t$t_delin_s / 60, t_attr_blk_min = t$t_attr_blk_s / 60,
    attr_rows = t$attr_rows, fallback_cells = t$fallback_cells, peak_rss_gb = rss(t$arm),
    stringsAsFactors = FALSE)))
  for (i in seq_len(nrow(arm_tab))) for (m in setdiff(names(arm_tab), c("arm", "label")))
    put("arm", arm_tab$arm[i], m, arm_tab[[m]][i])
  put("dem", "common", "t_fetch_min", dmj$t_dem_s / 60)
  put("dem", "common", "ncell", dmj$ncol * dmj$nrow)
  put("dem", "common", "peak_rss_gb", rss("dem"))
  if (!is.null(seg)) {
    put("seg", 3, "groups", seg$n_groups); put("seg", 3, "t_attr_seg_min", seg$t_attr_seg_s / 60)
    put("seg", 3, "attr_rows", seg$attr_rows); put("seg", 3, "peak_rss_gb", rss("seg"))
  }
  # Attribution cost against group count across the five blk arms. Same grid, but the valleys grow
  # with the floor, so the slope is confounded with valley extent -- reported as such.
  fit <- stats::lm(t ~ n, data = data.frame(t = vapply(tm, `[[`, 0, "t_attr_blk_s"), n = vapply(tm, `[[`, 0, "n_blk")))
  put("attr_fit", "blk", "intercept_s", stats::coef(fit)[[1]])
  put("attr_fit", "blk", "s_per_group", stats::coef(fit)[[2]])
  seg_rate <- if (!is.null(seg)) seg$t_attr_seg_s / seg$n_groups else NA_real_
  put("attr_fit", "seg", "s_per_group_arm3", seg_rate)

  # --- 2. area on the common grid: each floor against the next one up -----------------------------
  fp <- lapply(1:5, function(k) terra::rast(p_out("arm", k, "_floodplain.tif")))
  wb <- lapply(1:5, function(k) terra::rast(p_out("arm", k, "_waterbody.tif")))
  pairs <- list(`1_vs_2` = c(1, 2), `2_vs_3` = c(2, 3), `4_vs_3` = c(4, 3), `3_vs_5` = c(3, 5),
                `1_vs_5` = c(1, 5), `2_vs_5` = c(2, 5), `4_vs_5` = c(4, 5))
  ov_tab <- do.call(rbind, lapply(names(pairs), function(tag) {
    a <- pairs[[tag]][1]; b <- pairs[[tag]][2]
    o <- fp_wf_overlap(fp[[a]], fp[[b]])
    va <- terra::values(fp[[a]], mat = FALSE); vb <- terra::values(fp[[b]], mat = FALSE)
    gained <- !is.na(va) & va == 1 & !(!is.na(vb) & vb == 1)
    gained_wb <- sum(gained & terra::values(wb[[a]], mat = FALSE) == 1, na.rm = TRUE) * ha_cell
    g <- o$ha[o$metric == "a_only"]
    data.frame(pair = tag, both_ha = o$ha[o$metric == "both"], gained_ha = g, lost_ha = o$ha[o$metric == "b_only"],
               gained_in_waterbody_ha = gained_wb, gained_outside_wb_share = if (g > 0) 1 - gained_wb / g else NA_real_,
               gained_share_of_b = g / o$ha[o$metric == "b"], stringsAsFactors = FALSE)
  }))
  for (i in seq_len(nrow(ov_tab))) for (m in names(ov_tab)[-1]) put("overlap", ov_tab$pair[i], m, ov_tab[[m]][i])

  # Extent effect: arm 5 on the common grid against the anchor's arm 5 on its own grid. Two grids,
  # so totals only; it carries regridding as well as extent.
  a5_ha <- tm[[5]]$valley_cells * ha_cell
  anc_r <- terra::rast(p_out("anchor_floodplain.tif"))
  anc_ha <- sum(terra::values(anc_r, mat = FALSE) == 1, na.rm = TRUE) * prod(terra::res(anc_r)) / 1e4
  put("extent", 5, "anchor_ha", anc_ha); put("extent", 5, "common_grid_ha", a5_ha)
  put("extent", 5, "diff_pct", 100 * (a5_ha - anc_ha) / anc_ha)
  put("toolchain", 5, "published_ha", anc$published_ha); put("toolchain", 5, "today_ha", anc$today_ha)

  # --- 3. the boundary move: coho-reachable floodplain per arm against arm 5's --------------------
  # Polygons are cell-exact (fl_cells_poly), so rasterizing by cell centre recovers the cells.
  dem <- terra::rast(p_out("dem_common.tif"))
  reach_r <- lapply(1:5, function(k) {
    x <- sf::st_read(p_out("arm", k, "_coho_reach.gpkg"), quiet = TRUE)
    r <- terra::rasterize(terra::vect(x), dem, field = 1, background = 0, touches = FALSE)
    # Content tie to reach.json: the gpkg must hold exactly the cells the `reach` mode counted.
    n <- sum(terra::values(r, mat = FALSE) == 1)
    if (n != rch$arms$reach_cells[rch$arms$arm == k])
      stop("arm", k, "_coho_reach.gpkg holds ", n, " cells, reach.json ", rch$arms$reach_cells[rch$arms$arm == k],
           ": re-run `reach`", call. = FALSE)
    r
  })
  # NOT a pure boundary move. flooded's fl_group_cells() keeps valley cells inside a zone set by the
  # coho seeds and the DEM alone, so this is arm k's valley within the SAME zone for every arm: it
  # carries the boundary move AND tributary-mouth valleys and waterbodies that new seeds bring inside
  # the zone. That is the supersession question as #104 would meet it -- what a consumer gets by
  # querying the whole floodplain for the coho network, against today's item -- and the waterbody
  # split below says how much of the gain is lakes and wetlands.
  reach_tab <- do.call(rbind, lapply(1:4, function(k) {
    o <- fp_wf_overlap(reach_r[[k]], reach_r[[5]])
    g <- o$ha[o$metric == "a_only"]; l <- o$ha[o$metric == "b_only"]; b <- o$ha[o$metric == "b"]
    ra <- terra::values(reach_r[[k]], mat = FALSE) == 1; rb <- terra::values(reach_r[[5]], mat = FALSE) == 1
    g_wb <- sum(ra & !rb & terra::values(wb[[k]], mat = FALSE) == 1, na.rm = TRUE) * ha_cell
    data.frame(arm = k, reach_ha = o$ha[o$metric == "a"], arm5_reach_ha = b, gained_ha = g,
               gained_in_waterbody_ha = g_wb, lost_ha = l, moved_share = (g + l) / b)
  }))
  for (i in seq_len(nrow(reach_tab))) for (m in names(reach_tab)[-1]) put("coho_reach", reach_tab$arm[i], m, reach_tab[[m]][i])

  # Per-blk, for the record: these grow from added seeds AND the boundary move, so they are not the
  # supersession measure (section 3 is).
  by <- lapply(1:5, function(k) {
    x <- sf::st_read(p_out("arm", k, "_by_blk.gpkg"), quiet = TRUE)
    data.frame(blue_line_key = x$blue_line_key, ha = as.numeric(sf::st_area(x)) / 1e4)
  })
  blk_tab <- do.call(rbind, lapply(1:4, function(k) {
    m <- merge(by[[5]], by[[k]], by = "blue_line_key", all.x = TRUE, suffixes = c("_5", "_k"))
    m$ha_k[is.na(m$ha_k)] <- 0
    r <- m$ha_k / m$ha_5
    data.frame(arm = k, blk = nrow(m), ha_5 = sum(m$ha_5), ha_k = sum(m$ha_k), median_ratio = stats::median(r),
               share_up_10pct = mean(r > 1.1), share_down_10pct = mean(r < 0.9))
  }))
  for (i in seq_len(nrow(blk_tab))) for (m in names(blk_tab)[-1]) put("coho_blk", blk_tab$arm[i], m, blk_tab[[m]][i])

  # --- 4. habitat by order band: fresh.streams_vw_bcfp, "modelled" = codes 1 and 2 ----------------
  # bcfp codes: 1 modelled, 2 modelled and known, 3 known not modelled, -1 known non-habitat, 0 none.
  # IN (1, 2) is "modelled", the definition #104's 20-29% was measured with. The ch columns describe
  # MORR's chinook network, not the coho baseline.
  conn <- DBI::dbConnect(RPostgres::Postgres())
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  hab <- DBI::dbGetQuery(conn, sprintf("
    SELECT CASE WHEN stream_order >= 3 THEN '3+' ELSE stream_order::text END AS order_band,
           coalesce(stream_order = 1 AND stream_order_parent >= %2$d, false) AS bypass,
           round(sum(length_metre)::numeric / 1000, 1)                                          AS km,
           round(coalesce(sum(length_metre) FILTER (WHERE rearing_co  IN (1, 2)), 0)::numeric / 1000, 1) AS rearing_co_km,
           round(coalesce(sum(length_metre) FILTER (WHERE rearing_ch  IN (1, 2)), 0)::numeric / 1000, 1) AS rearing_ch_km,
           round(coalesce(sum(length_metre) FILTER (WHERE spawning_co IN (1, 2)), 0)::numeric / 1000, 1) AS spawning_co_km,
           round(coalesce(sum(length_metre) FILTER (WHERE spawning_ch IN (1, 2)), 0)::numeric / 1000, 1) AS spawning_ch_km
    FROM fresh.streams_vw_bcfp WHERE watershed_group_code = '%1$s'
    GROUP BY 1, 2 ORDER BY 1, 2", wsg, FP_WF_PARENT_MIN))
  hab$bypass <- as.logical(hab$bypass)
  for (i in seq_len(nrow(hab))) for (m in names(hab)[-(1:2)])
    put("habitat", paste0(hab$order_band[i], if (isTRUE(hab$bypass[i])) "_bypass" else ""), m, hab[[m]][i])
  below3 <- function(col) sum(hab[[col]][hab$order_band != "3+"]) / sum(hab[[col]])
  hab_share <- vapply(c("rearing_co_km", "rearing_ch_km", "spawning_co_km", "spawning_ch_km"), below3, 0)
  for (m in names(hab_share)) put("habitat_below_3", "share", m, hab_share[[m]])

  # --- 5. the pre-registered rule -----------------------------------------------------------------
  arm3_ha <- tm[[3]]$valley_cells * ha_cell
  cand <- data.frame(floor = c("order >= 2 (arm 2 vs 3)", "order >= 1 (arm 1 vs 2)", "bypass (arm 4 vs 3)"),
                     arm = c(2, 1, 4), pair = c("2_vs_3", "1_vs_2", "4_vs_3"), stringsAsFactors = FALSE)
  cand$cost_min <- vapply(cand$arm, function(k) (dmj$t_dem_s + tm[[k]]$t_delin_s + tm[[k]]$t_attr_blk_s) / 60, 0)
  # NA, never a fallback: an arm whose log carries no RSS line was not measured, and neither the DEM
  # stage's figure nor max(na.rm = TRUE)'s -Inf may stand in for it (both would pass the gate).
  cand$peak_rss_gb <- vapply(cand$arm, function(k) {
    a <- rss(k); d <- rss("dem")
    if (is.na(a) || is.na(d)) NA_real_ else max(a, d)
  }, 0)
  cand$added_share_of_arm3 <- ov_tab$gained_ha[match(cand$pair, ov_tab$pair)] / arm3_ha
  cand$outside_wb_share <- ov_tab$gained_outside_wb_share[match(cand$pair, ov_tab$pair)]
  cand$affordable <- !is.na(cand$cost_min) & !is.na(cand$peak_rss_gb) &
    cand$cost_min <= FP_WF_RULE$max_min & cand$peak_rss_gb <= FP_WF_RULE$max_rss_gb
  cand$adds_floodplain <- !is.na(cand$outside_wb_share) & cand$added_share_of_arm3 >= FP_WF_RULE$min_added_share &
    cand$outside_wb_share >= FP_WF_RULE$min_outside_wb
  cand$visual <- "pending"
  cand$supersedes <- reach_tab$moved_share[match(cand$arm, reach_tab$arm)] > FP_WF_RULE$supersede_share
  for (i in seq_len(nrow(cand))) for (m in c("cost_min", "peak_rss_gb", "added_share_of_arm3", "outside_wb_share",
                                             "affordable", "adds_floodplain", "supersedes"))
    put("rule", cand$pair[i], m, cand[[m]][i])
  # Grain: segment attribution at the measured per-segment rate, over each floor's segment count.
  grain <- data.frame(arm = 1:5, segments = vapply(tm, `[[`, 0, "n_segments"))
  grain$seg_attr_min_est <- grain$segments * seg_rate / 60
  grain$seg_affordable <- grain$seg_attr_min_est <= FP_WF_RULE$max_min
  for (i in seq_len(nrow(grain))) {
    put("grain", grain$arm[i], "seg_attr_min_est", grain$seg_attr_min_est[i])
    put("grain", grain$arm[i], "seg_affordable", grain$seg_affordable[i])
  }

  out <- do.call(rbind, rows)

  # --- 6. review layers + panels ------------------------------------------------------------------
  adds <- list(order1_added = c(1, 2), order2_added = c(2, 3), bypass_added = c(4, 3))
  rv <- p_out("review.gpkg")
  if (file.exists(rv)) unlink(rv)
  patches <- list()
  for (nm in names(adds)) {
    a <- fp[[adds[[nm]][1]]] == 1; b <- fp[[adds[[nm]][2]]] == 1
    d <- terra::ifel(a & !b, 1, NA)
    if (all(is.na(terra::values(d, mat = FALSE)))) next
    pg <- sf::st_as_sf(terra::as.polygons(terra::patches(d, directions = 8, zeroAsNA = TRUE), dissolve = TRUE))
    pg$area_ha <- as.numeric(sf::st_area(pg)) / 1e4
    wb_a <- wb[[adds[[nm]][1]]]
    pg$waterbody_share <- terra::extract(wb_a, terra::vect(pg), fun = mean, na.rm = TRUE, ID = FALSE)[[1]]
    pg$layer <- nm
    pg <- pg[, c("layer", "area_ha", "waterbody_share")]
    sf::st_write(pg, rv, layer = nm, append = file.exists(rv), quiet = TRUE)
    patches[[nm]] <- pg
  }
  base_poly <- sf::st_as_sf(terra::as.polygons(terra::ifel(fp[[3]] == 1, 1, NA), dissolve = TRUE))
  sf::st_write(base_poly, rv, layer = "arm3_floodplain", append = TRUE, quiet = TRUE)

  panels <- character(0)
  o1 <- patches$order1_added
  if (!is.null(o1) && nrow(o1)) {
    # Panels sample order-1 additions that are NOT waterbodies: a lake is floodplain by flooded's
    # construction, so it cannot inform whether a first-order valley is.
    o1 <- o1[!is.na(o1$waterbody_share) & o1$waterbody_share < 0.5, ]
    o1 <- o1[order(-o1$area_ha), ]
    set.seed(110)
    mid <- o1[o1$area_ha >= stats::quantile(o1$area_ha, 0.4) & o1$area_ha <= stats::quantile(o1$area_ha, 0.6), ]
    small <- o1[o1$area_ha <= stats::quantile(o1$area_ha, 0.2), ]
    pick <- rbind(o1[seq_len(min(2, nrow(o1))), ], mid[sample(nrow(mid), min(2, nrow(mid))), ],
                  small[sample(nrow(small), min(2, nrow(small))), ])
    kind <- rep(c("largest", "median-size", "small"), times = c(min(2, nrow(o1)), min(2, nrow(mid)), min(2, nrow(small))))
    net <- fp_wf_read_network(conn, read_schema, wsg, species)
    bbx <- function(e, crs) sf::st_bbox(c(xmin = e[1], ymin = e[3], xmax = e[2], ymax = e[4]), crs = crs)
    for (i in seq_len(nrow(pick))) {
      cen <- sf::st_coordinates(sf::st_centroid(sf::st_geometry(pick[i, ])))
      half <- max(1500, sqrt(pick$area_ha[i] * 1e4) * 1.5)
      e <- terra::ext(cen[1] - half, cen[1] + half, cen[2] - half, cen[2] + half)
      dm <- terra::crop(dem, e)
      hs <- terra::shade(terra::terrain(dm, "slope", unit = "radians"), terra::terrain(dm, "aspect", unit = "radians"))
      f <- p_out("panel_", i, ".png")
      grDevices::png(f, width = 1400, height = 1400, res = 160)
      terra::plot(hs, col = grDevices::grey.colors(50, 0.3, 0.95), legend = FALSE, axes = FALSE, mar = c(1, 1, 2, 1),
                  main = sprintf("Panel %d (%s): order-1 addition %.1f ha", i, kind[i], pick$area_ha[i]))
      a3 <- terra::crop(fp[[3]], e)
      terra::plot(terra::ifel(a3 == 1, 1, NA), col = grDevices::adjustcolor("steelblue", 0.45), add = TRUE, legend = FALSE)
      for (nm in c("order2_added", "order1_added")) {
        pg <- patches[[nm]]
        if (is.null(pg)) next
        pg <- suppressWarnings(sf::st_crop(pg, bbx(e, sf::st_crs(pg))))
        if (nrow(pg)) plot(sf::st_geometry(pg), add = TRUE, border = NA,
                           col = grDevices::adjustcolor(if (nm == "order1_added") "darkorange" else "gold", 0.6))
      }
      ln <- suppressWarnings(sf::st_crop(net, bbx(e, sf::st_crs(net))))
      if (nrow(ln)) plot(sf::st_geometry(ln), add = TRUE, col = "navy", lwd = 0.4 + 0.35 * pmin(ln$stream_order, 6))
      # Legend at explicit map coordinates: a keyword position draws nothing after terra::plot().
      graphics::legend(e[1] + half * 0.04, e[4] - half * 0.04, bty = "o", bg = "white", cex = 0.8,
                       legend = c("order >= 3 floodplain (arm 3)", "added by order 2", "added by order 1", "FWA stream"),
                       fill = c(grDevices::adjustcolor("steelblue", 0.45), grDevices::adjustcolor("gold", 0.6),
                                grDevices::adjustcolor("darkorange", 0.6), NA),
                       border = c("grey40", "grey40", "grey40", NA), lty = c(NA, NA, NA, 1), col = c(NA, NA, NA, "navy"))
      grDevices::dev.off()
      panels <- c(panels, f)
    }
  }

  # --- 7. outputs ---------------------------------------------------------------------------------
  utils::write.csv(out, p_out("report.csv"), row.names = FALSE)
  stamp <- format(Sys.time(), "%Y%m%d", tz = "UTC")
  log_base <- here::here("scripts", "floodplain_lcc", "logs", sprintf("%s_floodplain_probe-whole-fwa_%s", stamp, area))
  utils::write.csv(out, paste0(log_base, ".csv"), row.names = FALSE)
  md_tab <- function(df) {
    df[] <- lapply(df, function(v) if (is.numeric(v)) format(round(v, 3), big.mark = ",", trim = TRUE) else as.character(v))
    c(paste0("| ", paste(names(df), collapse = " | "), " |"), paste0("|", strrep("---|", ncol(df))),
      apply(df, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |")))
  }
  yn <- function(x) if (isTRUE(x)) "MATCH" else "DIFFERS"
  md <- c(
    sprintf("# Whole-FWA floodplain probe: %s, `%s` (#110)", toupper(area), scen_id), "",
    sprintf("Report %s UTC. flooded %s, terra %s (GDAL %s), sf %s (GDAL %s). Produced by `scripts/floodplain_lcc/floodplain_probe-run.sh %s`; rule in `research/whole_fwa_floodplain.md`.",
            format(Sys.time(), "%Y-%m-%d %H:%M", tz = "UTC"), dmj$flooded, dmj$terra, dmj$terra_gdal, dmj$sf, dmj$sf_gdal, area), "",
    "## Anchor", "",
    sprintf("- arm 5 network vs step 1's record: %s", yn(anc$network_match)),
    sprintf("- arm 5 DEM vs `fp_floodplain()` replayed the same day: %s; floodplain: %s", yn(anc$dem_match_replay), yn(anc$floodplain_match_replay)),
    sprintf("- vs the published 2026-09-03 record: DEM %s, floodplain %s (%.1f ha published, %.1f ha today, %+.2f%%)",
            yn(anc$dem_match_published), yn(anc$floodplain_match_published), anc$published_ha, anc$today_ha,
            100 * (anc$today_ha - anc$published_ha) / anc$published_ha), "",
    sprintf("## Cost and size per arm (common DEM: %s cells, fetched in %.1f min, %.1f GiB peak)",
            format(dmj$ncol * dmj$nrow, big.mark = ","), dmj$t_dem_s / 60, rss("dem")), "", md_tab(arm_tab), "",
    if (!is.null(seg)) c(sprintf("Segment-grain attribution on arm 3: %s segments, %.1f min (%.3f s per segment), %s rows, %.1f GiB peak.",
                                 format(seg$n_groups, big.mark = ","), seg$t_attr_seg_s / 60, seg_rate,
                                 format(seg$attr_rows, big.mark = ","), rss("seg")), ""),
    sprintf("Blue-line attribution across the five arms: %.0f s + %.3f s per blue line (the slope is confounded with valley extent).",
            stats::coef(fit)[[1]], stats::coef(fit)[[2]]), "",
    "## Area on the common grid (ha; a = first arm, b = second)", "", md_tab(ov_tab), "",
    sprintf("Extent and regridding effect: arm 5 on the common grid %.1f ha vs on its own grid %.1f ha (%+.3f%%).",
            a5_ha, anc_ha, 100 * (a5_ha - anc_ha) / anc_ha), "",
    "## The coho network's floodplain under each delineation, arm k vs arm 5 (ha)", "",
    "Valley cells inside the zone the coho seeds reach (distance and cost from coho seeds only), so it carries the boundary move plus tributary-mouth valleys and waterbodies new seeds bring into that zone.", "",
    md_tab(reach_tab), "",
    "Per-blk attributed area for the coho network's blue lines (includes added seeds, so not the supersession measure):", "",
    md_tab(blk_tab), "",
    "## Habitat by order band (`fresh.streams_vw_bcfp`, modelled = codes 1, 2; km)", "", md_tab(hab), "",
    sprintf("Share below order 3: coho rearing %.1f%%, chinook rearing %.1f%%, coho spawning %.1f%%, chinook spawning %.1f%%.",
            100 * hab_share[["rearing_co_km"]], 100 * hab_share[["rearing_ch_km"]], 100 * hab_share[["spawning_co_km"]],
            100 * hab_share[["spawning_ch_km"]]), "",
    "## Pre-registered rule", "", md_tab(cand[, setdiff(names(cand), "pair")]), "",
    "Segment grain at the measured arm-3 rate:", "", md_tab(grain), "",
    sprintf("Review layers: `data/%s/probe_whole_fwa/review.gpkg`; panels: %s.", area,
            if (length(panels)) paste0("`", basename(panels), "`", collapse = ", ") else "none"))
  writeLines(md, paste0(log_base, ".md"))
  message("  wrote ", basename(log_base), ".{csv,md}")
  invisible(out)
}
