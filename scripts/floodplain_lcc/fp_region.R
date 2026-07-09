#!/usr/bin/env Rscript
#
# fp_region.R  —  batch helpers for running many watershed groups.
#
# fp_wsg_subbasin(conn, wsg, name_basin): the single whole-WSG "sub-basin" is just the
#   FWA watershed-group polygon itself — exact, robust, and needs no break point or
#   frs_watershed_split. (An earlier attempt derived a mainstem-outlet break point and
#   delineated upstream of it; that only works for headwater groups like MORR/UFRA —
#   for a tributary group with a large river passing through, delineating upstream of
#   the mainstem grabs the whole upstream basin, over-shooting the group by 2-40x.)
#   Returns a 1-row sf in the subbasins schema (name_basin + geometry, EPSG:3005).

fp_wsg_subbasin <- function(conn, wsg, name_basin = NULL) {
  name_basin <- if (is.null(name_basin) || !nzchar(name_basin)) wsg else name_basin
  g <- sf::st_read(conn, query = sprintf(
    "SELECT watershed_group_code, geom
     FROM whse_basemapping.fwa_watershed_groups_poly
     WHERE watershed_group_code = '%s'", wsg), quiet = TRUE)
  if (nrow(g) == 0) stop("watershed group not found: ", wsg, call. = FALSE)
  g$name_basin <- name_basin
  g[, c("name_basin", "watershed_group_code")]
}
