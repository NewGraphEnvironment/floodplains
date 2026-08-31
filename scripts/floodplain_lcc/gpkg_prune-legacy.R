# gpkg_prune-legacy.R — remove obsolete transition layers left behind by a rename (#55).
#
# floodplain_landcover.gpkg can carry THREE transition layers for one scenario, two of them stale,
# with no way for a consumer to tell which is live:
#
#   transition_<scenario>_<span>                current -- carries in_fire + in_harvest
#   transition_<scenario>_<span>_disturbance    legacy
#   transition_<scenario>_<span>_fire           legacy
#
# Disturbance attribution used to write a separate `_disturbance` layer (and fire_tag.R a `_fire`
# one); it now writes those columns onto the main transition layer. The old names were never
# removed, and NOTHING removes them: #23 made writes per-layer (append = file.exists +
# delete_layer = TRUE) precisely so a second species does not wipe the first, which means a layer
# whose NAME goes obsolete is never cleaned up. Correct for coexistence, and it strands orphans
# behind a rename -- so this is the flip side of a deliberate decision, not a bug in it, and it
# wants an explicit sweep rather than a change to the write path.
#
# Deliberately NOT automatic on every run. A script that deletes layers it does not recognise is a
# worse hazard than the orphans it cleans, so it removes only names matching an explicit pattern and
# reports everything it leaves alone.
#
# Idempotent: a second run finds nothing and says so.
#
# usage: Rscript scripts/floodplain_lcc/gpkg_prune-legacy.R <area>       # prune
#        DRY=1 Rscript scripts/floodplain_lcc/gpkg_prune-legacy.R <area> # report only

suppressMessages({library(sf)})
sf::sf_use_s2(FALSE)

area <- commandArgs(TRUE)[1]
if (is.na(area)) stop("usage: Rscript gpkg_prune-legacy.R <area>", call. = FALSE)
dry <- nzchar(Sys.getenv("DRY"))

gpkg <- here::here("data", area, "floodplain_landcover.gpkg")
if (!file.exists(gpkg)) stop("no floodplain_landcover.gpkg for area '", area, "'", call. = FALSE)

# The ONLY names this script will remove. A transition layer named anything else -- including a
# suffix invented later -- is left alone and reported, so the failure mode is "did not clean up"
# rather than "deleted something it did not understand".
LEGACY <- "^transition_.*_[0-9]{4}_[0-9]{4}_(fire|disturbance)$"

lyrs   <- sf::st_layers(gpkg)$name
legacy <- grep(LEGACY, lyrs, value = TRUE)
kept   <- setdiff(lyrs, legacy)

message("Area: ", area, " | ", basename(gpkg), " | ", length(lyrs), " layers",
        if (dry) "  [DRY: report only]" else "")

if (length(legacy) == 0) {
  message("  nothing to prune — no legacy transition layers present.")
} else {
  for (l in legacy) {
    n <- tryCatch(nrow(sf::st_read(gpkg, layer = l, quiet = TRUE)), error = function(e) NA_integer_)
    message("  ", if (dry) "would remove" else "REMOVE", ": ", l,
            if (!is.na(n)) paste0(" (", n, " rows)") else "")
    if (!dry) sf::st_delete(gpkg, layer = l, quiet = TRUE)
  }
}

# Say what survived, not just what went: the point of the sweep is that exactly one transition layer
# per scenario per span remains, and that is only checkable by looking at what is left.
cur <- grep("^transition_.*_[0-9]{4}_[0-9]{4}$", kept, value = TRUE)
message("  kept ", length(kept), " layer(s); current transition layer(s): ",
        if (length(cur)) paste(cur, collapse = ", ") else "NONE")
if (!dry && length(legacy)) {
  after <- sf::st_layers(gpkg)$name
  still <- grep(LEGACY, after, value = TRUE)
  if (length(still)) {
    stop("prune did not take: ", paste(still, collapse = ", "), call. = FALSE)
  }
  message("  verified: ", length(after), " layers remain, 0 legacy.")
}
