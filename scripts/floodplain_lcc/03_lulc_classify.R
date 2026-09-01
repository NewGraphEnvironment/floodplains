#!/usr/bin/env Rscript
#
# 03_lulc_classify.R  —  defines fp_lulc(cfg, scenario = cfg$primary_scenario)
#
# Land cover classification and transition detection for the modelled floodplain.
# Two passes:
#   1. Whole-floodplain: classify + transition for interactive map
#   2. Per-sub-basin: summarize for tables/plots
#
# `scenario` selects the floodplain AOI (a layer in floodplain.gpkg). Defaults to
# cfg$primary_scenario (co_ff04, the functional floodplain).
#
# Consumes subbasins.gpkg + floodplain.gpkg (from step 2). Runs the drift pipeline:
# fetch, classify, summarize, transition.
#
# Outputs (data/<area>/):
#   floodplain_landcover.gpkg       -- classified_{scenario}_{year} + transition layer
#   lulc_summary_{scenario_id}.rds  -- area/pct by class, sub-basin, year
#   lulc_summary.rds                -- copy of active scenario (report reads this)
#   rasters/{scenario_id}/          -- classified + transition tifs
#
# Called by scripts/run_area.R (step 3). cfg comes from fp_read_config().

fp_lulc <- function(cfg, scenario = cfg$primary_scenario) {
  library(drift)
  library(sf)
  library(terra)
  library(dplyr)

  # fp_lulc passes tile_size to dft_stac_fetch unconditionally (NULL = off), a param that
  # only exists in drift >= 0.6.0 — on an older drift the call errors with "unused argument"
  # for EVERY area, tiled or not. update_packages defaults FALSE, so guard loudly here.
  if (utils::packageVersion("drift") < "0.6.0") {
    stop("fp_lulc requires drift >= 0.6.0 (dft_stac_fetch tile_size); installed ",
         as.character(utils::packageVersion("drift")),
         ". Update: pak::pak('newgraphenvironment/drift')", call. = FALSE)
  }

  sf::sf_use_s2(FALSE)
  terra::terraOptions(threads = 12)

  out_dir <- cfg$dir_out
  fs::dir_create(out_dir)
  ag_classes <- c("Crops", "Rangeland", "Bare Ground")
  # Snapshots to fetch: the change-interval endpoints + midpoint. cfg$change_interval is the single
  # source of truth (also drives the transition from/to and layer name below) so they can't drift.
  # Default c(2017, 2023) => c(2017, 2020, 2023), unchanged (#19).
  yrs   <- sort(cfg$change_interval)   # ascending: from=yrs[1], to=yrs[2] (guard a reversed config)
  years <- sort(unique(c(yrs[1], round(mean(yrs)), yrs[2])))

  # Patch-size sieve: drop transition patches smaller than 1.0 ha (100 px at
  # 10 m IO LULC resolution). 0.5 ha (BC VRI minimum mapping unit) and 1.0 ha
  # outputs were compared manually in QGIS during report preparation; 1.0 ha was
  # selected as the better noise/signal tradeoff. Applied bidirectionally in
  # dft_rast_transition() -- affects transition.tif, the gpkg, and any downstream
  # tree-loss numbers computed from transition.tif.
  patch_min_m2 <- 10000

  # --- Select scenario ---
  scenarios <- cfg$scenarios
  scenario_id <- scenario
  if (is.null(scenario_id) || !scenario_id %in% scenarios$scenario_id) {
    scenario_id <- cfg$primary_scenario
  }
  scenario_row <- scenarios |> dplyr::filter(scenario_id == !!scenario_id)
  message("=== Scenario: ", scenario_id, " (ff=", scenario_row$flood_factor, ") ===")
  message("  ", scenario_row$description)

  # --- Load inputs ---
  subbasins <- sf::st_read(
    file.path(out_dir, "subbasins.gpkg"), quiet = TRUE
  ) |> sf::st_transform(4326)

  fp_file <- file.path(out_dir, "floodplain.gpkg")
  floodplain <- sf::st_read(fp_file, layer = scenario_id, quiet = TRUE) |> sf::st_transform(4326)

  # Use name_basin from break_points (carried through via fresh::frs_watershed_split)

  # --- Pass 1: Whole floodplain (for interactive map) ---
  # tile_size (drift#36, opt-in via area.yml; NULL = off) bounds the STAC download to
  # tiles intersecting the AOI instead of the whole floodplain bounding box (~10x the
  # polygon for a thin corridor). Left NULL for the parity fixture + already-published
  # groups so their fetch path is byte-for-byte unchanged; set per-area for large
  # whole-WSG floodplains where the bbox waste dominates the ~30 min fetch.
  message("=== Whole floodplain ===")
  # `years` derives from cfg$change_interval, a user-settable area.yml key -- change_interval
  # [2017, 2025] asks for 2025, which io-lulc-annual-v02 does not have. Checked BEFORE the ~30 min
  # fetch so the failure is immediate and names both sets, rather than surfacing as an empty cube
  # half an hour in. (#33)
  lc_available <- drift::dft_stac_config("io-lulc")$available_years
  if (length(setdiff(years, lc_available))) {
    stop("change_interval asks for year(s) io-lulc does not carry: ",
         paste(setdiff(years, lc_available), collapse = ", "),
         " (available: ", min(lc_available), "-", max(lc_available), ")", call. = FALSE)
  }
  rasters_all <- dft_stac_fetch(floodplain, source = "io-lulc", years = years,
                                tile_size = cfg$tile_size)
  # Landcover fingerprint (#33) -- captured HERE, written at the end of this function so a run that
  # fails downstream never leaves provenance for an output that does not exist. Read from
  # `rasters_all` itself: drift attaches the resolved items to the LIST, so the attribute is gone
  # the moment anything subsets or lapply()s over it.
  lc_items <- fp_prov_stac_items(attr(rasters_all, "stac_items"), years)
  # A `next` link means drift's single get_request() was TRUNCATED, so the gdalcubes collection was
  # built from a partial item set -- a wrong raster, not a partial record. Say so loudly; the guard
  # treats item_ids_complete = FALSE as a failure, not as information.
  if (isFALSE(lc_items$item_ids_complete)) {
    warning("STAC item list was TRUNCATED (the response advertises another page). drift fetches ",
            "one page, so the landcover raster for this AOI may be built from a partial item ",
            "set. Do not publish this run.", call. = FALSE, immediate. = TRUE)
  }
  classified_all <- dft_rast_classify(rasters_all, source = "io-lulc")
  trans_all <- dft_rast_transition(
    classified_all, from = as.character(yrs[1]), to = as.character(yrs[2]),
    patch_area_min = patch_min_m2
  )

  # Save rasters as tif
  fp_dir <- file.path(out_dir, "rasters", scenario_id)
  dir.create(fp_dir, recursive = TRUE, showWarnings = FALSE)
  classified_hashes <- list()
  for (yr in names(classified_all)) {
    cls_tif <- file.path(fp_dir, paste0("classified_", yr, ".tif"))
    terra::writeRaster(classified_all[[yr]], cls_tif, overwrite = TRUE, datatype = "INT1U")
    # Hash the .tif only -- GDAL writes a .aux.xml statistics sidecar beside it on later reads,
    # which is not the data and would make the digest depend on who has opened the file.
    classified_hashes[[yr]] <- fp_file_sha256(cls_tif)
  }
  if (nrow(trans_all$summary) > 0) {
    terra::writeRaster(trans_all$raster, file.path(fp_dir, "transition.tif"),
                       overwrite = TRUE, datatype = "INT4S")
  }
  message("Floodplain rasters saved to ", fp_dir)

  # --- Vectorize to floodplain_landcover.gpkg ---
  # Do NOT wipe the file: layers are species+scenario keyed (classified_<scenario>_<yr>,
  # transition_<scenario>_...), so a second species writes alongside the first. Each write below
  # uses delete_layer=TRUE (append=file.exists) => re-running replaces only its own layers (#23).
  out_lc_gpkg <- file.path(out_dir, "floodplain_landcover.gpkg")
  message("Vectorizing to ", basename(out_lc_gpkg), "...")

  # Classified land cover per year (dissolved by class)
  for (yr in names(classified_all)) {
    lyr <- paste0("classified_", scenario_id, "_", yr)
    polys <- terra::as.polygons(classified_all[[yr]]) |> sf::st_as_sf()
    # Item key (#30): every published layer carries wsg + species + scenario, mirroring the STAC
    # item id (<wsg>_<species>_<scenario>). Layer names stay producer-keyed; these columns are what
    # let many areas merge into one gpkg downstream and stay separable by attribute.
    polys$wsg      <- cfg$watershed_group
    polys$species  <- cfg$species
    polys$scenario <- scenario_id
    sf::st_write(polys, out_lc_gpkg, layer = lyr, append = file.exists(out_lc_gpkg),
                 delete_layer = TRUE, quiet = TRUE)
    message("  Layer: ", lyr)
  }

  # Transition patches -- exploded with area + sub-basin attribution.
  # changes_only = TRUE (drift#34) builds polygons ONLY for actual changes (from != to),
  # never materializing the stable "Trees -> Trees" / "Water -> Water" patches that
  # dominate a large floodplain and OOM the vectorizer. So the post-filter is unneeded.
  if (nrow(trans_all$summary) > 0) {
    lyr <- paste0("transition_", scenario_id, "_", yrs[1], "_", yrs[2])
    trans_polys <- dft_transition_vectors(
      trans_all$raster,
      zones = subbasins,
      zone_col = "name_basin",
      changes_only = TRUE
    )
    parts <- strsplit(trans_polys$transition, " -> ", fixed = TRUE)
    trans_polys$from_class <- vapply(parts, `[`, character(1), 1)
    trans_polys$to_class   <- vapply(parts, `[`, character(1), 2)

    # Recompute area_ha from geometry post-intersection. drift's column is
    # pre-intersection so patches straddling sub-basin boundaries are
    # double-counted when summed by row.
    trans_polys$area_ha <- as.numeric(sf::st_area(trans_polys)) / 1e4

    # Disturbance attribution (#19): tag each change patch by configured overlay layer, in memory
    # before the write so the transition layer carries in_<source> + carried attrs. Open a DB conn
    # ONLY when sources are configured, so offline step-3 runs (no cfg$disturbance) are unaffected.
    if (!is.null(cfg$disturbance)) {
      conn <- DBI::dbConnect(RPostgres::Postgres())
      on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)  # norm: disconnect even on error
      trans_polys <- fp_disturbance_tag(trans_polys, cfg$disturbance, conn,
                                        window = cfg$change_interval)
      DBI::dbDisconnect(conn)
      message("  Tagged disturbance: ",
              paste(vapply(cfg$disturbance, function(s) s$name, character(1)), collapse = ", "))
    }

    # Item key (#30) — set after disturbance tagging so the keys sit alongside the tagged columns.
    trans_polys$wsg      <- cfg$watershed_group
    trans_polys$species  <- cfg$species
    trans_polys$scenario <- scenario_id

    sf::st_write(trans_polys, out_lc_gpkg, layer = lyr,
                 append = file.exists(out_lc_gpkg), delete_layer = TRUE, quiet = TRUE)
    message("  Layer: ", lyr, " (", nrow(trans_polys),
            " change patches >= ", patch_min_m2 / 1e4, " ha)")

    # --- Bridge: which change patches belong to which watercourse (#54) ---
    # The floodplain is exploded two ways that cannot be joined by a column. Change patches are
    # DISJOINT (one row per patch); per-watercourse attribution rows deliberately OVERLAP where
    # ground is shared at a confluence (#40) -- on MORR they sum to 795.8 km2 over a 411.1 km2
    # floodplain. So a patch belongs to several watercourses at once, and writing a single
    # blue_line_key onto it would force a choice that destroys exactly the overlap #40 preserves.
    #
    # Ship the relation instead, as a non-spatial table: one row per (patch, watercourse) pair with
    # the overlap. overlap_frac is what lets a consumer pick their own semantics -- inclusive (every
    # patch touching a river), apportioned (weight by frac; sums back to the basin total), or
    # exclusive (frac == 1). Without it the natural join -- intersect, then sum area_ha by
    # watercourse -- overcounts by up to 94% with nothing to warn them.
    #
    # No attribute_by => no attribution layer => no bridge, and step 3 output is unchanged.
    attr_lyr <- if (!is.null(cfg$attribute_by))
      paste0(scenario_id, "_by_", cfg$attribute_by) else NA_character_
    if (!is.na(attr_lyr) && file.exists(fp_file) && attr_lyr %in% sf::st_layers(fp_file)$name) {
      key <- cfg$attribute_by
      wc  <- sf::st_read(fp_file, layer = attr_lyr, quiet = TRUE)[, key]
      # patch_id is a PER-SUB-BASIN key, not a global one: dft_transition_vectors numbers patches
      # within each sub-basin, so a multi-sub-basin area repeats ids across basins (neexdzii: 2032
      # rows, 1973 distinct ids, 13 sub-basins). Every whole-WSG area has ONE sub-basin, which makes
      # patch_id look globally unique and hides this until the first subset area runs. Grouping on it
      # alone pools rows from different patches and silently mis-apportions -- the same
      # per-tenant-key-against-a-multi-tenant-table trap code-check.md records for id_segment.
      pat <- trans_polys[, c("patch_id", "name_basin", "area_ha")]
      pat$patch_key <- paste(pat$name_basin, pat$patch_id, sep = "\u00a6")
      # The two layers are in DIFFERENT projected CRS -- the attribution layer inherits the stream
      # network's BC Albers, the transition layer the landcover raster's UTM -- so st_intersection
      # errors outright. Transform the watercourses TO the patches, not the reverse: area_ha was
      # measured in the patch CRS, and computing overlap in the other one would leave the coverage
      # check comparing areas from two projections and drifting against its own denominator.
      if (sf::st_crs(wc) != sf::st_crs(pat)) wc <- sf::st_transform(wc, sf::st_crs(pat))
      # st_intersection on two sf data.frames returns ONE ROW PER INTERSECTING PAIR carrying columns
      # from both sides, using the spatial index -- which is the bridge itself. Do not hand-roll
      # st_intersects + pairwise indexing: st_intersection takes no `by_feature` argument, so such a
      # call silently computes a cross product of the paired vectors instead.
      inter <- suppressWarnings(sf::st_intersection(pat, wc))
      if (nrow(inter) > 0) {
        ov_ha  <- as.numeric(sf::st_area(inter)) / 1e4
        bridge <- data.frame(
          patch_id     = inter$patch_id,
          name_basin   = inter$name_basin,
          k            = inter[[key]],
          overlap_ha   = round(ov_ha, 4),
          # Capped at 1: a fully contained patch can overshoot by a float epsilon, and a fraction
          # above 1 reads as a defect rather than as rounding.
          overlap_frac = round(pmin(1, ov_ha / inter$area_ha), 4),
          wsg = cfg$watershed_group, species = cfg$species, scenario = scenario_id,
          stringsAsFactors = FALSE)
        # TWO different fractions, and only one of them is additive. Watercourse rows overlap each
        # other (#40), so a patch under three of them gets three rows each covering most of it and
        # overlap_frac sums to ~2.3 per patch on MORR -- weighting by it overstates the basin total
        # by 83%. apportion_weight normalises within the patch so the weights sum to exactly 1.
        #   overlap_frac      "what share of this patch does this watercourse cover?"  (sums > 1)
        #   apportion_weight  "what share of this patch is credited to it?"            (sums to 1)
        # Ship both: the first answers whether a patch belongs to a river, the second is the only
        # one that reconciles to an ungrouped total.
        pk <- paste(bridge$name_basin, bridge$patch_id, sep = "\u00a6")
        tot_ov <- tapply(bridge$overlap_ha, pk, sum)
        bridge$apportion_weight <- round(bridge$overlap_ha / tot_ov[pk], 4)
        names(bridge)[names(bridge) == "k"] <- key
        # A shared boundary yields a zero-area pair: a join artefact, not a relationship. Keeping it
        # would inflate the row count without changing any sum.
        bridge <- bridge[bridge$overlap_ha > 0, , drop = FALSE]
        b_lyr <- sub("^transition_", "patch_watercourse_", lyr)
        sf::st_write(bridge, out_lc_gpkg, layer = b_lyr,
                     append = file.exists(out_lc_gpkg), delete_layer = TRUE, quiet = TRUE)
        # Coverage worth printing is the UNION one -- how much of a patch any watercourse reaches.
        # Summing overlap_ha would report ~2.3 because the rows overlap, which says nothing about
        # whether ground was missed. max(overlap_frac) under ~0.97 means patch boundaries and
        # attribution boundaries are drifting apart (they come off different raster grids), and a
        # sharp drop would mean the join is quietly losing ground.
        u <- tapply(bridge$overlap_frac, pk, max)
        message("  Layer: ", b_lyr, " (", nrow(bridge), " pairs over ",
                length(unique(pk)), " patches and ",
                length(unique(bridge[[key]])), " watercourses; union coverage ",
                sprintf("%.3f", mean(u)),
                ", unbridged patches ", sum(!pat$patch_key %in% pk), ")")
      }
    }
  }

  # --- Pass 2: Per-sub-basin summaries (for tables/plots) ---
  message("\n=== Per-sub-basin summaries ===")
  results <- list()

  for (i in seq_len(nrow(subbasins))) {
    sb <- subbasins[i, ]
    lab <- sb$name_basin

    fp_clip <- sf::st_intersection(floodplain, sb) |>
      sf::st_collection_extract("POLYGON") |>
      sf::st_union() |>
      sf::st_sf(geometry = _)
    sf::st_crs(fp_clip) <- sf::st_crs(floodplain)

    if (nrow(fp_clip) == 0 || as.numeric(sf::st_area(fp_clip)) < 1e4) {
      message("Skipping ", lab, " -- no floodplain overlap")
      next
    }

    message("Processing: ", lab)
    # Reuse Pass 1's whole-floodplain classified raster instead of re-fetching per
    # sub-basin: each sub-basin is a subset of classified_all, so crop + mask gives the
    # same pixels with no STAC round-trip. classified_all is a NAMED LIST of per-year
    # SpatRasters (indexed classified_all[[yr]] above), so crop/mask each element; the
    # rasters are auto-UTM and fp_clip is in the floodplain CRS, so project fp_clip to
    # the raster CRS first. dft_rast_summarize takes the same list shape as Pass 1. (#11)
    v <- terra::project(terra::vect(fp_clip), terra::crs(classified_all[[1]]))
    classified <- lapply(classified_all, function(r) terra::mask(terra::crop(r, v), v))
    summary <- dft_rast_summarize(classified, unit = "ha")
    summary$name_basin <- lab
    results[[i]] <- summary
  }

  # --- Save ---
  lulc_summary <- dplyr::bind_rows(results)
  lulc_summary$scenario_id <- scenario_id
  lulc_summary$flood_factor <- scenario_row$flood_factor

  # lulc_summary_<scenario_id>.rds is the durable per-scenario store. lulc_summary.rds is a
  # last-writer-wins pointer to the most recently run scenario, kept for the report / 05 /
  # run_region cache (all coho today); with two species in one dir it reflects whichever ran step 3
  # last -- read the per-scenario file for a specific species/scenario (#23).
  saveRDS(lulc_summary, file.path(out_dir, paste0("lulc_summary_", scenario_id, ".rds")))
  saveRDS(lulc_summary, file.path(out_dir, "lulc_summary.rds"))

  # --- Machine-readable provenance (#33) ---
  # The sharp edge this issue exists for: io-lulc-annual-v02 is a REMOTE collection that can be
  # reprocessed upstream, and drift caches by request hash -- so a stale cache keeps serving the
  # old raster while a fresh machine gets the new one, with no error on either side. The recorded
  # item ids are what make that visible.
  #
  # res/crs/dt/aggregation/resampling are read from formals(): fp_lulc passes NONE of them, so the
  # defaults ARE what ran, and reading them keeps the record honest if drift ever changes one.
  # stac_url/collection/asset come from drift's own exported resolver rather than being restated.
  dft_defaults <- formals(drift::dft_stac_fetch)
  lc_cfg <- drift::dft_stac_config("io-lulc")
  fp_prov_set(cfg, "landcover", scenario_id, list(
    inputs = c(list(
      source            = "io-lulc",
      stac_url          = lc_cfg$stac_url,
      collection        = lc_cfg$collection,
      asset             = lc_cfg$asset,
      res               = eval(dft_defaults$res),
      crs               = eval(dft_defaults$crs),
      dt                = eval(dft_defaults$dt),
      aggregation       = eval(dft_defaults$aggregation),
      resampling        = eval(dft_defaults$resampling),
      tile_size         = cfg$tile_size,
      years             = I(as.integer(years)),
      change_interval   = I(as.integer(yrs)),
      patch_area_min_m2 = patch_min_m2,
      # THE content pin, and the only field here that can move when Planetary Computer reprocesses
      # a year. The item ids above are an IDENTITY of what was read -- `<tile>-<year>`, with no
      # `created`/`updated` property on the item (verified live) -- so an in-place re-derivation
      # leaves every id and every href byte-identical. A digest of the classified raster cannot:
      # it is the landcover as it actually entered the model, measured on the output rather than
      # restated from the request. It also closes the cache-hit hole, where the recorded items
      # describe today's query while the raster came from a cache written weeks ago.
      classified_sha256 = classified_hashes,
      floodplain_layer  = scenario_id,
      drift             = fp_pkg_stamp("drift")),
      lc_items),
    run = fp_prov_run()))

  message("\nDone. Scenario: ", scenario_id, " -- outputs in ", out_dir)
  invisible(out_lc_gpkg)
}
