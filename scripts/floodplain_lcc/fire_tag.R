# fire_tag.R — ONE-OFF (prototype for floodplains#19 disturbance attribution).
# Tag each floodplain LULC transition patch with whether it falls inside a 2017-2023 fire
# perimeter, and stamp the dominant overlapping fire's year + number. Writes a new
# `transition_<scenario>_2017_2023_fire` layer alongside the original (original untouched).
#
# WHY 2017-2023: LULC change is measured 2017->2023 (io-lulc-annual-v02 ends at 2023), so only a
# fire inside that window can EXPLAIN an observed Trees->non-Trees loss. Later perimeters are noise.
#
# usage: Rscript scripts/floodplain_lcc/fire_tag.R <area> [scenario]
#   <area>     e.g. bulk         (reads data/<area>/floodplain_landcover.gpkg)
#   [scenario] e.g. co_ff04      (default: first transition_* layer found)

suppressMessages({library(sf); library(DBI); library(RPostgres); library(dplyr)})
sf::sf_use_s2(FALSE)

a    <- commandArgs(TRUE)
area <- a[1]
if (is.na(area)) stop("usage: Rscript fire_tag.R <area> [scenario]")

gpkg <- sprintf("data/%s/floodplain_landcover.gpkg", area)
if (!file.exists(gpkg)) stop("no gpkg: ", gpkg)

lyrs <- sf::st_layers(gpkg)$name
tlyr <- if (!is.na(a[2])) {
  grep(sprintf("^transition_%s_", a[2]), lyrs, value = TRUE)[1]
} else {
  grep("^transition_", lyrs, value = TRUE)[1]
}
if (is.na(tlyr)) stop("no transition_ layer in ", gpkg)
cat(sprintf("area=%s  layer=%s\n", area, tlyr))

tr    <- sf::st_read(gpkg, layer = tlyr, quiet = TRUE) |> sf::st_make_valid()
crs_t <- sf::st_crs(tr)

# --- fire perimeters that could explain a 2017->2023 change ---------------------------------
conn <- dbConnect(Postgres())
on.exit(dbDisconnect(conn), add = TRUE)
fire <- sf::st_read(conn, query = "
  SELECT fire_year, fire_number, geom
  FROM whse_land_and_natural_resource.prot_historical_fire_polys_sp
  WHERE fire_year BETWEEN 2017 AND 2023", quiet = TRUE) |>
  sf::st_transform(crs_t) |> sf::st_make_valid()
cat(sprintf("fire perimeters (2017-2023, province): %d\n", nrow(fire)))

# --- boolean in_fire for every patch --------------------------------------------------------
hit <- sf::st_intersects(tr, fire)
tr$in_fire <- lengths(hit) > 0

# --- dominant overlapping fire (largest intersection area) -> year + number -----------------
tr$fire_year   <- NA_integer_
tr$fire_number <- NA_character_
burn_idx <- which(tr$in_fire)
if (length(burn_idx)) {
  inter <- suppressWarnings(sf::st_intersection(tr[burn_idx, c("patch_id")], fire))
  if (nrow(inter)) {
    inter$ov <- as.numeric(sf::st_area(inter))
    dom <- sf::st_drop_geometry(inter) |>
      dplyr::group_by(patch_id) |>
      dplyr::slice_max(ov, n = 1, with_ties = FALSE) |>
      dplyr::ungroup()
    m <- match(tr$patch_id, dom$patch_id)
    tr$fire_year[!is.na(m)]   <- dom$fire_year[m[!is.na(m)]]
    tr$fire_number[!is.na(m)] <- dom$fire_number[m[!is.na(m)]]
  }
}

# --- write tagged layer alongside original --------------------------------------------------
out_lyr <- paste0(tlyr, "_fire")
sf::st_write(tr, gpkg, layer = out_lyr, delete_layer = TRUE, quiet = TRUE)
cat(sprintf("wrote layer: %s (%d patches)\n", out_lyr, nrow(tr)))

# --- report: tree LOSS split by fire --------------------------------------------------------
loss <- tr[tr$from_class == "Trees" & tr$to_class != "Trees", ]
loss_total <- sum(loss$area_ha)
loss_fire  <- sum(loss$area_ha[loss$in_fire])
cat(sprintf("\n=== %s Trees->non-Trees LOSS vs fire (2017-2023) ===\n", toupper(area)))
cat(sprintf(" total loss            : %.1f ha\n", loss_total))
cat(sprintf(" inside a fire         : %.1f ha (%.0f%%)\n", loss_fire, 100*loss_fire/loss_total))
cat(sprintf(" outside (harvest/noise): %.1f ha (%.0f%%)\n",
            loss_total-loss_fire, 100*(loss_total-loss_fire)/loss_total))
brk <- sf::st_drop_geometry(loss) |>
  dplyr::group_by(to_class, in_fire) |>
  dplyr::summarise(ha = round(sum(area_ha),1), n = dplyr::n(), .groups="drop") |>
  dplyr::arrange(desc(ha))
cat("\n by to_class (patch-level fire overlap):\n"); print(as.data.frame(brk), row.names=FALSE)
