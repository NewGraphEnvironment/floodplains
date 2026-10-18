# fp_lulc_vectors.R — step 3's vector half: classified layers, change patches, bridge (#53).
#
# Everything step 3 does AFTER the rasters exist, so the backfill (gpkg_backfill-split.R) takes the
# same path from rasters/<scenario>/ with no STAC fetch and the two cannot disagree -- the shape
# fp_composition_build() already has for the composition table. Needs fp_wsg.R and fp_disturbance.R.

suppressMessages({library(sf); library(terra)})

# Classified land cover per year, dissolved by class, item-keyed (#30) and split at the group line.
fp_classified_layer <- function(r, cfg, scenario_id, wsg_poly) {
  polys <- terra::as.polygons(r) |> sf::st_as_sf()
  # Item key (#30): every published layer carries wsg + species + scenario, mirroring the STAC
  # item id (<wsg>_<species>_<scenario>). Layer names stay producer-keyed; these columns are what
  # let many areas merge into one gpkg downstream and stay separable by attribute.
  polys$wsg      <- cfg$watershed_group
  polys$species  <- cfg$species
  polys$scenario <- scenario_id
  fp_wsg_split(polys, wsg_poly)
}

# Change patches from a transition raster: vectorised UNCLIPPED, then split into sub-basin pieces
# (name_basin, NA outside every sub-basin) and group pieces (in_wsg), tagged with every overlay
# configured, item-keyed. Returns the sf step 3 writes as transition_<scenario>_<from>_<to>.
#
# changes_only = TRUE (drift#34) builds polygons ONLY for actual changes (from != to), never
# materializing the stable "Trees -> Trees" / "Water -> Water" patches that dominate a large
# floodplain and OOM the vectorizer.
#
# NO zones: drift's zones= intersects last, after patch_id, so passing them CLIPPED away every patch
# outside the sub-basins while the composition table kept those cells (#53). fp_split_patches() runs
# that same intersection and keeps the remainder, so the inside rows are unchanged.
fp_transition_patches <- function(trans_raster, subbasins, wsg_poly, cfg, scenario_id, conn = NULL) {
  trans_polys <- drift::dft_transition_vectors(trans_raster, changes_only = TRUE)
  trans_polys <- fp_split_patches(trans_polys, subbasins, "name_basin", wsg_poly)
  parts <- strsplit(trans_polys$transition, " -> ", fixed = TRUE)
  trans_polys$from_class <- vapply(parts, `[`, character(1), 1)
  trans_polys$to_class   <- vapply(parts, `[`, character(1), 2)

  # Recompute area_ha from geometry post-split. drift's column is the whole patch's, so a patch the
  # sub-basin or group line divides would be counted once per piece when summed by row.
  trans_polys$area_ha <- as.numeric(sf::st_area(trans_polys)) / 1e4

  # Disturbance attribution (#19): tag each change patch by configured overlay layer, in memory
  # before the write so the transition layer carries in_<source> + carried attrs. Context overlays
  # (#95 in_wetland, #108 in_alr, #138 in_open_water) ride the same pass -- they locate change and
  # never explain it, which is why only cfg$disturbance ever reaches the attribution report.
  # Lookback overlays (#103, prior fires) ride it too and are not causes either. A DB conn is opened
  # ONLY when something is configured, so offline step-3 runs are unaffected.
  dst_entries <- c(cfg[["disturbance"]], cfg[["context_overlays"]], cfg[["lookback_overlays"]])
  if (length(dst_entries)) {
    if (is.null(conn)) {
      conn <- DBI::dbConnect(RPostgres::Postgres())
      on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)  # norm: disconnect even on error
    }
    trans_polys <- fp_disturbance_tag(trans_polys, dst_entries, conn, window = cfg$change_interval)
    nms <- function(x) paste(vapply(x, function(s) s$name, character(1)), collapse = ", ")
    message("  Tagged disturbance: ", nms(cfg[["disturbance"]]),
            if (length(cfg[["context_overlays"]])) paste0("; context: ", nms(cfg[["context_overlays"]])),
            if (length(cfg[["lookback_overlays"]])) paste0("; lookback: ", nms(cfg[["lookback_overlays"]])))
  }

  # Item key (#30) — set after disturbance tagging so the keys sit alongside the tagged columns.
  trans_polys$wsg      <- cfg$watershed_group
  trans_polys$species  <- cfg$species
  trans_polys$scenario <- scenario_id
  trans_polys
}

# The patch key. patch_id is GLOBAL (drift numbers patches before any zoning, #87), but a patch
# divided by a sub-basin boundary or the group line is several rows sharing it, so the key is the
# piece: (name_basin, patch_id, in_wsg). Without in_wsg, neexdzii's pieces outside every sub-basin
# (name_basin NA) on either side of the BULK line would collide.
fp_patch_key <- function(x) paste(x$name_basin, x$patch_id, x$in_wsg, sep = "¦")

# --- Bridge: which change patches belong to which watercourse (#54) ---
# The floodplain is exploded two ways that cannot be joined by a column. Change patches are
# DISJOINT (one row per patch piece); per-watercourse attribution rows deliberately OVERLAP where
# ground is shared at a confluence (#40) -- on MORR they sum to 795.8 km2 over a 411.1 km2
# floodplain. So a patch belongs to several watercourses at once, and writing a single blue_line_key
# onto it would force a choice that destroys exactly the overlap #40 preserves.
#
# Ship the relation instead, as a non-spatial table: one row per (patch piece, watercourse) pair
# with the overlap. overlap_frac lets a consumer pick inclusive / apportioned / exclusive semantics;
# without it the natural join overcounts by up to 94%.
#
# ONE builder for step 3 and attribute_tag.R (#53): two copies had already drifted (one filtered
# slivers after building, one before), and the in_wsg key had to reach both.
#
# A watercourse can now be two rows too (its inside and outside pieces), so overlaps are summed per
# (patch piece, watercourse) before anything is derived: a patch piece meets one side of the line
# only, but the bridge must hold one row per pair whatever the attribution layer's row count.
#
# Returns the bridge data.frame, or NULL when no pair survives the sliver filter.
fp_bridge_build <- function(pat, wc, key, item) {
  pat <- pat[, c("patch_id", "name_basin", "in_wsg", "area_ha")]
  pat$._pk <- fp_patch_key(pat)
  wc <- wc[, key]
  # The two layers are in DIFFERENT projected CRS -- the attribution layer inherits the stream
  # network's BC Albers, the transition layer the landcover raster's UTM. Transform the watercourses
  # TO the patches: area_ha was measured in the patch CRS.
  if (sf::st_crs(wc) != sf::st_crs(pat)) wc <- sf::st_transform(wc, sf::st_crs(pat))
  # st_intersection on two sf data.frames returns ONE ROW PER INTERSECTING PAIR carrying columns from
  # both sides, using the spatial index -- which is the bridge itself.
  inter <- suppressWarnings(sf::st_intersection(pat, wc))
  if (!nrow(inter)) return(NULL)
  ov <- as.numeric(sf::st_area(inter)) / 1e4
  d <- sf::st_drop_geometry(inter)
  # Sum per pair FIRST, then drop slivers, then derive -- never filter a frame a hoisted key indexes
  # (#63: a key outside the frame goes stale the instant the frame is filtered).
  pair <- paste(d$._pk, d[[key]], sep = "§")
  first <- !duplicated(pair)
  b <- d[first, c("patch_id", "name_basin", "in_wsg", key, "._pk", "area_ha"), drop = FALSE]
  b$overlap_ha <- as.numeric(rowsum(ov, pair, reorder = FALSE)[, 1])
  # A shared boundary yields a zero-area pair -- and so does a SLIVER, because overlap_ha is rounded
  # to 4 dp and a 9.9e-5 m2 intersection lands on exactly 0.0000 ha. A join artefact, not a relation.
  b <- b[round(b$overlap_ha, 4) > 0, , drop = FALSE]
  if (!nrow(b)) return(NULL)
  bridge <- data.frame(
    patch_id     = b$patch_id,
    name_basin   = b$name_basin,
    in_wsg       = b$in_wsg,
    k            = b[[key]],
    overlap_ha   = round(b$overlap_ha, 4),
    # Capped at 1: a fully contained patch can overshoot by a float epsilon.
    overlap_frac = round(pmin(1, b$overlap_ha / b$area_ha), 4),
    wsg = item$wsg, species = item$species, scenario = item$scenario,
    stringsAsFactors = FALSE)
  # TWO fractions, and only one is additive. Watercourse rows overlap each other (#40), so overlap_frac
  # sums to ~2.3 per patch on MORR; apportion_weight normalises within the patch piece to exactly 1.
  #   overlap_frac      "what share of this patch does this watercourse cover?"  (sums > 1)
  #   apportion_weight  "what share of this patch is credited to it?"            (sums to 1)
  tot <- tapply(bridge$overlap_ha, b$._pk, sum)
  bridge$apportion_weight <- round(bridge$overlap_ha / tot[b$._pk], 4)
  attr(bridge, "union_coverage") <- tapply(bridge$overlap_frac, b$._pk, max)
  attr(bridge, "unbridged") <- sum(!pat$._pk %in% b$._pk)
  names(bridge)[names(bridge) == "k"] <- key
  bridge
}

# Write the transition layer and its bridge (or remove a stale one). Returns the patch count.
fp_write_transition <- function(trans_polys, cfg, scenario_id, lyr, out_lc_gpkg, fp_file) {
  sf::st_write(trans_polys, out_lc_gpkg, layer = lyr,
               append = file.exists(out_lc_gpkg), delete_layer = TRUE, quiet = TRUE)
  message("  Layer: ", lyr, " (", nrow(trans_polys), " change patch pieces, ",
          sum(!trans_polys$in_wsg), " outside ", cfg$watershed_group, ")")
  fp_write_bridge(trans_polys, cfg, scenario_id, lyr, out_lc_gpkg, fp_file)
  nrow(trans_polys)
}

# The bridge for a transition layer: written, or -- when this run finds none -- a stale one removed.
# Its own function so the backfill can rebuild it from the layer on disk when a run died between the
# two writes (the transition layer split, the bridge not yet).
fp_write_bridge <- function(trans_polys, cfg, scenario_id, lyr, out_lc_gpkg, fp_file) {
  attr_lyr <- if (!is.null(cfg$attribute_by))
    paste0(scenario_id, "_by_", cfg$attribute_by) else NA_character_
  # b_lyr and the flag live OUTSIDE the gate below. Three different things mean "no bridge this
  # run" -- attribute_by unset, the attribution layer missing, or every pair filtered out as a
  # sliver -- and any of the three would otherwise leave an earlier run's bridge beside a freshly
  # written transition layer, describing a relation this run did not find (#55's orphan class).
  # (A run with no change patches never reaches here and leaves both stale: #68.)
  b_lyr <- sub("^transition_", "patch_watercourse_", lyr)
  wrote_bridge <- FALSE
  if (!is.na(attr_lyr) && file.exists(fp_file) && attr_lyr %in% sf::st_layers(fp_file)$name) {
    key <- cfg$attribute_by
    wc  <- sf::st_read(fp_file, layer = attr_lyr, quiet = TRUE)
    bridge <- fp_bridge_build(trans_polys, wc, key,
                              list(wsg = cfg$watershed_group, species = cfg$species, scenario = scenario_id))
    if (!is.null(bridge)) {
      u <- attr(bridge, "union_coverage"); unb <- attr(bridge, "unbridged")
      attr(bridge, "union_coverage") <- NULL; attr(bridge, "unbridged") <- NULL
      sf::st_write(bridge, out_lc_gpkg, layer = b_lyr,
                   append = file.exists(out_lc_gpkg), delete_layer = TRUE, quiet = TRUE)
      # Coverage worth printing is the UNION one -- how much of a patch any watercourse reaches.
      message("  Layer: ", b_lyr, " (", nrow(bridge), " pairs over ", length(u), " patch pieces and ",
              length(unique(bridge[[key]])), " watercourses; union coverage ", sprintf("%.3f", mean(u)),
              ", unbridged pieces ", unb, ")")
      wrote_bridge <- TRUE
    }
  }
  if (!wrote_bridge && file.exists(out_lc_gpkg) && b_lyr %in% sf::st_layers(out_lc_gpkg)$name) {
    # MEASURE THE OUTPUT, not the return value: st_delete returns TRUE while GDAL fails to delete
    # (measured on sf 1.1.2 with a read-only directory). Re-reading the layer list is the file telling us.
    sf::st_delete(out_lc_gpkg, layer = b_lyr, quiet = TRUE)
    if (!b_lyr %in% sf::st_layers(out_lc_gpkg)$name) {
      message("  Removed stale ", b_lyr, " -- no bridge written this run")
    } else {
      warning("could not remove stale layer ", b_lyr, " from ", basename(out_lc_gpkg),
              " -- it describes a relation this run did not find",
              call. = FALSE, immediate. = TRUE)
    }
  }
  invisible(wrote_bridge)
}
