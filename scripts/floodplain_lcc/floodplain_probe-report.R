# floodplain_probe-report.R — tables, review layers and panels for the whole-FWA probe (#110)
#
# Sourced by floodplain_probe-whole-fwa.R in `report` mode; defines fp_wf_report(). Reads only what
# the earlier modes wrote to data/<area>/probe_whole_fwa/ plus, for the habitat-below-floor table,
# fresh.streams_vw_bcfp. Writes:
#   data/<area>/probe_whole_fwa/report.csv              the long table (the driver's done-marker)
#   data/<area>/probe_whole_fwa/review.gpkg             added-valley patches per floor, for review
#   data/<area>/probe_whole_fwa/panel_<n>.png           hillshade panels on order-1 additions
#   scripts/floodplain_lcc/logs/<yyyymmdd>_floodplain_probe-whole-fwa_<area>.{csv,md}

fp_wf_report <- function(area, dir_area, dir_out, scen_id, species, min_order, wsg, read_schema) {
  p_out <- function(...) file.path(dir_out, paste0(...))
  rd <- function(f) jsonlite::read_json(f, simplifyVector = TRUE)
  need <- c(p_out("anchor.json"), p_out("arm", 1:5, "_timing.json"), p_out("arm", 1:5, "_floodplain.tif"),
            p_out("arm", 1:5, "_by_blk.gpkg"))
  if (any(!file.exists(need))) stop("missing probe outputs:\n  ", paste(need[!file.exists(need)], collapse = "\n  "),
                                    call. = FALSE)
  rss <- function(mode) {
    f <- file.path(dir_out, "logs", paste0(mode, ".log"))
    if (file.exists(f)) fp_wf_peak_rss_gb(readLines(f, warn = FALSE)) else NA_real_
  }
  rows <- list()
  put <- function(section, arm, metric, value) {
    rows[[length(rows) + 1L]] <<- data.frame(section = section, arm = as.character(arm), metric = metric,
                                             value = as.numeric(value), stringsAsFactors = FALSE)
  }

  # --- 1. cost and size per arm -------------------------------------------------------------------
  anc <- rd(p_out("anchor.json"))
  tm  <- lapply(1:5, function(k) rd(p_out("arm", k, "_timing.json")))
  # Every arm must sit on ONE DEM, or the overlaps below compare different grids by construction.
  dem_shas <- vapply(tm, `[[`, "", "dem_content_sha256")
  if (length(unique(dem_shas)) != 1L) stop("arms were delineated on different DEMs", call. = FALSE)
  arm_tab <- do.call(rbind, lapply(tm, function(t) data.frame(
    arm = t$arm, label = t$label, segments = t$n_segments, km = t$km, blue_lines = t$n_blk,
    floodplain_km2 = round(t$valley_cells * t$cell_m2 / 1e6, 1), t_delin_min = round(t$t_delin_s / 60, 1),
    t_attr_blk_min = round(t$t_attr_blk_s / 60, 1), attr_rows = t$attr_rows, attr_warnings = t$attr_warnings,
    fallback_cells = t$fallback_cells, peak_rss_gb = round(rss(t$arm), 1), stringsAsFactors = FALSE)))
  for (i in seq_len(nrow(arm_tab))) for (m in setdiff(names(arm_tab), c("arm", "label")))
    put("arm", arm_tab$arm[i], m, arm_tab[[m]][i])
  seg <- if (file.exists(p_out("seg_timing.json"))) rd(p_out("seg_timing.json")) else NULL
  if (!is.null(seg)) {
    put("seg", 3, "groups", seg$n_groups); put("seg", 3, "t_attr_seg_min", seg$t_attr_seg_s / 60)
    put("seg", 3, "attr_rows", seg$attr_rows); put("seg", 3, "attr_warnings", seg$attr_warnings)
    put("seg", 3, "peak_rss_gb", rss("seg"))
  }
  # Attribution cost against group count, across the five blk arms (same grid, different valley
  # extents, so the slope is confounded with valley size -- stated, not hidden) and the segment run.
  fit <- stats::lm(t_attr_blk_s ~ n_blk, data = data.frame(
    t_attr_blk_s = vapply(tm, `[[`, 0, "t_attr_blk_s"), n_blk = vapply(tm, `[[`, 0, "n_blk")))
  put("attr_fit", "blk", "intercept_s", stats::coef(fit)[[1]])
  put("attr_fit", "blk", "s_per_group", stats::coef(fit)[[2]])
  if (!is.null(seg)) put("attr_fit", "seg", "s_per_group_arm3", seg$t_attr_seg_s / seg$n_groups)

  # --- 2. area: every arm against arm 5 on the common grid, and the floor-by-floor additions -------
  fp <- lapply(1:5, function(k) terra::rast(p_out("arm", k, "_floodplain.tif")))
  ov <- function(a, b, tag) {
    o <- fp_wf_overlap(fp[[a]], fp[[b]])
    for (m in c("both", "a_only", "b_only")) put("overlap", tag, paste0(m, "_ha"), o$ha[o$metric == m])
    o
  }
  for (k in 1:4) ov(k, 5, paste0(k, "_vs_5"))
  ov(1, 2, "1_vs_2"); ov(2, 3, "2_vs_3"); ov(4, 3, "4_vs_3")
  # Extent effect: arm 5 on the common grid against the anchor (arm 5 on its own grid, digest-equal
  # to the published baseline). Different grids, so totals only.
  cell_ha <- prod(terra::res(fp[[5]])) / 1e4
  a5_ha <- sum(terra::values(fp[[5]], mat = FALSE) == 1, na.rm = TRUE) * cell_ha
  anc_r <- terra::rast(p_out("anchor_floodplain.tif"))
  anc_ha <- sum(terra::values(anc_r, mat = FALSE) == 1, na.rm = TRUE) * prod(terra::res(anc_r)) / 1e4
  put("extent", 5, "anchor_ha", anc_ha); put("extent", 5, "common_grid_ha", a5_ha)
  put("extent", 5, "diff_pct", 100 * (a5_ha - anc_ha) / anc_ha)

  # --- 3. the baseline's own watercourses: per-blk attributed area, arm k vs arm 5 ----------------
  by <- lapply(1:5, function(k) {
    x <- sf::st_read(p_out("arm", k, "_by_blk.gpkg"), quiet = TRUE)
    data.frame(blue_line_key = x$blue_line_key, ha = as.numeric(sf::st_area(x)) / 1e4)
  })
  base <- by[[5]]
  blk_tab <- do.call(rbind, lapply(1:4, function(k) {
    m <- merge(base, by[[k]], by = "blue_line_key", all.x = TRUE, suffixes = c("_5", "_k"))
    m$ha_k[is.na(m$ha_k)] <- 0
    r <- m$ha_k / m$ha_5
    data.frame(arm = k, blk = nrow(m), ha_5 = sum(m$ha_5), ha_k = sum(m$ha_k),
               median_ratio = stats::median(r), share_up_10pct = mean(r > 1.1),
               share_down_10pct = mean(r < 0.9))
  }))
  for (i in seq_len(nrow(blk_tab))) for (m in names(blk_tab)[-1]) put("coho_blk", blk_tab$arm[i], m, blk_tab[[m]][i])

  # --- 4. habitat below each floor (fresh.streams_vw_bcfp) ----------------------------------------
  conn <- DBI::dbConnect(RPostgres::Postgres())
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  hab <- DBI::dbGetQuery(conn, sprintf("
    SELECT CASE WHEN stream_order >= 3 THEN '3+' ELSE stream_order::text END AS order_band,
           (stream_order = 1 AND stream_order_parent >= %2$d) AS parent_rule,
           round(sum(length_metre)::numeric / 1000, 3)                                   AS km,
           round(sum(length_metre) FILTER (WHERE rearing_co  > 0)::numeric / 1000, 3)    AS rearing_co_km,
           round(sum(length_metre) FILTER (WHERE rearing_ch  > 0)::numeric / 1000, 3)    AS rearing_ch_km,
           round(sum(length_metre) FILTER (WHERE spawning_co > 0)::numeric / 1000, 3)    AS spawning_co_km,
           round(sum(length_metre) FILTER (WHERE spawning_ch > 0)::numeric / 1000, 3)    AS spawning_ch_km
    FROM fresh.streams_vw_bcfp WHERE watershed_group_code = '%1$s'
    GROUP BY 1, 2 ORDER BY 1, 2", wsg, FP_WF_PARENT_MIN))
  hab[is.na(hab)] <- 0
  hab$parent_rule <- as.logical(hab$parent_rule)
  for (i in seq_len(nrow(hab))) for (m in names(hab)[-(1:2)])
    put("habitat", paste0(hab$order_band[i], if (isTRUE(hab$parent_rule[i])) "_parent5" else ""), m, hab[[m]][i])

  out <- do.call(rbind, rows)
  utils::write.csv(out, p_out("report.csv"), row.names = FALSE)

  # --- 5. review layers + panels ------------------------------------------------------------------
  adds <- list(order1_added = c(1, 2), order2_added = c(2, 3), parent5_added = c(4, 3))
  rv <- p_out("review.gpkg")
  if (file.exists(rv)) unlink(rv)
  patches <- list()
  for (nm in names(adds)) {
    a <- fp[[adds[[nm]][1]]] == 1; b <- fp[[adds[[nm]][2]]] == 1
    d <- terra::ifel(a & !b, 1, NA)
    if (all(is.na(terra::values(d, mat = FALSE)))) next
    pp <- terra::as.polygons(terra::patches(d, directions = 8, zeroAsNA = TRUE), dissolve = TRUE)
    pg <- sf::st_as_sf(pp)
    pg$area_ha <- as.numeric(sf::st_area(pg)) / 1e4
    pg$layer <- nm
    pg <- pg[, c("layer", "area_ha")]
    sf::st_write(pg, rv, layer = nm, append = file.exists(rv), quiet = TRUE)
    patches[[nm]] <- pg
  }
  base_poly <- sf::st_as_sf(terra::as.polygons(terra::ifel(fp[[3]] == 1, 1, NA), dissolve = TRUE))
  sf::st_write(base_poly, rv, layer = "arm3_floodplain", append = TRUE, quiet = TRUE)

  panels <- character(0)
  if (!is.null(patches$order1_added) && nrow(patches$order1_added)) {
    o1 <- patches$order1_added[order(-patches$order1_added$area_ha), ]
    set.seed(110)
    mid <- o1[o1$area_ha >= stats::quantile(o1$area_ha, 0.4) & o1$area_ha <= stats::quantile(o1$area_ha, 0.6), ]
    pick <- rbind(o1[seq_len(min(2, nrow(o1))), ], mid[sample(nrow(mid), min(2, nrow(mid))), ])
    dem <- terra::rast(p_out("dem_common.tif"))
    net <- fp_wf_read_network(conn, read_schema, wsg, species)
    for (i in seq_len(nrow(pick))) {
      cen <- sf::st_coordinates(sf::st_centroid(sf::st_geometry(pick[i, ])))
      e <- terra::ext(cen[1] - 2500, cen[1] + 2500, cen[2] - 2500, cen[2] + 2500)
      dm <- terra::crop(dem, e)
      hs <- terra::shade(terra::terrain(dm, "slope", unit = "radians"), terra::terrain(dm, "aspect", unit = "radians"))
      f <- p_out("panel_", i, ".png")
      grDevices::png(f, width = 1400, height = 1400, res = 160)
      terra::plot(hs, col = grDevices::grey.colors(50, 0.3, 0.95), legend = FALSE, axes = FALSE, mar = c(1, 1, 2, 1),
                  main = sprintf("Panel %d: order-1 addition %.1f ha (%s)", i, pick$area_ha[i],
                                 if (i <= 2) "largest" else "median-size"))
      terra::plot(terra::crop(fp[[3]], e), col = c(NA, grDevices::adjustcolor("steelblue", 0.45)), add = TRUE,
                  legend = FALSE)
      for (nm in c("order1_added", "order2_added")) {
        pg <- patches[[nm]]
        if (is.null(pg)) next
        pg <- suppressWarnings(sf::st_crop(pg, sf::st_bbox(c(xmin = e[1], ymin = e[3], xmax = e[2], ymax = e[4]),
                                                          crs = sf::st_crs(pg))))
        if (nrow(pg)) plot(sf::st_geometry(pg), add = TRUE, border = NA,
                           col = grDevices::adjustcolor(if (nm == "order1_added") "darkorange" else "gold", 0.6))
      }
      ln <- suppressWarnings(sf::st_crop(net, sf::st_bbox(c(xmin = e[1], ymin = e[3], xmax = e[2], ymax = e[4]),
                                                          crs = sf::st_crs(net))))
      if (nrow(ln)) plot(sf::st_geometry(ln), add = TRUE, col = "navy", lwd = 0.4 + 0.35 * pmin(ln$stream_order, 6))
      # Legend at explicit map coordinates: a keyword position draws nothing after terra::plot().
      graphics::legend(e[1] + 100, e[4] - 100, bty = "o", bg = "white", cex = 0.8,
                       legend = c("order >= 3 floodplain (arm 3)", "added by order 2", "added by order 1", "FWA stream"),
                       fill = c(grDevices::adjustcolor("steelblue", 0.45), grDevices::adjustcolor("gold", 0.6),
                                grDevices::adjustcolor("darkorange", 0.6), NA),
                       border = c("grey40", "grey40", "grey40", NA), lty = c(NA, NA, NA, 1), col = c(NA, NA, NA, "navy"))
      grDevices::dev.off()
      panels <- c(panels, f)
    }
  }

  # --- 6. committed logs --------------------------------------------------------------------------
  stamp <- format(Sys.time(), "%Y%m%d", tz = "UTC")
  log_base <- here::here("scripts", "floodplain_lcc", "logs", sprintf("%s_floodplain_probe-whole-fwa_%s", stamp, area))
  utils::write.csv(out, paste0(log_base, ".csv"), row.names = FALSE)
  md_tab <- function(df) {
    df[] <- lapply(df, function(v) if (is.numeric(v)) format(round(v, 2), big.mark = ",", trim = TRUE) else v)
    c(paste0("| ", paste(names(df), collapse = " | "), " |"), paste0("|", strrep("---|", ncol(df))),
      apply(df, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |")))
  }
  ovt <- out[out$section == "overlap", ]
  ovw <- stats::reshape(ovt[, c("arm", "metric", "value")], idvar = "arm", timevar = "metric", direction = "wide")
  names(ovw) <- sub("^value\\.", "", names(ovw))
  md <- c(
    sprintf("# Whole-FWA floodplain probe: %s, `%s` (#110)", toupper(area), scen_id), "",
    sprintf("Run %s UTC. flooded %s, terra %s. Produced by `scripts/floodplain_lcc/floodplain_probe-run.sh %s`.",
            format(Sys.time(), "%Y-%m-%d %H:%M", tz = "UTC"), tm[[1]]$flooded, tm[[1]]$terra, area), "",
    "## Anchor (arm 5 on its own DEM against step 1 / step 2's record)", "",
    sprintf("network %s · DEM %s · floodplain %s · on-disk raster vs its record %s",
            if (anc$network_match) "MATCH" else "DIFFERS", if (anc$dem_match) "MATCH" else "DIFFERS",
            if (anc$floodplain_match) "MATCH" else "DIFFERS", if (anc$ondisk_match) "MATCH" else "DIFFERS"), "",
    "## Cost and size per arm (common DEM)", "", md_tab(arm_tab), "",
    if (!is.null(seg)) c(sprintf("Segment-grain attribution on arm 3: %s groups, %.1f min, %d rows, %d warnings, %.1f GiB peak.",
                                 format(seg$n_groups, big.mark = ","), seg$t_attr_seg_s / 60, seg$attr_rows,
                                 seg$attr_warnings, rss("seg")), ""),
    sprintf("Attribution fit over the five blk arms: %.0f s + %.3f s per blue line (confounded with valley extent).",
            stats::coef(fit)[[1]], stats::coef(fit)[[2]]), "",
    "## Overlap (ha; a = first arm, b = second)", "", md_tab(ovw), "",
    sprintf("Extent effect: arm 5 on the common grid %.1f ha vs the anchor %.1f ha (%+.3f%%).",
            a5_ha, anc_ha, 100 * (a5_ha - anc_ha) / anc_ha), "",
    "## The baseline's own watercourses (per-blk attributed ha, arm k vs arm 5)", "", md_tab(blk_tab), "",
    "## Habitat by order band (`fresh.streams_vw_bcfp`, km)", "", md_tab(hab), "",
    sprintf("Review layers: `data/%s/probe_whole_fwa/review.gpkg`; panels: %s.", area,
            if (length(panels)) paste0("`", basename(panels), "`", collapse = ", ") else "none"))
  writeLines(md, paste0(log_base, ".md"))
  message("  wrote ", basename(log_base), ".{csv,md}")
  invisible(out)
}
