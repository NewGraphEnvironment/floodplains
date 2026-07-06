#!/usr/bin/env Rscript
#
# run_area.R  —  top-level driver: run the floodplain + LULC pipeline for one area.
#
# SKELETON. The pipeline steps (scripts/floodplain_lcc/01-05) are currently the verbatim
# Neexdzii originals and are NOT yet AOI-parameterized. Generalizing them to read config
# from config/<area>/ and wiring them into this runner is the first tracked issue.
#
# Target interface:
#   Rscript scripts/run_area.R <area> [steps]
#     <area>   directory name under config/ (e.g. neexdzii, morr)
#     [steps]  optional comma list, default "1,2,3" (network, floodplain, lulc)
#
# Reads:  config/<area>/area.yml  + flood_scenarios.csv + break_points.csv
# Writes: data/<area>/ ...  (aquatic_network.gpkg, floodplain.gpkg, floodplain_landcover.gpkg, ...)
#
# Parity contract: `run_area.R neexdzii` must reproduce the known-good Neexdzii numbers
# (coho-3 network 678.2 km | floodplain co_ff04 171.0 km² | floodplain tree loss 943 ha)
# before any new area's numbers are trusted.

args <- commandArgs(trailingOnly = TRUE)
area  <- args[1]
steps <- if (length(args) >= 2) strsplit(args[2], ",")[[1]] else c("1", "2", "3")

if (is.na(area)) stop("usage: Rscript scripts/run_area.R <area> [steps]", call. = FALSE)

cfg_dir <- here::here("config", area)
if (!dir.exists(cfg_dir)) stop("no config for area '", area, "' at ", cfg_dir, call. = FALSE)

cfg <- yaml::read_yaml(file.path(cfg_dir, "area.yml"))
message("Area: ", cfg$name, " | WSG: ", cfg$watershed_group,
        " | order >= ", cfg$min_order, " | schema: ", cfg$schema)

# TODO(#1): source scripts/packages.R, then dispatch the generalized 01-05 with `cfg` +
# the per-area CSVs, writing to data/<area>/. Until 01-05 are parameterized this is a stub.
stop("run_area.R is a skeleton — see the MORR generalization issue.", call. = FALSE)
