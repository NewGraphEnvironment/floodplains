#!/usr/bin/env Rscript
#
# prioritization_score.R
#
# Build area-level and project-level prioritization CSVs from sub-basin
# polygons, LULC outputs, fish habitat (DB), land ownership, reserves,
# and cultural sites.
#
# Sources:
#   - Sub-basins: data/lulc/subbasins.gpkg (from fwa_extract_flood.R)
#     — carries name_basin, description, fisheries_value from break_points.csv
#   - LULC: data/lulc/lulc_summary.rds (from lulc_classify.R)
#   - Fish habitat: bcfishpass streams_co_vw + streams_ch_vw (DB via fresh)
#   - Land ownership: background_layers.gpkg (pmbc parcels ∩ floodplain)
#   - Reserves: background_layers.gpkg (clab_indian_reserves ∩ sub-basins)
#   - Cultural sites: trad_fish_sites_gottesfeld_rabnett2007.gpkg ∩ sub-basins
#   - Sites: data/gis/sites_prioritized.geojson (from prioritize.R)
#
# Requires:
#   - SSH tunnel: ssh -L 63333:<db_host>:5432 <ssh_host>
#   - R packages: fresh, sf, readr, dplyr, purrr, tidyr
#
# Outputs:
#   data/prioritization/area_scores.csv    — sub-basin level metrics
#   data/prioritization/project_scores.csv — site/project level scaffold
#
# Relates to #125, #135

library(sf)
library(dplyr)
library(readr)
library(fresh)

sf_use_s2(FALSE)

# --- DB connection (fwapg via standard libpq env vars; local fwapg for portable builds) ---
conn <- DBI::dbConnect(RPostgres::Postgres())

# --- Paths ---
out_dir <- here::here("data", "prioritization")
lulc_dir <- here::here("data", "lulc")
gis_dir <- "/Users/airvine/Projects/gis/restoration_wedzin_kwa"
cultural_sites_path <- "/Users/airvine/Library/CloudStorage/OneDrive-Personal/Projects/gis/data_secure/wetsuweten_treaty_society/trad_fish_sites_gottesfeld_rabnett2007FishPassage.gpkg"

# =============================================================================
# Part 1: Area scores
# =============================================================================

# --- Load sub-basins and floodplain ---
message("Loading sub-basins and floodplain...")
subbasins <- sf::st_read(file.path(lulc_dir, "subbasins.gpkg"), quiet = TRUE) |>
  sf::st_transform(3005)

fp_file <- file.path(lulc_dir, "floodplain.gpkg")
floodplain <- sf::st_read(fp_file, layer = "co_ff04", quiet = TRUE) |>
  sf::st_transform(sf::st_crs(subbasins))

# --- Floodplain area per sub-basin ---
fp_areas <- subbasins |>
  dplyr::mutate(
    fp_geom = purrr::map(
      seq_len(dplyr::n()),
      ~ {
        clip <- sf::st_intersection(floodplain, subbasins[.x, ])
        if (nrow(clip) == 0) return(sf::st_sfc(sf::st_polygon(), crs = sf::st_crs(subbasins)))
        sf::st_union(clip)
      }
    ),
    floodplain_area_ha = purrr::map_dbl(fp_geom, ~ as.numeric(sf::st_area(.x)) / 10000)
  ) |>
  sf::st_drop_geometry() |>
  dplyr::select(name_basin, description, fisheries_value, falls_downstream, area_km2, floodplain_area_ha)

# --- LULC change ---
# Per-class 2017/2023 areas (composition snapshot) come from lulc_summary.rds.
# Net tree_loss_ha and ag_change_ha derive from the sieved transition vector
# (patches >= 1 ha) so they match the headline figures in the report.
# 0400-results.Rmd and 2043-Appendix-lulc.Rmd also recompute these values
# inline against the same source; values written here should agree.
lulc <- readRDS(file.path(lulc_dir, "lulc_summary.rds"))
ag_classes <- c("Crops", "Rangeland", "Bare Ground")

# Class-area snapshot (kept for context columns in area_scores.csv)
trees_snapshot <- lulc |>
  dplyr::filter(class_name == "Trees", year %in% c(2017, 2023)) |>
  dplyr::select(name_basin, year, area) |>
  tidyr::pivot_wider(names_from = year, values_from = area, names_prefix = "trees_ha_")

ag_snapshot <- lulc |>
  dplyr::filter(class_name %in% ag_classes, year %in% c(2017, 2023)) |>
  dplyr::group_by(name_basin, year) |>
  dplyr::summarise(ag_area = sum(area), .groups = "drop") |>
  tidyr::pivot_wider(names_from = year, values_from = ag_area, names_prefix = "ag_ha_")

# Sieved change-patch totals per sub-basin (matches the gpkg layer in QGIS).
trans_v <- sf::st_read(
  file.path(lulc_dir, "floodplain_landcover.gpkg"),
  layer = "transition_co_ff04_2017_2023", quiet = TRUE
) |> sf::st_drop_geometry()

sieved_delta <- trans_v |>
  dplyr::group_by(name_basin) |>
  dplyr::summarise(
    tree_loss_ha = sum(area_ha[to_class   == "Trees"]) -
                   sum(area_ha[from_class == "Trees"]),
    ag_change_ha = sum(area_ha[to_class   %in% ag_classes]) -
                   sum(area_ha[from_class %in% ag_classes]),
    .groups = "drop"
  )

tree_change <- trees_snapshot |>
  dplyr::left_join(sieved_delta |> dplyr::select(name_basin, tree_loss_ha), by = "name_basin") |>
  dplyr::mutate(tree_loss_pct = round(tree_loss_ha / trees_ha_2017 * 100, 1))

ag_change <- ag_snapshot |>
  dplyr::left_join(sieved_delta |> dplyr::select(name_basin, ag_change_ha), by = "name_basin") |>
  dplyr::mutate(ag_change_pct = round(ag_change_ha / ag_ha_2017 * 100, 1))

# --- Fish habitat from DB (coho + chinook) ---
blk <- 360873822
drm <- 166030.4

message("Querying coho habitat streams from DB...")
co_result <- frs_network(
  conn,
  blue_line_key = blk,
  downstream_route_measure = drm,
  tables = list(
    streams = list(
      table = "bcfishpass.streams_co_vw",
      cols = c("segmented_stream_id", "stream_order", "spawning", "rearing", "access", "geom"),
      wscode_col = "wscode",
      localcode_col = "localcode"
    )
  )
)
co_streams <- if (inherits(co_result, "sf")) co_result else co_result$streams
co_streams <- sf::st_zm(co_streams, drop = TRUE)

message("Querying chinook habitat streams from DB...")
ch_result <- frs_network(
  conn,
  blue_line_key = blk,
  downstream_route_measure = drm,
  tables = list(
    streams = list(
      table = "bcfishpass.streams_ch_vw",
      cols = c("segmented_stream_id", "stream_order", "spawning", "rearing", "access", "geom"),
      wscode_col = "wscode",
      localcode_col = "localcode"
    )
  )
)
ch_streams <- if (inherits(ch_result, "sf")) ch_result else ch_result$streams
ch_streams <- sf::st_zm(ch_streams, drop = TRUE)

co_streams$length_m <- as.numeric(sf::st_length(co_streams))
ch_streams$length_m <- as.numeric(sf::st_length(ch_streams))

message("Joining streams to sub-basins...")
co_joined <- sf::st_join(co_streams, subbasins["name_basin"], largest = TRUE)
ch_joined <- sf::st_join(ch_streams, subbasins["name_basin"], largest = TRUE)

co_hab <- co_joined |>
  sf::st_drop_geometry() |>
  dplyr::group_by(name_basin) |>
  dplyr::summarize(
    co_total_km = round(sum(length_m) / 1000, 1),
    co_spawn_km = round(sum(length_m[spawning == 1]) / 1000, 1),
    co_rear_km  = round(sum(length_m[rearing == 1]) / 1000, 1),
    .groups = "drop"
  )

ch_hab <- ch_joined |>
  sf::st_drop_geometry() |>
  dplyr::group_by(name_basin) |>
  dplyr::summarize(
    ch_total_km = round(sum(length_m) / 1000, 1),
    ch_spawn_km = round(sum(length_m[spawning == 1]) / 1000, 1),
    ch_rear_km  = round(sum(length_m[rearing == 1]) / 1000, 1),
    .groups = "drop"
  )

message("  Coho: ", nrow(co_hab), " sub-basins with habitat")
message("  Chinook: ", nrow(ch_hab), " sub-basins with habitat")

# --- Land ownership within floodplain per sub-basin ---
message("Loading parcels from GIS project...")
parcels <- sf::st_read(
  file.path(gis_dir, "background_layers.gpkg"),
  layer = "whse_cadastre.pmbc_parcel_fabric_poly_svw",
  quiet = TRUE
) |> sf::st_make_valid()

message("Intersecting parcels with floodplain...")
fp_parcels <- sf::st_intersection(parcels, sf::st_union(floodplain)) |>
  sf::st_make_valid()

fp_parcels_by_basin <- sf::st_join(fp_parcels, subbasins["name_basin"], largest = TRUE)
fp_parcels_by_basin$area_ha <- as.numeric(sf::st_area(fp_parcels_by_basin)) / 1e4

ownership <- fp_parcels_by_basin |>
  sf::st_drop_geometry() |>
  dplyr::group_by(name_basin) |>
  dplyr::summarize(
    fp_private_ha = round(sum(area_ha[owner_type == "Private"], na.rm = TRUE), 1),
    fp_crown_ha   = round(sum(area_ha[owner_type %in% c("Crown Provincial", "Untitled Provincial", "Crown Agency", "Local Government", "Federal", "Unclassified")], na.rm = TRUE), 1),
    fp_other_ha   = round(sum(area_ha[!owner_type %in% c("Private", "Crown Provincial", "Untitled Provincial", "Crown Agency", "Local Government", "Federal", "Unclassified")], na.rm = TRUE), 1),
    .groups = "drop"
  )

message("  Ownership: ", nrow(ownership), " sub-basins")

# --- Reserves ---
message("Loading reserves...")
reserves <- sf::st_read(
  file.path(gis_dir, "background_layers.gpkg"),
  layer = "whse_admin_boundaries.clab_indian_reserves",
  quiet = TRUE
) |> sf::st_make_valid()

reserves_by_basin <- sf::st_join(reserves, subbasins["name_basin"], largest = TRUE)
reserves_by_basin$area_ha <- as.numeric(sf::st_area(reserves_by_basin)) / 1e4

reserve_summary <- reserves_by_basin |>
  sf::st_drop_geometry() |>
  dplyr::group_by(name_basin) |>
  dplyr::summarize(
    reserve_area_ha = round(sum(area_ha, na.rm = TRUE), 1),
    n_reserves = dplyr::n(),
    .groups = "drop"
  )

message("  Reserves: ", sum(reserve_summary$n_reserves), " in ", nrow(reserve_summary), " sub-basins")

# --- Cultural sites ---
message("Loading cultural sites...")
cultural <- sf::st_read(cultural_sites_path, quiet = TRUE)

cultural_by_basin <- sf::st_join(cultural, subbasins["name_basin"])

cultural_summary <- cultural_by_basin |>
  sf::st_drop_geometry() |>
  dplyr::group_by(name_basin) |>
  dplyr::summarize(
    n_cultural_sites = dplyr::n(),
    .groups = "drop"
  )

message("  Cultural sites: ", sum(cultural_summary$n_cultural_sites), " in ", nrow(cultural_summary), " sub-basins")

# --- Assemble area_scores ---
message("Assembling area_scores...")
area_scores <- fp_areas |>
  dplyr::left_join(tree_change, by = "name_basin") |>
  dplyr::left_join(ag_change, by = "name_basin") |>
  dplyr::left_join(co_hab, by = "name_basin") |>
  dplyr::left_join(ch_hab, by = "name_basin") |>
  dplyr::left_join(ownership, by = "name_basin") |>
  dplyr::left_join(reserve_summary, by = "name_basin") |>
  dplyr::left_join(cultural_summary, by = "name_basin")

# Fill NA with 0 for numeric columns
fill_cols <- c(
  "co_total_km", "co_spawn_km", "co_rear_km",
  "ch_total_km", "ch_spawn_km", "ch_rear_km",
  "fp_private_ha", "fp_crown_ha", "fp_other_ha",
  "reserve_area_ha", "n_reserves", "n_cultural_sites"
)
area_scores <- area_scores |>
  dplyr::mutate(dplyr::across(dplyr::any_of(fill_cols), ~ tidyr::replace_na(.x, 0)))

readr::write_csv(area_scores, file.path(out_dir, "area_scores.csv"))
message("\nWrote: data/prioritization/area_scores.csv")
message("Columns: ", paste(names(area_scores), collapse = ", "))

# =============================================================================
# Part 2: Project scores from prioritized sites
# =============================================================================

# --- Load GIS-scored sites ---
sites <- sf::st_read(
  here::here("data", "gis", "sites_prioritized.geojson"), quiet = TRUE
)

# --- Assign sub-basin to each site via spatial join ---
sites_sb <- sf::st_transform(sites, sf::st_crs(subbasins)) |>
  sf::st_join(
    subbasins |> dplyr::select(name_basin),
    join = sf::st_within,
    left = TRUE
  )

# --- Build project scaffold ---
project_scores <- sites_sb |>
  sf::st_drop_geometry() |>
  dplyr::select(
    idx, site_id, site_name_proposed, source, name_basin,
    lon, lat,
    total_score,
    bulkley_falls_downstream, floodplain_ind, owner_type,
    dplyr::any_of(c("name_wet_house", "house", "clan", "clan_english", "chiefs")),
    dplyr::starts_with("model_spawning"),
    dplyr::starts_with("model_rearing")
  ) |>
  dplyr::mutate(
    gate_diagnostic_certainty = NA,
    gate_active_degradation_clear = NA,
    gate_access_willingness = NA,
    project_type = NA_character_,
    watershed_function_gain = NA_integer_,
    root_cause_alignment = NA_integer_,
    scale_of_benefit_ha = NA_real_,
    fish_habitat_connectivity = NA_integer_,
    probability_of_success = NA_integer_,
    cultural_significance = NA_integer_,
    collective_wellbeing = NA_integer_,
    passive_first_bonus = NA_integer_,
    delivery_bucket = NA_integer_,
    framework_score = NA_integer_,
    notes = NA_character_
  )

readr::write_csv(project_scores, file.path(out_dir, "project_scores.csv"))
message("Wrote: data/prioritization/project_scores.csv")

message("\nDone. ", nrow(area_scores), " sub-basins, ", nrow(project_scores), " sites")

DBI::dbDisconnect(conn)
