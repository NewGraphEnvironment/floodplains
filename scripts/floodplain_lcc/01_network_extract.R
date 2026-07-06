#!/usr/bin/env Rscript
#
# 01_network_extract.R  —  defines fp_network(cfg)
#
# Build the coho-accessible stream network + filtered waterbodies for an area using
# the `link` package (a config-driven pipeline that orchestrates `fresh` over a fwapg
# PostgreSQL database). Produces data/<area>/aquatic_network.gpkg with:
#   streams_co3      coho-accessible streams, order >= cfg$min_order (input to 02)
#   waterbodies_co3  lakes/wetlands on the accessible network
#
# `link` is watershed-group scoped, so we run cfg$watershed_group, persist into the
# DEDICATED cfg$schema (never the shared province-wide `fresh.*`). If cfg$subset is set
# (blue_line_key + downstream_route_measure) the network is subset to that reach
# (e.g. Neexdzii = upstream of the Wedzin Kwa confluence within BULK); if cfg$subset is
# NULL the whole watershed group is exported (e.g. MORR).
#
# Requires:
#   - fwapg database (local fwapg via standard libpq env vars; see scripts/README.md)
#   - link >= 0.44.0 (access-segmentation over-credit fix -- streams break at every
#     gradient+falls frontier, matching bcfishpass; link#223/#228. Prior 0.43.x
#     over-credited reaches above gradient>15% barriers as coho-accessible.)
#
# Called by scripts/run_area.R (step 1). cfg comes from fp_read_config().

fp_network <- function(cfg) {
  library(link)
  library(sf)
  sf_use_s2(FALSE)

  # Local fwapg via standard libpq env vars (PGHOST/PGPORT/PGDATABASE/PGUSER/
  # PGPASSWORD). NOT lnk_db_conn() -- that prefers the remote PG_*_SHARE profile;
  # we want the local DB. See scripts/README.md "Prerequisite -- fwapg database".
  conn <- DBI::dbConnect(RPostgres::Postgres())
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  min_order <- cfg$min_order
  aoi_wsg   <- cfg$watershed_group
  schema    <- cfg$schema
  out_dir   <- cfg$dir_out
  fs::dir_create(out_dir)

  # --- Run the link habitat pipeline for the watershed group ---
  # Use the `default` config (NewGraph methodology), NOT `bcfishpass`. They differ
  # in the natural-barrier set: bcfishpass opts in `subsurfaceflow` for parity,
  # whereas the default bundle leaves it OFF (config.yaml: "NewGraph methodology
  # decision"). Default => natural access barriers = gradient + falls only, which
  # matches the historical 01 accessibility definition. Persist into the dedicated
  # schema by overriding cfg$pipeline$schema (shared fresh.* untouched).
  #
  # dams = TRUE is the documented default (conn_tunnel = conn loads the LOCAL
  # cabd.dams, link#137, no real tunnel). mapping_code = FALSE: we don't need the
  # token strings; as of link#218 (v0.43.0) `streams_access` (access_co) is built
  # regardless. access_co is NATURAL-barrier accessibility (dams/anthropogenic are
  # excluded from access since link#200) = potential-habitat reachability.
  message("Loading link config + overrides...")
  lnk_cfg <- lnk_config("default")   # method choice, not area config
  lnk_cfg$pipeline$schema <- schema
  loaded <- lnk_load_overrides(lnk_cfg)

  # RUNBOOK Sec 6: set timeouts so a runaway/locked op cancels server-side instead
  # of orphaning the backend.
  DBI::dbExecute(conn, "SET statement_timeout = '1800000'")  # 30 min
  DBI::dbExecute(conn, "SET lock_timeout = '60000'")          # 60 s

  # Start the dedicated persist schema fresh. lnk_persist_init only creates tables
  # when absent (force_recreate = FALSE), so a leftover schema from a prior run with
  # a different config/species set mismatches the persist INSERT (e.g. a missing
  # has_barriers_rb_dnstr column). Dropping guarantees columns match the config.
  DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schema))

  message("Running link pipeline for WSG ", aoi_wsg, " into schema ", schema, " ...")
  lnk_pipeline_run(conn, aoi = aoi_wsg, cfg = lnk_cfg, loaded = loaded,
                   dams = TRUE, mapping_code = FALSE)

  message("Pipeline complete (schema ", schema, ").")

  # --- Read the coho-accessible network ---
  # Coho-accessible (access_co IN (1,2): 1 = modelled accessible past natural
  # barriers, 2 = observation-confirmed above a barrier; 0 = blocked), order >=
  # min_order. Join upstream_area_ha (VCA field) + map_upstream (precip) from fwapg
  # -- link's streams table doesn't carry them but `02`/flooded need them.
  message("Reading coho-accessible order >= ", min_order, " streams + attributes...")
  streams_sql <- sprintf("
    SELECT s.id_segment, s.blue_line_key, s.downstream_route_measure,
           s.stream_order, s.gnis_name, s.channel_width, s.gradient,
           s.length_metre, s.waterbody_key, s.linear_feature_id,
           ua.upstream_area_ha, p.map_upstream, s.geom
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
    WHERE a.access_co IN (1, 2) AND s.stream_order >= %2$s",
    schema, min_order)
  streams <- sf::st_read(conn, query = streams_sql, quiet = TRUE) |> sf::st_zm(drop = TRUE)

  # --- Optional reach subset ---
  # If cfg$subset is set, keep only the network upstream of the confluence measure
  # (e.g. Neexdzii within BULK). If NULL, export the whole watershed group (e.g. MORR).
  if (!is.null(cfg$subset)) {
    blk <- cfg$subset$blue_line_key
    drm <- cfg$subset$downstream_route_measure
    message("Subsetting to reach upstream of blk ", blk, " @ drm ", drm, " ...")
    aoi <- fresh::frs_watershed_at_measure(conn, blk, drm)
    streams <- sf::st_transform(streams, sf::st_crs(aoi))
    streams <- sf::st_filter(streams, aoi, .predicate = sf::st_intersects)
  } else {
    message("No subset — exporting whole WSG ", aoi_wsg, " network.")
  }

  # Waterbodies (lakes + wetlands) on the accessible order >= min_order network
  wb_keys <- unique(streams$waterbody_key[!is.na(streams$waterbody_key)])
  if (length(wb_keys)) {
    keys_lit <- paste(wb_keys, collapse = ",")
    wb_sql <- sprintf("
      SELECT waterbody_key, 'lake'::text AS waterbody_type, geom
        FROM whse_basemapping.fwa_lakes_poly    WHERE waterbody_key IN (%1$s)
      UNION ALL
      SELECT waterbody_key, 'wetland'::text AS waterbody_type, geom
        FROM whse_basemapping.fwa_wetlands_poly WHERE waterbody_key IN (%1$s)",
      keys_lit)
    waterbodies <- sf::st_read(conn, query = wb_sql, quiet = TRUE) |> sf::st_zm(drop = TRUE)
  } else {
    waterbodies <- streams[0, ]
  }

  message("  streams_co3: ", nrow(streams), " segments | waterbodies_co3: ",
          nrow(waterbodies))

  # --- Save multi-layer aquatic_network.gpkg (02 reads streams_co3 + waterbodies_co3) ---
  out_gpkg <- file.path(out_dir, "aquatic_network.gpkg")
  if (file.exists(out_gpkg)) file.remove(out_gpkg)
  sf::st_write(streams, out_gpkg, layer = "streams_co3", quiet = TRUE)
  if (nrow(waterbodies)) {
    sf::st_write(waterbodies, out_gpkg, layer = "waterbodies_co3",
                 append = TRUE, quiet = TRUE)
  }
  message("Saved: ", basename(out_gpkg))

  invisible(out_gpkg)
}
