#!/usr/bin/env Rscript
#
# inspect_sieve_thresholds.R
#
# One-off helper for choosing the patch-size sieve threshold used in
# 03_lulc_classify.R. Reuses cached classified rasters from
# data/lulc/rasters/co_ff04/, re-runs dft_rast_transition() at multiple
# thresholds, and writes the resulting change-patch vectors as named layers
# into the QGIS floodplain_landcover.gpkg so they can be compared visually
# against the existing unsieved transition layer.
#
# Layer names written:
#   transition_co_ff04_2017_2023_sieve05ha  — patches >= 0.5 ha
#   transition_co_ff04_2017_2023_sieve10ha  — patches >= 1.0 ha
#
# Existing layers (including the unsieved transition_co_ff04_2017_2023)
# are NOT touched. Refresh QGIS to see the new layers.
#
# Once a threshold is chosen, update patch_min_m2 in 03_lulc_classify.R
# and delete the inspection layers from the gpkg if desired.

library(drift)
library(sf)
library(terra)
library(dplyr)

sf::sf_use_s2(FALSE)

out_dir   <- here::here("data", "lulc")
fp_dir    <- file.path(out_dir, "rasters", "co_ff04")
params    <- rmarkdown::yaml_front_matter(here::here("index.Rmd"))$params
qgis_gpkg <- file.path(params$path_gis, "floodplain_landcover.gpkg")

if (!file.exists(qgis_gpkg)) {
  stop("QGIS gpkg not found: ", qgis_gpkg)
}
message("Writing inspection layers into: ", qgis_gpkg)

subbasins <- sf::st_read(file.path(out_dir, "subbasins.gpkg"), quiet = TRUE) |>
  sf::st_transform(4326)

classified <- list(
  "2017" = terra::rast(file.path(fp_dir, "classified_2017.tif")),
  "2023" = terra::rast(file.path(fp_dir, "classified_2023.tif"))
)

thresholds_m2 <- c(`05ha` = 5000, `10ha` = 10000)

summary_rows <- list()

for (lbl in names(thresholds_m2)) {
  thr <- thresholds_m2[[lbl]]
  message("\n=== Threshold: ", thr / 1e4, " ha ===")

  trans <- drift::dft_rast_transition(
    classified, from = "2017", to = "2023",
    patch_area_min = thr
  )
  if (nrow(trans$summary) == 0) {
    message("  No transitions kept — skipping")
    next
  }

  patches <- drift::dft_transition_vectors(
    trans$raster, zones = subbasins, zone_col = "name_basin"
  )
  parts <- strsplit(patches$transition, " -> ", fixed = TRUE)
  patches$from_class <- vapply(parts, `[`, character(1), 1)
  patches$to_class   <- vapply(parts, `[`, character(1), 2)
  patches <- patches[patches$from_class != patches$to_class, ]

  # Recompute area_ha from geometry post-intersection. drift's column is
  # pre-intersection so patches straddling sub-basin boundaries are
  # double-counted when summed. Overwrite with per-slice area.
  patches$area_ha <- as.numeric(sf::st_area(patches)) / 1e4

  lyr <- paste0("transition_co_ff04_2017_2023_sieve", lbl)
  sf::st_write(patches, qgis_gpkg, layer = lyr, append = TRUE,
               delete_layer = TRUE, quiet = TRUE)

  loss <- patches |> sf::st_drop_geometry() |>
    dplyr::filter(from_class == "Trees") |>
    dplyr::pull(area_ha) |> sum()
  gain <- patches |> sf::st_drop_geometry() |>
    dplyr::filter(to_class == "Trees") |>
    dplyr::pull(area_ha) |> sum()

  message(sprintf("  Wrote layer:           %s", lyr))
  message(sprintf("  Patch rows:            %d", nrow(patches)))
  message(sprintf("  Gross Trees -> non-Trees: %6.1f ha", loss))
  message(sprintf("  Gross non-Trees -> Trees: %6.1f ha", gain))
  message(sprintf("  Net decline:              %6.1f ha", loss - gain))

  summary_rows[[lbl]] <- tibble::tibble(
    threshold_ha = thr / 1e4,
    patch_rows   = nrow(patches),
    tree_loss_ha = round(loss, 1),
    tree_gain_ha = round(gain, 1),
    net_decline_ha = round(loss - gain, 1),
    layer        = lyr
  )
}

cat("\n=== Summary across thresholds ===\n")
print(dplyr::bind_rows(summary_rows))
