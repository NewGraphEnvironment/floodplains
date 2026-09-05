# fp_raster.R — keep written GeoTIFF CONTAINERS free of metadata that describes something else (#83).
#
# Step 3 writes classified_<yyyy>.tif from a SpatRaster that drift hands back backed by a gdalcubes
# NetCDF cube (drift's untiled fetch is terra::mask(terra::rast(<year>_<key>.nc), aoi)). On terra
# 1.9.11 the cube's CF/NetCDF attributes ride along and terra writes them into TIFF tag 42112
# (GDAL_METADATA); on 1.9.34 they are never picked up off the .nc in the first place. Measured under
# #79, where the two-machine split had already left terra as the only unlevelled package: necr and
# kotl (m4, 1.9.11) carried 30 stray tags on all seven years, bulk and lnth (m1, 1.9.34) carried
# none, and transition.tif was clean everywhere because dft_rast_transition() builds a NEW raster.
#
# TWO of the thirty CONTRADICT the file they are attached to -- data#type = float64 and
# data#_FillValue = nan on a Byte raster whose nodata is 255 -- and NC_GLOBAL#process_graph leaks
# the producing session's /tmp/Rtmp... path. stac_floodplains_bc COGs these with a CreateCopy, which
# carries source metadata through, so they reach the published assets.
#
# WHY THIS IS A PIN AND NOT A MACHINE UPGRADE: levelling m4's terra removes the symptom and leaves
# nothing behind. #65 already answered this class one field over -- 02 pins datatype = "FLT4S" so a
# terra version choosing a different on-disk type cannot move the container, and that pin was kept
# even though it measured byte-identical. This is the same argument for the raster's METADATA.
#
# It is invisible to everything else in the repo by design: fp_raster_content_sha256() (#64) digests
# cell values and geometry, so it is deliberately container-invariant and cannot see this. That is
# the right split -- "same answer?" and "same bytes?" are different questions (#65) -- but it means
# the container needs a guard of its own, which is what fp_rast_stray_tags() is.

# An ALLOWLIST, not a denylist of the thirty names observed on necr and kotl. A denylist is a fact
# about what gdalcubes 0.3.2 happened to emit, and goes stale the moment a version emits a
# differently-named tag -- which would then pass silently into a published COG. The allowlist fails
# the other way: an unrecognised tag stops the run and someone reads it. AREA_OR_POINT is GDAL's own
# pixel-is-area convention and is present on every clean raster in data/ (bulk, lnth, neexdzii,
# morr, checked), so it is the negative control, not a target.
FP_RAST_TAGS_OK <- "AREA_OR_POINT"

#' Drop every dataset-level metadata tag from a SpatRaster before it is written.
#'
#' Returns the raster; does NOT modify the caller's object. Measured on terra 1.9.34: `metags<-`
#' deepcopies before mutating, so the source stays at its original tag count and stripping cannot
#' disturb the `classified_all` list step 3's Pass 2 crops and masks. Written to return rather than
#' mutate so that stays true if a future terra changes its reference semantics.
#'
#' A full clear is deliberate, and measured rather than assumed: terra re-adds AREA_OR_POINT on
#' write, so a stripped raster lands with exactly the tag set the clean areas already carry.
#' Restoring it by hand would be a second thing to keep true.
#'
#' THE EMPTY CASE IS THE COMMON ONE, AND `metags(r) <- NULL` ERRORS ON IT. On terra 1.9.34
#' `metags()` returns `NULL` -- not a 0-row frame -- for a raster carrying no tags, and the setter
#' then dies with "incorrect number of subscripts on matrix". That is precisely the raster this
#' repo produces on 1.9.34, where `terra::rast(<gdalcubes .nc>)` yields no tags at all: an
#' unguarded strip would have aborted step 3 on every area on this machine while working fine on
#' the one machine that needed it. Caught by writing the zero-tag case, not by reading the code --
#' every raster already on disk carries AREA_OR_POINT, so no existing file can reach it.
fp_rast_strip_tags <- function(r) {
  stopifnot(inherits(r, "SpatRaster"))
  tg <- terra::metags(r)
  # NULL and a 0-row frame are both "nothing to strip", and they are different objects. Handle both
  # rather than the one this terra happens to return.
  if (!is.null(tg) && NROW(tg) > 0) terra::metags(r) <- NULL
  r
}

#' Tags on a WRITTEN raster that are outside the allowlist, by NAME.
#'
#' Names, not a count, so a failure can say which tag it found -- a count sends the reader back to
#' gdalinfo to learn what a guard already knew.
#'
#' READ THROUGH GDAL, NOT THROUGH terra. terra is the library under suspicion: the whole defect is
#' that one terra version surfaces a NetCDF's attributes and another does not, so `metags()` is the
#' one reader whose silence proves nothing. A guard built on it would report clean on exactly the
#' toolchain where the strip fails -- CLAUDE.md's "a verifier built on the writer's own library
#' shares its blind spot", in the guard written to catch that library. `sf::gdal_utils()` asks GDAL
#' directly and returns the same domain-keyed structure `gdalinfo -json` does (checked against the
#' Python sweep over all 116 tifs under data/).
#'
#' SCOPE IS THE DATASET-LEVEL, DEFAULT DOMAIN, deliberately and on measurement. IMAGE_STRUCTURE is
#' GDAL describing its own encoding (COMPRESSION, INTERLEAVE), and every classified raster -- clean
#' and dirty alike -- carries BAND-level DATE_TIME and STATISTICS_* that terra itself writes. A
#' guard reading either would fire on every correct file in the repo.
#'
#' The default-domain key is the EMPTY STRING, which `md[[""]]` does not index. Select it by
#' position or the guard silently sees no tags on every raster and passes everything.
fp_rast_stray_tags <- function(path) {
  # ERRORS on an absent file rather than returning character(0). "No file" and "a clean file" are
  # different answers, and collapsing them makes every caller read a failed write as a pass -- the
  # guard-fails-toward-pass shape, in the one function whose whole job is to refuse. Every caller
  # has a path it has either just written or just enumerated, so absence is a defect, not a state.
  if (!file.exists(path)) {
    stop("cannot read tags: ", path, " does not exist", call. = FALSE)
  }
  # READ WITH PAM DISABLED. GDAL merges a dataset-level <Metadata> block from a .aux.xml sidecar
  # into the default domain, so without this a sidecar carrying TIFFTAG_SOFTWARE=QGIS reports two
  # stray tags on a perfectly clean raster (measured). Two reasons that is the wrong answer here:
  #
  #   1. It is not FIXABLE by the thing this guard drives. raster_strip-tags.R rewrites the TIFF,
  #      which cannot remove a tag that lives in a sidecar -- so the file would be reported dirty,
  #      "repaired", and reported dirty again, forever.
  #   2. It is machine-local. CLAUDE.md's #64 block records that GDAL writes that sidecar as a
  #      side effect of anyone OPENING the file, so a PAM-sensitive guard makes a published-artifact
  #      property depend on who has looked at the raster in QGIS -- the machine dependence #64 was
  #      opened to remove, arriving one field over.
  #
  # So the subject is the TIFF's own tag 42112 and nothing else. Sidecars are untracked, gitignored
  # and excluded from the stac release sync; none of the 112 under data/ carries a dataset-level
  # block today. Restore the default by unsetting the variable if that ever needs revisiting.
  old_pam <- Sys.getenv("GDAL_PAM_ENABLED", unset = NA)
  Sys.setenv(GDAL_PAM_ENABLED = "NO")
  on.exit(if (is.na(old_pam)) Sys.unsetenv("GDAL_PAM_ENABLED")
          else Sys.setenv(GDAL_PAM_ENABLED = old_pam), add = TRUE)
  j <- sf::gdal_utils("info", path, options = c("-json"), quiet = TRUE)
  md <- jsonlite::fromJSON(j, simplifyVector = FALSE)$metadata
  if (is.null(md)) return(character(0))
  i <- which(names(md) == "")
  if (!length(i)) return(character(0))
  sort(setdiff(names(md[[i[1]]]), FP_RAST_TAGS_OK))
}

#' Write a raster with the container pinned, then MEASURE THE FILE.
#'
#' The strip and the check are one function because they are one contract. Splitting them invites a
#' future write site that strips and does not check -- the "a fix lands in one of two callers"
#' shape -- and there is no reason to want one without the other.
#'
#' It stops rather than warns. The failure it exists to catch is a toolchain that ignores the strip,
#' and the cost of continuing is a published COG carrying metadata that contradicts it; a deferred
#' warning under Rscript's default warn = 0 prints after the run's last message and is exactly what
#' a long run's output buries. Stopping on the FIRST year costs the fetch, not the publish.
#'
#' THE MESSAGE NAMES A REMEDY THAT CAN ACTUALLY UNBLOCK THE RUN. Pointing at raster_strip-tags.R
#' would be worse than silence here: that script repairs files a COMPLETED run left behind, and a
#' run aborted at the first year has written no gpkg layers, no summaries and no provenance -- so
#' repairing and re-running just aborts at the same line. The remedy for a strip that did not take
#' is the toolchain.
fp_rast_write <- function(r, path, ...) {
  terra::writeRaster(fp_rast_strip_tags(r), path, ...)
  bad <- fp_rast_stray_tags(path)
  if (length(bad)) {
    stop(basename(path), " was written with ", length(bad), " metadata tag",
         if (length(bad) > 1) "s" else "", " outside the allowlist (", paste(head(bad, 3),
         collapse = ", "), if (length(bad) > 3) ", ..." else "", ") -- the metags strip did not ",
         "take on terra ", as.character(utils::packageVersion("terra")), ". These describe the ",
         "gdalcubes cube, not this raster, and would reach the published COGs (#83). Update terra ",
         "on this machine and re-run step 3 for this area -- do NOT publish it. If the tag is a ",
         "NEW and legitimate one a later terra writes by default, the fix is FP_RAST_TAGS_OK in ",
         "scripts/fp_raster.R, not the toolchain. Note this area's rasters are now MIXED: one year ",
         "freshly written beside the previous run's, with the gpkg and provenance still describing ",
         "that earlier run.", call. = FALSE)
  }
  invisible(path)
}
