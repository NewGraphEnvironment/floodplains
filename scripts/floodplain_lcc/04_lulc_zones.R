#!/usr/bin/env Rscript
#
# lulc_classify_zones.R
#
# SKETCH — Zone-stratified land cover classification.
# Extends lulc_classify.R to run drift within each nested flood zone
# (from VCA scenarios in #123) per sub-basin reach.
#
# Inputs:
#   data/lulc/subbasins.gpkg                — sub-basin polygons (from watershed picker)
#   data/lulc/floodplain_scenarios.gpkg     — nested flood zone polygons (from VCA runs)
#     layers: zone_ff02, zone_ff04, zone_ff06, zone_ff12
#   data/floodplain_scenarios.csv           — scenario definitions (from #123)
#
# Outputs:
#   data/lulc/lulc_summary_zones.rds        — reach × zone × year × class → area
#   data/lulc/rasters/zones/                — classified tifs per zone (optional)
#
# The zone polygons are nested (ff02 ⊂ ff04 ⊂ ff06 ⊂ ff12). For LULC analysis
# we want the *annular rings* between zones, not the cumulative polygons, so that
# each pixel is counted once:
#   bankfull_margin = ff02 (the channel itself)
#   rearing         = ff04 - ff02 (off-channel zone only)
#   functional      = ff06 - ff04 (floodplain beyond rearing)
#   migration       = ff12 - ff06 (outer migration zone only)
#
# Relates to #123, #125

library(drift)
library(sf)
library(terra)
library(dplyr)
library(readr)

sf::sf_use_s2(FALSE)
terra::terraOptions(threads = 12)

out_dir <- here::here("data", "lulc")
years <- c(2017, 2020, 2023)

# --- Load inputs ---
subbasins <- sf::st_read(
  file.path(out_dir, "subbasins.gpkg"), quiet = TRUE
) |> sf::st_transform(4326)

# Scenario definitions — which flood_factor levels to analyze
# TODO: read from data/floodplain_scenarios.csv once #123 Phase 2 complete
scenarios <- tibble::tribble(
  ~zone_id,           ~flood_factor, ~layer_name,  ~ecological_process,
  "bankfull_margin",  2,             "zone_ff02",  "Active channel / riparian margin",
  "rearing",          4,             "zone_ff04",  "Off-channel rearing habitat",
  "functional",       6,             "zone_ff06",  "Functional floodplain",
  "migration",        12,            "zone_ff12",  "Channel migration zone"
)

# --- Load zone polygons ---
# These come from VCA runs at each flood_factor (fwa_extract_flood.R)
# TODO: replace with multi-layer GeoPackage once VCA scenarios are run
zones_path <- file.path(out_dir, "floodplain_scenarios.gpkg")

if (!file.exists(zones_path)) {
  message("floodplain_scenarios.gpkg not found — falling back to ff06 only")
  zone_polys <- list(
    zone_ff06 = sf::st_read(
      file.path(out_dir, "floodplain_co_ff04.gpkg"), quiet = TRUE
    ) |> sf::st_transform(4326)
  )
  # Filter scenarios to just what we have
  scenarios <- scenarios |> dplyr::filter(layer_name %in% names(zone_polys))
} else {
  zone_polys <- purrr::set_names(scenarios$layer_name) |>
    purrr::map(~ sf::st_read(zones_path, layer = .x, quiet = TRUE) |>
                 sf::st_transform(4326))
}

# --- Build annular rings (difference between nested zones) ---
# Each pixel should be counted once: rearing = ff04 - ff02, etc.
build_rings <- function(zone_polys, scenarios) {
  rings <- list()
  ordered <- scenarios |> dplyr::arrange(flood_factor)

  for (i in seq_len(nrow(ordered))) {
    layer <- ordered$layer_name[i]
    zone_id <- ordered$zone_id[i]

    if (i == 1 || !(ordered$layer_name[i - 1] %in% names(zone_polys))) {
      # Innermost zone or previous zone not available — use full polygon
      rings[[zone_id]] <- zone_polys[[layer]]
    } else {
      # Subtract inner zone to get the ring
      inner_layer <- ordered$layer_name[i - 1]
      rings[[zone_id]] <- sf::st_difference(
        sf::st_union(zone_polys[[layer]]),
        sf::st_union(zone_polys[[inner_layer]])
      ) |> sf::st_sf(geometry = _)
      sf::st_crs(rings[[zone_id]]) <- sf::st_crs(zone_polys[[layer]])
    }
    message("Ring: ", zone_id, " — ",
            round(as.numeric(sf::st_area(sf::st_union(rings[[zone_id]]))) / 1e6, 1), " km2")
  }
  rings
}

rings <- build_rings(zone_polys, scenarios)

# --- Pass: Sub-basin × Zone summaries ---
message("\n=== Zone-stratified sub-basin summaries ===")
results <- list()

for (i in seq_len(nrow(subbasins))) {
  sb <- subbasins[i, ]
  reach <- sb$name_basin

  for (zone_id in names(rings)) {
    zone_ring <- rings[[zone_id]]

    # Clip zone ring to sub-basin
    clip <- tryCatch(
      sf::st_intersection(zone_ring, sb) |>
        sf::st_collection_extract("POLYGON") |>
        sf::st_union() |>
        sf::st_sf(geometry = _),
      error = function(e) NULL
    )

    if (is.null(clip) || nrow(clip) == 0) next
    sf::st_crs(clip) <- sf::st_crs(zone_ring)

    area_m2 <- as.numeric(sf::st_area(clip))
    if (area_m2 < 1e4) next  # skip tiny slivers

    message("  ", reach, " × ", zone_id, " (",
            round(area_m2 / 1e4, 1), " ha)")

    rasters <- dft_stac_fetch(clip, source = "io-lulc", years = years)
    classified <- dft_rast_classify(rasters, source = "io-lulc")
    summary <- dft_rast_summarize(classified, unit = "ha")
    summary$name_basin <- reach
    summary$zone <- zone_id
    summary$zone_area_ha <- round(area_m2 / 1e4, 1)

    results[[length(results) + 1]] <- summary
  }
}

# --- Save ---
lulc_zones <- dplyr::bind_rows(results)
saveRDS(lulc_zones, file.path(out_dir, "lulc_summary_zones.rds"))
message("\nWrote ", file.path(out_dir, "lulc_summary_zones.rds"))
message("  ", length(unique(lulc_zones$name_basin)), " reaches × ",
        length(unique(lulc_zones$zone)), " zones × ",
        length(years), " years")

# --- Quick summary: tree loss per reach × zone ---
tree_loss <- lulc_zones |>
  dplyr::filter(class_name == "Trees", year %in% c(2017, 2023)) |>
  dplyr::select(name_basin, zone, year, area) |>
  tidyr::pivot_wider(names_from = year, values_from = area, names_prefix = "trees_") |>
  dplyr::mutate(
    loss_ha = trees_2023 - trees_2017,
    loss_pct = round(loss_ha / trees_2017 * 100, 1)
  ) |>
  dplyr::arrange(zone, loss_pct)

message("\n=== Tree loss by reach × zone ===")
print(tree_loss, n = 50)

message("\nDone.")
