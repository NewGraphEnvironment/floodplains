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

  if (is.null(cfg$primary_scenario)) cfg$primary_scenario <- "co_ff04"
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
lcc_dir <- here::here("scripts", "floodplain_lcc")
source(file.path(lcc_dir, "fp_region.R"))          # fp_wsg_subbasin (whole-WSG sub-basin)
source(file.path(lcc_dir, "01_network_extract.R"))
source(file.path(lcc_dir, "02_floodplain_model.R"))
source(file.path(lcc_dir, "03_lulc_classify.R"))

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
