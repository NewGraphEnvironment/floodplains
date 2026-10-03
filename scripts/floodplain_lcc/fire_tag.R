# fire_tag.R — re-tag an area's transition layers with config/disturbance.yml, in place (#19, #95).
#
# Runs fp_disturbance_tag over every `transition_<scenario>_<from>_<to>` layer WITHOUT re-running
# step 3's ~30-min STAC fetch, and writes the result back onto the SAME layer, exactly as step 3
# would have: cause columns (`sources:`), context columns (`context:`, e.g. in_wetland), lookback
# columns (`lookback:`, e.g. in_fire_prior, #103), then the item keys last. It used to write a `_disturbance` sibling, which is the orphan class #55 swept --
# the published layer never gained the new columns and the gpkg gained a layer nobody read.
#
# The name is historical (it began as the fire-only prototype); it tags whatever the yml lists.
#
# Because the write REPLACES a published layer, it compares before it writes. Re-tagging must not
# move a cause: if any `sources:` column would change -- a reloaded cutblock table, a new source --
# the layer is left alone and the differing columns are named. The geometry is never rewritten. FORCE=1 writes anyway. Context and lookback columns are free to change; adding them is the point.
#
# The change window is read from the layer name's `_<from>_<to>` suffix, which step 3 wrote from
# cfg$change_interval, so a re-tag windows the causes the way the run that made the layer did.
#
# usage: Rscript scripts/floodplain_lcc/fire_tag.R <area> [scenario]
#        FORCE=1 Rscript scripts/floodplain_lcc/fire_tag.R <area> [scenario]

suppressMessages({library(sf); library(DBI); library(RPostgres); library(yaml)})
sf::sf_use_s2(FALSE)
source(here::here("scripts", "floodplain_lcc", "fp_disturbance.R"))
source(here::here("scripts", "fp_gpkg.R"))       # standalone CLI: not covered by run_area.R
fp_gpkg_pin_date()                                # #45

ITEM_KEYS <- c("wsg", "species", "scenario")

fire_tag_main <- function(area, scenario = NA, force = FALSE) {
  gpkg <- here::here("data", area, "floodplain_landcover.gpkg")
  if (!file.exists(gpkg)) stop("no gpkg: ", gpkg, call. = FALSE)

  if (!is.na(scenario) && !grepl("^[a-z0-9_]+$", scenario))
    stop("scenario must be a scenario id such as co_ff04, got: ", scenario, call. = FALSE)
  pat  <- sprintf("^transition_(%s)_([0-9]{4})_([0-9]{4})$",
                  if (is.na(scenario)) "[a-z0-9_]+" else scenario)
  lyrs <- grep(pat, sf::st_layers(gpkg)$name, value = TRUE)
  if (!length(lyrs)) stop("no transition layer matching ", pat, " in ", gpkg, call. = FALSE)

  dst     <- fp_disturbance_validate(yaml::read_yaml(here::here("config", "disturbance.yml")))
  entries <- c(dst[["sources"]], dst[["context"]], dst[["lookback"]])
  nms     <- function(x) paste(vapply(x, function(s) s[["name"]], character(1)), collapse = ",")
  cause_cols <- unlist(lapply(dst[["sources"]], function(s) c(paste0("in_", s[["name"]]), unlist(s[["carry"]]))))
  # Lookback columns may move -- `lookback: 15` is a number #93 may revisit, and fire_load-prior.sh
  # documents a delete-and-reload -- but once published, a move is REPORTED, never silent.
  lb_cols <- unlist(lapply(dst[["lookback"]], function(s) c(paste0("in_", s[["name"]]), unlist(s[["carry"]]))))

  conn <- DBI::dbConnect(RPostgres::Postgres())
  on.exit(DBI::dbDisconnect(conn), add = TRUE)   # inside a function, so it fires

  refused <- character(0)
  for (tlyr in lyrs) {
    yrs <- as.integer(regmatches(tlyr, regexec(pat, tlyr))[[1]][3:4])
    cat(sprintf("\narea=%s  layer=%s  window=%d-%d  sources=%s  context=%s  lookback=%s\n",
                area, tlyr, yrs[1], yrs[2], nms(dst[["sources"]]), nms(dst[["context"]]),
                nms(dst[["lookback"]])))

    # promote_to_multi = FALSE: step 3 writes a MIX of POLYGON and MULTIPOLYGON (declared GEOMETRY),
    # and st_read's default promotes every POLYGON on read. Written back, that re-declared the layer
    # MULTIPOLYGON and rewrote 3,947 of NECR's 5,692 geometries (5,024 of BULK's 7,161).
    tr     <- sf::st_read(gpkg, layer = tlyr, quiet = TRUE, promote_to_multi = FALSE)
    tagged <- fp_disturbance_tag(tr, entries, conn, window = yrs)
    # Keep the PUBLISHED geometry. The tagger intersects on st_make_valid() output, and that rewrites
    # every geometry even when none is invalid -- measured on NECR: 0 of 5,692 invalid, all 5,692
    # rewritten (ring normalisation, some MULTIPOLYGON -> POLYGON), areas unchanged. Step 3 does that
    # once before its first write; a re-tag has no business doing it again. Rows keep their order.
    stopifnot(nrow(tagged) == nrow(tr))
    sf::st_geometry(tagged) <- sf::st_geometry(tr)
    keys   <- intersect(ITEM_KEYS, names(tagged))
    tagged <- tagged[, c(setdiff(names(tagged), c(keys, attr(tagged, "sf_column"))), keys)]

    # What a re-tag must not move: every cause column. (Geometry cannot move -- it is the published
    # geometry by construction, above; disturbance-check.R compares it as WKB before and after.)
    moved <- cause_cols[!vapply(cause_cols, function(k) fp_same_values(tr[[k]], tagged[[k]]), logical(1))]
    if (length(moved) && !force) {
      cat(sprintf("  REFUSED: re-tagging would change %s -- layer left as it was (FORCE=1 to write)\n",
                  paste(moved, collapse = ", ")))
      refused <- c(refused, tlyr)
      next
    }
    if (length(moved)) cat(sprintf("  FORCE: writing despite changes to %s\n", paste(moved, collapse = ", ")))
    lb_had   <- intersect(lb_cols, names(tr))
    lb_moved <- lb_had[!vapply(lb_had, function(k) fp_same_values(tr[[k]], tagged[[k]]), logical(1))]
    if (length(lb_moved))
      cat(sprintf("  NOTE: published lookback column(s) change: %s (lookback years or the fire table moved)\n",
                  paste(lb_moved, collapse = ", ")))

    sf::st_write(tagged, gpkg, layer = tlyr, append = TRUE, delete_layer = TRUE, quiet = TRUE)
    cat(sprintf("  wrote layer: %s (%d patches)\n", tlyr, nrow(tagged)))

    fp_disturbance_report(tagged, dst[["sources"]], area, lookback = dst[["lookback"]])
    for (s in dst[["context"]]) {
      hit <- tagged[[paste0("in_", s[["name"]])]] %in% TRUE
      # Patches TOUCHING the overlay, and their whole area. in_<name> is any-touch, so this is not
      # "ha in the ALR/wetland" -- that is the composition table's number (#108), counted per cell.
      cat(sprintf(" context in_%-10s: %d patches touching, %.1f ha of patch (any-touch, not an area share)\n",
                  s[["name"]], sum(hit), sum(tagged[["area_ha"]][hit])))
    }
  }
  if (length(refused))
    stop(length(refused), " layer(s) refused: ", paste(refused, collapse = ", "), call. = FALSE)
}

a <- commandArgs(TRUE)
if (is.na(a[1])) stop("usage: Rscript fire_tag.R <area> [scenario]", call. = FALSE)
fire_tag_main(a[1], a[2], force = identical(Sys.getenv("FORCE"), "1"))
