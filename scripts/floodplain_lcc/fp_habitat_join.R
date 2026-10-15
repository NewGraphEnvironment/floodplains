# fp_habitat_join.R — the habitat join on a blue-line floodplain (#104), shared by habitat_join-demo.R
# (MORR, the probe's arms) and habitat_join-query.R (an area's published layers).
#
# Join by POSITION, never by blue line (CLAUDE.md, "Habitat join on the blue-line floodplain"): each
# floodplain cell takes the flags of the nearest segment on a blue line that claims it. The position
# join itself is flooded::fl_valley_join() (flooded#83), which returns both resolutions of shared cells:
#   nearest  the nearest of the claiming blue lines' nearest segments, one owner per cell -- the rule
#            for AREAS, so per-reach areas add up to the floodplain (ties go to the lowest
#            blue_line_key and are counted)
#   any      habitat if any claiming blue line's nearest segment says so -- the "connected" view
# Only claiming blue lines compete: the nearest segment anywhere is, for about a quarter of MORR's
# cells, an order-1 line the floor left out.
# This file keeps what the callers need around it: the claims table and integrity check, the
# by-blue-line contrast, and the area summary.
#
# `h` everywhere is an sf of segments with blue_line_key (numeric), spawning and rearing (logical,
# NA already resolved by the caller) and line geometry, in the floodplain's CRS.

# Floodplain cells per attributed group, and the integrity check: every floodplain cell attributed,
# nothing outside it. `v` is the attributed layer (one row per group), `r` the 0/1 floodplain raster.
fp_hj_grid_cells <- function(r, v, key, crs) {
  if (sf::st_crs(v) != crs || sf::st_crs(terra::crs(r)) != crs)
    stop("the floodplain raster, its attributed layer and the habitat are not all in one CRS", call. = FALSE)
  # The same claims fl_valley_join() takes: a cell is claimed when its centre is inside, and a polygon
  # covering no cell centre claims nothing (terra returns NaN for it).
  cb <- terra::cells(r, terra::vect(v), touches = FALSE, small = FALSE)
  cb <- cb[!is.na(cb[, "cell"]), , drop = FALSE]
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

# The position join, flooded::fl_valley_join(), with NA flags read as FALSE. NA arises only on cells
# claimed solely by blue lines with no segments (counted as blk_without_segments): fl_valley_join()
# calls their flags unknown, while these summaries count habitat, so unknown counts as none, as the
# local join did before flooded#83. Unsummed NA would turn every by-position hectare figure NA.
fp_hj_join_position <- function(r, v, h, key) {
  # Released flooded after 0.7.2: fl_valley_join() first ships there, and a development install of an
  # earlier flooded#83 commit (versioned 0.7.2) claimed cells differently from fp_hj_grid_cells().
  if (!exists("fl_valley_join", envir = asNamespace("flooded"), inherits = FALSE) ||
      utils::packageVersion("flooded") <= "0.7.2")
    stop("the habitat join needs a released flooded with fl_valley_join() (> 0.7.2, flooded#83); ",
         "update it with scripts/packages.R", call. = FALSE)
  fr <- suppressMessages(flooded::fl_valley_join(r, v, h, group = key, cols = c("spawning", "rearing")))
  if (any(fr$check[c("missing", "extra")] != 0)) {
    print(fr$check); stop("fl_valley_join()'s integrity check failed: floodplain and attribution disagree", call. = FALSE)
  }
  for (t in c("nearest", "any")) for (f in c("spawning", "rearing")) fr[[t]][[f]] <- fr[[t]][[f]] %in% TRUE
  fr
}

fp_hj_summ <- function(f, label, build, cell_ha) {
  data.frame(join = label, build = build,
             spawning_ha = sum(f$spawning) * cell_ha, rearing_ha = sum(f$rearing) * cell_ha,
             both_ha = sum(f$spawning & f$rearing) * cell_ha,
             spawn_only_ha = sum(f$spawning & !f$rearing) * cell_ha,
             rear_only_ha = sum(!f$spawning & f$rearing) * cell_ha)
}
