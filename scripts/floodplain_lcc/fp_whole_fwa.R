# fp_whole_fwa.R — helpers for the whole-FWA floodplain probe (#110)
#
# Sourced by floodplain_probe-whole-fwa.R and asserted offline by floodplain_probe-check.R. Pure
# except fp_wf_read_network() / fp_wf_read_waterbodies(), which take a connection.
#
# THE ARMS ARE R PREDICATES OVER ONE READ, not five SQL WHERE clauses. The probe reads the whole
# group once (every segment, with the access column and stream_order_parent carried along) and each
# arm is a filter of that frame. One definition per arm, so the nesting the comparison depends on
# (arm 3 contains arm 5 exactly; only the filter differs) is a property of the code, checkable with
# no database, rather than of five SQL strings happening to agree.

# --- the arms ------------------------------------------------------------------------------------
# k = 1..5 as numbered in #110. Arm 1 is every segment of `fresh.streams`, which is not quite all FWA:
# on MORR it holds 9,033 of fwa_stream_networks_sp's 9,385 km (mostly edge types 1100, 1350, 1400,
# 1450 absent). Floors are fixed by the issue, not tuned: 1, 2, 3, the bcfishpass
# bypass predicate (first-order channels whose parent is >= 5th order), and today's network. Arm 4
# is bcfishpass's hard-coded predicate, NOT link's: link applies fresh::frs_order_child, which also
# caps on the blue line's own maximum order, and takes 3,998 MORR segments where this takes 7,035.
FP_WF_ARMS <- data.frame(
  arm   = 1:5,
  label = c("all fresh.streams (order >= 1)", "order >= 2", "order >= 3",
            "order >= 3 + first-order with parent >= 5 (bcfp bypass)", "species network (baseline)"),
  stringsAsFactors = FALSE)
FP_WF_PARENT_MIN <- 5L

# Species and arm are interpolated into SQL (a column name) or index a table, so both are refused
# outside a closed shape, the same guard 01 applies to cfg$species.
fp_wf_check_species <- function(species) {
  if (!is.character(species) || length(species) != 1L || is.na(species) ||
      !grepl("^[a-z]{2,4}$", species)) {
    stop("species must be a short lowercase code (e.g. 'co'), got: ", format(species), call. = FALSE)
  }
  invisible(species)
}
fp_wf_check_arm <- function(arm) {
  if (length(arm) != 1L || is.na(suppressWarnings(as.integer(arm))) ||
      !as.integer(arm) %in% FP_WF_ARMS$arm || as.character(as.integer(arm)) != as.character(arm)) {
    stop("arm must be one of ", paste(FP_WF_ARMS$arm, collapse = ", "), ", got: ", format(arm),
         call. = FALSE)
  }
  as.integer(arm)
}

# Logical keep-vector for one arm over the whole-group frame. NA never passes: SQL's three-valued
# logic drops a NULL comparison, so `access IN (1,2)` and `parent >= 5` must not keep an NA row here
# either, or the R arm would hold rows 01's SQL never returns and anchor 1 would fail for a reason
# that has nothing to do with the network.
fp_wf_keep <- function(df, arm, min_order = 3L) {
  arm <- fp_wf_check_arm(arm)
  ord <- df$stream_order
  ge  <- function(x, n) !is.na(x) & x >= n
  switch(arm,
    ge(ord, 1L),
    ge(ord, 2L),
    ge(ord, 3L),
    ge(ord, 3L) | (!is.na(ord) & ord == 1L & ge(df$stream_order_parent, FP_WF_PARENT_MIN)),
    !is.na(df$access) & df$access %in% c(1L, 2L) & ge(ord, min_order))
}

# --- the network read ----------------------------------------------------------------------------
# 01's SELECT, copied rather than shared: #110 forbids touching steps 1-3, and lifting the SQL into a
# helper would be a step-1 change. A copy can drift, so the probe's anchor 1 re-derives arm 5 from
# this read and refuses to run unless it digests equal to the network step 1 recorded in
# provenance.json. Two additions only, both carried along and filtered in R: the species' access
# column (renamed `access`) and stream_order_parent (arm 4). The WHERE keeps the watershed group and
# nothing else. The inner JOIN to streams_access stays, so every arm sees the same segment universe.
fp_wf_network_sql <- function(read_schema, wsg, species) {
  fp_wf_check_species(species)
  if (!grepl("^[a-z_][a-z0-9_]*$", read_schema)) stop("bad schema name: ", read_schema, call. = FALSE)
  if (!grepl("^[A-Z]{4}$", wsg)) stop("bad watershed group code: ", wsg, call. = FALSE)
  sprintf("
    SELECT s.id_segment, s.blue_line_key, s.downstream_route_measure,
           s.stream_order, s.gnis_name, s.channel_width, s.gradient,
           s.length_metre, s.waterbody_key, s.linear_feature_id,
           ua.upstream_area_ha, p.map_upstream,
           a.access_%3$s AS access, s.stream_order_parent, s.geom
    FROM %1$s.streams s
    JOIN %1$s.streams_access a USING (id_segment, watershed_group_code)
    LEFT JOIN (
      SELECT l.linear_feature_id, u.upstream_area_ha
      FROM whse_basemapping.fwa_streams_watersheds_lut l
      JOIN whse_basemapping.fwa_watersheds_upstream_area u
        ON l.watershed_feature_id = u.watershed_feature_id
    ) ua ON ua.linear_feature_id = s.linear_feature_id
    LEFT JOIN whse_basemapping.fwa_stream_networks_mean_annual_precip p
      ON p.wscode_ltree = s.wscode_ltree AND p.localcode_ltree = s.localcode_ltree
    WHERE s.watershed_group_code = '%2$s'",
    read_schema, wsg, species)
}

fp_wf_read_network <- function(conn, read_schema, wsg, species) {
  x <- sf::st_read(conn, query = fp_wf_network_sql(read_schema, wsg, species), quiet = TRUE)
  x <- sf::st_zm(x, drop = TRUE)
  # Same coercion 02 applies after its gpkg read, so the VCA sees the types step 2 saw.
  for (col in c("upstream_area_ha", "map_upstream", "channel_width", "stream_order")) {
    x[[col]] <- as.numeric(x[[col]])
  }
  x$access <- as.integer(x$access)
  x$stream_order_parent <- as.integer(x$stream_order_parent)
  x
}

# 01's waterbody rule: every lake and wetland whose waterbody_key is on the arm's network.
fp_wf_read_waterbodies <- function(conn, streams) {
  keys <- unique(streams$waterbody_key[!is.na(streams$waterbody_key)])
  if (!length(keys)) return(NULL)
  lit <- paste(sprintf("%.0f", as.numeric(keys)), collapse = ",")
  sf::st_zm(sf::st_read(conn, quiet = TRUE, query = sprintf("
    SELECT waterbody_key, 'lake'::text AS waterbody_type, geom
      FROM whse_basemapping.fwa_lakes_poly    WHERE waterbody_key IN (%1$s)
    UNION ALL
    SELECT waterbody_key, 'wetland'::text AS waterbody_type, geom
      FROM whse_basemapping.fwa_wetlands_poly WHERE waterbody_key IN (%1$s)", lit)), drop = TRUE)
}

# Segment key for the segment-grain attribution: (blue_line_key, downstream_route_measure), never
# id_segment, which link numbers per group during generation (#65, #104). Character because
# fl_valley_attribute() groups on ONE column; the measure is fixed at 3 decimals (mm) so the key
# cannot depend on a print option.
fp_wf_seg_key <- function(blk, drm) {
  if (anyNA(blk) || anyNA(drm)) stop("segment key: blue_line_key / downstream_route_measure has NA",
                                     call. = FALSE)
  sprintf("%.0f:%.3f", as.numeric(blk), as.numeric(drm))
}

# --- comparison ----------------------------------------------------------------------------------
# Cell counts between two 0/1 floodplain rasters ON ONE GRID. A floodplain cell is a 1; 0 and NA
# are both "not floodplain". Refuses mismatched grids rather than resampling: every arm is
# delineated on the same DEM precisely so this comparison needs no interpolation.
fp_wf_overlap <- function(a, b) {
  if (!terra::compareGeom(a, b, stopOnError = FALSE)) {
    stop("fp_wf_overlap: rasters are not on one grid (extent, resolution or CRS differ)", call. = FALSE)
  }
  va <- terra::values(a, mat = FALSE); va <- !is.na(va) & va == 1
  vb <- terra::values(b, mat = FALSE); vb <- !is.na(vb) & vb == 1
  ha <- prod(terra::res(a)) / 1e4
  n  <- c(a = sum(va), b = sum(vb), both = sum(va & vb), a_only = sum(va & !vb), b_only = sum(!va & vb))
  data.frame(metric = names(n), cells = as.numeric(n), ha = as.numeric(n) * ha,
             stringsAsFactors = FALSE)
}

# Peak RSS from macOS `/usr/bin/time -l` output ("<n>  maximum resident set size", bytes). NA when
# absent, so a run whose wrapper never printed reads as unmeasured rather than as zero.
fp_wf_peak_rss_gb <- function(lines) {
  hit <- grep("maximum resident set size", lines, value = TRUE)
  if (!length(hit)) return(NA_real_)
  as.numeric(sub("^\\s*([0-9]+).*$", "\\1", hit[length(hit)])) / 1024^3
}
