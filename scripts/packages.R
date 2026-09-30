# Dependency install/load for the floodplains pipeline.
# Install runs only when update_packages is TRUE (set by the caller / runner); otherwise load.

# ensure a CRAN mirror is set (a bare Rscript has repos = "@CRAN@")
if (identical(getOption("repos")[["CRAN"]], "@CRAN@") ||
      is.null(getOption("repos")[["CRAN"]])) {
  options(repos = c(CRAN = "https://cloud.r-project.org"))
}

if (!requireNamespace("pak", quietly = TRUE)) install.packages("pak")

pkgs_cran <- c(
  "sf", "terra", "stars",          # spatial (terra >= 1.8-10 for drift's transition patches fix)
  "DBI", "RPostgres",              # fwapg
  "here", "fs", "yaml", "jsonlite", "digest",  # utils + config (jsonlite/digest: provenance, #33)
  "dplyr", "readr", "stringr"
)

pkgs_gh <- c(
  "newgraphenvironment/link",      # network extraction (>= 0.44.0 access fix)
  "newgraphenvironment/flooded",   # VCA floodplain delineation
  "newgraphenvironment/drift",     # STAC LULC classify + transition (>= 0.10.0: paged STAC fetch, #81; fp_lulc asserts this floor;
                                   #   >= 0.19.0 for dft_accuracy_* in scripts/landcover_accuracy/, #93)
  "newgraphenvironment/fresh"      # falls.csv + parameter CSVs (link engine)
)

# scripts/landcover_accuracy/ (#93) -- installed, NOT attached: the pipeline never needs them, and
# attaching rfp on every run would put its exports on the search path for nothing.
pkgs_accuracy <- c(
  "tidyhydat", "tidyr", "rstac",   # drought ranking (HYDAT), window item cross-check
  "newgraphenvironment/rfp"        # QGIS review project
)

if (exists("update_packages") && isTRUE(update_packages)) {
  lapply(c(pkgs_cran, pkgs_gh, pkgs_accuracy), pak::pkg_install, ask = FALSE)
}

pkgs_ld <- c(pkgs_cran, basename(pkgs_gh) |> stringr::str_remove("@.*"))
invisible(lapply(pkgs_ld, require, character.only = TRUE))
