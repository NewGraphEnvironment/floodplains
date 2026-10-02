# fp_composition.R — what the floodplain is made of, and where its change sat, per cell (#108).
#
# The transition layer answers "what changed". It cannot answer "how much of the floodplain is ALR"
# or "how much is wetland", because step 3 vectorises CHANGES ONLY (changes_only = TRUE), so stable
# land never becomes a row; and it cannot answer "how much change was inside the ALR" honestly,
# because `in_alr` is an ANY-TOUCH flag -- summing flagged patch areas counts every patch that grazes
# the reserve as wholly inside it (#100 measured half of NECR's harvest-attributed tree loss lying
# outside any cutblock; #88 is the same point). So shares are read from cells, never from flags.
#
# THE TABLE. One row per combination present in the classified footprint of
#   (from_class, to_class, status, in_<context>...)
# with `cells` and `ha`. Every share in #108 is a sum over it:
#   floodplain ha          sum(ha)
#   ALR ha                 sum(ha[in_alr])
#   change ha              sum(ha[status == "change"])
#   change in ALR ha       sum(ha[status == "change" & in_alr]), by from/to for the class split
# which is why the shape is long and crossed rather than a row of named totals: a new question is a
# new sum, never a schema change, and a new context overlay is a new column.
#
# DEFINITIONS (measured on NECR before they were written down, 2026-10-02):
#   population  cells non-NA in EITHER endpoint classified raster -- the classified footprint. (The
#               accuracy module's footprint is BOTH endpoints; the difference is exactly the `nodata`
#               status below, which is zero on NECR and BULK.) The rasters are masked to the
#               floodplain with terra::mask (touches = TRUE), so the footprint runs a ring of cells
#               past the polygon: +5.5% on NECR, +6.3% on BULK. Change is counted on the footprint,
#               because the transition patches are ring-inclusive too.
#   in_floodplain  the cell CENTRE lies in the published floodplain polygon. Always present. It is the
#               population a share "of the floodplain" uses, and the one that reconciles with vector
#               areas: NECR's ALR is 17,809 ha on the footprint but 16,885.5 ha on in_floodplain cells,
#               against 16,894.7 ha of vector floodplain-ALR intersection (measured 2026-10-02).
#   status      stable  from == to
#               change  from != to and transition.tif non-NA: exactly what the transition layer
#                       vectorises. transition.tif carries STABLE cells too (NECR: 3,605,869 of its
#                       4,078,867), so "non-NA" alone is not "changed".
#               sieved  from != to but the 1 ha sieve removed it (NA in transition.tif): 18% of
#                       NECR's IO change. Kept as its own status so the table still sums to the
#                       footprint and "change" still equals the transition layer.
#               nodata  an endpoint is NA (IO had no label). Zero on NECR; kept so nothing is dropped.
#   in_<name>   (context) the cell CENTRE lies in a `context:` polygon (fp_rast_cells, touches = FALSE), the
#               accuracy module's rule. in_wetland is the FWA polygon; IO's Flooded Vegetation is
#               visible through the class columns, so either wetland definition is a sum.
#
# One pass: every input is stacked and lapp() encodes each cell into one integer, which terra::freq()
# counts in C++. A per-class loop over a whole-WSG grid is the shape code-check-spatial.md warns
# accumulates full-grid rasters in memory.

suppressMessages({library(sf); library(terra)})

FP_COMP_STATUS <- c("stable", "change", "sieved", "nodata")   # status codes 0..3
FP_COMP_MAX_OVERLAYS <- 8L   # keeps every code below 2^24, exact in the FLT4S lapp may hand back

.comp_refuse <- function(...) {
  stop(structure(class = c("fp_composition_error", "error", "condition"),
                 list(message = paste0(...), call = NULL)))
}

# The per-chunk encoder. Vectors in (one per layer), one code per cell out:
#   code = ((from * 100 + to) * 4 + status) * 2^k + overlay bits      (0 for an NA class)
#   NA  outside the footprint
#   -1  transition.tif disagrees with from * 1000 + to (step 3 outputs out of sync)
#   -2  a class code outside 1..99, which the encoding cannot hold
# lapp() hands each layer as its own vector, so this never meets terra::app()'s per-cell /
# transposed-matrix contract (code-check-spatial.md).
.comp_encode <- function(f, t, tr, ...) {
  ov <- list(...)
  st <- ifelse(is.na(f) | is.na(t), 3, ifelse(f == t, 0, ifelse(is.na(tr), 2, 1)))
  f0 <- ifelse(is.na(f), 0, f); t0 <- ifelse(is.na(t), 0, t)
  code <- (f0 * 100 + t0) * 4 + st
  bits <- 0
  for (i in seq_along(ov)) bits <- bits + 2^(i - 1) * !is.na(ov[[i]])
  code <- code * 2^length(ov) + bits
  code[!is.na(f0) & ((f0 < 0 | f0 > 99) | (t0 < 0 | t0 > 99))] <- -2
  code[!is.na(tr) & (is.na(f) | is.na(t) | tr != f * 1000 + t)] <- -1
  code[is.na(f) & is.na(t)] <- NA
  code
}

#' Cell-level composition of a classified footprint.
#'
#' from, to   endpoint classified rasters with RAW IO codes (category tables stripped)
#' trans      transition.tif, raw from*1000+to codes, NA where sieved; or NULL when the run wrote
#'            none (zero change patches), in which case every from != to cell is `sieved`
#' overlays   NAMED list of 1/NA rasters on the same grid (fp_rast_cells), one column each
#' classes    named character vector, IO code -> class name (names are the codes)
#' Returns a data.frame ordered by code.
fp_composition <- function(from, to, trans = NULL, overlays = list(), classes) {
  if (length(overlays) && (is.null(names(overlays)) || any(!nzchar(names(overlays))) ||
                           anyDuplicated(names(overlays))))
    .comp_refuse("overlays must be a list with unique, non-empty names")
  if (length(overlays) > FP_COMP_MAX_OVERLAYS)
    .comp_refuse("at most ", FP_COMP_MAX_OVERLAYS, " overlays")
  if (terra::is.lonlat(from)) .comp_refuse("the classified grid is lon/lat; cell area would not be constant")
  if (is.null(trans)) trans <- terra::init(terra::rast(from), NA)
  for (r in c(list(to = to, trans = trans), overlays))
    if (!terra::compareGeom(from, r, stopOnError = FALSE))
      .comp_refuse("every input must be on the classified grid")
  stk  <- c(from, to, trans, if (length(overlays)) terra::rast(unname(overlays)))
  code <- terra::lapp(stk, fun = .comp_encode, usenames = FALSE,
                      wopt = list(datatype = "FLT4S", names = "code"))
  fr <- terra::freq(code)
  fr <- fr[!is.na(fr$value), c("value", "count")]
  if (any(fr$value == -1))
    .comp_refuse(fr$count[fr$value == -1], " transition cells disagree with from*1000+to -- ",
                 "transition.tif and the classified endpoints are from different runs")
  if (any(fr$value == -2)) .comp_refuse("class codes outside 1..99 in the classified rasters")

  k    <- length(overlays)
  v    <- round(fr$value)
  bits <- v %% 2^k; rest <- v %/% 2^k
  st   <- rest %% 4; pair <- rest %/% 4
  fc   <- pair %/% 100; tc <- pair %% 100
  na0  <- function(x) { x <- as.integer(x); x[x == 0L] <- NA_integer_; x }
  out <- data.frame(from_code = na0(fc), to_code = na0(tc), stringsAsFactors = FALSE)
  out$from_class <- unname(classes[as.character(out$from_code)])
  out$to_class   <- unname(classes[as.character(out$to_code)])
  if (any(is.na(out$from_class) & !is.na(out$from_code)) || any(is.na(out$to_class) & !is.na(out$to_code)))
    .comp_refuse("a class code in the rasters has no name in `classes`")
  out$status <- FP_COMP_STATUS[st + 1]
  for (i in seq_len(k)) out[[paste0("in_", names(overlays)[i])]] <- (bits %/% 2^(i - 1)) %% 2 == 1
  out$cells <- as.numeric(fr$count)
  out$ha    <- round(out$cells * prod(terra::res(from)) / 1e4, 4)
  out[order(v), , drop = FALSE]
}

# The #108 headline numbers, from the table. One definition, so the rollout log and the per-WSG
# report (#92) cannot each write their own sum. Shares "of the floodplain" use in_floodplain cells;
# change uses the footprint, so it reconciles with the transition patches.
fp_composition_summary <- function(comp) {
  ha  <- function(sel) sum(comp$ha[sel & !is.na(sel)])
  fpc <- comp$in_floodplain; chg <- comp$status == "change"
  out <- list(footprint_ha = ha(rep(TRUE, nrow(comp))), floodplain_ha = ha(fpc),
              change_ha = ha(chg), sieved_ha = ha(comp$status == "sieved"))
  for (n in setdiff(sub("^in_", "", grep("^in_", names(comp), value = TRUE)), "floodplain")) {
    inn <- comp[[paste0("in_", n)]]
    out[[paste0(n, "_ha")]]           <- ha(fpc & inn)
    out[[paste0(n, "_share")]]        <- ha(fpc & inn) / out$floodplain_ha
    out[[paste0("change_in_", n, "_ha")]]    <- ha(chg & inn)
    out[[paste0("change_in_", n, "_share")]] <- ha(chg & inn) / out$change_ha
  }
  out
}

# The numeric view the provenance digest is taken over (fp_table_content_sha256 refuses text).
fp_composition_digest <- function(comp) {
  in_cols <- grep("^in_", names(comp), value = TRUE)
  d <- data.frame(from_code = comp$from_code, to_code = comp$to_code,
                  status = match(comp$status, FP_COMP_STATUS) - 1)
  for (c in in_cols) d[[c]] <- as.numeric(comp[[c]])
  d$cells <- comp$cells
  fp_table_content_sha256(d, c("from_code", "to_code", "status", in_cols), "cells")
}

# A classified raster with its category table stripped (raw IO codes), plus the code -> name map.
.comp_read_class <- function(path) {
  r <- terra::rast(path)
  ct <- terra::cats(r)[[1]]
  classes <- if (is.null(ct)) character(0) else
    stats::setNames(as.character(ct[[terra::activeCat(r) + 1]]), ct[[1]])
  r <- terra::deepcopy(r); terra::set.cats(r, layer = 1, value = NULL)
  list(r = r, classes = classes)
}

#' Build, write and record the composition table for one scenario of an area.
#'
#' Reads the rasters step 3 wrote (rasters/<scenario>/), so step 3 and composition_build.R take the
#' same path from the same files and cannot disagree. Writes `composition_<scenario>_<from>_<to>` into
#' floodplain_landcover.gpkg (per-layer, #23) and records it as the `composition` sibling of
#' landcover[<scenario>] in provenance.json -- a sibling, never a new top-level section, because
#' stac_floodplains_bc's reader refuses an unrecognised top-level key and would stop publishing
#' every area that gained one.
#'
#' cfg needs dir_out, change_interval, watershed_group, species and context_overlays (the
#' config/disturbance.yml `context:` list). A DB connection is opened only when context is configured.
fp_composition_build <- function(cfg, scenario_id, conn = NULL) {
  # EVERY refusal before any computation or write. A guard that fires after the st_write below leaves
  # a table nobody vouches for in a gpkg the publisher copies whole -- and on an area with no
  # provenance.json at all (mcgr, pine) nothing downstream would ever report it.
  prov_now <- fp_prov_read(cfg)
  lc_rec <- prov_now[["landcover"]][[scenario_id]]
  if (is.null(lc_rec))
    .comp_refuse("no landcover[", scenario_id, "] in provenance.json: the composition describes ",
                 "rasters that record vouches for, so step 3 has to have recorded them (re-run step 3)")
  fp_rec <- prov_now[["floodplain"]][[scenario_id]]
  # The floodplain polygon is read NOW, the rasters were masked to the one step 3 read. Step 2 having
  # run since step 3 means they differ, and pinning the current floodplain record would compare it
  # with itself. The run timestamps are what order the two (fp_prov_run: UTC, fixed format).
  t_of <- function(r) as.POSIXct(r[["run"]][["datetime_utc"]] %||% NA_character_,
                                 format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  if (!is.null(fp_rec) && isTRUE(t_of(fp_rec) > t_of(lc_rec)))
    .comp_refuse("floodplain[", scenario_id, "] was re-run after landcover[", scenario_id, "]: the ",
                 "classified rasters are masked to the OLD floodplain. Re-run step 3, not this.")
  fp_out_hash <- fp_rec[["outputs_hash"]] %||% NA_character_
  yrs    <- sort(cfg$change_interval)
  # The span comes from area.yml NOW. With no transition.tif the sync guard in fp_composition() never
  # runs, and on an annual area every year's raster exists -- so an interval edited since step 3 would
  # build a composition for another span whose per-year digests still match. Compare the record.
  lc_span <- sort(as.integer(unlist(lc_rec[["inputs"]][["change_interval"]])))
  if (!identical(lc_span, as.integer(yrs)))
    .comp_refuse("change_interval ", paste(yrs, collapse = "-"), " is not the one landcover[",
                 scenario_id, "] was run with (", paste(lc_span, collapse = "-"), "). Re-run step 3.")
  fp_dir <- file.path(cfg$dir_out, "rasters", scenario_id)
  paths  <- file.path(fp_dir, sprintf("classified_%d.tif", as.integer(yrs)))
  if (!all(file.exists(paths))) .comp_refuse("missing endpoint raster(s): ", paste(paths[!file.exists(paths)], collapse = ", "))
  tr_path <- file.path(fp_dir, "transition.tif")
  # GUARD, not merely tie: the rasters on disk must be the ones landcover[<scenario>] records, checked
  # here before anything is computed or written. Step 3 writes the tifs long before its landcover
  # record, so a re-run that dies in between (#63 aborted in the bridge) leaves NEW rasters beside the
  # OLD record; a repair run would otherwise overwrite the published table from rasters no record
  # vouches for, and only a later provenance-check would say so. An unlinked transition.tif (a
  # zero-change run that then died) is the same case: NA here against a recorded digest.
  cls_sha <- stats::setNames(lapply(paths, fp_raster_content_sha256), as.character(as.integer(yrs)))
  tr_sha  <- if (file.exists(tr_path)) fp_raster_content_sha256(tr_path) else NA_character_
  rec_cls <- lc_rec[["inputs"]][["classified_content_sha256"]][names(cls_sha)]
  if (!identical(unlist(cls_sha), unlist(rec_cls)))
    .comp_refuse("classified_", paste(names(cls_sha), collapse = "/"), ".tif are not the rasters ",
                 "landcover[", scenario_id, "] records -- step 3 rewrote them and did not finish. Re-run step 3.")
  if (!identical(tr_sha, lc_rec[["outputs"]][["transition_content_sha256"]] %||% NA_character_))
    .comp_refuse("transition.tif is not the one landcover[", scenario_id, "] records -- re-run step 3.")
  fr <- .comp_read_class(paths[1]); to <- .comp_read_class(paths[2])
  # The rasters' own category tables first, drift's class table to fill: a year whose table omits a
  # class (NECR's carries no Clouds; BULK 2017 has 280 Clouds cells) must still decode.
  ct <- drift::dft_class_table("io-lulc")
  classes <- c(fr$classes, to$classes, stats::setNames(ct$class_name, ct$code))
  classes <- classes[!duplicated(names(classes))]
  trans <- if (file.exists(tr_path)) {
    x <- terra::deepcopy(terra::rast(tr_path)); terra::set.cats(x, layer = 1, value = NULL); x
  } else NULL

  ctx <- cfg[["context_overlays"]]
  # Projected to the RASTER CRS before anything is fetched: .dst_fetch pads the bbox by 1000 CRS
  # units, which on step 3's EPSG:4326 floodplain would be 1000 degrees -- a province-wide fetch.
  fp <- sf::st_read(file.path(cfg$dir_out, "floodplain.gpkg"), layer = scenario_id, quiet = TRUE)
  fp <- sf::st_transform(fp, terra::crs(fr$r))
  overlays <- list(floodplain = fp_rast_cells(fp, fr$r)); ov_rec <- list()
  if (length(ctx)) {
    if (is.null(conn)) {
      conn <- DBI::dbConnect(RPostgres::Postgres())
      on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)
    }
    for (s in ctx) {
      p0 <- .dst_fetch(conn, s, fp, cfg$change_interval)
      # Count and digest the set the DATABASE returned for the bbox, before PROJ and GEOS touch it:
      # a post-filter digest in `inputs` would move with the sf build -- a polygon grazing the
      # floodplain edge in or out -- which is the cross-machine churn #64/#65 removed (CLAUDE.md).
      keys <- unlist(s[["carry"]])
      kd <- sf::st_drop_geometry(p0)[keys]
      # Raw columns, never as.numeric(): fp_table_content_sha256 refuses a text carry on purpose,
      # and coercing it first would turn it all-NA and freeze the digest.
      kdig <- if (length(keys)) fp_table_content_sha256(kd, keys, character(0)) else NA_character_
      p <- sf::st_transform(p0, sf::st_crs(fp))
      p <- p[lengths(sf::st_intersects(p, fp)) > 0, ]
      overlays[[s$name]] <- fp_rast_cells(p, fr$r)
      # The table's COMMENT is how a frozen snapshot says which one it is (scripts/fwapg/alr_load.sh).
      # NA, not a guess, for a table nobody stamped (fwa_wetlands_poly).
      cm <- DBI::dbGetQuery(conn, "SELECT obj_description(to_regclass($1), 'pg_class') AS c",
                            params = list(s$table))$c
      # The keys digest because only the ALR carries a snapshot comment: without it an FWA wetland
      # reload could change this table and move no input.
      ov_rec[[s$name]] <- list(table = s$table, snapshot = if (length(cm) && !is.na(cm)) cm else NA_character_,
                               bbox_features = nrow(p0), keys_sha256 = kdig)
    }
  }

  # fp_out_hash (read above, after the step-2-since-step-3 refusal) pins which floodplain this used,
  # so a step 2 re-run AFTER this composition is visible too (provenance-check compares the two).
  comp <- fp_composition(fr$r, to$r, trans, overlays, classes)
  comp$wsg <- cfg$watershed_group; comp$species <- cfg$species; comp$scenario <- scenario_id
  lyr  <- sprintf("composition_%s_%d_%d", scenario_id, as.integer(yrs[1]), as.integer(yrs[2]))
  gpkg <- file.path(cfg$dir_out, "floodplain_landcover.gpkg")
  sf::st_write(comp, gpkg, layer = lyr, append = file.exists(gpkg), delete_layer = TRUE, quiet = TRUE)

  fp_prov_set_sibling(cfg, "landcover", scenario_id, "composition", list(
    inputs = list(
      change_interval           = I(as.integer(yrs)),
      floodplain_layer          = scenario_id,
      floodplain_outputs_hash   = fp_out_hash,
      classified_content_sha256 = cls_sha,
      transition_content_sha256 = tr_sha,
      membership                = "cell_centre",
      population                = "either_endpoint",
      overlays                  = ov_rec),
    outputs = list(
      layer                 = lyr,
      rows                  = nrow(comp),
      footprint_cells       = sum(comp$cells),
      table_content_sha256  = fp_composition_digest(comp)),
    run = fp_prov_run(toolchain = fp_toolchain())))

  sm <- fp_composition_summary(comp)
  msg <- sprintf("  Layer: %s (%d rows; floodplain %.1f ha of a %.1f ha footprint; change %.1f ha",
                 lyr, nrow(comp), sm$floodplain_ha, sm$footprint_ha, sm$change_ha)
  for (n in setdiff(names(overlays), "floodplain"))
    msg <- paste0(msg, sprintf("; %s %.1f ha, change in %s %.1f ha", n, sm[[paste0(n, "_ha")]], n,
                               sm[[paste0("change_in_", n, "_ha")]]))
  message(msg, ")")
  invisible(comp)
}
