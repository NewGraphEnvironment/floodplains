# fp_gpkg.R — make GeoPackage writes byte-deterministic (#45).
#
# GDAL stamps gpkg_contents.last_change with wall-clock time at write, so two writes of IDENTICAL
# data produce different bytes. Two costs: a rerun is indistinguishable from a change, and
# `file:checksum` on the published assets would churn every build regardless of content — noise
# where provenance is wanted. GeoPackage is 72% of the published bucket by size, so this is most of
# the catalogue.
#
# The stamp is pinned to a FIXED EPOCH, deliberately carrying no information. Deriving it from a
# run value (config hash, source date) would keep the field meaningful but reintroduce churn the
# moment a config field changes without changing the output, encoded so no consumer can decode it.
# Run provenance belongs to the run record (#33) and the STAC properties, not to a SQLite
# housekeeping column nothing queries.
#
# WHY AN ENV VAR and not `st_write(config_options = )` at each call: GDAL reads config options from
# the environment, so one call here covers every write in the process — all 13 current st_write
# sites, st_delete, and any added later. Per-call arguments are silently incomplete the moment
# someone adds the 14th. Measured on data/morr/floodplain.gpkg: without the pin two writes of the
# same layer differ; with it they are byte-identical.
#
# SCOPE OF THE GUARANTEE: a full rebuild into an ABSENT file is byte-reproducible. Rewriting one
# layer into an EXISTING gpkg is not — SQLite free-page state differs from a fresh insert, and the
# pin cannot reach that. See scripts/floodplain_lcc/gpkg_determinism-check.R.
#
# GeoTIFF output (terra::writeRaster) was measured deterministic already and needs nothing.

# The pinned value. Any fixed instant works; this is the one #45 verified.
FP_GPKG_EPOCH <- "2000-01-01T00:00:00.000Z"

fp_gpkg_pin_date <- function(quiet = TRUE) {
  Sys.setenv(OGR_CURRENT_DATE = FP_GPKG_EPOCH)
  if (!quiet) message("GeoPackage timestamps pinned to ", FP_GPKG_EPOCH, " (#45)")
  invisible(FP_GPKG_EPOCH)
}
