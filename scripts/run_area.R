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
# (coho-3 network 678.2 km | floodplain co_ff04 171.0 km² | floodplain tree loss 943 ha)
# before any new area's numbers are trusted.

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
