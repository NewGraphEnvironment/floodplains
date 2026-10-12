#!/usr/bin/env Rscript
#
# 01_network_extract.R  —  defines fp_network(cfg)
#
# Build the coho-accessible stream network + filtered waterbodies for an area using
# the `link` package (a config-driven pipeline that orchestrates `fresh` over a fwapg
# PostgreSQL database). Produces data/<area>/aquatic_network.gpkg with:
#   streams_<sp><order>      <species>-accessible streams, order >= cfg$min_order (input to 02)
#   waterbodies_<sp><order>  lakes/wetlands on the accessible network
#   (e.g. streams_co3 / waterbodies_co3 for coho order-3; multiple species coexist in one gpkg)
#   habitat_link             whole mode only: link's per-segment habitat, keyed by FWA position
#
# `species: all` (#104) is the WHOLE network at order >= min_order with no access filter
# (streams_all2 for order 2): one floodplain per group, habitat joined afterwards from habitat_link.
#
# `link` is watershed-group scoped, so we run cfg$watershed_group, persist into the
# DEDICATED cfg$schema. When cfg$network_source is set (e.g. "fresh_default") the accessible
# network is GRABBED from that already-built schema instead of re-running the pipeline, with
# a freshness guard against the bcfp reference (#14). If cfg$subset is set
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

# The link config bundle this repo BUILDS with, named once (#65). Every lnk_config() call in this
# file uses it, and provenance-check.R parses them to assert that -- so changing the methodology
# here cannot silently leave the recorded `link_config_name` describing the old one. Not a tuning
# knob: `default` leaves `subsurfaceflow` OFF as a natural barrier where `bcfishpass` opts it in,
# which is the NewGraph methodology decision documented below.
LNK_BUILD_CONFIG <- "default"

# --- The network read, as functions (#104) ------------------------------------------------------
# Lifted out of fp_network() so whole_network-check.R can assert both modes with no database: the
# species-mode SQL is pinned there BYTE-IDENTICAL to what this file ran before the lift, so the lift
# cannot move any existing area's network.
#
# species mode  access_<species> IN (1,2): 1 = modelled accessible past natural barriers, 2 =
#               observation-confirmed above a barrier; 0 = blocked (NULL = species not modelled here).
# whole mode    species == FP_SPECIES_WHOLE ("all"): every segment at order >= min_order, NO join to
#               streams_access. Not merely "no filter": the inner join itself restricts the read to the
#               groups link ran its access model on, and DUNC (the #104 pilot) is in streams but not
#               in streams_access.
# Both join upstream_area_ha (VCA field) + map_upstream (precip) from fwapg -- link's streams table
# doesn't carry them but `02`/flooded need them.
#
# species is interpolated into SQL as a column name, so it is restricted to a short lowercase code.
fp_network_check_species <- function(species) {
  if (!is.character(species) || length(species) != 1L || is.na(species) ||
      !grepl("^[a-z]{2,4}$", species)) {
    stop("cfg$species must be a short lowercase species code (e.g. 'co', 'ch'), got: ",
         format(species), call. = FALSE)
  }
  invisible(species)
}

fp_network_sql <- function(read_schema, aoi_wsg, species, min_order) {
  fp_network_check_species(species)
  if (identical(species, FP_SPECIES_WHOLE)) {
    return(sprintf("
    SELECT s.id_segment, s.blue_line_key, s.downstream_route_measure,
           s.stream_order, s.gnis_name, s.channel_width, s.gradient,
           s.length_metre, s.waterbody_key, s.linear_feature_id,
           ua.upstream_area_ha, p.map_upstream, s.geom
    FROM %1$s.streams s
    LEFT JOIN (
      SELECT l.linear_feature_id, u.upstream_area_ha
      FROM whse_basemapping.fwa_streams_watersheds_lut l
      JOIN whse_basemapping.fwa_watersheds_upstream_area u
        ON l.watershed_feature_id = u.watershed_feature_id
    ) ua ON ua.linear_feature_id = s.linear_feature_id
    LEFT JOIN whse_basemapping.fwa_stream_networks_mean_annual_precip p
      ON p.wscode_ltree = s.wscode_ltree AND p.localcode_ltree = s.localcode_ltree
    WHERE s.stream_order >= %2$s
      AND s.watershed_group_code = '%3$s'",
      read_schema, min_order, aoi_wsg))
  }
  sprintf("
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
    WHERE a.access_%3$s IN (1, 2) AND s.stream_order >= %2$s
      AND s.watershed_group_code = '%4$s'",
    read_schema, min_order, species, aoi_wsg)
}

# The freshness guard's reference km. Same predicate as the read, minus the network join: whole mode
# compares every segment at order >= min_order, species mode the accessible ones.
fp_bcfp_km_sql <- function(species, min_order, aoi_wsg) {
  fp_network_check_species(species)
  if (identical(species, FP_SPECIES_WHOLE)) {
    return(sprintf(
      "SELECT sum(length_metre)/1000.0 FROM fresh.streams_vw_bcfp
       WHERE stream_order >= %1$d AND watershed_group_code = '%2$s'",
      as.integer(min_order), aoi_wsg))
  }
  sprintf(
      "SELECT sum(length_metre)/1000.0 FROM fresh.streams_vw_bcfp
       WHERE access_%1$s IN (1,2) AND stream_order >= %2$d AND watershed_group_code = '%3$s'",
      species, min_order, aoi_wsg)
}

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
  species   <- cfg$species
  out_dir   <- cfg$dir_out
  fs::dir_create(out_dir)

  # species drives which accessibility column is read (access_co, access_ch, ...).
  # Guard it: it is interpolated into SQL as a column name, so restrict to a short
  # lowercase code (co, ch, sk, st, wct, ...).
  fp_network_check_species(species)
  # `species: all` is the whole network (#104): no access column is read, here or in the guard.
  whole <- fp_whole_network(cfg)
  fp_whole_network_validate(cfg)

  # Network source: BUILD (default) re-runs the link pipeline into cfg$schema; GRAB reads
  # the accessible network from an already-built schema (cfg$network_source, e.g.
  # "fresh_default"), skipping the pipeline. Grab schemas are province-wide, so the read
  # below filters watershed_group_code and a freshness guard checks the grabbed km against
  # the bcfp reference (a stale source fails loud). (#14)
  grab        <- !is.null(cfg$network_source) && nzchar(cfg$network_source)
  read_schema <- if (grab) cfg$network_source else schema
  net_source  <- if (grab) paste0("GRAB from ", read_schema) else paste0("BUILD into ", schema)
  fresh_note  <- "built (no freshness check)"
  # network_guard: strict (default, stop on divergence) | warn (log + proceed) | off (skip
  # the check). Set warn/off when a divergence is EXPECTED and understood -- updated crossings
  # data or a deliberately different config -- with the stamp sidecar recording the override.
  guard       <- if (is.null(cfg$network_guard)) "strict" else cfg$network_guard

  # lnk_config for the schema we will READ from. Needed on BOTH branches: the provenance lookup
  # below calls lnk_log_read(), which resolves its schema from cfg$pipeline$schema, and on a GRAB
  # that is the SOURCE schema, not this area's. Built here rather than inside the else-branch
  # (where the pipeline's own copy lives) so a GRAB run can look up the row too -- which is the
  # only way most published areas get a config_hash at all, since they GRAB and never build. (#33)
  lnk_cfg_read <- lnk_config(LNK_BUILD_CONFIG)
  lnk_cfg_read$pipeline$schema <- read_schema

  if (grab) {
    message("Network source: GRAB from '", read_schema, "' (skipping link pipeline build).")
  } else {
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
  lnk_cfg <- lnk_config(LNK_BUILD_CONFIG)   # method choice, not area config
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
  }

  # --- Read the network: species-accessible, or the whole network (#104) ---
  # The predicates and joins are in fp_network_sql(), above.
  if (whole) {
    message("Reading the WHOLE network (no access filter, #104), order >= ", min_order, " + attributes...")
  } else {
    message("Reading ", species, "-accessible order >= ", min_order, " streams + attributes...")
  }
  streams_sql <- fp_network_sql(read_schema, aoi_wsg, species, min_order)
  streams <- sf::st_read(conn, query = streams_sql, quiet = TRUE) |> sf::st_zm(drop = TRUE)
  # The habitat table is READ here, before anything is written, so a group with no habitat refuses
  # without leaving a network and a network record behind; it is written after the record (#104).
  hab <- if (whole) fp_habitat_read(conn, cfg, read_schema, aoi_wsg) else NULL

  # --- The network content digest (#65) ---
  # THE INPUT digest, taken HERE: on the full-WSG read, BEFORE the optional reach subset. Same
  # placement as the freshness guard below and for the same reason, stated there as "checked on the
  # full-WSG read, before any reach subset".
  #
  # Before this field, network `inputs_hash` covered the watershed group, the species, the schema
  # name and the package versions -- a description of the JOB, with nothing derived from the
  # network's content. `link_log` is a SIBLING of `inputs`, so even `config_hash` and `run_uid` were
  # outside the hash. Rebuild `fresh` with a different config, a different link, or different data
  # and the recorded hash did not move.
  #
  # The subset must NOT be inside this digest. It is st_transform + st_intersects -- PROJ and GEOS --
  # so a post-subset digest would make `inputs_hash` a function of the sf build, reintroducing one
  # field over exactly the cross-machine churn #64 removed. The subset set is digested separately
  # into `outputs`. Being outside `inputs_hash` is what matters: a toolchain difference there
  # does not churn the question "same ingredients?". It is NOT a licence to vary -- the A/B treats
  # an `outputs_hash` mismatch as a hard failure, correctly, because that script compares two runs
  # on ONE machine where any difference is a real defect. The one case where a legitimate
  # difference could arise is a CROSS-MACHINE comparison of this digest on a subset area, and
  # provenance_ab-compare.R says so in its header rather than quietly tolerating it.
  NETWORK_DIGEST_KEY <- c("blue_line_key", "downstream_route_measure")
  # The VALUE columns are EVERY COLUMN STEP 2 CONSUMES, enumerated against flooded's own body
  # rather than from memory. fl_valley_confine() reads `upstream_area_ha` for the bankfull
  # regression, `map_upstream` for precipitation, and -- the one this list originally missed --
  # `channel_width`: it auto-enables `channel_buffer` whenever that column is present on an sf
  # streams object and burns st_buffer(streams, channel_width / 2) into the valley mask. Measured:
  # tripling every width left both network digests BYTE-IDENTICAL while adding >= 2.7 km2 (+1.9%)
  # of ground to neexdzii's co_ff04. `waterbody_key` selects the waterbodies layer, which is
  # rasterized into the same mask, so it belongs here for the same reason.
  #
  # The test for this list is not "does it look complete" but "name the flooded argument each
  # column feeds". A column that feeds nothing is noise; one that feeds the delineation and is
  # absent is the defect this whole issue is about, one column over.
  NETWORK_DIGEST_VAL <- c("length_metre", "stream_order", "upstream_area_ha", "map_upstream",
                          "channel_width", "waterbody_key")
  network_sha_input <- fp_table_content_sha256(streams, NETWORK_DIGEST_KEY, NETWORK_DIGEST_VAL)

  # --- Freshness guard (grab only) ---
  # A shared schema is not uniformly current per-WSG, so compare the grabbed accessible km
  # to the province bcfp reference and fail loud if it diverges beyond tolerance (default
  # 2%). A current default-config source is within ~0.5% of bcfp; a stale one is caught
  # here instead of silently shifting the floodplain. Checked on the full-WSG read, before
  # any reach subset. (#14)
  if (grab) {
    grab_km <- sum(streams$length_metre, na.rm = TRUE) / 1000
    bcfp_km <- DBI::dbGetQuery(conn, fp_bcfp_km_sql(species, min_order, aoi_wsg))[1, 1]
    tol <- if (is.null(cfg$network_source_tol)) 0.02 else cfg$network_source_tol
    if (is.na(bcfp_km) || bcfp_km == 0) {
      fresh_note <- sprintf("grabbed %.0f km; no bcfp reference (UNVERIFIED)", grab_km)
      message("Freshness check: ", fresh_note)
    } else {
      dev <- abs(grab_km - bcfp_km) / bcfp_km
      fresh_note <- sprintf("grabbed %.0f km vs bcfp %.0f km = %.1f%% dev (tol %.0f%%, guard=%s)",
                            grab_km, bcfp_km, 100 * dev, 100 * tol, guard)
      message("Freshness check: ", fresh_note)
      if (dev > tol) {
        msg <- sprintf("network_source '%s' diverges from bcfp by %.1f%% (> %.0f%% tol) for %s",
                       read_schema, 100 * dev, 100 * tol, aoi_wsg)
        if (identical(guard, "off")) {
          message(msg, " -- network_guard=off, proceeding (override recorded in stamp).")
        } else if (identical(guard, "warn")) {
          warning(msg, " -- network_guard=warn, proceeding.", call. = FALSE)
        } else {
          stop(msg, " -- likely stale. If intentional (updated crossings / different config), ",
               "set network_guard: warn|off; else drop network_source to build.", call. = FALSE)
        }
      }
    }
  }

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

  # Layer names are species-keyed (streams_<sp><min_order>) so multiple species coexist in one
  # aquatic_network.gpkg (e.g. streams_co3 + streams_ch3). Coho order-3 => streams_co3 (unchanged).
  streams_lyr     <- paste0("streams_", species, min_order)
  waterbodies_lyr <- paste0("waterbodies_", species, min_order)
  message("  ", streams_lyr, ": ", nrow(streams), " segments | ",
          waterbodies_lyr, ": ", nrow(waterbodies))

  # --- Save multi-layer aquatic_network.gpkg (02 reads streams_<sp><order> + waterbodies_<sp><order>) ---
  # Do NOT wipe the whole gpkg: a second species writes alongside the first. Per-layer
  # delete_layer=TRUE replaces only the same-species layer; append=file.exists creates the file on
  # the first species and appends subsequent species (#23).
  out_gpkg <- file.path(out_dir, "aquatic_network.gpkg")
  sf::st_write(streams, out_gpkg, layer = streams_lyr,
               append = file.exists(out_gpkg), delete_layer = TRUE, quiet = TRUE)
  if (nrow(waterbodies)) {
    sf::st_write(waterbodies, out_gpkg, layer = waterbodies_lyr,
                 append = file.exists(out_gpkg), delete_layer = TRUE, quiet = TRUE)
  } else if (file.exists(out_gpkg) && waterbodies_lyr %in% sf::st_layers(out_gpkg)$name) {
    # No waterbodies this run: drop any same-species layer left by a prior run so 02 does not
    # silently read stale waterbodies (the old whole-file wipe used to prevent this) (#23).
    sf::st_delete(out_gpkg, layer = waterbodies_lyr, quiet = TRUE)
  }
  message("Saved: ", basename(out_gpkg))

  # --- Resolve the config name that actually produced this network (#65) ---
  # Read BEFORE the stamp sidecar below, because that sidecar states the methodology too and used to
  # state it wrongly for the same reason.
  # --- Machine-readable provenance (#33) ---
  # The stamp above is markdown for a human; this is the block stac_floodplains_bc (#17) publishes
  # as STAC item properties. It records the LINK LOG ROW rather than re-deriving anything: link's
  # config_hash is a hash over 17 files plus the config name and species list, so a self-computed
  # SHA of config.yaml would match nothing in fresh.log and the two records could never be joined.
  #
  # Read the row WHOLESALE. lnk_log_read() is a `SELECT *`, so a column the DATABASE has arrives
  # whether or not the installed link names it -- measured, the installed link here is 0.47.3
  # whose cols_log has neither run_uid nor bcfp_pin_source, while the checkout is 0.49.0. That is
  # why link#264 (the RemoteSha SHA tier) is off this issue's critical path: naming fields we
  # expect would couple us to a version, and reading the row does not.
  link_log <- tryCatch({
    row <- link::lnk_log_read(conn, lnk_cfg_read, aoi = aoi_wsg)
    if (nrow(row) == 0) NULL else as.list(row[1, ])
  }, error = function(e) structure(list(), note = conditionMessage(e)))
  link_log_note <- NULL
  if (is.null(link_log)) {
    link_log_note <- paste0("no log row for ", aoi_wsg, " in schema '", read_schema, "'")
  } else if (!length(link_log)) {
    link_log <- NULL
    link_log_note <- paste0("log unreadable in schema '", read_schema, "'")
  } else {
    # Null-fill the declared set. `run_uid` is absent from any schema predating link#262 -- record
    # that as an explicit null, never by omission: an absent key reads as "not implemented", a
    # null one reads as "we looked and there was not one", and only the second is true. (#33)
    # `config_name` joined this list in #65: it is the field the resolution below reads, and a key
    # that is absent rather than null cannot be told apart from one the source schema does not have.
    link_log <- fp_prov_null_fill(link_log, c(
      "run_uid", "config_hash", "config_name", "link_sha", "link_dirty", "fwapg_sha",
      "bcfp_model_version", "bcfp_pin_source", "date_start", "date_end"))
    # text[] columns (species, wsg_upstream) arrive as a list; timestamps as POSIXct. Flatten both
    # to JSON-safe scalars so the serialized bytes cannot depend on the session's timezone.
    link_log <- lapply(link_log, fp_prov_scalar)
  }
  if (!is.null(link_log_note)) message("  provenance: ", link_log_note)

  # `link_config_name` used to be the LITERAL "default" on both branches. True on a BUILD, where this
  # script hands lnk_config("default") to the pipeline. WRONG on a GRAB -- measured live in
  # data/neexdzii: inputs.link_config_name said "default" while link_log.config_name said
  # "bcfishpass", and the two differ in the natural-barrier set (bcfishpass opts in
  # `subsurfaceflow`; the default bundle leaves it off). So the published provenance claimed the
  # NewGraph default methodology for a network built under the config this repo explicitly chose not
  # to use.
  #
  # The predicate is `grab`, NOT log presence. Falling back to the build literal "when there is no
  # log row" would reproduce the defect exactly where it lives: link_log is NULL precisely when a
  # GRAB source has no log table. A GRAB may never assert a locally-assumed config name --
  # provenance-check.R asserts that against the real file, which is the one arm here with an
  # external reference.
  #
  # `link_config_name_source` names which tier answered, so an NA is diagnosable rather than mute --
  # the same contract fp_pkg_stamp's `sha_source` carries.
  log_config_name <- if (!is.null(link_log)) link_log[["config_name"]] else NULL
  if (!is.null(log_config_name) && (length(log_config_name) != 1L || is.na(log_config_name))) {
    log_config_name <- NULL
  }
  if (!grab) {
    link_config_name <- LNK_BUILD_CONFIG
    link_config_name_source <- "built_literal"
    # A BUILD writes its own log row, so the two SHOULD agree. When they do not, the pipeline ran
    # something other than what this script asked for -- say so rather than silently preferring one.
    if (!is.null(log_config_name) && !identical(as.character(log_config_name), LNK_BUILD_CONFIG)) {
      warning("link built with config '", LNK_BUILD_CONFIG, "' but the log row for ", aoi_wsg,
              " reports '", log_config_name, "'", call. = FALSE, immediate. = TRUE)
    }
  } else if (!is.null(log_config_name)) {
    link_config_name <- as.character(log_config_name)
    link_config_name_source <- "link_log"
  } else {
    link_config_name <- NA_character_
    link_config_name_source <- "unresolved"
  }
  message("  provenance: link config '", link_config_name, "' (", link_config_name_source, ")")

  # --- Provenance stamp sidecar ---
  # lnk_stamp records config identity + link/fresh versions + git SHAs + a DB snapshot
  # (bcfishobs.observations = the crossings/observations signal) + per-file config
  # provenance (the crossings/barrier override CSVs + their drift status). Written next to
  # every network so a floodplain self-documents what produced it -- and so a grab-guard
  # override (network_guard = warn|off) is auditable: the stamp shows whether the source's
  # divergence lines up with updated crossings / a different config. (#14)
  # lnk_stamp is handed the LOCAL bundle on both branches, deliberately -- it snapshots this
  # machine's config files and package state, which is a fact about this run whichever schema the
  # network came from. On a GRAB that makes the block below describe a config that did NOT produce
  # the network, so say so in the sidecar rather than let a reader take it as the methodology. Same
  # defect the provenance record carried until #65, in the file a person actually opens.
  stamp <- lnk_stamp_finish(lnk_stamp(lnk_config(LNK_BUILD_CONFIG), conn, aoi = aoi_wsg))
  stamp_md <- c(format(stamp, "markdown"), "",
                "### Floodplains network source",
                paste0("- source: ", net_source),
                paste0("- freshness: ", fresh_note),
                paste0("- link config that produced this network: ", link_config_name,
                       " (", link_config_name_source, ")"),
                if (grab) paste0(
                  "- NOTE: the config block above describes the LOCAL `", LNK_BUILD_CONFIG,
                  "` bundle on this machine, NOT the config the grabbed network was built under."))
  # Species-suffixed so a second species' step 1 doesn't overwrite the first's stamp (#23).
  stamp_name <- paste0("aquatic_network_", species, min_order, ".stamp.md")
  writeLines(stamp_md, file.path(out_dir, stamp_name))
  message("Wrote provenance sidecar: ", stamp_name)

  fp_prov_set(cfg, "network", paste0(species, min_order), list(
    inputs = list(
      watershed_group  = aoi_wsg,
      species          = species,
      min_order        = min_order,
      network_source   = net_source,
      read_schema      = read_schema,
      subset           = cfg$subset,
      link_config_name = link_config_name,
      link_config_name_source = link_config_name_source,
      # The one field in this block derived from the network's CONTENT rather than from a
      # description of the job (#65). Taken pre-subset -- see where it is computed.
      network_content_sha256 = network_sha_input,
      link             = fp_pkg_stamp("link"),
      fresh            = fp_pkg_stamp("fresh")),
    # What this step PRODUCED, digested over the same non-geometric key the input digest uses (#65).
    # It differs from the input digest exactly when the reach subset removed something, so on a
    # whole-WSG area the two agree by construction and on a subset area they must not. Geometry stays
    # out: a GeoPackage layer has no guaranteed row order and carries floats, which is #72.
    outputs = list(
      streams_layer          = streams_lyr,
      # Named for the LAYER, not repeating the input key. Same digest function, different stage --
      # and a distinct name is what lets provenance-check.R keep its inputs/outputs overlap arm,
      # which is the thing that would catch a parameter accidentally duplicated across the two.
      streams_content_sha256 = fp_table_content_sha256(streams, NETWORK_DIGEST_KEY,
                                                       NETWORK_DIGEST_VAL),
      n_segments             = nrow(streams)),
    link_log = link_log,
    link_log_note = link_log_note,
    # freshness and the guard setting are OBSERVATIONS of this run, not inputs: the guard can be
    # overridden per-run by FP_NETWORK_GUARD, and the measured km moves whenever the source schema
    # is rebuilt. Keeping them out of `inputs` is what lets the determinism check mean something.
    run = fp_prov_run(network_guard = guard, freshness = fresh_note)))

  # --- The habitat table (#104, whole mode only) ---
  # The whole-network floodplain carries no habitat: habitat is JOINED to it afterwards, by FWA
  # position, from whichever model is wanted. This writes link's model, from the schema the network
  # was read from, as one non-spatial table beside the network so the join needs no database.
  # The whole group is written, every order and never subset: order-1 habitat is what a join's
  # integrity check counts as having no floodplain to join to, and a reach subset is a property of
  # the floodplain, not of the model.
  if (whole) fp_habitat_write(conn, cfg, hab, read_schema, aoi_wsg, out_gpkg, link_log)

  invisible(out_gpkg)
}

# Species tables link persists as <schema>.streams_habitat_<sp>. Discovered rather than listed, so a
# species link adds is carried without an edit here; `streams_habitat_long_vw` does not match.
fp_habitat_tables_sql <- function(read_schema) {
  if (!grepl("^[a-z_][a-z0-9_]*$", read_schema)) stop("bad schema name: ", read_schema, call. = FALSE)
  sprintf("SELECT table_name FROM information_schema.tables
            WHERE table_schema = '%s' AND table_name ~ '^streams_habitat_[a-z]{2,4}$'
            ORDER BY table_name", read_schema)
}

# Keyed on (id_segment, watershed_group_code): link numbers id_segment per watershed group, so a join
# on id_segment alone matches every group's segment of that number (measured: 1.96 M rows for DUNC's
# 26,827). The table carries FWA position, never id_segment, because link renumbers on a rebuild.
fp_habitat_sql <- function(read_schema, aoi_wsg, sp) {
  fp_network_check_species(sp)
  if (!grepl("^[a-z_][a-z0-9_]*$", read_schema)) stop("bad schema name: ", read_schema, call. = FALSE)
  if (!grepl("^[A-Z]{4}$", aoi_wsg)) stop("bad watershed group code: ", aoi_wsg, call. = FALSE)
  sprintf("
    SELECT s.blue_line_key, s.downstream_route_measure, s.upstream_route_measure,
           s.stream_order, s.length_metre, '%3$s'::text AS species,
           h.accessible, h.spawning, h.rearing, h.lake_rearing, h.wetland_rearing
    FROM %1$s.streams s
    JOIN %1$s.streams_habitat_%3$s h USING (id_segment, watershed_group_code)
    WHERE s.watershed_group_code = '%2$s'",
    read_schema, aoi_wsg, sp)
}

FP_HABITAT_LAYER <- "habitat_link"

fp_habitat_read <- function(conn, cfg, read_schema, aoi_wsg) {
  tabs <- DBI::dbGetQuery(conn, fp_habitat_tables_sql(read_schema))$table_name
  sps  <- sub("^streams_habitat_", "", tabs)
  parts <- lapply(sps, function(sp) DBI::dbGetQuery(conn, fp_habitat_sql(read_schema, aoi_wsg, sp)))
  hab <- do.call(rbind, parts[vapply(parts, nrow, integer(1)) > 0])
  if (is.null(hab) || !nrow(hab)) {
    stop("whole-network area '", cfg$name, "': no habitat rows for ", aoi_wsg, " in any ",
         read_schema, ".streams_habitat_<sp> table (", length(tabs), " tables). The floodplain ",
         "would publish with nothing to join to.", call. = FALSE)
  }
  # Driver values arrive as integer64 / pq types for some columns; the digest renders numerics only.
  for (k in c("blue_line_key", "downstream_route_measure", "upstream_route_measure", "stream_order",
              "length_metre")) hab[[k]] <- as.numeric(hab[[k]])
  hab$wsg   <- aoi_wsg
  hab$model <- paste0("link:", read_schema)
  hab <- hab[order(hab$species, hab$blue_line_key, hab$downstream_route_measure, method = "radix"), ]
  rownames(hab) <- NULL
  hab
}

# The FWA the keys belong to, as content: one digest over the group's FWA stream segments on the same
# (blue_line_key, downstream_route_measure) key, with length_metre. link's log row carries fwapg_sha,
# but a group link never logged (DUNC) has none, and no FWA version table exists in the database. A
# consumer can recompute this against their own FWA to check their keys mean the same lines (#104).
fp_fwa_sql <- function(aoi_wsg) {
  if (!grepl("^[A-Z]{4}$", aoi_wsg)) stop("bad watershed group code: ", aoi_wsg, call. = FALSE)
  sprintf("SELECT blue_line_key, downstream_route_measure, length_metre
             FROM whse_basemapping.fwa_stream_networks_sp WHERE watershed_group_code = '%s'", aoi_wsg)
}

fp_habitat_write <- function(conn, cfg, hab, read_schema, aoi_wsg, out_gpkg, link_log) {
  fwa <- DBI::dbGetQuery(conn, fp_fwa_sql(aoi_wsg))
  for (k in names(fwa)) fwa[[k]] <- as.numeric(fwa[[k]])
  sf::st_write(hab, out_gpkg, layer = FP_HABITAT_LAYER,
               append = file.exists(out_gpkg), delete_layer = TRUE, quiet = TRUE)
  by_sp <- table(hab$species)
  message("  ", FP_HABITAT_LAYER, ": ", nrow(hab), " rows (",
          paste(names(by_sp), as.integer(by_sp), sep = " ", collapse = ", "), ")")

  # The FWA version the keys belong to (#104: "publish the FWA version beside the key"): fwapg_sha
  # from link's log row when the group has one, NA with its source "unresolved" when it does not,
  # never a guess; and fwa_content_sha256 always, which needs no log row.
  fwapg_sha <- if (!is.null(link_log)) link_log[["fwapg_sha"]] else NULL
  if (is.null(fwapg_sha) || length(fwapg_sha) != 1L) fwapg_sha <- NA_character_
  fp_prov_set_sibling(cfg, "network", paste0(cfg$species, cfg$min_order), "habitat", list(
    inputs = list(
      model       = "link",
      read_schema = read_schema,
      watershed_group = aoi_wsg,
      # I(): one species must still publish as an array, never unboxed to a scalar.
      species     = I(sort(unique(hab$species), method = "radix")),
      fwapg_sha   = as.character(fwapg_sha),
      fwa_content_sha256 = fp_table_content_sha256(fwa, c("blue_line_key", "downstream_route_measure"),
                                                   "length_metre"),
      fwapg_sha_source = if (is.na(fwapg_sha)) "unresolved" else "link_log"),
    outputs = list(
      layer = FP_HABITAT_LAYER,
      rows  = nrow(hab),
      table_content_sha256 = fp_habitat_content_sha256(hab)),
    run = fp_prov_run()))
  invisible(hab)
}
