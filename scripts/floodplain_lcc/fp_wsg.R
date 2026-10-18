# fp_wsg.R — the group line (#53, #138).
#
# A group's floodplain runs past its watershed group polygon, onto the receiving river's valley floor
# at the outlet and across shared lakes (PCEA takes all three FWA polygons of Williston). Neither
# clipping (a landform cut at an administrative line) nor leaving it unlabelled (neighbouring items
# double-count) was taken. Decided 2026-10-18: the delineation stays WHOLE and every published layer
# is SPLIT along the group polygon, each piece carrying `in_wsg` -- TRUE inside the item's own group,
# FALSE outside. The #40 pattern: attribute a fixed delineation, never re-run it.
#
#   everything        the whole landform, as published before #53
#   in_wsg            items are disjoint (group polygons tile BC), so a regional total is a sum
#   !in_wsg           the overlap with neighbours, discoverable per item
#
# Not `wsg`: that is the item key (#30), which row belongs to which item. `in_wsg` follows the
# repo's `in_*` columns.
#
# The change patches used to be CLIPPED to the sub-basins by drift (dft_transition_vectors(zones=)
# intersects last, after patch_id is assigned), while the cell-level composition kept the outside
# cells -- so the two populations disagreed and composition-check.R failed its bound on every
# whole-network group. fp_split_patches() reproduces drift's intersection exactly and adds the
# remainder, so the inside rows are byte-for-byte what step 3 wrote before and their totals cannot move.

suppressMessages(library(sf))

# The group polygon for an area, in EPSG:3005. A whole-WSG area's subbasins.gpkg IS the group
# polygon (fp_wsg_subbasin wrote it, carrying watershed_group_code), so it is read from disk -- the
# backfill needs no database for the 23 region groups. A subset area (neexdzii: 14 interior
# sub-basins from frs_watershed_split) reads the group from fwapg.
#
# attr "zones_are_wsg" says whether the sub-basins ARE the group polygon, which fp_split_patches()
# needs: then the sub-basin split already is the group split, and splitting again would re-node the
# inside pieces and move their areas in the last digits.
fp_wsg_polygon <- function(cfg, conn = NULL) {
  wsg <- cfg$watershed_group
  if (is.null(wsg) || !nzchar(wsg)) stop("cfg has no watershed_group", call. = FALSE)
  sb_path <- file.path(cfg$dir_out, "subbasins.gpkg")
  if (!file.exists(sb_path)) stop("no ", sb_path, " -- run step 2 first", call. = FALSE)
  sb <- sf::st_read(sb_path, quiet = TRUE)
  whole <- nrow(sb) == 1L && "watershed_group_code" %in% names(sb) &&
    identical(as.character(sb$watershed_group_code), wsg)
  if (whole) {
    g <- sb["watershed_group_code"]
  } else {
    if (is.null(conn)) {
      conn <- DBI::dbConnect(RPostgres::Postgres())
      on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)
    }
    g <- fp_wsg_subbasin(conn, wsg)["watershed_group_code"]
  }
  attr(g, "zones_are_wsg") <- whole
  g
}

# Polygon parts only, one geometry per input geometry. An intersection or difference returns a
# GEOMETRYCOLLECTION where the inputs also touch along a line or a point, which QGIS will not draw
# (code-check-spatial.md); st_collection_extract() on an sf can explode a row into several, so this
# works per geometry and keeps one row per piece. Non-polygon parts are dropped, an empty result
# stays empty (the caller drops it).
.fp_poly_only <- function(g) {
  crs <- sf::st_crs(g)
  out <- lapply(g, function(x) {
    if (inherits(x, c("POLYGON", "MULTIPOLYGON"))) return(x)
    if (inherits(x, "GEOMETRYCOLLECTION")) {
      parts <- Filter(function(p) inherits(p, c("POLYGON", "MULTIPOLYGON")), unclass(x))
      if (!length(parts)) return(sf::st_multipolygon())
      if (length(parts) == 1L) return(parts[[1]])
      return(sf::st_cast(sf::st_combine(sf::st_sfc(parts)), "MULTIPOLYGON")[[1]])
    }
    sf::st_multipolygon()
  })
  sf::st_sfc(out, crs = crs)
}

.fp_keep_area <- function(x) {
  sf::st_geometry(x) <- .fp_poly_only(sf::st_geometry(x))
  x[!sf::st_is_empty(x) & as.numeric(sf::st_area(x)) > 0, , drop = FALSE]
}

# Split every row of `x` along the group polygon. Each row becomes up to two rows -- the part inside
# (in_wsg TRUE) and the part outside (FALSE) -- with every column kept, inside first, in input order.
# A row wholly on one side is one row. Pieces with no area (a shared edge) are dropped, so the pieces
# of a row conserve its area.
fp_wsg_split <- function(x, wsg_poly) {
  if ("in_wsg" %in% names(x)) stop("x already carries in_wsg -- it has been split", call. = FALSE)
  g <- sf::st_union(sf::st_geometry(sf::st_transform(wsg_poly, sf::st_crs(x))))
  x$._row <- seq_len(nrow(x))
  inn <- suppressWarnings(sf::st_intersection(x, g))
  out <- suppressWarnings(sf::st_difference(x, g))
  inn <- .fp_keep_area(inn); out <- .fp_keep_area(out)
  inn$in_wsg <- rep(TRUE, nrow(inn)); out$in_wsg <- rep(FALSE, nrow(out))
  res <- rbind(inn, out)
  res <- res[order(res$._row, !res$in_wsg), , drop = FALSE]
  res$._row <- NULL
  rownames(res) <- NULL
  res
}

# Change patches -> sub-basin pieces + group pieces. `patches` is dft_transition_vectors() run with
# NO zones. The inside half is EXACTLY the intersection drift ran with zones= (same transform, same
# column subset, same st_intersection), so those rows equal what step 3 wrote before #53. The rest of
# each patch -- outside every sub-basin -- follows with `zone_col` NA. Then `in_wsg`:
#   zones are the group polygon (every whole-WSG area): in_wsg is exactly "has a zone"
#   zones are interior sub-basins (neexdzii): every piece is split along the group line
fp_split_patches <- function(patches, zones, zone_col, wsg_poly) {
  zones_proj <- sf::st_transform(zones[zone_col], sf::st_crs(patches))
  inn <- suppressWarnings(sf::st_intersection(patches, zones_proj))
  out <- suppressWarnings(sf::st_difference(patches, sf::st_union(sf::st_geometry(zones_proj))))
  out <- .fp_keep_area(out)
  out[[zone_col]] <- zones_proj[[zone_col]][rep(NA_integer_, nrow(out))]
  out <- out[, names(inn)]
  if (isTRUE(attr(wsg_poly, "zones_are_wsg"))) {
    inn$in_wsg <- rep(TRUE, nrow(inn)); out$in_wsg <- rep(FALSE, nrow(out))
    res <- rbind(inn, out)
  } else {
    res <- fp_wsg_split(rbind(inn, out), wsg_poly)
  }
  rownames(res) <- NULL
  res
}

# A scenario layer as ONE feature, for the readers that use the delineation as an AOI (the STAC
# fetch, the per-sub-basin summaries, the cell rasterisation): split pieces are re-joined. A layer
# that predates the split (one row) passes through untouched, so its geometry -- and anything keyed
# on its bytes -- does not move.
fp_floodplain_whole <- function(fp) {
  if (nrow(fp) <= 1L) return(fp)
  sf::st_sf(geometry = sf::st_union(sf::st_geometry(fp)))
}
