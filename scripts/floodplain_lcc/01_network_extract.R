#!/usr/bin/env Rscript
#
# 01_network_extract.R
#
# Build the coho habitat network for the Neexdzii Kwa study area using the
# `link` package (a config-driven pipeline that orchestrates `fresh` over a
# fwapg PostgreSQL database). Produces data/lulc/aquatic_network.gpkg with:
#   streams_co3      coho-accessible streams, order >= 3 (input to 02)
#   waterbodies_co3  lakes/wetlands on the accessible order 3+ network
#
# `link` is watershed-group scoped, so we run the BULK (Bulkley) group that
# contains Neexdzii, persist into a DEDICATED `neexdzii` schema (never the
# shared province-wide `fresh.*`), then subset the Neexdzii reach (upstream of
# the Wedzin Kwa confluence) for export.
#
# Requires:
#   - fwapg database (local fwapg via standard libpq env vars; see scripts/README.md)
#   - link >= 0.44.0 (access-segmentation over-credit fix -- streams break at every
#     gradient+falls frontier, matching bcfishpass; link#223/#228. Prior 0.43.x
#     over-credited reaches above gradient>15% barriers as coho-accessible.)
#
# Relates to #148
#
# Usage:
#   Rscript scripts/floodplain_lcc/01_network_extract.R

library(link)
library(sf)
sf_use_s2(FALSE)

# Local fwapg via standard libpq env vars (PGHOST/PGPORT/PGDATABASE/PGUSER/
# PGPASSWORD). NOT lnk_db_conn() -- that prefers the remote PG_*_SHARE profile;
# we want the local DB. See scripts/README.md "Prerequisite -- fwapg database".
conn <- DBI::dbConnect(RPostgres::Postgres())

# Study area: Neexdzii = upstream of the Bulkley / Wedzin Kwa confluence.
blk <- 360873822
drm_confluence <- 166030.4
min_order <- 3          # minimum stream order for the floodplain input network

out_dir <- here::here("data", "lulc")
fs::dir_create(out_dir)

aoi_wsg <- "BULK"       # watershed group containing Neexdzii
schema  <- "neexdzii"   # dedicated schema -- do NOT clobber shared fresh.*

# --- Run the link habitat pipeline for the BULK watershed group ---
# Use the `default` config (NewGraph methodology), NOT `bcfishpass`. They differ
# in the natural-barrier set: bcfishpass opts in `subsurfaceflow` for parity,
# whereas the default bundle leaves it OFF (config.yaml: "NewGraph methodology
# decision"). Default => natural access barriers = gradient + falls only, which
# matches the historical 01 accessibility definition. Persist into the dedicated
# `neexdzii` schema by overriding cfg$pipeline$schema (shared fresh.* untouched).
#
# dams = TRUE is the documented default (conn_tunnel = conn loads the LOCAL
# cabd.dams, link#137, no real tunnel). mapping_code = FALSE: we don't need the
# token strings; as of link#218 (v0.43.0) `streams_access` (access_co) is built
# regardless. access_co is NATURAL-barrier accessibility (dams/anthropogenic are
# excluded from access since link#200) = potential-habitat reachability.
message("Loading link config + overrides...")
cfg <- lnk_config("default")
cfg$pipeline$schema <- schema
loaded <- lnk_load_overrides(cfg)

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
lnk_pipeline_run(conn, aoi = aoi_wsg, cfg = cfg, loaded = loaded,
                 dams = TRUE, mapping_code = FALSE)

message("Pipeline complete (schema ", schema, ").")

# --- Export the coho-accessible network for the Neexdzii reach ---
# link runs the whole BULK watershed group; Neexdzii is upstream of the Wedzin Kwa
# confluence, so we subset spatially to that watershed here.
message("Delineating Neexdzii AOI (upstream of confluence)...")
aoi <- fresh::frs_watershed_at_measure(conn, blk, drm_confluence)

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

# Subset to the Neexdzii reach
streams <- sf::st_transform(streams, sf::st_crs(aoi))
streams <- sf::st_filter(streams, aoi, .predicate = sf::st_intersects)

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

# --- Copy to QGIS project for field/team use (gated on update_gis) ---
params <- rmarkdown::yaml_front_matter(here::here("index.Rmd"))$params
if (isTRUE(params$update_gis) && dir.exists(params$path_gis)) {
  file.copy(out_gpkg, file.path(params$path_gis, "aquatic_network.gpkg"),
            overwrite = TRUE)
  message("Copied to QGIS project: ", params$path_gis)
}

DBI::dbDisconnect(conn)
message("Done.")
