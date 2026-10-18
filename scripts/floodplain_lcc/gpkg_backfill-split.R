# gpkg_backfill-split.R — bring an area's published outputs onto the group line (#53, #138).
#
# Step 2 and step 3 now split every layer along the watershed group polygon (in_wsg), stop clipping
# change patches to the sub-basins, and tag open water (in_open_water). This puts outputs written
# before that onto the same footing WITHOUT a VCA run or a STAC fetch, through the same functions the
# steps call, so a backfilled area and a re-run one cannot differ:
#
#   floodplain.gpkg            <sp>_ffNN and <sp>_ffNN_by_<key>     split (fp_wsg_split)
#   floodplain_landcover.gpkg  classified_<scen>_<yr>               split (fp_wsg_split)
#                              transition_<scen>_<span>             re-vectorised from transition.tif,
#                                                                   unclipped, split, re-tagged
#                                                                   (fp_transition_patches)
#                              patch_watercourse_<scen>_<span>      rebuilt (fp_write_transition)
#                              composition_<scen>_<span>            rebuilt (fp_composition_build)
#   provenance.json            landcover[<scen>].outputs.transition_patches -> the layer's rows
#                              (fp_prov_set_outputs), plus the composition sibling
#
# Only the area's own species (area.yml) is touched: the species items were retired by
# stac_floodplains_bc v2.0.0, and pruning their files is #131.
#
# REFUSES BEFORE ANY WRITE unless the re-vectorised patches reproduce the published ones: every
# published (name_basin, patch_id) present, the pieces of each summing to its area_ha (1e-6
# relative), and every cause column holding the published values (fp_same_values). A cause column
# that moves means the fire or cutblock table changed since step 3, which this must not publish
# silently -- FORCE=1 writes anyway, as fire_tag.R's does. Context and lookback columns may move
# (in_open_water is new; a context table reloaded is reported).
#
# IDEMPOTENT BY STATE: a layer already carrying in_wsg is left alone, the composition is rebuilt only
# when it lacks in_wsg or a configured context column, and the patch count is set from the layer on
# disk -- so a run killed half way is finished by running it again.
#
# DRY=1 runs every check and writes nothing. A write run needs BACKUP=<dir>: the three files are
# copied to <dir>/<area>/ first, and an existing backup is never overwritten (it is the pre-split one).
# Use a durable path -- the 2026-10-18 sweep used data/backup/20261018_wsg_split (gitignored).
#
# Standalone CLI: pins the gpkg date itself (#45). Then run wsg_split-check.R <area> with
# FP_SPLIT_BACKUP=<dir>/<area>, composition-check.R, provenance-check.R, bridge-check.R.
#
# usage: BACKUP=<dir> Rscript scripts/floodplain_lcc/gpkg_backfill-split.R <area>
#        DRY=1        Rscript scripts/floodplain_lcc/gpkg_backfill-split.R <area>

suppressMessages({library(sf); library(terra); library(yaml)})
sf::sf_use_s2(FALSE)
`%||%` <- function(a, b) if (is.null(a)) b else a
lcc <- here::here("scripts", "floodplain_lcc")
source(here::here("scripts", "fp_gpkg.R"))
source(here::here("scripts", "fp_raster.R"))
for (f in c("fp_provenance.R", "fp_disturbance.R", "fp_region.R", "fp_wsg.R", "fp_lulc_vectors.R",
            "fp_composition.R")) source(file.path(lcc, f))
fp_gpkg_pin_date()

a <- commandArgs(TRUE)
area <- a[1]
if (is.na(area) || !grepl("^[a-z0-9_]+$", area)) stop("usage: gpkg_backfill-split.R <area>", call. = FALSE)
dry   <- identical(Sys.getenv("DRY"), "1")
force <- identical(Sys.getenv("FORCE"), "1")
bk_root <- Sys.getenv("BACKUP", "")
if (!dry && !nzchar(bk_root)) stop("a write run needs BACKUP=<dir> (or DRY=1 to preview)", call. = FALSE)

cfg_dir <- here::here("config", area)
if (!dir.exists(cfg_dir)) stop("no config for area '", area, "'", call. = FALSE)
cfg <- yaml::read_yaml(file.path(cfg_dir, "area.yml"))
cfg$area <- area; cfg$name <- cfg$name %||% area
cfg$dir_out <- here::here("data", area)
cfg$change_interval <- cfg$change_interval %||% c(2017L, 2023L)
cfg$primary_scenario <- cfg$primary_scenario %||% paste0(cfg$species, "_ff04")
dst <- fp_disturbance_validate(yaml::read_yaml(here::here("config", "disturbance.yml")))
cfg$disturbance <- dst[["sources"]]; cfg$context_overlays <- dst[["context"]]
cfg$lookback_overlays <- dst[["lookback"]]
scen <- cfg$primary_scenario; sp <- cfg$species
yrs  <- sort(as.integer(cfg$change_interval))

dd   <- cfg$dir_out
fpg  <- file.path(dd, "floodplain.gpkg")
lcg  <- file.path(dd, "floodplain_landcover.gpkg")
prov_path <- file.path(dd, "provenance.json")
for (f in c(fpg, lcg, prov_path, file.path(dd, "subbasins.gpkg")))
  if (!file.exists(f)) stop("missing ", f, call. = FALSE)
tlyr <- sprintf("transition_%s_%d_%d", scen, yrs[1], yrs[2])
clyr <- sprintf("composition_%s_%d_%d", scen, yrs[1], yrs[2])
ttif <- file.path(dd, "rasters", scen, "transition.tif")

message(sprintf("backfill-split: area=%s wsg=%s species=%s scenario=%s%s%s", area, cfg$watershed_group,
                sp, scen, if (dry) " DRY" else "", if (force) " FORCE" else ""))
conn <- DBI::dbConnect(RPostgres::Postgres())
on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)
wsg_poly <- fp_wsg_polygon(cfg, conn)
message("  group polygon from ", if (isTRUE(attr(wsg_poly, "zones_are_wsg"))) "subbasins.gpkg" else "fwapg")

has_col <- function(g, l, col) col %in% names(sf::st_read(g, query = sprintf('SELECT * FROM "%s" LIMIT 0', l), quiet = TRUE))
area_m2 <- function(x) sum(as.numeric(sf::st_area(x)))
plan <- list()   # name -> list(gpkg, layer, value) for the vector writes

# ---- 1. floodplain.gpkg + classified layers: split -------------------------------------------
split_lyrs <- c(
  file.path("floodplain.gpkg", grep(sprintf("^%s_ff[0-9]+(_by_.+)?$", sp), sf::st_layers(fpg)$name, value = TRUE)),
  file.path("floodplain_landcover.gpkg", grep(sprintf("^classified_%s_[0-9]{4}$", scen), sf::st_layers(lcg)$name, value = TRUE)))
for (gl in split_lyrs) {
  g <- file.path(dd, dirname(gl)); l <- basename(gl)
  if (has_col(g, l, "in_wsg")) { message(sprintf("  %-40s already split", l)); next }
  x <- sf::st_read(g, layer = l, quiet = TRUE, promote_to_multi = FALSE)
  y <- fp_wsg_split(x, wsg_poly)
  rel <- abs(area_m2(y) - area_m2(x)) / area_m2(x)
  if (!(rel < 1e-6)) stop(l, ": the split pieces do not conserve the layer's area (", signif(rel, 3), ")", call. = FALSE)
  message(sprintf("  %-40s split %d -> %d rows, %.1f ha outside", l, nrow(x), nrow(y),
                  area_m2(y[!y$in_wsg, ]) / 1e4))
  plan[[gl]] <- list(gpkg = g, layer = l, value = y)
}

# ---- 2. transition: re-vectorise unclipped, split, re-tag, and prove it reproduces the layer ----
do_trans <- tlyr %in% sf::st_layers(lcg)$name && !has_col(lcg, tlyr, "in_wsg")
if (do_trans) {
  if (!file.exists(ttif)) stop("no ", ttif, " to re-vectorise", call. = FALSE)
  old <- sf::st_read(lcg, layer = tlyr, quiet = TRUE, promote_to_multi = FALSE)
  # The sub-basins exactly as step 3 read them -- transformed to 4326 first, then to the patch CRS --
  # because a different transform chain moves the intersection in the last digits.
  sb <- sf::st_read(file.path(dd, "subbasins.gpkg"), quiet = TRUE) |> sf::st_transform(4326)
  new <- fp_transition_patches(terra::rast(ttif), sb, wsg_poly, cfg, scen, conn)
  # Reproduction, by the published key. A whole-WSG area's inside rows are drift's own intersection
  # (identical areas); a subset area's sub-basin pieces may be re-noded by the group line, so the
  # comparison is per key, summed, to 1e-6 relative.
  k_old <- paste(old$name_basin, old$patch_id, sep = "¦")
  inb <- !is.na(new$name_basin)
  k_new <- paste(new$name_basin, new$patch_id, sep = "¦")[inb]
  a_new <- tapply(new$area_ha[inb], k_new, sum)
  miss <- setdiff(k_old, names(a_new)); extra <- setdiff(names(a_new), k_old)
  if (length(miss) || length(extra) || anyDuplicated(k_old))
    stop(tlyr, ": re-vectorising does not reproduce the published patch keys (", length(miss), " missing, ",
         length(extra), " new inside a sub-basin) -- transition.tif is not the raster this layer came from",
         call. = FALSE)
  rel <- abs(a_new[k_old] - old$area_ha) / pmax(old$area_ha, 1e-12)
  if (any(rel > 1e-6))
    stop(tlyr, ": ", sum(rel > 1e-6), " patches re-vectorise to a different area (max ", signif(max(rel), 3),
         " relative)", call. = FALSE)
  # A whole-WSG area's inside rows are drift's own intersection, so they must be the published rows to
  # the BYTE, in order -- area to 1e-6 would wave through a re-noded geometry (#53 plan review, A1).
  # FORCE does not reach this gate: it overrides a moved cause column, never a different patch.
  if (isTRUE(attr(wsg_poly, "zones_are_wsg"))) {
    wkb <- function(x) vapply(sf::st_as_binary(sf::st_geometry(x)), function(r) paste(r, collapse = ""), "")
    nin <- new[inb, ]
    if (nrow(nin) != nrow(old) || !identical(wkb(nin), wkb(old)) ||
        !identical(paste(nin$name_basin, nin$patch_id), paste(old$name_basin, old$patch_id)))
      stop(tlyr, ": the inside rows are not the published rows byte for byte (", nrow(nin), " vs ", nrow(old),
           " rows) -- this toolchain does not reproduce step 3's vectorisation", call. = FALSE)
  } else {
    message(sprintf("  sub-basins reach %.2f ha outside %s (drawn separately from the group polygon)",
                    attr(new, "subbasins_outside_wsg_m2") / 1e4, cfg$watershed_group))
  }
  tag_of <- function(e) c(paste0("in_", e$name), unlist(e$carry))
  cause_cols <- unlist(lapply(dst[["sources"]], tag_of))
  # Values per key: the first piece of each published patch inside its sub-basin.
  first <- match(k_old, paste(new$name_basin, new$patch_id, sep = "¦"))
  # Over the columns the published layer HAS: one it lacks is new (reported), not moved.
  cmp <- function(cols) { cols <- intersect(cols, names(old))
    cols[!vapply(cols, function(k) fp_same_values(old[[k]], new[[k]][first]), logical(1))] }
  added <- setdiff(names(new), c(names(old), "in_wsg", attr(new, "sf_column")))
  if (length(added)) message("  new column(s) on the patches: ", paste(added, collapse = ", "))
  moved <- cmp(cause_cols)
  if (length(moved) && !force)
    stop(tlyr, ": re-tagging would change cause column(s) ", paste(moved, collapse = ", "),
         " -- the fire or cutblock table has moved since step 3. FORCE=1 writes anyway.", call. = FALSE)
  if (length(moved)) message("  FORCE: writing despite changes to ", paste(moved, collapse = ", "))
  om <- cmp(unlist(lapply(c(dst[["context"]], dst[["lookback"]]), tag_of)))
  if (length(om)) message("  NOTE: context/lookback column(s) change on published patches: ", paste(om, collapse = ", "))
  message(sprintf("  %-40s %d patches -> %d pieces (%d outside, %.1f ha); inside %.4f ha = published %.4f ha",
                  tlyr, nrow(old), nrow(new), sum(!new$in_wsg), sum(new$area_ha[!new$in_wsg]),
                  sum(new$area_ha[inb]), sum(old$area_ha)))
} else message(sprintf("  %-40s %s", tlyr, if (tlyr %in% sf::st_layers(lcg)$name) "already split" else "absent"))

# The composition is TWO writes -- the table, then its provenance sibling -- so "current" needs both
# (code-check round 2): the columns this backfill adds, AND a sibling record whose digest and row count
# re-derive from the table on disk. A run killed between the two leaves a complete table beside a stale
# record, and reading the table alone would call it current forever.
comp_current <- function() {
  if (!clyr %in% sf::st_layers(lcg)$name) return(FALSE)
  want <- c("in_wsg", paste0("in_", vapply(cfg$context_overlays, function(s) s$name, character(1))))
  if (!all(vapply(want, function(c) has_col(lcg, clyr, c), logical(1)))) return(FALSE)
  rec <- fp_prov_read(cfg)[["landcover"]][[scen]][["composition"]][["outputs"]]
  tab <- sf::st_read(lcg, layer = clyr, quiet = TRUE)
  !is.null(rec) && identical(rec[["table_content_sha256"]], fp_composition_digest(tab)) &&
    identical(as.integer(rec[["rows"]]), nrow(tab))
}
need_comp <- do_trans || ((clyr %in% sf::st_layers(lcg)$name || tlyr %in% sf::st_layers(lcg)$name) && !comp_current())
message(sprintf("  %-40s %s", clyr, if (need_comp) "rebuild" else "current"))

# The bridge, decided from ITS OWN state (code-check round 1): fp_write_transition() writes the layer
# and then the bridge, so a run killed between them leaves a split layer beside a pre-split bridge,
# and deciding from the transition layer alone would never rebuild it.
blyr <- sub("^transition_", "patch_watercourse_", tlyr)
need_bridge <- !do_trans && !is.null(cfg$attribute_by) && tlyr %in% sf::st_layers(lcg)$name &&
  has_col(lcg, tlyr, "in_wsg") && (!blyr %in% sf::st_layers(lcg)$name || !has_col(lcg, blyr, "in_wsg"))
if (need_bridge) message(sprintf("  %-40s rebuild (the transition layer is split, the bridge is not)", blyr))

# The premises of every later write, BEFORE the first one (#53 plan review O1; code-check round 1): the
# composition's (fp_composition_build() checks them too, but only after the vector layers are
# rewritten) and the provenance record's (fp_prov_set_outputs() runs last).
if (need_comp) invisible(fp_composition_premise(cfg, scen))
if (tlyr %in% sf::st_layers(lcg)$name) invisible(fp_prov_outputs_premise(cfg, scen, "transition_patches"))

if (dry) { message("DRY: nothing written"); quit(status = 0) }

# ---- writes -------------------------------------------------------------------------------------
bk <- file.path(bk_root, area); dir.create(bk, recursive = TRUE, showWarnings = FALSE)
for (f in c(fpg, lcg, prov_path)) {
  dest <- file.path(bk, basename(f))
  if (file.exists(dest)) { message("  backup kept: ", dest); next }
  if (!file.copy(f, dest, copy.date = TRUE)) stop("backup failed: ", dest, call. = FALSE)
  if (!identical(unname(tools::md5sum(f)), unname(tools::md5sum(dest)))) stop("backup differs: ", dest, call. = FALSE)
}
message("  backup: ", bk)

for (p in plan) {
  sf::st_write(p$value, p$gpkg, layer = p$layer, append = TRUE, delete_layer = TRUE, quiet = TRUE)
  if (nrow(sf::st_read(p$gpkg, layer = p$layer, quiet = TRUE)) != nrow(p$value))
    stop("FEATURE COUNT CHANGED on write for ", p$layer, call. = FALSE)
}
if (do_trans) {
  n <- fp_write_transition(new, cfg, scen, tlyr, lcg, fpg)
  if (nrow(sf::st_read(lcg, layer = tlyr, quiet = TRUE)) != n) stop("FEATURE COUNT CHANGED on write for ", tlyr, call. = FALSE)
}
if (need_bridge) fp_write_bridge(sf::st_read(lcg, layer = tlyr, quiet = TRUE, promote_to_multi = FALSE),
                                 cfg, scen, tlyr, lcg, fpg)
if (need_comp) invisible(fp_composition_build(cfg, scen, conn))

# The patch count, from the layer ON DISK (state, not this run's memory), so a re-run after a crash
# between the layer write and here still lands it.
if (tlyr %in% sf::st_layers(lcg)$name && has_col(lcg, tlyr, "in_wsg")) {
  n_disk <- nrow(sf::st_read(lcg, query = sprintf('SELECT patch_id FROM "%s"', tlyr), quiet = TRUE))
  fp_prov_set_outputs(cfg, scen, list(transition_patches = as.integer(n_disk)),
                      list(kind = "wsg_split", issue = 53L,
                           note = "transition layer re-vectorised unclipped and split at the group line (in_wsg); rasters unchanged",
                           toolchain = fp_toolchain()))
}
message("Done: ", area)
