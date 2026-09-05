#!/usr/bin/env Rscript
#
# run_area.R  —  top-level driver: run the floodplain + LULC pipeline for one area.
#
# Usage:
#   Rscript scripts/run_area.R <area> [steps]
#     <area>   directory name under config/ (e.g. neexdzii, morr)
#     [steps]  optional comma list, default "1,2,3" (network, floodplain, lulc)
#
# Reads:  config/<area>/area.yml + flood_scenarios.csv + break_points.csv
# Writes: data/<area>/ ... (aquatic_network.gpkg, floodplain.gpkg,
#                           floodplain_landcover.gpkg, subbasins.gpkg, lulc_summary.rds, ...)
#
# Architecture: the per-area config is resolved ONCE here into a single `cfg` list
# (fp_read_config) and passed explicitly to each step function. The step functions
# live in scripts/floodplain_lcc/ and each take `cfg`:
#   1 -> fp_network(cfg)      01_network_extract.R
#   2 -> fp_floodplain(cfg)   02_floodplain_model.R
#   3 -> fp_lulc(cfg)         03_lulc_classify.R
#
# Parity contract: `run_area.R neexdzii` must reproduce the known-good Neexdzii numbers
# (coho-3 network 673.5 km | floodplain co_ff04 142.8 km² | floodplain tree loss 770.0 ha)
# before any new area's numbers are trusted.
#
# RE-BASELINED 2026-09-01 under flooded 0.5.0 + link's rebuilt `fresh` network. The previous
# contract (678.2 / 171.0 / 943.13) is DEAD, not merely superseded: it was produced by a bankfull
# regression fed hectares where Hall et al. specify km² and mm where they specify cm/yr. Record
# the numbers above as a fresh contract, never as a delta from the old ones. See CLAUDE.md.

# --- fp_read_config: area name -> one cfg list carrying everything the steps need ---
`%||%` <- function(a, b) if (is.null(a)) b else a   # base R ships %||% only >= 4.4.0; define locally
fp_read_config <- function(area) {
  cfg_dir <- here::here("config", area)
  if (!dir.exists(cfg_dir)) {
    stop("no config for area '", area, "' at ", cfg_dir, call. = FALSE)
  }

  cfg <- yaml::read_yaml(file.path(cfg_dir, "area.yml"))
  cfg$scenarios    <- readr::read_csv(file.path(cfg_dir, "flood_scenarios.csv"),
                                      show_col_types = FALSE)
  # break_points.csv is OPTIONAL: present => interior sub-basins via frs_watershed_split
  # (e.g. a reach like neexdzii); absent => whole-WSG single sub-basin = the group polygon
  # (fp_floodplain uses fp_wsg_subbasin). Whole-WSG areas need no break_points.csv.
  bp_path <- file.path(cfg_dir, "break_points.csv")
  cfg$break_points <- if (file.exists(bp_path)) {
    readr::read_csv(bp_path, show_col_types = FALSE)
  } else NULL

  cfg$area    <- area
  cfg$dir_out <- here::here("data", area)
  fs::dir_create(cfg$dir_out)

  # FP_SPECIES overrides the committed area.yml species at runtime (e.g. run MORR chinook against a
  # coho-default config) WITHOUT editing the config — parallels the other FP_* overrides below.
  # Must be applied BEFORE the primary_scenario default so that default keys off the right species (#23).
  env_species <- Sys.getenv("FP_SPECIES", "")
  if (nzchar(env_species)) cfg$species <- env_species
  # primary_scenario defaults to <species>_ff04 (functional floodplain) when the config omits it;
  # FP_PRIMARY_SCENARIO overrides it at runtime (pair with FP_SPECIES, e.g. run ch_ff06).
  if (is.null(cfg$primary_scenario)) cfg$primary_scenario <- paste0(cfg$species, "_ff04")
  env_ps <- Sys.getenv("FP_PRIMARY_SCENARIO", "")
  if (nzchar(env_ps)) cfg$primary_scenario <- env_ps
  # Guard: the resolved primary_scenario must be a scenario of the selected species in the CSV,
  # else step 3 would read the wrong (or a missing) floodplain layer. Fail loud early.
  if (!nrow(cfg$scenarios[cfg$scenarios$scenario_id == cfg$primary_scenario &
                          cfg$scenarios$species == cfg$species, ])) {
    stop("primary_scenario '", cfg$primary_scenario, "' is not a '", cfg$species,
         "' scenario in config/", area, "/flood_scenarios.csv", call. = FALSE)
  }
  # tile_size: OPTIONAL area.yml key (CRS metres). Absent => cfg$tile_size is NULL =>
  # fp_lulc fetches the whole floodplain bbox (unchanged). Set it to bound the STAC
  # download to the AOI footprint on large whole-WSG floodplains (drift#36).
  # FP_TILE_SIZE env var overrides area.yml at runtime WITHOUT editing a committed config —
  # so the neexdzii parity fixture can be run tiled for the #8 benchmark and reverted by
  # unsetting the var, never risking a committed tile_size in the fixture. Empty => no override.
  env_tile <- Sys.getenv("FP_TILE_SIZE", "")
  if (nzchar(env_tile)) cfg$tile_size <- as.numeric(env_tile)
  # network_source (optional area.yml key): a schema to GRAB the accessible network from in
  # step 1 (e.g. "fresh_default"), skipping the link build; absent => build. A freshness guard
  # (fp_network) refuses a source that diverges from the bcfp reference. FP_NETWORK_SOURCE
  # overrides at runtime without editing a committed config (used to validate a source).
  env_ns <- Sys.getenv("FP_NETWORK_SOURCE", "")
  if (nzchar(env_ns)) cfg$network_source <- env_ns
  # network_guard (optional): strict (default) | warn | off — override the grab freshness
  # guard when a divergence is expected (updated crossings / different config). The
  # lnk_stamp sidecar records the override. FP_NETWORK_GUARD overrides at runtime.
  env_guard <- Sys.getenv("FP_NETWORK_GUARD", "")
  if (nzchar(env_guard)) cfg$network_guard <- env_guard
  # attribute_by (optional area.yml key): a column in the streams network to attribute the
  # floodplain by, so a delineation can answer "where is the floodplain of THIS river?" and not
  # only "of this watershed group's network" (#40). e.g. "gnis_name" (named watercourses) or
  # "blue_line_key" (every distinct watercourse). Absent => NULL => 02 skips attribution and the
  # output is unchanged -- same opt-in-by-config-presence shape as tile_size and disturbance.yml.
  # FP_ATTRIBUTE_BY overrides at runtime without editing a committed config.
  env_ab <- Sys.getenv("FP_ATTRIBUTE_BY", "")
  if (nzchar(env_ab)) cfg$attribute_by <- env_ab
  # change_interval: the [from, to] years the LULC transition (03) is measured over, and the default
  # window for disturbance attribution — one source of truth so the two can never drift (#19).
  cfg$change_interval <- cfg$change_interval %||% c(2017L, 2023L)
  # lulc_annual (optional area.yml key, logical): fetch EVERY year in change_interval rather than
  # the endpoints + midpoint (#79). Absent => NULL => 03 fetches 2017/2020/2023 as before. The
  # transition is unaffected either way -- it is measured endpoint-to-endpoint from
  # change_interval, not from the fetched set.
  #
  # ONE-WAY DOOR per area. Turning it back off leaves classified_<scen>_{2018,2019,2021,2022} in
  # floodplain_landcover.gpkg and four .tif siblings in rasters/<scen>/, describing years the
  # config no longer models. Writes have been per-layer since #23 and fp_dir is never cleaned, so
  # nothing removes them -- #55's orphan class. Prune by hand if an area is ever reverted.
  #
  # The type guard runs on the value the CONFIG carries, BEFORE the env override, so a malformed
  # committed config is caught whether or not an override is present. yaml gives TRUE for
  # true/yes/on, but a QUOTED "true" is a character vector that isTRUE() reads as off -- the area
  # would run three years under a config that reads as annual, silently.
  #
  # Keyed on `%in% names()`, NOT on `!is.null()`. `lulc_annual:` with no value, `~` and `null` all
  # parse to NULL, so an is.null() short-circuit skips the guard entirely and isTRUE(NULL) is
  # FALSE -- the same silent-off failure this guard exists to close, one shape over, reached by
  # blanking a value or commenting out the `true`. Key-present-with-null is refused; an explicit
  # `lulc_annual: false` stays legal because it is a length-1 logical.
  if ("lulc_annual" %in% names(cfg) &&
      (!is.logical(cfg$lulc_annual) || length(cfg$lulc_annual) != 1L ||
       is.na(cfg$lulc_annual))) {
    stop("area.yml lulc_annual must be a single unquoted true/false; got ",
         if (is.null(cfg$lulc_annual)) "an empty value (key present with no value, ~ or null)"
         else paste0(class(cfg$lulc_annual)[1], " of length ", length(cfg$lulc_annual), " (",
                     paste(format(cfg$lulc_annual), collapse = ", "), ")"), call. = FALSE)
  }
  # FP_LULC_ANNUAL overrides at runtime WITHOUT editing a committed config -- which is how the
  # neexdzii parity fixture is exercised annually without a flag landing in its area.yml, the same
  # reason FP_TILE_SIZE exists above. Empty => no override.
  # A CLOSED vocabulary, not a truthiness test. `%in% c("1","TRUE",...)` would read a typo
  # (FP_LULC_ANNUAL=treu) as FALSE and run three years on an area whose committed config says
  # annual -- the same silent-off failure the type guard above exists to stop, one layer out.
  #
  # NOTE it is inherited by run_region.R's children (`system2("Rscript", ...)`), so setting it for
  # a region run flips every not-yet-cached group with no trace in any area.yml -- and combined
  # with the one-way door above that is not cheaply reversible. Same shape as FP_TILE_SIZE;
  # `inputs$years` records what actually ran, so it stays diagnosable.
  #
  # The vocabulary matches what YAML 1.1 accepts for the config key (y/yes/on/true and their
  # negatives) plus R's T/F, so the two spellings of the same switch do not disagree. Trimmed,
  # because a trailing newline from a shell capture is not a typo.
  env_annual <- trimws(Sys.getenv("FP_LULC_ANNUAL", ""))
  if (nzchar(env_annual)) {
    on  <- c("1", "TRUE", "T", "YES", "Y", "ON")
    off <- c("0", "FALSE", "F", "NO", "N", "OFF")
    v   <- toupper(env_annual)
    if (!v %in% c(on, off)) {
      stop("FP_LULC_ANNUAL must be one of ", paste(tolower(c(on, off)), collapse = "/"),
           "; got '", env_annual, "'", call. = FALSE)
    }
    cfg$lulc_annual <- v %in% on
  }
  # disturbance: shared province-wide sources (config/disturbance.yml) for tagging change patches by
  # overlay layer (fire, harvest, …). Absent => NULL => 03 skips tagging (behaviour unchanged) (#19).
  dst_path <- here::here("config", "disturbance.yml")
  cfg$disturbance <- if (file.exists(dst_path)) yaml::read_yaml(dst_path)$sources else NULL
  cfg
}

# --- CLI ---
args  <- commandArgs(trailingOnly = TRUE)
area  <- args[1]
steps <- if (length(args) >= 2) strsplit(args[2], ",")[[1]] else c("1", "2", "3")

if (is.na(area)) stop("usage: Rscript scripts/run_area.R <area> [steps]", call. = FALSE)

# --- Load packages + step functions ---
update_packages <- FALSE
source(here::here("scripts", "packages.R"))
source(here::here("scripts", "fp_gpkg.R"))       # fp_gpkg_pin_date (byte-deterministic gpkg)
fp_gpkg_pin_date()                                # #45: pin gpkg_contents.last_change
lcc_dir <- here::here("scripts", "floodplain_lcc")
source(here::here("scripts", "publish_hint.R"))    # fp_publish_hint (advisory publish handoff)
source(file.path(lcc_dir, "fp_region.R"))          # fp_wsg_subbasin (whole-WSG sub-basin)
source(file.path(lcc_dir, "01_network_extract.R"))
source(file.path(lcc_dir, "02_floodplain_model.R"))
source(file.path(lcc_dir, "03_lulc_classify.R"))
source(file.path(lcc_dir, "fp_disturbance.R"))     # fp_disturbance_tag (config-driven attribution)
source(file.path(lcc_dir, "fp_provenance.R"))      # fp_prov_set (per-area run provenance, #33)

# --- Resolve config ---
cfg <- fp_read_config(area)
message("Area: ", cfg$name, " | WSG: ", cfg$watershed_group,
        " | order >= ", cfg$min_order, " | schema: ", cfg$schema,
        " | subset: ", if (is.null(cfg$subset)) "whole WSG" else "reach",
        " | steps: ", paste(steps, collapse = ","))

# --- Dispatch requested steps in order ---
if ("1" %in% steps) {
  message("\n### Step 1: network extract ###")
  fp_network(cfg)
}
if ("2" %in% steps) {
  message("\n### Step 2: floodplain model ###")
  fp_floodplain(cfg)
}
if ("3" %in% steps) {
  message("\n### Step 3: LULC classify + transition ###")
  fp_lulc(cfg)
}

message("\nDone: ", cfg$name, " (steps ", paste(steps, collapse = ","), ").")

# Advisory publish handoff (#32) — prints the stac release sequence; does not run it.
fp_publish_hint(cfg$name, steps)
