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
#   floodplain_landcover.gpkg       -- classified_{scenario}_{year} + transition layer, every layer
#                                      split at the group line with in_wsg (#53)
#                                      + composition_{scenario}_{from}_{to} (cell-level, #108)
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
  # 0.6.0 was the tile_size floor. 0.10.0 is a CORRECTNESS floor and supersedes it: before it,
  # dft_stac_fetch issued a single get_request() with no paging, so an AOI whose item set spans
  # more than one page was built from a partial collection -- a wrong raster, silently, with
  # item_ids_complete unable to report it (#81). Measured on KOTL under #79.
  if (utils::packageVersion("drift") < "0.10.0") {
    stop("fp_lulc requires drift >= 0.10.0 (paged STAC fetch; < 0.10.0 can silently ",
         "build a raster from a truncated item set); installed ",
         as.character(utils::packageVersion("drift")),
         ". Update: pak::pak('newgraphenvironment/drift')", call. = FALSE)
  }

  sf::sf_use_s2(FALSE)
  terra::terraOptions(threads = 12)

  out_dir <- cfg$dir_out
  fs::dir_create(out_dir)
  ag_classes <- c("Crops", "Rangeland", "Bare Ground")
  # Snapshots to fetch. cfg$change_interval is the single source of truth (it also drives the
  # transition from/to and the layer name below) so they can't drift. Default c(2017, 2023) =>
  # c(2017, 2020, 2023) (#19); lulc_annual: true => EVERY year in the interval, 2017..2023 (#79).
  # The transition is endpoint-to-endpoint either way -- it reads `yrs`, never `years` -- so
  # turning lulc_annual on adds classified years and moves no transition.
  yrs   <- sort(cfg$change_interval)   # ascending: from=yrs[1], to=yrs[2] (guard a reversed config)
  years <- if (isTRUE(cfg$lulc_annual)) seq(yrs[1], yrs[2]) else
    sort(unique(c(yrs[1], round(mean(yrs)), yrs[2])))

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
  # ONE feature, and the SAME bytes as before #53. The scenario layer is now split at the group line,
  # but the STAC fetch takes the delineation as its AOI and drift keys its cache on the AOI's WKB, so a
  # union of the pieces would miss the cache once per area (a ~30 min fetch) and could re-mask the
  # rasters. fl_valley_poly() of step 2's raster IS the pre-split layer (WKB-identical on DUNC, #53
  # plan review), so the AOI comes from the raster; a missing raster falls back to the union.
  fp_tif <- file.path(out_dir, paste0("floodplain_", scenario_id, ".tif"))
  floodplain <- if (file.exists(fp_tif)) {
    flooded::fl_valley_poly(terra::rast(fp_tif))
  } else {
    fp_floodplain_whole(sf::st_read(fp_file, layer = scenario_id, quiet = TRUE))
  }
  floodplain <- sf::st_transform(floodplain, 4326)

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
    # fp_rast_write, not writeRaster: strips the container metadata and then MEASURES the file
    # (#83). drift's untiled fetch returns a raster backed by the gdalcubes NetCDF cube, and on
    # terra 1.9.11 the cube's CF attributes ride into TIFF tag 42112 -- 30 of them, two
    # contradicting the raster (data#type = float64 on a Byte file) and one leaking the producing
    # session's /tmp path -- and a CreateCopy carries them into the published COGs. Pinned here for
    # the same reason 02 pins datatype: the container must not be a function of which terra ran.
    fp_rast_write(classified_all[[yr]], cls_tif, overwrite = TRUE, datatype = "INT1U")
    # Digest the CELL VALUES, not the file. A file hash moves with whatever the writer's version
    # puts in the container -- measured across two machines whose rasters agreed on all 28,291,615
    # cells (#64). Reading only the .tif also keeps GDAL's .aux.xml statistics sidecar out of it,
    # which is not the data and would make the digest depend on who had opened the file.
    classified_hashes[[yr]] <- fp_raster_content_sha256(cls_tif)
  }
  # The transition raster is THE ANSWER of this step, so it is what `outputs` digests (#65). It is
  # written only when there is a transition to write; the path form of the digest returns NA for an
  # absent file, so the empty case records an honest absence rather than erroring or fabricating a
  # hash. NOTE the asymmetry with `classified_content_sha256`, which stays in `inputs`: the
  # classified rasters are the landcover AS IT ENTERED the model, and an upstream reprocess moving
  # them is an INGREDIENT change. The transition is what we computed FROM them.
  trans_tif <- file.path(fp_dir, "transition.tif")
  if (nrow(trans_all$summary) > 0) {
    # Pinned too, though every measured transition.tif is already clean -- dft_rast_transition()
    # builds a NEW raster, which drops the source metadata on either terra. Same reasoning as #65
    # pinning datatype where it measured byte-identical: an unpinned write is one refactor upstream
    # from carrying whatever its input carries, and the asymmetry with the classified series is a
    # property of drift's internals, not a contract it owes us.
    fp_rast_write(trans_all$raster, trans_tif, overwrite = TRUE, datatype = "INT4S")
    transition_sha <- fp_raster_content_sha256(trans_tif)
  } else {
    # A zero-transition run writes no raster -- and `fp_dir` is never cleaned, so digesting the path
    # unconditionally would fingerprint the PREVIOUS run's transition.tif and publish a populated
    # hash beside a zero patch count. Remove the stale file for the same reason #55 removes an
    # orphaned bridge layer: it describes a result this run did not produce.
    if (file.exists(trans_tif)) unlink(trans_tif)
    transition_sha <- NA_character_
  }
  # Initialised BEFORE the vector branch below, which is what actually counts patches. Without it,
  # a zero-transition run would reach the provenance write with the variable undefined.
  n_transition_patches <- 0L
  message("Floodplain rasters saved to ", fp_dir)

  # --- Vectorize to floodplain_landcover.gpkg ---
  # Do NOT wipe the file: layers are species+scenario keyed (classified_<scenario>_<yr>,
  # transition_<scenario>_...), so a second species writes alongside the first. Each write below
  # uses delete_layer=TRUE (append=file.exists) => re-running replaces only its own layers (#23).
  out_lc_gpkg <- file.path(out_dir, "floodplain_landcover.gpkg")
  message("Vectorizing to ", basename(out_lc_gpkg), "...")

  # The group line (#53): every layer below is split along the watershed group polygon, each piece
  # carrying in_wsg, and the change patches are no longer clipped to the sub-basins. The vector half
  # is fp_lulc_vectors.R, which the backfill (gpkg_backfill-split.R) shares.
  wsg_poly <- fp_wsg_polygon(cfg)

  # Classified land cover per year (dissolved by class)
  for (yr in names(classified_all)) {
    lyr <- paste0("classified_", scenario_id, "_", yr)
    polys <- fp_classified_layer(classified_all[[yr]], cfg, scenario_id, wsg_poly)
    sf::st_write(polys, out_lc_gpkg, layer = lyr, append = file.exists(out_lc_gpkg),
                 delete_layer = TRUE, quiet = TRUE)
    message("  Layer: ", lyr)
  }

  # Transition patches -- unclipped, split by sub-basin and group line, tagged, plus the bridge (#54).
  if (nrow(trans_all$summary) > 0) {
    lyr <- paste0("transition_", scenario_id, "_", yrs[1], "_", yrs[2])
    trans_polys <- fp_transition_patches(trans_all$raster, subbasins, wsg_poly, cfg, scenario_id)
    # The patch count comes from the POLYGONS, which is what a patch is. `trans_all$summary` is one
    # row per (from_class, to_class) PAIR -- 48 on neexdzii against 2032 actual patches, measured,
    # 42x low. Since #53 a row is a PIECE (a patch the group line divides is two), and
    # provenance-check.R reconciles this count against the layer's rows.
    n_transition_patches <- fp_write_transition(trans_polys, cfg, scenario_id, lyr, out_lc_gpkg, fp_file)
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
  # (saved at the END of this function, after the composition -- see there)

  # --- Machine-readable provenance (#33) ---
  # The sharp edge this issue exists for: io-lulc-annual-v02 is a REMOTE collection that can be
  # reprocessed upstream, and drift caches by request hash -- so a stale cache keeps serving the
  # old raster while a fresh machine gets the new one, with no error on either side. The recorded
  # item ids are what make that visible.
  #
  # res/crs/dt/aggregation/resampling are read from formals(): fp_lulc passes NONE of them, so the
  # defaults ARE what ran, and reading them keeps the record honest if drift ever changes one.
  # stac_url/collection/asset come from drift's own exported resolver rather than being restated.
  # The composition table describes THIS run's rasters, and the record about to be written replaces
  # landcover[<scenario>] whole -- its `composition` sibling included. So an earlier run's table goes
  # now, before anything can fail between here and its rebuild below: a stale table left in a gpkg
  # the publisher copies whole would describe rasters that no longer exist (#55's orphan class).
  # EVERY span's table for this scenario, not just today's: after a change_interval edit the old-span
  # layer would otherwise outlive the record that described it, under a name nothing asks about.
  comp_gpkg <- file.path(out_dir, "floodplain_landcover.gpkg")
  comp_pat  <- paste0("^composition_", scenario_id, "_[0-9]{4}_[0-9]{4}$")
  if (file.exists(comp_gpkg)) {
    for (comp_lyr in grep(comp_pat, sf::st_layers(comp_gpkg)$name, value = TRUE)) {
      sf::st_delete(comp_gpkg, layer = comp_lyr, quiet = TRUE)
      if (comp_lyr %in% sf::st_layers(comp_gpkg)$name)   # measure the file, not st_delete's return
        stop("could not remove stale ", comp_lyr, " from ", basename(comp_gpkg), call. = FALSE)
    }
  }
  # ...and the PREVIOUS run's resume marker with it. It is rewritten at the end of this function, after
  # the composition; left in place, a re-run that dies in between would be skipped by run_region.R as
  # done, with no composition, and 7c would read the area as merely predating #108.
  unlink(file.path(out_dir, c(paste0("lulc_summary_", scenario_id, ".rds"), "lulc_summary.rds")))
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
      classified_content_sha256 = classified_hashes,
      floodplain_layer  = scenario_id,
      drift             = fp_pkg_stamp("drift")),
      lc_items),
    outputs = list(
      # NA, not a filename, when the run produced no transition -- the raster is unlinked above, so
      # naming it would be round-2's defect with the halves swapped: an honest NA digest beside a
      # filename for a file that does not exist.
      transition_raster         = if (n_transition_patches > 0) basename(trans_tif) else NA_character_,
      transition_content_sha256 = transition_sha,
      transition_patches        = n_transition_patches),
    run = fp_prov_run(toolchain = fp_toolchain())))

  # --- Composition (#108) ---
  # What the floodplain is made of and where its change sat, counted per CELL so stable land is in
  # it and no share inherits the any-touch overstatement of an in_<context> flag. AFTER the landcover
  # record above, for two reasons: it reads the rasters this step just wrote (the same files
  # composition_build.R reads, so the two paths cannot disagree), and its provenance is a sibling
  # INSIDE landcover[<scenario>] -- fp_prov_set replaces the whole entry, so writing it first would
  # have it wiped. Runs whatever the patch count: a run with no change still has a composition.
  # Opens its own DB connection only when context overlays are configured.
  fp_composition_build(cfg, scenario_id)

  # The summaries LAST: lulc_summary.rds is run_region.R's "this group is done" marker, so writing it
  # before the composition would let a composition failure (DB down, OOM) be skipped on every resume
  # and never rebuilt. A step 3 that dies here is re-run whole, or repaired with composition_build.R.
  saveRDS(lulc_summary, file.path(out_dir, paste0("lulc_summary_", scenario_id, ".rds")))
  saveRDS(lulc_summary, file.path(out_dir, "lulc_summary.rds"))

  message("\nDone. Scenario: ", scenario_id, " -- outputs in ", out_dir)
  invisible(out_lc_gpkg)
}
