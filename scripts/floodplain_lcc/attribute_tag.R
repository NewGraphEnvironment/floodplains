# attribute_tag.R — add per-watercourse attribution (and its bridge) to an EXISTING delineation.
#
# `attribute_by` produces two things nothing else does: `<scenario>_by_<key>`, the floodplain split
# one row per watercourse, and `patch_watercourse_<scenario>_<span>`, the bridge that lets change
# patches be summed per river (#40, #54). Both are written mid-pipeline — the attribution in step 2,
# the bridge in step 3 — so an area whose region file lacked `attribute_by` at run time has neither,
# and getting them has meant re-running both steps.
#
# It does not have to. Step 2 already saves the delineation as `floodplain_<scenario>.tif`, and that
# raster plus the stream network is everything `fl_valley_attribute()` needs. Re-running step 2 would
# recompute a VCA we already have — the expensive part — to arrive at the same answer.
#
# So this is the `fire_tag.R` shape: re-derive one product from what is on disk without repeating the
# work that produced it. Cost is the attribution itself (~15 min on a large group) rather than hours.
#
# Writes only NEW layers. The delineation, the transition layer and their numbers are untouched, so
# this cannot move a figure that has already been verified or published.
#
# usage: Rscript scripts/floodplain_lcc/attribute_tag.R <area> [scenario]
#        scenario defaults to the area's primary_scenario.

suppressMessages({library(sf); library(terra); library(yaml); library(readr)})
sf::sf_use_s2(FALSE)
source(here::here("scripts", "fp_gpkg.R")); fp_gpkg_pin_date()   # #45: keep writes deterministic
source(here::here("scripts", "fp_raster.R"))                       # fp_rast_write (the DEM cache's writer)
source(here::here("scripts", "floodplain_lcc", "fp_provenance.R"))  # fp_raster_content_sha256, fp_toolchain
source(here::here("scripts", "floodplain_lcc", "fp_dem.R"))         # fp_dem_cached (#122)
source(here::here("scripts", "floodplain_lcc", "fp_region.R"))      # fp_wsg_subbasin (a subset area's group)
source(here::here("scripts", "floodplain_lcc", "fp_wsg.R"))         # fp_wsg_split (the group line, #53)

a    <- commandArgs(TRUE)
area <- a[1]
if (is.na(area)) stop("usage: Rscript attribute_tag.R <area> [scenario]", call. = FALSE)

cfg_dir <- here::here("config", area)
cfg     <- yaml::read_yaml(file.path(cfg_dir, "area.yml"))
scen_tb <- readr::read_csv(file.path(cfg_dir, "flood_scenarios.csv"), show_col_types = FALSE)
scenario <- if (!is.na(a[2])) a[2] else (cfg$primary_scenario %||% paste0(cfg$species, "_ff04"))
`%||%` <- function(x, y) if (is.null(x)) y else x

key <- cfg$attribute_by
if (is.null(key) || !nzchar(key)) {
  stop("area '", area, "' has no attribute_by. It is region-owned: set it in the region file so the ",
       "output is reproducible, then re-run. An env override would leave these layers unexplainable.",
       call. = FALSE)
}
sc <- scen_tb[scen_tb$scenario_id == scenario, ]
if (nrow(sc) != 1L) stop("scenario '", scenario, "' not found in ", area, "/flood_scenarios.csv",
                         call. = FALSE)

out_dir  <- here::here("data", area)
fp_gpkg  <- file.path(out_dir, "floodplain.gpkg")
lc_gpkg  <- file.path(out_dir, "floodplain_landcover.gpkg")
tif      <- file.path(out_dir, paste0("floodplain_", scenario, ".tif"))
net_gpkg <- file.path(out_dir, "aquatic_network.gpkg")
if (!file.exists(tif)) stop("no saved delineation raster: ", basename(tif),
                            " -- run step 2 for this scenario first.", call. = FALSE)

streams_lyr <- paste0("streams_", sc$species, cfg$min_order)
streams <- sf::st_read(net_gpkg, layer = streams_lyr, quiet = TRUE) |> sf::st_zm(drop = TRUE)
if (!key %in% setdiff(names(streams), attr(streams, "sf_column"))) {
  stop("attribute_by '", key, "' is not a column of ", streams_lyr, call. = FALSE)
}
valleys <- terra::rast(tif)
# The DEM fetched below comes from the installed flooded. A delineation written before flooded 0.7.0
# sits on a grid GDAL chose (~30.4 m, not aligned), while 0.7.0 returns a 30 m grid aligned to
# multiples of 30 (#117, flooded#67). fl_valley_attribute() would stop on the mismatch with a
# message about extents, which points at the wrong cause. Refuse up front, naming the real one.
# Both directions: a pinned delineation tagged with an older flooded mismatches the same way.
pinned_tif <- isTRUE(all.equal(terra::res(valleys), c(30, 30))) &&
  isTRUE(all.equal(c(terra::xmin(valleys), terra::ymin(valleys)) %% 30, c(0, 0)))
pinned_pkg <- utils::packageVersion("flooded") >= "0.7.0"
if (pinned_pkg && !pinned_tif) {
  stop(basename(tif), " is on a pre-0.7.0 DEM grid (res ", paste(signif(terra::res(valleys), 9),
       collapse = " x "), "); flooded ", as.character(utils::packageVersion("flooded")),
       " fetches a different one (#117). Re-run step 2 for '", area, "' first.", call. = FALSE)
}
if (!pinned_pkg && pinned_tif) {
  stop(basename(tif), " is on flooded 0.7.0's pinned DEM grid, and the installed flooded ",
       as.character(utils::packageVersion("flooded")), " fetches a different one (#117). ",
       "Install flooded >= 0.7.0 first.", call. = FALSE)
}
message("Area: ", area, " | scenario: ", scenario, " | key: ", key,
        " | ", length(unique(streams[[key]])), " groups | ", nrow(streams), " segments")

# The DEM must be the one the delineation came from, so it is read the way step 2 read it: through
# step 2's cache (#122), at the buffer step 2 RECORDED for this scenario, and then checked against the
# digest step 2 recorded. That makes "the same DEM" a check rather than a claim. The scenario's
# max_width is NOT the buffer: it equals step 2's 2000 in every table today, but a different value
# would fetch a DEM on another grid, replace step 2's cache, and then stop in fl_valley_attribute()'s
# extent check. Thresholds still come from the scenario ROW, so the attribution matches the
# delineation it describes.
prov_path <- file.path(out_dir, "provenance.json")
rec <- if (file.exists(prov_path)) jsonlite::read_json(prov_path)$floodplain[[scenario]]$inputs
if (is.null(rec$dem_buffer_m) || is.null(rec$dem_content_sha256)) {
  stop("provenance.json has no floodplain[", scenario, "] DEM record (dem_buffer_m, dem_content_sha256) ",
       "for '", area, "'; re-run step 2 for this scenario first.", call. = FALSE)
}
buf <- as.numeric(rec$dem_buffer_m)
message("DEM: MRDEM-30 for the network + ", buf, " m buffer (step 2's) ...")
dem <- fp_dem_cached(streams, buffer = buf, target_crs = sf::st_crs(streams),
                     dir = out_dir, stem = paste0(sc$species, cfg$min_order))
if (!identical(attr(dem, "fp_dem_cache")$dem_content_sha256, rec$dem_content_sha256)) {
  stop("the DEM read now (", attr(dem, "fp_dem_cache")$dem_content_sha256, ") is not the one ", scenario,
       " was delineated from (", rec$dem_content_sha256, "): the source, the toolchain or the network ",
       "has moved since step 2. Re-run step 2 for '", area, "' first.", call. = FALSE)
}

message("Attributing ", scenario, " by '", key, "' ...")
attributed <- flooded::fl_valley_attribute(
  valleys, streams, group = key, dem = dem,
  max_width = sc$max_width, cost_threshold = sc$cost_threshold)
attributed$wsg <- cfg$watershed_group; attributed$species <- sc$species
attributed$scenario <- scenario

# Carried label (#48): grouping on an opaque key is complete but unreadable in the field. Attach the
# name when the key maps cleanly to one; refuse rather than mislabel when it does not.
label_col <- "gnis_name"
if (!identical(key, label_col) && label_col %in% names(streams)) {
  lut <- unique(sf::st_drop_geometry(streams)[, c(key, label_col)])
  lut <- lut[!is.na(lut[[label_col]]), , drop = FALSE]
  n_per <- tapply(lut[[label_col]], lut[[key]], function(x) length(unique(x)))
  if (any(n_per > 1)) {
    message("  Label: skipped -- ", sum(n_per > 1), " key(s) carry more than one ", label_col)
  } else {
    lut <- lut[!duplicated(lut[[key]]), , drop = FALSE]
    attributed[[label_col]] <- lut[[label_col]][match(attributed[[key]], lut[[key]])]
    message("  Label: ", sum(!is.na(attributed[[label_col]])), " of ", nrow(attributed),
            " groups carry a ", label_col)
  }
}
attr_lyr <- paste0(scenario, "_by_", key)
# Split at the group line, as step 2 splits it (#53): the same layer from either writer.
attributed <- fp_wsg_split(attributed, fp_wsg_polygon(list(watershed_group = cfg$watershed_group,
                                                           dir_out = out_dir)))
sf::st_write(attributed, fp_gpkg, layer = attr_lyr,
             append = file.exists(fp_gpkg), delete_layer = TRUE, quiet = TRUE)
fb <- attr(attributed, "fl_fallback_cells")
message("  Wrote ", attr_lyr, " (", nrow(attributed), " groups",
        if (!is.null(fb)) paste0("; ", fb, " fallback cells") else "", ")")

# --- Bridge (#54), from the transition layer already on disk ---
t_lyr <- if (file.exists(lc_gpkg))
  grep(paste0("^transition_", scenario, "_[0-9]{4}_[0-9]{4}$"),
       sf::st_layers(lc_gpkg)$name, value = TRUE) else character(0)
if (!length(t_lyr)) {
  message("  No transition layer for ", scenario, " -- bridge skipped (run step 3 to create it).")
} else {
  tp  <- sf::st_read(lc_gpkg, layer = t_lyr[1], quiet = TRUE)
  # patch_id is per-SUB-BASIN, not global (see 03_lulc_classify.R). Key on the pair.
  pat <- tp[, c("patch_id", "name_basin", "area_ha")]
  wc  <- attributed[, key]
  if (sf::st_crs(wc) != sf::st_crs(pat)) wc <- sf::st_transform(wc, sf::st_crs(pat))
  inter <- suppressWarnings(sf::st_intersection(pat, wc))
  ov <- as.numeric(sf::st_area(inter)) / 1e4
  bridge <- data.frame(patch_id = inter$patch_id, name_basin = inter$name_basin, k = inter[[key]],
                       overlap_ha = round(ov, 4),
                       overlap_frac = round(pmin(1, ov / inter$area_ha), 4),
                       wsg = cfg$watershed_group, species = sc$species, scenario = scenario,
                       stringsAsFactors = FALSE)
  names(bridge)[names(bridge) == "k"] <- key
  bridge <- bridge[bridge$overlap_ha > 0, , drop = FALSE]
  # Only apportion_weight is additive -- overlap_frac sums past 1 because the rows overlap (#54).
  pk <- paste(bridge$name_basin, bridge$patch_id, sep = "\u00a6")
  tot <- tapply(bridge$overlap_ha, pk, sum)
  bridge$apportion_weight <- round(bridge$overlap_ha / tot[pk], 4)
  b_lyr <- sub("^transition_", "patch_watercourse_", t_lyr[1])
  sf::st_write(bridge, lc_gpkg, layer = b_lyr,
               append = file.exists(lc_gpkg), delete_layer = TRUE, quiet = TRUE)
  u <- tapply(bridge$overlap_frac, pk, max)
  message("  Wrote ", b_lyr, " (", nrow(bridge), " pairs; union coverage ",
          sprintf("%.3f", mean(u)), ")")
}
message("Done: ", area, "/", scenario, " -- delineation and transition layers untouched.")
