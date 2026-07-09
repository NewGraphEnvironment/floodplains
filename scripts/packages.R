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
  "here", "fs", "yaml",            # utils + config
  "dplyr", "readr", "stringr"
)

pkgs_gh <- c(
  "newgraphenvironment/link",      # network extraction (>= 0.44.0 access fix)
  "newgraphenvironment/flooded",   # VCA floodplain delineation
  "newgraphenvironment/drift",     # STAC LULC classify + transition (>= 0.4.0: changes_only bounds large-floodplain memory, drift#25/#27/#34)
  "newgraphenvironment/fresh"      # falls.csv + parameter CSVs (link engine)
)

if (exists("update_packages") && isTRUE(update_packages)) {
  lapply(c(pkgs_cran, pkgs_gh), pak::pkg_install, ask = FALSE)
}

pkgs_ld <- c(pkgs_cran, basename(pkgs_gh) |> stringr::str_remove("@.*"))
invisible(lapply(pkgs_ld, require, character.only = TRUE))
