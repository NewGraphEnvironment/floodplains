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
# IDEMPOTENT BY STATE: a layer already carrying in_wsg is left alone, the composition is rebuilt unless
# it has every column and its record re-derives from it, and the patch count is set from the layer on
# disk. A run killed half way is finished by running it again with the SAME BACKUP dir -- after one
# read-write open of a gpkg it left a hot journal on (the refusal says how).
#
# DRY=1 runs every check and writes nothing. A write run needs BACKUP=<dir>: the three files are
# copied to <dir>/<area>/ first (to .part, md5-checked, renamed), and an existing backup is never
# overwritten -- it is the pre-split one, and every layer to process is read from it.
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

# ---- 0. the SOURCE: the pre-split backup, made first and never rewritten -------------------------
# Progress is read from the live files, but the WORK LIST and every input are read from the backup
# (code-check round 3). st_write(delete_layer = TRUE) drops a layer in one commit and writes it in the
# next, so a run killed between them leaves a live file with the layer simply absent -- and a list read
# from the live file would never know it had been there. The backup holds the pre-split layers, so
# "expected" cannot change while the run changes "done".
#
# The backup is complete BY CONSTRUCTION: copied to <dest>.part, md5-checked against the source, then
# renamed, so a file under the real name is a finished, verified copy and "exists" means "is good". A
# source with a SQLite sidecar is refused: a byte copy of it is not a snapshot (code-check-spatial.md).
# A DRY run makes no backup and reads the live files, which it does not change.
sidecars <- function(f) f[file.exists(paste0(f, "-journal")) | file.exists(paste0(f, "-wal")) | file.exists(paste0(f, "-shm"))]
# A killed write leaves a HOT journal. Deleting it corrupts the file; one read-write open rolls the
# interrupted write back (code-check round 4), after which the layer is either its old self or absent,
# and this script finishes the job.
if (length(sc <- sidecars(c(fpg, lcg))))
  stop(paste(basename(sc), collapse = ", "), " has a SQLite sidecar (-journal/-wal/-shm): a write was ",
       "interrupted or is in progress. If nothing is writing it, roll it back with ONE read-write open -- ",
       "`sqlite3 <file> 'pragma quick_check'` -- never by deleting the sidecar; then run this again.",
       call. = FALSE)
# The backup must be the PRE-SPLIT predecessor of the live files (code-check round 4): taken before any
# layer here carried in_wsg, and from the same step-2 and step-3 runs as the live files. A copy taken
# from a half-split live file (an interrupted run, re-run under a new BACKUP dir) would silently drop
# the layer that run lost from the work list; a backup from before a step 2 or 3 re-run would put an
# old layer back. Both are refused.
split_any <- function(g) {
  l <- grep(sprintf("^(%s_ff[0-9]+(_by_.+)?|classified_%s_[0-9]{4}|transition_%s_[0-9]{4}_[0-9]{4})$", sp, scen, scen),
            sf::st_layers(g)$name, value = TRUE)
  l[vapply(l, function(x) has_col(g, x, "in_wsg"), logical(1))]
}
same_runs <- function(bk_prov) {
  a <- jsonlite::read_json(bk_prov, simplifyVector = FALSE); b <- jsonlite::read_json(prov_path, simplifyVector = FALSE)
  identical(a[["floodplain"]], b[["floodplain"]]) &&
    identical(a[["landcover"]][[scen]][["inputs"]], b[["landcover"]][[scen]][["inputs"]])
}
bk <- if (nzchar(bk_root)) file.path(bk_root, area) else NA_character_
if (dry) {
  # The SAME work list a write run would use: the backup when there is one, else the live files.
  have_bk <- !is.na(bk) && all(file.exists(file.path(bk, basename(c(fpg, lcg, prov_path)))))
  src_fpg <- if (have_bk) file.path(bk, "floodplain.gpkg") else fpg
  src_lcg <- if (have_bk) file.path(bk, "floodplain_landcover.gpkg") else lcg
} else {
  dir.create(bk, recursive = TRUE, showWarnings = FALSE)
  for (f in c(fpg, lcg, prov_path)) {
    dest <- file.path(bk, basename(f))
    if (file.exists(dest)) { message("  backup kept: ", dest); next }
    part <- paste0(dest, ".part"); unlink(part)
    if (!file.copy(f, part, copy.date = TRUE)) stop("backup failed: ", part, call. = FALSE)
    if (!identical(unname(tools::md5sum(f)), unname(tools::md5sum(part)))) stop("backup differs: ", part, call. = FALSE)
    if (grepl("\\.gpkg$", f) && length(sp_l <- split_any(part))) {
      unlink(part)
      stop(basename(f), " already has split layers (", paste(sp_l, collapse = ", "), "), so a backup of it ",
           "now is not the pre-split one. Use the BACKUP dir the first run used.", call. = FALSE)
    }
    if (!file.rename(part, dest)) stop("backup could not be moved into place: ", dest, call. = FALSE)
  }
  message("  backup: ", bk)
  src_fpg <- file.path(bk, "floodplain.gpkg"); src_lcg <- file.path(bk, "floodplain_landcover.gpkg")
  if (length(sc <- sidecars(c(src_fpg, src_lcg))))
    stop(paste(sc, collapse = ", "), " (the backup) has a SQLite sidecar; something opened it for writing", call. = FALSE)
}
if (!identical(src_fpg, fpg)) {
  if (length(sp_l <- c(split_any(src_fpg), split_any(src_lcg))))
    stop("the backup in ", bk, " already has split layers (", paste(sp_l, collapse = ", "), ") -- it is not ",
         "the pre-split copy", call. = FALSE)
  if (!same_runs(file.path(bk, "provenance.json")))
    stop("the backup in ", bk, " is from different step-2 or step-3 runs than the live files (its ",
         "floodplain section or landcover[", scen, "].inputs differ): a step re-ran since. Re-backfill ",
         "with a fresh BACKUP dir.", call. = FALSE)
}
live_has <- function(g, l) l %in% sf::st_layers(g)$name
# The input for a layer: the LIVE layer while it exists (it is what a step last wrote), the backup's
# only when the live file has lost it -- which the checks above confine to an interrupted run of this.
input_of <- function(live_g, src_g, l) if (live_has(live_g, l)) live_g else src_g

# ---- 1. floodplain.gpkg + classified layers: split -------------------------------------------
split_lyrs <- c(
  file.path("floodplain.gpkg", grep(sprintf("^%s_ff[0-9]+(_by_.+)?$", sp), sf::st_layers(src_fpg)$name, value = TRUE)),
  file.path("floodplain_landcover.gpkg", grep(sprintf("^classified_%s_[0-9]{4}$", scen), sf::st_layers(src_lcg)$name, value = TRUE)))
src_of <- function(gl) if (dirname(gl) == "floodplain.gpkg") src_fpg else src_lcg
for (gl in split_lyrs) {
  g <- file.path(dd, dirname(gl)); l <- basename(gl)
  if (live_has(g, l) && has_col(g, l, "in_wsg")) { message(sprintf("  %-40s already split", l)); next }
  if (!live_has(g, l)) message(sprintf("  %-40s MISSING from the live file -- re-split from the backup", l))
  x <- sf::st_read(input_of(g, src_of(gl), l), layer = l, quiet = TRUE, promote_to_multi = FALSE)
  if ("in_wsg" %in% names(x)) stop(l, ": the source copy is already split -- the backup is not the pre-split one", call. = FALSE)
  y <- fp_wsg_split(x, wsg_poly)
  rel <- abs(area_m2(y) - area_m2(x)) / area_m2(x)
  if (!(rel < 1e-6)) stop(l, ": the split pieces do not conserve the layer's area (", signif(rel, 3), ")", call. = FALSE)
  message(sprintf("  %-40s split %d -> %d rows, %.1f ha outside", l, nrow(x), nrow(y),
                  area_m2(y[!y$in_wsg, ]) / 1e4))
  plan[[gl]] <- list(gpkg = g, layer = l, value = y)
}

# ---- 2. transition: re-vectorise unclipped, split, re-tag, and prove it reproduces the layer ----
trans_expected <- live_has(src_lcg, tlyr)
do_trans <- trans_expected && !(live_has(lcg, tlyr) && has_col(lcg, tlyr, "in_wsg"))
if (do_trans) {
  if (!file.exists(ttif)) stop("no ", ttif, " to re-vectorise", call. = FALSE)
  if (!live_has(lcg, tlyr)) message(sprintf("  %-40s MISSING from the live file -- rebuilt against the backup", tlyr))
  old <- sf::st_read(input_of(lcg, src_lcg, tlyr), layer = tlyr, quiet = TRUE, promote_to_multi = FALSE)
  if ("in_wsg" %in% names(old)) stop(tlyr, ": the source copy is already split -- the backup is not the pre-split one", call. = FALSE)
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
} else message(sprintf("  %-40s %s", tlyr, if (trans_expected) "already split" else "absent"))

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
need_comp <- do_trans || ((live_has(src_lcg, clyr) || trans_expected) && !comp_current())
message(sprintf("  %-40s %s", clyr, if (need_comp) "rebuild" else "current"))

# The bridge, decided from ITS OWN state (code-check round 1): fp_write_transition() writes the layer
# and then the bridge, so a run killed between them leaves a split layer beside a pre-split bridge,
# and deciding from the transition layer alone would never rebuild it.
blyr <- sub("^transition_", "patch_watercourse_", tlyr)
# With attribute_by unset there is no bridge to build, but a pre-split one left by an interrupted run
# must still go: fp_write_bridge() removes it (code-check round 4, enumeration row 5).
need_bridge <- !do_trans && trans_expected &&
  ((live_has(lcg, blyr) && !has_col(lcg, blyr, "in_wsg")) ||
     (!is.null(cfg$attribute_by) && !live_has(lcg, blyr)))
if (need_bridge) message(sprintf("  %-40s rebuild (the transition layer is split, the bridge is not)", blyr))

# The premises of every later write, BEFORE the first one (#53 plan review O1; code-check round 1): the
# composition's (fp_composition_build() checks them too, but only after the vector layers are
# rewritten) and the provenance record's (fp_prov_set_outputs() runs last).
if (need_comp) invisible(fp_composition_premise(cfg, scen))
if (trans_expected) invisible(fp_prov_outputs_premise(cfg, scen, "transition_patches"))

if (dry) { message("DRY: nothing written"); quit(status = 0) }

# ---- writes -------------------------------------------------------------------------------------
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
# Every layer the backup says should exist, present and split -- the check that catches a layer lost
# to an interrupted delete_layer write, which no other check here enumerates.
lost <- c(Filter(function(gl) { g <- file.path(dd, dirname(gl)); l <- basename(gl)
                                !(live_has(g, l) && has_col(g, l, "in_wsg")) }, split_lyrs),
          if (trans_expected && !(live_has(lcg, tlyr) && has_col(lcg, tlyr, "in_wsg"))) tlyr)
if (length(lost)) stop("after the writes, missing or unsplit: ", paste(basename(lost), collapse = ", "), call. = FALSE)
if (trans_expected) {
  n_disk <- nrow(sf::st_read(lcg, query = sprintf('SELECT patch_id FROM "%s"', tlyr), quiet = TRUE))
  fp_prov_set_outputs(cfg, scen, list(transition_patches = as.integer(n_disk)),
                      list(kind = "wsg_split", issue = 53L,
                           note = "transition layer re-vectorised unclipped and split at the group line (in_wsg); rasters unchanged",
                           toolchain = fp_toolchain()))
}
message("Done: ", area)
