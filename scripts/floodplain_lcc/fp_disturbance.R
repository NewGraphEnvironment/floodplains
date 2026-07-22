# fp_disturbance.R — config-driven, layer-agnostic disturbance attribution (#19).
#
# Generalizes the fire-only fire_tag.R prototype. Given land-cover-change patches (the transition
# layer) and a list of disturbance SOURCES (config, not code), tag each patch with, per source:
#   in_<name>      : does the patch overlap any source polygon within the change window?
#   <carry attrs>  : the DOMINANT overlapping feature's carried attributes (largest intersection area)
# Attribution is ADDITIVE — a patch may match several sources (burned AND salvage-logged). The
# residual (matches no source) is the classification-noise floor.
#
# A source is a config entry (see config/disturbance.yml):
#   name      short id -> in_<name>
#   table     fwapg schema.table (loaded via bc2pg)
#   geom_col  geometry column
#   year_col  temporal field used to window to the change interval
#   carry     source columns copied onto the patch from the dominant overlapping feature
#   filter    OPTIONAL extra SQL predicate (e.g. a pest-species subset)
#   window    OPTIONAL [from, to] override (default = the change interval passed in)
#
# The AOI bbox is pushed into the SQL WHERE server-side (ST_Intersects + ST_MakeEnvelope) so a
# province-wide layer (e.g. consolidated cutblocks) never streams the whole table into R.

suppressMessages({library(sf); library(dplyr)})

`%|null|%` <- function(a, b) if (is.null(a)) b else a

# Fetch one source's polygons intersecting the patches' AOI bbox, within the year window.
.dst_fetch <- function(conn, src, patches, window) {
  w   <- src$window %|null|% window
  env <- sf::st_bbox(sf::st_transform(sf::st_as_sfc(sf::st_bbox(patches)), 4326))
  carry <- paste(src$carry, collapse = ", ")
  filt  <- if (!is.null(src$filter) && nzchar(src$filter)) paste0(" AND (", src$filter, ")") else ""
  q <- sprintf(
    "SELECT %s, %s AS geom
       FROM %s
      WHERE %s BETWEEN %d AND %d%s
        AND ST_Intersects(%s, ST_Transform(ST_MakeEnvelope(%.8f,%.8f,%.8f,%.8f,4326), ST_SRID(%s)))",
    carry, src$geom_col, src$table,
    src$year_col, as.integer(w[1]), as.integer(w[2]), filt,
    src$geom_col, env[["xmin"]], env[["ymin"]], env[["xmax"]], env[["ymax"]], src$geom_col)
  sf::st_read(conn, query = q, quiet = TRUE)
}

# Tag `patches` (an sf with a unique `patch_id`) with in_<name> + carry columns for each source.
# Returns the augmented sf. window = c(from, to) change interval (per-source override via src$window).
fp_disturbance_tag <- function(patches, sources, conn, window = c(2017, 2023)) {
  patches    <- sf::st_make_valid(patches)
  target_crs <- sf::st_crs(patches)

  for (src in sources) {
    nm     <- src$name
    in_col <- paste0("in_", nm)
    poly   <- .dst_fetch(conn, src, patches, window)

    patches[[in_col]] <- FALSE
    for (a in src$carry) patches[[a]] <- NA
    if (nrow(poly) == 0) next

    poly <- sf::st_make_valid(sf::st_transform(poly, target_crs))
    patches[[in_col]] <- lengths(sf::st_intersects(patches, poly)) > 0

    # dominant overlapping feature (largest intersection area) -> carry its attributes
    idx <- which(patches[[in_col]])
    if (length(idx)) {
      inter <- suppressWarnings(sf::st_intersection(patches[idx, "patch_id"], poly))
      if (nrow(inter)) {
        inter$._ov <- as.numeric(sf::st_area(inter))
        dom <- sf::st_drop_geometry(inter) |>
          dplyr::group_by(patch_id) |>
          dplyr::slice_max(._ov, n = 1, with_ties = FALSE) |>
          dplyr::ungroup()
        m <- match(patches$patch_id, dom$patch_id)
        keep <- !is.na(m)
        for (a in src$carry) patches[[a]][keep] <- dom[[a]][m[keep]]
      }
    }
  }
  patches
}

# Report the Trees->non-Trees loss split by source + additive residual (the noise floor).
fp_disturbance_report <- function(patches, sources, area = "") {
  loss <- patches[patches$from_class == "Trees" & patches$to_class != "Trees", ]
  tot  <- sum(loss$area_ha)
  in_cols <- vapply(sources, function(s) paste0("in_", s$name), character(1))

  cat(sprintf("\n=== %s Trees->non-Trees LOSS vs disturbance ===\n", toupper(area)))
  cat(sprintf(" total loss      : %.1f ha\n", tot))
  for (ic in in_cols) {
    ha <- sum(loss$area_ha[loss[[ic]] %in% TRUE])
    cat(sprintf(" %-15s: %.1f ha (%.0f%%)\n", ic, ha, 100 * ha / tot))
  }
  any_in <- Reduce(`|`, lapply(in_cols, function(ic) loss[[ic]] %in% TRUE))
  resid  <- sum(loss$area_ha[!any_in])
  cat(sprintf(" residual (noise): %.1f ha (%.0f%%)\n", resid, 100 * resid / tot))
  invisible(loss)
}
