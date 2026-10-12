# fp_habitat_join.R — the habitat join on a blue-line floodplain (#104), shared by habitat_join-demo.R
# (MORR, the probe's arms) and habitat_join-query.R (an area's published layers).
#
# Join by POSITION, never by blue line (CLAUDE.md, "Habitat join on the blue-line floodplain"): each
# floodplain cell takes the flags of the nearest segment on a blue line that claims it. Shared cells:
#   nearest  the nearest of the claiming blue lines' nearest segments, one owner per cell -- the rule
#            for AREAS, so per-reach areas add up to the floodplain (ties go to the lowest
#            blue_line_key and are counted)
#   any      habitat if any claiming blue line's nearest segment says so -- the "connected" view
# Only claiming blue lines compete: the nearest segment anywhere is, for about a quarter of MORR's
# cells, an order-1 line the floor left out.
#
# `h` everywhere is an sf of segments with blue_line_key (numeric), spawning and rearing (logical,
# NA already resolved by the caller) and line geometry, in the floodplain's CRS.

# Floodplain cells per attributed group, and the integrity check: every floodplain cell attributed,
# nothing outside it. `v` is the attributed layer (one row per group), `r` the 0/1 floodplain raster.
fp_hj_grid_cells <- function(r, v, key, crs) {
  if (sf::st_crs(v) != crs || sf::st_crs(terra::crs(r)) != crs)
    stop("the floodplain raster, its attributed layer and the habitat are not all in one CRS", call. = FALSE)
  cb <- terra::cells(r, terra::vect(v))
  out <- data.frame(key = v[[key]][cb[, "ID"]], cell = cb[, "cell"])
  fpc <- which(terra::values(r, mat = FALSE) == 1L)
  chk <- c(floodplain_cells = length(fpc), attributed_cells = length(unique(out$cell)),
           missing = length(setdiff(fpc, out$cell)), extra = length(setdiff(out$cell, fpc)))
  list(r = r, cells = out, check = chk)
}

# Per-claim flags, then OR over the groups that claim a cell.
fp_hj_or_by_cell <- function(cell, sp, re) {
  s <- tapply(sp, cell, any); r <- tapply(re, cell, any)
  data.frame(cell = as.numeric(names(s)), spawning = as.logical(s), rearing = as.logical(r[names(s)]))
}

# By blue line: a blue line's whole floodplain takes any habitat anywhere on it. Kept as the contrast
# the position join is measured against, never as an answer.
fp_hj_join_blk <- function(cells, h) {
  f <- stats::aggregate(cbind(spawning, rearing) ~ blue_line_key, data = sf::st_drop_geometry(h), FUN = any)
  m <- match(cells$key, f$blue_line_key)
  fp_hj_or_by_cell(cells$cell, !is.na(m) & f$spawning[m], !is.na(m) & f$rearing[m])
}

# By position: each cell takes the nearest segment on each blue line that claims it, then `nearest` and
# `any` resolve the shared cells.
fp_hj_join_range <- function(cells, h, r) {
  out <- list(); no_seg <- 0; hk <- split(seq_len(nrow(h)), sprintf("%.0f", h$blue_line_key))
  for (b in unique(cells$key)) {
    cc <- cells$cell[cells$key == b]; idx <- hk[[sprintf("%.0f", b)]]
    if (is.null(idx)) {   # the blue line has no segment in this build: no habitat, and no distance
      no_seg <- no_seg + 1  # to compete with, so it never owns a cell under `nearest`
      out[[length(out) + 1]] <- data.frame(cell = cc, blk = b, dist = Inf, spawning = FALSE, rearing = FALSE); next
    }
    pts <- sf::st_as_sf(as.data.frame(terra::xyFromCell(r, cc)), coords = c("x", "y"), crs = sf::st_crs(h))
    nn <- idx[sf::st_nearest_feature(pts, h[idx, ])]
    out[[length(out) + 1]] <- data.frame(cell = cc, blk = b,
      dist = as.numeric(sf::st_distance(pts, h[nn, ], by_element = TRUE)),
      spawning = h$spawning[nn], rearing = h$rearing[nn])
  }
  o <- do.call(rbind, out)
  any_ <- fp_hj_or_by_cell(o$cell, o$spawning, o$rearing)
  o <- o[order(o$cell, o$dist, o$blk), ]
  first <- !duplicated(o$cell)
  ties <- sum(!first & is.finite(o$dist) & o$dist == c(NA, o$dist[-nrow(o)]) & o$cell == c(NA, o$cell[-nrow(o)]) &
                c(FALSE, first[-length(first)]), na.rm = TRUE)
  near <- data.frame(cell = o$cell[first], spawning = o$spawning[first], rearing = o$rearing[first])
  attr(near, "ties") <- ties
  attr(any_, "blk_without_segments") <- attr(near, "blk_without_segments") <- no_seg
  list(nearest = near, any = any_)
}

fp_hj_summ <- function(f, label, build, cell_ha) {
  data.frame(join = label, build = build,
             spawning_ha = sum(f$spawning) * cell_ha, rearing_ha = sum(f$rearing) * cell_ha,
             both_ha = sum(f$spawning & f$rearing) * cell_ha,
             spawn_only_ha = sum(f$spawning & !f$rearing) * cell_ha,
             rear_only_ha = sum(!f$spawning & f$rearing) * cell_ha)
}
