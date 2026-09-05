# raster_strip-tags.R — remove gdalcubes/NetCDF container tags from already-written rasters (#83).
#
# The writer is fixed (scripts/fp_raster.R, wired into 02 and 03), and a fix to code that writes
# data is not done until the written data is reconciled. Fourteen files are affected: seven
# classified_<yr>.tif in necr and seven in kotl, produced on m4 under terra 1.9.11, which carries a
# gdalcubes NetCDF cube's CF attributes into TIFF tag 42112. Thirty tags, two of which CONTRADICT
# the raster (data#type = float64, data#_FillValue = nan on a Byte file whose nodata is 255) and one
# of which carries the producing session's /tmp path. stac_floodplains_bc COGs these with a
# CreateCopy, so they reach the published assets.
#
# THE CATEGORY NAMES ARE NOT IN THE TIFF. They live in the `.aux.xml` PAM sidecar, and only there:
# `GDAL_PAM_ENABLED=NO gdalinfo` on an untouched classified raster shows no Categories block at all.
# stac_floodplains_bc reads the RAT from that sidecar (stac#34/#35 is the incident where an XML
# declaration in it made GDAL silently ignore the file and publish COGs with zero class labels). So
# the sidecar is part of the artefact, and a repair that moves the .tif without it destroys the
# published class names while every checksum agrees. This script renames both, and asserts the
# category names survived.
#
# That fact also corrects this issue's first measurement, which is recorded rather than quietly
# dropped: `gdal_edit.py -unsetmd` was tried, reported as destroying the RAT, and rejected for it.
# It does NOT -- re-measured with the sidecar in place, all 256 category rows and 256 palette
# entries survive and the tags go. The
# first test copied the .tif WITHOUT its sidecar and compared it against an original that had one,
# so the categories were never there to lose. A comparison whose two sides differ in something other
# than the treatment.
#
# WHY A REWRITE THROUGH terra IS STILL THE ROUTE, on the reasons that actually hold: it is the fixed
# step 3's own write path, so a repaired raster is byte-for-byte what a re-run would produce rather
# than a third thing; it uses the toolchain that wrote these files (GDAL 3.8.5 via terra) instead of
# the newer standalone GDAL 3.13.0 on PATH; it needs no `osgeo` Python bindings, which nothing else
# in this repo depends on; and it is idempotent in bytes, where every GDAL in-place variant grows
# the file ~54 kB per invocation by orphaning the TIFF directory it rewrites.
#
# THE ONE DEVIATION, and it is asserted rather than footnoted. The nodata palette entry moves
# 255: 0,0,0,0 -> 255: 255,255,255,0. Alpha is 0 both ways so nothing renders differently; it is a
# property of the round-trip, not of the strip (it survives NAflag<-, writeRaster(NAflag=) and
# re-applying the source colour table verbatim), and every published area carries the former because
# a fresh step-3 raster is masked in memory and never round-trips. The script permits that ONE line
# of band-section difference and aborts the file on any other, so the claim "only the container
# moved" is a check rather than a comment.
#
# Idempotent: it touches only files that actually carry stray tags, so a second run finds nothing.
#
# usage: Rscript scripts/floodplain_lcc/raster_strip-tags.R <area>       # repair
#        DRY=1 Rscript scripts/floodplain_lcc/raster_strip-tags.R <area> # report only

suppressMessages({library(terra); library(sf)})

# Root on THIS SCRIPT's path, not here::here(), for the same reason provenance-check.R does: under
# the worktree-per-session convention here::here() answers from the CWD's project root, and data/ is
# gitignored, so a worktree's data/ is EMPTY. A run from the wrong tree would find no rasters and
# report "nothing to repair" -- indistinguishable from "already clean", on a script whose whole
# output is a claim about what was left alone. The resolved root is printed so it is visible.
fp_root <- local({
  f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(f)) normalizePath(file.path(dirname(sub("^--file=", "", f[1])), "..", ".."),
                               mustWork = FALSE) else getwd()
})
source(file.path(fp_root, "scripts", "fp_raster.R"))
source(file.path(fp_root, "scripts", "floodplain_lcc", "fp_provenance.R"))

area <- commandArgs(TRUE)[1]
if (is.na(area)) stop("usage: Rscript raster_strip-tags.R <area>", call. = FALSE)
dry <- nzchar(Sys.getenv("DRY"))

adir <- file.path(fp_root, "data", area)
if (!dir.exists(adir)) stop("no data/ for area '", area, "' under ", fp_root, call. = FALSE)

# Every .tif this repo writes: step 3's classified + transition under rasters/<scenario>/, and
# step 2's floodplain_<scenario>.tif one level up. The first sweep written for this issue globbed
# only rasters/*/*.tif -- 112 files -- and missed the other 72, clean as they turned out, but the
# boundary was chosen by a glob rather than by what the repo writes.
tifs <- sort(c(list.files(file.path(adir, "rasters"), pattern = "\\.tif$",
                          recursive = TRUE, full.names = TRUE),
               list.files(adir, pattern = "^floodplain_.*\\.tif$", full.names = TRUE)))

message("Area: ", area, " | root ", fp_root, " | ", length(tifs), " raster",
        if (length(tifs) != 1) "s" else "", if (dry) "  [DRY: report only]" else "")
if (!length(tifs)) stop("no rasters found under ", adir, " -- nothing to sweep", call. = FALSE)

# The band section, minus the one deviation the round-trip is allowed. `Files:` names the path and
# moves with a temp copy; the palette's nodata entry is the measured, permitted difference.
band_section <- function(p) {
  g <- suppressWarnings(system2("gdalinfo", shQuote(p), stdout = TRUE, stderr = FALSE))
  i <- grep("^Band 1", g)
  if (!length(i)) return(character(0))
  g[i[1]:length(g)]
}
PALETTE_NODATA <- "^ *255: (0,0,0,0|255,255,255,0) *$"

# `flagged` counts what carries stray tags; `repaired` counts what was actually rewritten. They are
# different numbers and DRY=1 makes them differ by everything -- reporting `repaired` under DRY
# printed "Would repair 0 of 11" over a list of seven files it had just said it would repair, which
# is a preview that contradicts itself.
# Orphans from a killed run. The temp is a dot-file in the target directory, so `list.files()` below
# does not see it and nothing else would ever mention it -- #55's orphan class, self-inflicted. A
# kill between the write and the rename is not hypothetical: the kotl pass was interrupted by a
# command timeout while this was being written. Swept by an explicit pattern, never by a wildcard.
orphans <- list.files(adir, pattern = "^\\..*\\.strip[0-9]+\\.tif(\\.aux\\.xml)?$",
                      recursive = TRUE, full.names = TRUE, all.files = TRUE)
if (length(orphans)) {
  message("  ", if (dry) "would remove" else "removing", " ", length(orphans),
          " orphaned temp file(s) from an interrupted run")
  if (!dry) unlink(orphans)
}

flagged <- 0L; repaired <- 0L; clean <- 0L; failed <- character(0)

for (f in tifs) {
  stray <- fp_rast_stray_tags(f)
  if (!length(stray)) { clean <- clean + 1L; next }

  flagged <- flagged + 1L
  rel <- sub(paste0("^", adir, "/"), "", f)
  message("  ", if (dry) "would repair" else "REPAIR", ": ", rel,
          " (", length(stray), " stray: ", paste(head(stray, 2), collapse = ", "), ", ...)")
  if (dry) next

  # The content digest BEFORE. NA is a hard error, not a match: fp_raster_content_sha256() returns
  # NA_character_ for a path it cannot read, and identical(NA, NA) is TRUE -- so a broken probe on
  # both sides reports "content unchanged" and blesses whatever happened. Measured live while
  # writing this, from an unexported environment variable giving a relative path.
  sha_before <- fp_raster_content_sha256(f)
  if (is.na(sha_before)) { failed <- c(failed, rel); message("    ABORT: unreadable before edit"); next }
  band_before <- band_section(f)
  if (!length(band_before)) { failed <- c(failed, rel); message("    ABORT: no band section"); next }

  # Rewrite via a temp file in the SAME directory, then rename. An in-place overwrite that failed
  # part way would leave the published raster truncated with its only copy gone; the rename is
  # atomic on one filesystem, so the original survives until a complete, verified file exists.
  # datatype is read from the file rather than assumed -- classified is INT1U and transition INT4S,
  # and hardcoding either would silently requantise the other.
  dt  <- terra::datatype(terra::rast(f))[1]
  # The temp name must still END IN .tif -- terra guesses the driver from the extension and
  # otherwise aborts with "cannot guess file type from filename". Leading dot so a crash leaves a
  # hidden file rather than something that looks like an output, and the pid so two runs cannot
  # collide. It sits in the SAME directory as the target, which is what makes the rename atomic.
  tmp <- file.path(dirname(f), sprintf(".%s.strip%d.tif", sub("\\.tif$", "", basename(f)),
                                       Sys.getpid()))
  res <- tryCatch({
    r <- terra::rast(f)
    suppressWarnings(fp_rast_write(r, tmp, overwrite = TRUE, datatype = dt))
    ""
  }, error = function(e) conditionMessage(e))
  if (nzchar(res)) {
    unlink(c(tmp, paste0(tmp, ".aux.xml")))
    failed <- c(failed, rel); message("    ABORT: ", res); next
  }

  # VERIFY BEFORE THE RENAME, so a file that fails any check never replaces the original.
  sha_after  <- fp_raster_content_sha256(tmp)
  band_after <- band_section(tmp)
  diffs <- if (length(band_before) != length(band_after)) "band section length moved" else {
    d <- which(band_before != band_after)
    unexpected <- d[!(grepl(PALETTE_NODATA, band_before[d]) & grepl(PALETTE_NODATA, band_after[d]))]
    if (length(unexpected)) paste0(length(unexpected), " unexpected band-section line(s), first: ",
                                   trimws(band_before[unexpected[1]])) else ""
  }
  # The category names, asserted directly rather than inferred from the band-section diff -- that
  # diff compares two files each read WITH their own sidecar, so it cannot see the sidecar going
  # missing at rename time, which is exactly how they were lost once.
  cats_before <- terra::cats(terra::rast(f))[[1]]
  cats_after  <- terra::cats(terra::rast(tmp))[[1]]
  problem <-
    if (is.na(sha_after)) "content digest unreadable after rewrite"
    else if (!identical(cats_before, cats_after))
      "the band CATEGORY NAMES (the published RAT) did not survive the rewrite"
    else if (!identical(sha_before, sha_after)) "CONTENT DIGEST MOVED -- pixels or geometry changed"
    else if (nzchar(diffs)) diffs
    else if (length(fp_rast_stray_tags(tmp))) "stray tags survived the rewrite"
    else ""
  if (nzchar(problem)) {
    unlink(c(tmp, paste0(tmp, ".aux.xml")))
    failed <- c(failed, rel); message("    ABORT (original untouched): ", problem); next
  }

  # RENAME BOTH, when there are both. terra writes the band's category names into the temp file's own
  # sidecar, so for a CATEGORICAL raster the .tif and its .aux.xml are one artefact and moving only
  # the .tif strands the class labels. The first draft deleted the target's sidecar instead, on the
  # theory that it was a regenerable statistics cache -- measured after: `is.factor()` FALSE and
  # `cats()` NULL on the repaired raster, the RAT stac publishes, silently gone, content digest
  # agreeing.
  #
  # REQUIRING one unconditionally is the opposite defect and is what the first fix did. Measured:
  # fp_rast_write() writes a sidecar for the categorical rasters (classified INT1U, transition
  # INT4S) and NONE for step 2's FLT4S floodplain mask, which has no categories to record. That is
  # 72 of the 184 tifs this sweeps -- so a dirty floodplain raster would pass all four acceptance
  # checks, then abort on "the category names would be lost" for a raster that has none, and the
  # script would be structurally unable to repair the very files it walks one directory up to find.
  # Unreachable so far only because all 14 dirty files happened to be categorical.
  #
  # So the requirement follows the SOURCE: a raster that HAD categories must still have them.
  had_cats <- !is.null(cats_before)
  aux_tmp  <- paste0(tmp, ".aux.xml")
  if (had_cats && !file.exists(aux_tmp)) {
    unlink(tmp); failed <- c(failed, rel)
    message("    ABORT (original untouched): the source is categorical but terra wrote no ",
            ".aux.xml -- the category names would be lost"); next
  }
  # file.rename() RETURNS FALSE; it does not error. Unchecked, a failed rename left the file
  # reported as repaired while still carrying its 30 tags -- and the second rename then overwrote
  # the ORIGINAL's sidecar, so the failure made things worse and the summary said "left untouched".
  # Rename the sidecar FIRST: if that fails nothing has moved, and if the .tif rename then fails the
  # pair is inconsistent and is reported as exactly that rather than as a success.
  if (had_cats && !file.rename(aux_tmp, paste0(f, ".aux.xml"))) {
    unlink(c(tmp, aux_tmp)); failed <- c(failed, rel)
    message("    ABORT (original untouched): could not move the .aux.xml into place"); next
  }
  if (!file.rename(tmp, f)) {
    unlink(tmp); failed <- c(failed, rel)
    message("    ABORT: could not move the repaired .tif into place. The .tif still carries its ",
            "stray tags", if (had_cats) " and its .aux.xml has been REPLACED with the rewritten ",
            if (had_cats) "one -- inspect this file by hand" else "", "."); next
  }
  repaired <- repaired + 1L
  message("    ok: ", length(stray), " tags removed, content sha unchanged (", substr(sha_after, 1, 19), "...)")
}

message("\n", if (dry) "Would repair " else "Repaired ", if (dry) flagged else repaired,
        " of ", length(tifs), " raster", if (length(tifs) != 1) "s" else "", "; ", clean,
        " already clean", if (length(failed)) paste0("; ", length(failed), " FAILED") else "", ".")
if (length(failed)) {
  message("FAILED (left untouched): ", paste(failed, collapse = ", "))
  quit(status = 1L)
}
