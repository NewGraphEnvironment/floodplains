#!/usr/bin/env Rscript
#
# fp_provenance.R  —  the per-area run-provenance record (#33)
#
# Writes data/<area>/provenance.json: one machine-readable block per area recording WHAT PRODUCED
# the floodplain products. Without it, a published `gross_loss_ha` cannot be traced to the link
# config, the package versions, or -- the sharp edge -- the landcover raster it came from.
# `io-lulc-annual-v02` is a REMOTE Planetary Computer collection that can be reprocessed upstream,
# and drift caches by request hash, so a stale local cache keeps serving the old raster while a
# fresh machine silently gets the new one. Consumed by stac_floodplains_bc (#17) as STAC item
# properties; the coupling stays one-way (that repo PULLS, this one never calls it).
#
# SHAPE -- one file, three sections, each written by the step that knows the facts:
#
#   { "area", "wsg", "schema_version",
#     "network":    { "<sp><order>": { inputs, link_log, run } },
#     "floodplain": { "<scenario>":  { inputs, run } },
#     "landcover":  { "<scenario>":  { inputs, run } } }
#
# Steps run INDEPENDENTLY (`run_area.R morr 3` is normal) and key differently -- step 1 by
# species+order, steps 2/3 by scenario. So each step read-modify-writes only its own section; a
# single writer at the end of run_area.R would have to blank or fabricate the steps that did not
# run.
#
# inputs vs run is the load-bearing split, inherited from #52: `inputs` is a function of the
# INPUTS and must be byte-stable across reruns; `run` is the run EVENT and is free to vary. It is
# what makes the acceptance criterion ("re-running with an unchanged config reproduces the same
# values") checkable at all -- a whole-file comparison could never pass with a timestamp in it.
# provenance-check.R enforces the split, so it is a control and not a convention.

`%||%` <- function(a, b) if (is.null(a)) b else a

FP_PROV_SCHEMA_VERSION <- 1L

fp_prov_path <- function(cfg) file.path(cfg$dir_out, "provenance.json")

# --- Read ------------------------------------------------------------------------------------
# Returns an empty skeleton when absent. Guards on NON-EMPTY, not existence: `cmd > file`
# truncates before the command runs, so a crashed writer can leave a 0-byte file that an
# existence check would bless forever. A corrupt file is reported, never silently discarded --
# losing a prior species' section to a parse error is exactly the damage #23 was about.
fp_prov_read <- function(cfg) {
  path <- fp_prov_path(cfg)
  empty <- list(area = cfg$area, wsg = cfg$watershed_group,
                schema_version = FP_PROV_SCHEMA_VERSION,
                network = list(), floodplain = list(), landcover = list())
  if (!file.exists(path) || file.size(path) == 0) return(empty)
  got <- tryCatch(
    jsonlite::read_json(path, simplifyVector = FALSE),
    error = function(e) {
      stop("provenance.json at ", path, " is unreadable (", conditionMessage(e), "). ",
           "Move it aside and re-run; do NOT delete it blind -- it may hold another ",
           "species' sections.", call. = FALSE)
    })
  for (s in c("network", "floodplain", "landcover")) got[[s]] <- got[[s]] %||% list()
  got$area <- cfg$area
  got$wsg <- cfg$watershed_group
  got$schema_version <- FP_PROV_SCHEMA_VERSION
  got
}

# --- Write -----------------------------------------------------------------------------------
# ATOMIC: serialize to a tempfile in the SAME directory (so the rename cannot cross a filesystem
# and silently degrade to a copy), then rename over the target. A failed or killed run then
# leaves the previous good file rather than a half-written one.
#
# Keys are sorted at every level so two runs with identical content serialize to identical bytes.
# jsonlite preserves insertion order, and R's list assignment appends -- so without this, adding a
# second species would reorder nothing but a re-run under a different code path could, and the
# determinism check would fail for a reason that is not a content change.
fp_prov_write <- function(cfg, prov) {
  path <- fp_prov_path(cfg)
  fp_prov_assert_unique(prov, "provenance")
  fp_prov_assert_serializable(prov, "provenance")
  txt <- jsonlite::toJSON(fp_prov_sort(prov), auto_unbox = TRUE, pretty = TRUE,
                          null = "null", na = "null", digits = NA)
  tmp <- tempfile("provenance", tmpdir = dirname(path), fileext = ".json")
  on.exit(unlink(tmp), add = TRUE)
  writeLines(txt, tmp)
  if (!file.rename(tmp, path)) {
    stop("failed to write ", path, call. = FALSE)   # file.rename returns FALSE, it does not error
  }
  invisible(path)
}

# A duplicate key is silent damage: `c(list(a = 1), list(a = 2))` gives a two-element list that
# serializes to a JSON object with the key twice, and `x$a` then returns whichever came first --
# so a later assignment appears to take and does not. Caught by this guard's own fixture while
# writing it, where it surfaced twice as unrelated-looking failures three checks apart. Refuse it
# at the boundary rather than hunt the symptoms.
fp_prov_assert_unique <- function(x, path) {
  if (!is.list(x)) return(invisible(NULL))
  nm <- names(x)
  if (!is.null(nm) && any(nzchar(nm))) {
    dup <- unique(nm[duplicated(nm)])
    if (length(dup)) {
      stop("provenance: duplicate key(s) at ", path, ": ", paste(dup, collapse = ", "),
           call. = FALSE)
    }
    for (k in nm) fp_prov_assert_unique(x[[k]], paste0(path, "$", k))
  } else {
    for (i in seq_along(x)) fp_prov_assert_unique(x[[i]], sprintf("%s[[%d]]", path, i))
  }
  invisible(NULL)
}

# jsonlite reports an unserializable value as "No method asJSON S3 class: <class>" with no path,
# which for a nested document is a scavenger hunt. Name the key instead. Cheap, and it is how the
# pq__text failure above would have announced itself in one line rather than three probes.
fp_prov_assert_serializable <- function(x, path) {
  if (is.null(x)) return(invisible(NULL))
  if (is.list(x)) {
    nm <- names(x)
    for (i in seq_along(x)) {
      fp_prov_assert_serializable(x[[i]], if (!is.null(nm) && nzchar(nm[i]))
                                            paste0(path, "$", nm[i]) else sprintf("%s[[%d]]", path, i))
    }
    return(invisible(NULL))
  }
  ok <- is.atomic(x) || inherits(x, "AsIs")
  if (!ok) {
    stop("provenance: value at ", path, " has class <", paste(class(x), collapse = "/"),
         "> which jsonlite cannot serialize. Coerce it in fp_prov_scalar().", call. = FALSE)
  }
  invisible(NULL)
}

# Recursively sort named lists by name. Unnamed lists (JSON arrays -- the item-id vectors) keep
# their order, because that order is data.
fp_prov_sort <- function(x) {
  if (!is.list(x)) return(x)
  x <- lapply(x, fp_prov_sort)
  nm <- names(x)
  if (is.null(nm) || any(!nzchar(nm))) return(x)
  x[order(nm)]
}

# --- Set one section entry -------------------------------------------------------------------
# The whole read-modify-write. Sequential by construction: run_area.R is one process per area, and
# run_region.R runs groups in series as subprocesses, so two writers never race. A second species
# lands ALONGSIDE the first (#23) rather than replacing the file.
fp_prov_set <- function(cfg, section, key, value) {
  stopifnot(section %in% c("network", "floodplain", "landcover"),
            is.character(key), length(key) == 1L, nzchar(key))
  path <- fp_prov_path(cfg)
  before <- if (file.exists(path)) file.mtime(path) else NA
  prov <- fp_prov_read(cfg)

  # One scalar per section over the STABLE half. It is what makes #33's second acceptance
  # criterion -- "changing the config, bumping a package, or the landcover being reprocessed each
  # produce a VISIBLY different block" -- a one-line assertion rather than a JSON diff, and it is
  # the value stac#17 should publish. Computed here, once, so the three producers cannot disagree
  # about how it is derived.
  value$inputs_hash <- fp_prov_hash(value$inputs)
  prov[[section]][[key]] <- value

  # Lost-update detection. Two `FP_SPECIES=... run_area.R <area>` processes against one data dir
  # would both read the old file and both write it, and the second would silently drop the first's
  # section. The window is small (read and write are adjacent) but the failure is silent, which is
  # the kind this repo has been bitten by. Turn it into a loud one.
  if (!is.na(before) && file.exists(path) && !identical(file.mtime(path), before)) {
    stop("provenance: ", basename(path), " changed while this run was writing it -- another ",
         "process is writing the same area. Run areas/species SEQUENTIALLY.", call. = FALSE)
  }
  fp_prov_write(cfg, prov)
  message("Provenance: ", section, "[", key, "] -> ", basename(fp_prov_path(cfg)))
  invisible(prov)
}

# Canonical sha256 over a subtree: keys sorted at every level, no auto_unbox (so a length-1 and a
# length-2 field cannot serialize to different SHAPES and hash apart for that reason alone),
# digits = NA so no float is silently rounded before hashing.
fp_prov_hash <- function(x) {
  if (is.null(x)) return(NA_character_)
  txt <- as.character(jsonlite::toJSON(fp_prov_sort(x), auto_unbox = FALSE, null = "null",
                                       na = "null", digits = NA))
  paste0("sha256:", digest::digest(txt, algo = "sha256", serialize = FALSE))
}

# --- Raster content digest ---------------------------------------------------------------------
# The CONTENT pin: a digest over the CELL VALUES and the geometry that makes them mean something,
# never over the file's bytes.
#
# Why it exists at all: io-lulc item ids are `<tile>-<year>`, a deterministic function of tile and
# year, and the items carry no `created` or `updated` property (verified live). If Planetary
# Computer re-derives a year IN PLACE, every id and every href is unchanged and an id-based hash is
# identical. The ids still belong in the record -- they name what was read -- but they are an
# IDENTITY, not a fingerprint, and only a digest of the raster can fail when the upstream moves.
#
# Why it is not a file hash any more (#64). It used to be `digest(file = path)`, on the recorded
# claim that terra's GeoTIFF writes are byte-deterministic. That holds WITHIN ONE TOOLCHAIN and
# fails across two. Measured across m1 and m4 running the identical commit against the same
# database: 28,291,615 cells per year, ZERO differing, and three different digests -- the files
# differing by exactly 10,028 bytes, all of it TIFF tag 42112 (`GDAL_METADATA`), which the older
# terra fills with the gdalcubes NetCDF attributes and the newer one drops.
#
# TWO NORMALIZATIONS, AND THE SECOND IS THE ONE NOBODY EXPECTS. `terra::readValues()` does not
# promise a storage type. Measured on ONE terra (1.9.34), the SAME file, changing nothing but
# whether GDAL is allowed to read its `.aux.xml` sidecar:
#
#   GDAL_PAM_ENABLED unset -> storage.mode "double",  NaN 324891, NA 324891
#   GDAL_PAM_ENABLED=NO    -> storage.mode "integer", NaN 0,      NA 324891
#
# That sidecar is written by GDAL as a side effect of anyone opening the file, so the storage type
# of a raster's values depends on who has looked at it. (The two sides of the #63 cross-machine
# comparison differed in exactly that way -- one had a sidecar, the copied one did not. Whether the
# terra version ALSO matters was never isolated, so do not claim it does.)
#
#   storage.mode(v) <- "double"   turns NA_integer_ into NA_real_ but leaves NaN as NaN, so the
#                                 vectors are still not identical() and the digests still disagree
#   v[is.na(v)] <- NA_real_       collapses both, because is.na() is TRUE for NaN too
#
# The first alone is not enough, and the gap is invisible to every value comparison -- all.equal()
# says TRUE, `sum(a != b, na.rm = TRUE)` is 0, and the NA counts match. Only identical() separates
# them. Do not simplify either line away: `provenance-check.R` §5c asserts both, in pure R.
#
# `block_rows` IS PART OF THE CONTRACT, not a tuning knob: the digest is over per-block hashes, so
# changing it changes every hash. It is a fixed constant rather than something derived from
# terra::blocks() or free memory, because either would make the digest depend on the machine --
# which is the whole defect being fixed here. Streaming at all is what keeps a whole-WSG raster off
# the heap, and the number that makes it non-optional is the WORST case, not the fixture: BULK's
# classified grid is 11552 x 14651 = 169.3M cells, 1.35 GB read whole, against ~47 MB per 512-row
# block. neexdzii's 28.3M cells (226 MB) is the small one.
#
# Cost, measured: 1.16 s for 28,291,615 cells, against a step 3 that runs for minutes.
# The two normalizations, factored out so they can be exercised with no raster and no GDAL at all.
# Keeping them inline made them untestable: a fixture that writes two files and reads both with the
# same terra in the same process gets the same storage type on both sides, so BOTH lines could be
# deleted and every assertion still passed. Measured -- that is exactly what the first version of
# `provenance-check.R` §5c did.
fp_norm_block <- function(v) {
  v <- as.double(v)             # integer and double serialize differently
  v[is.na(v)] <- NA_real_       # is.na() is TRUE for NaN too, so this collapses NaN and NA_real_
  v
}
# On the two lines above, honestly: the SECOND subsumes the first. Assigning a double into a vector
# promotes it whatever the index selects, so `v[is.na(v)] <- NA_real_` coerces an integer vector to
# double even when there is nothing to assign. Measured -- deleting the cast breaks no assertion,
# and §5d says so rather than pretending otherwise. The cast stays because the invariant should not
# depend on a subassignment side effect: change the sentinel to a logical `NA` some day and the
# coercion silently disappears with it. What IS independently provable is the second line, and §5d
# fails three checks without it.

fp_raster_content_sha256 <- function(path, block_rows = 512L) {
  if (!file.exists(path) || file.size(path) == 0) return(NA_character_)
  r <- terra::rast(path)
  # Geometry is part of the content: the same values on a different grid are not the same
  # landcover. Fixed precision so a float's printed representation cannot move the hash.
  # An absent authority code must not hash as the literal string "NA": two genuinely different
  # code-less CRSs would then collide, and the header exists precisely to make grid identity part
  # of the content. Fall back to the full WKT -- same reasoning as fp_pkg_stamp's "a confident wrong
  # SHA is worse than NA", one field over.
  #
  # Naming the tradeoff rather than hiding it: WKT is a ~1.4 kB, 39-line string that PROJ renders,
  # so a code-less CRS COULD make the digest PROJ-version-dependent -- the machine dependence this
  # function exists to remove. It is still strictly better than a silent collision between two
  # different projections, and it is unreachable for the rasters this pipeline writes (gdalcubes
  # attaches an authority code; measured EPSG:32609 on every classified raster). If a code-less CRS
  # ever does turn up here, the right fix is to make it an error, not to hash more text.
  code <- terra::crs(r, describe = TRUE)$code
  crs_id <- if (length(code) == 1L && !is.na(code) && nzchar(code)) paste0("EPSG:", code)
            else paste0("WKT:", terra::crs(r))
  hdr <- paste(c(dim(r),
                 sprintf("%.9f", as.vector(terra::ext(r))),
                 crs_id,
                 sprintf("%.9f", terra::res(r))), collapse = "|")
  terra::readStart(r)
  on.exit(terra::readStop(r), add = TRUE)
  nr <- terra::nrow(r)
  parts <- character(0)
  i <- 1L
  while (i <= nr) {
    n <- min(block_rows, nr - i + 1L)
    v <- terra::readValues(r, row = i, nrows = n)
    parts <- c(parts, digest::digest(fp_norm_block(v), algo = "sha256",
                                     # Pin the serialization format. digest hashes R's serialized
                                     # bytes, and `serializeVersion` is a base option any .Rprofile
                                     # can set; measured, version 3 gives a different digest for
                                     # identical cells and embeds the native encoding in the header,
                                     # making the hash locale-dependent. This function exists to be
                                     # machine-independent, so the format cannot be left to a option.
                                     serializeVersion = 2L))
    i <- i + n
  }
  paste0("sha256:", digest::digest(paste0(hdr, "|", paste(parts, collapse = "")),
                                   algo = "sha256", serialize = FALSE))
}

# --- Record absence as absence ---------------------------------------------------------------
# An OMITTED key reads as "not implemented"; a NULL one reads as "we looked and there was not
# one", and only the second is true. #33 requires this explicitly for `run_uid`, which a link
# schema predating link#262 does not have.
fp_prov_null_fill <- function(x, keys) {
  x <- as.list(x %||% list())
  for (k in keys) if (is.null(x[[k]])) x[[k]] <- NA
  x
}

# --- JSON-safe scalars ------------------------------------------------------------------------
# A DBI row is not JSON. Two columns in link's log need care:
#
#   timestamptz -> POSIXct. Serialized as-is, jsonlite formats it in the SESSION's timezone, so
#   the same row would produce different bytes on two machines and the determinism check would
#   fail for a reason that is not a content change. Forced to UTC ISO 8601, matching #33's
#   "run datetime in UTC (absolute, not relative)".
#
#   text[] (species, wsg_upstream) -> class `pq__text`, which is NOT a list: `is.list()` is FALSE
#   and `length()` is 1, so every type branch below skips it and jsonlite aborts the whole write
#   with "No method asJSON S3 class: pq__text". MEASURED against fresh.log, not assumed -- the
#   first draft of this function asserted in a comment that text[] arrives as a one-element list,
#   which is what the DBI docs suggest and not what RPostgres does. RPostgres names every array
#   type this way (`pq__int4`, `pq__float8`, ...), so match the prefix rather than the one class
#   that happened to appear. `x[[1]]` is the character vector inside.
#
# `auto_unbox` would turn a length-1 vector into a scalar and a length-2 into an array, so a
# single-species area and a two-species area would disagree on the SHAPE of the same field. The
# array-valued fields are marked with I() to hold the array shape at every length.
fp_prov_scalar <- function(x) {
  if (inherits(x, c("POSIXct", "POSIXt"))) {
    return(if (is.na(x)) NA_character_ else format(x, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  }
  if (inherits(x, "Date")) return(if (is.na(x)) NA_character_ else format(x, "%Y-%m-%d"))
  # RPostgres array column. Both edge cases below occur in fresh.log today (2 rows with an empty
  # array, 1 with SQL NULL), so neither is hypothetical.
  if (any(grepl("^pq__", class(x)))) {
    inner <- tryCatch(x[[1]], error = function(e) NULL)
    if (is.null(inner) || length(inner) == 0L || all(is.na(inner))) return(NA)
    return(fp_pg_array(as.character(inner)))
  }
  if (is.list(x)) {
    if (length(x) == 1L && !is.list(x[[1]])) {
      inner <- x[[1]]
      return(if (length(inner) == 0L) NA else I(as.character(inner)))
    }
    return(lapply(x, fp_prov_scalar))
  }
  if (length(x) > 1L) return(I(x))
  x
}

# Parse a Postgres array LITERAL into a character vector.
#
# RPostgres hands `text[]` back unparsed: `x[[1]]` is the single string `"{BT,CH,CO}"`, braces and
# all. Measured -- the first fix here unwrapped the pq__text correctly and then serialized
# `["{BT,CH,CO}"]`, a JSON array of one literal-brace string. It no longer errored, which is why
# it needed the values looked at rather than the absence of an exception trusted.
#
# Elements are comma-separated; any element containing a comma, brace, quote or space is
# double-quoted with backslash escaping. Our data is identifier codes, but split on unquoted
# commas anyway -- a naive strsplit would silently corrupt the first element that is not.
fp_pg_array <- function(txt) {
  if (length(txt) != 1L || is.na(txt)) return(NA)
  if (!grepl("^\\{.*\\}$", txt)) return(I(txt))         # not an array literal; pass through
  body <- substr(txt, 2, nchar(txt) - 1)
  if (!nzchar(body)) return(NA)                          # `{}` -- an empty array is an absence
  out <- character(0); cur <- ""; inq <- FALSE; esc <- FALSE
  for (ch in strsplit(body, "", fixed = TRUE)[[1]]) {
    if (esc)            { cur <- paste0(cur, ch); esc <- FALSE }
    else if (ch == "\\") esc <- TRUE
    else if (ch == "\"") inq <- !inq
    else if (ch == "," && !inq) { out <- c(out, cur); cur <- "" }
    else                 cur <- paste0(cur, ch)
  }
  out <- c(out, cur)
  out[out == "NULL"] <- NA_character_                    # an unquoted NULL element
  I(out)
}

# --- Package version + git SHA ---------------------------------------------------------------
# Four tiers, and `sha_source` names which one answered so an NA is DIAGNOSABLE rather than mute.
# Mirrors link's .lnk_pkg_git_sha() (link/R/lnk_stamp.R:264) and adds the tier that actually
# resolves here: measured on this machine, link/drift/flooded are all RemoteType=local with a NULL
# RemoteSha, and find.package() on a local install returns the LIBRARY path whose parent is not
# the checkout -- which is why every stamp in this repo reads "(sha NA)".
#
#   1. <PKG>_GIT_SHA env var      -- explicit override, same contract link honours
#   2. DESCRIPTION RemoteSha      -- set by pak/remotes GitHub installs (link#264's tier)
#   3. .git walk from find.package() -- resolves under devtools::load_all()
#   4. .git walk of <PKG>_DIR or ~/Projects/repo/<pkg> -- the local-install case
#
# `dirty` is NA when git could not answer. It must NEVER collapse to FALSE: "git failed" is not
# "nothing changed", and a SHA recorded against a dirty tree is a lie.
fp_pkg_stamp <- function(pkg) {
  ver <- suppressWarnings(
    tryCatch(as.character(utils::packageVersion(pkg)), error = function(e) NA_character_))

  env_sha <- Sys.getenv(paste0(toupper(pkg), "_GIT_SHA"), "")
  if (nzchar(env_sha)) {
    return(list(version = ver, sha = env_sha, sha_source = "env", dirty = NA))
  }

  remote <- suppressWarnings(
    tryCatch(utils::packageDescription(pkg)$RemoteSha, error = function(e) NULL))
  # Shape-check it: a CRAN/PPPM install puts a VERSION STRING in RemoteSha, not a SHA. Measured
  # while writing this -- sf reports RemoteSha = "1.1-2", which published as a git SHA is a
  # wrong-shaped value nothing downstream could resolve. Require hex.
  if (!is.null(remote) && length(remote) == 1L && grepl("^[0-9a-f]{7,40}$", remote)) {
    # A GitHub install is a pinned tarball: there is no working tree to be dirty.
    return(list(version = ver, sha = remote, sha_source = "RemoteSha", dirty = FALSE))
  }

  # A checkout is only evidence about the INSTALLED package if the two are the same version.
  # Measured on this machine while writing this: ~/Projects/repo/link is 0.49.0 and the installed
  # link is 0.47.3, so the checkout SHA describes code that did not run. Recording it would be a
  # confident lie, which is strictly worse than NA -- an NA prompts a question, a wrong SHA does
  # not. Presence of a checkout is not provenance of the install.
  repo <- fp_pkg_repo_dir(pkg)
  if (!is.null(repo)) {
    repo_ver <- fp_desc_version(repo)
    if (!is.na(ver) && !is.na(repo_ver) && identical(repo_ver, ver)) {
      st <- fp_git_state(repo)
      if (!is.na(st$sha)) {
        return(list(version = ver, sha = st$sha, sha_source = st$source, dirty = st$dirty))
      }
    } else if (!is.na(repo_ver)) {
      return(list(version = ver, sha = NA, dirty = NA,
                  sha_source = paste0("unresolved (checkout at ", repo, " is ", repo_ver,
                                      ", installed is ", ver, ")")))
    }
  }
  list(version = ver, sha = NA, sha_source = "unresolved", dirty = NA)
}

# Version field of a checkout's DESCRIPTION, or NA. Read with read.dcf rather than a grep so a
# continuation line or an unexpected field order cannot produce a plausible wrong answer.
fp_desc_version <- function(dir) {
  f <- file.path(dir, "DESCRIPTION")
  if (!file.exists(f)) return(NA_character_)
  v <- tryCatch(unname(read.dcf(f, fields = "Version")[1, 1]), error = function(e) NA_character_)
  if (is.na(v)) NA_character_ else as.character(v)
}

# Candidate checkout for a package, most specific first. Returns NULL when none is a git repo.
fp_pkg_repo_dir <- function(pkg) {
  env_dir <- Sys.getenv(paste0(toupper(pkg), "_DIR"), "")
  lib <- tryCatch(find.package(pkg, quiet = TRUE), error = function(e) character(0))
  cands <- c(if (nzchar(env_dir)) env_dir,
             lib, if (length(lib)) dirname(lib),
             path.expand(file.path("~", "Projects", "repo", pkg)))
  for (d in cands) {
    if (nzchar(d) && dir.exists(d) && file.exists(file.path(d, ".git"))) return(d)
  }
  NULL
}

# git state for a checkout. system2() shell-quotes the COMMAND but pastes ARGS raw, so every path
# is shQuote()d -- an unquoted path with a space is re-split by the shell and the command returns
# nothing, which reads as "not a checkout" and skips silently.
#
# Read the STATUS, not just the output: stdout = TRUE discards it, so length(out) == 0 conflates
# "git failed" with "there was nothing to report". And Sys.which() is checked FIRST because
# system2() RAISES when the command does not exist rather than returning a status.
fp_git_state <- function(dir) {
  none <- list(sha = NA_character_, dirty = NA, source = "unresolved")
  if (!nzchar(Sys.which("git"))) return(none)
  git <- function(args) {
    err <- tempfile(); on.exit(unlink(err), add = TRUE)
    out <- suppressWarnings(
      system2("git", c("-C", shQuote(dir), args), stdout = TRUE, stderr = err))
    if (!is.null(attr(out, "status")) && attr(out, "status") != 0) return(NULL)
    out
  }
  sha <- git(c("rev-parse", "HEAD"))
  if (is.null(sha) || !length(sha) || !nzchar(sha[1])) return(none)
  # `git status --porcelain` is empty for BOTH a clean tree and an aborted command, so trust
  # emptiness only after the exit status says the command succeeded.
  st <- git(c("status", "--porcelain", "--untracked-files=no"))
  list(sha = sha[1],
       dirty = if (is.null(st)) NA else length(st) > 0,
       source = "git")
}

# --- Landcover fingerprint from the resolved STAC items ---------------------------------------
# THE point of #33. `stac_cache_key()` -- which the issue originally named -- hashes the AOI and
# the request parameters and NOTHING about the items returned, so it is a fingerprint of the
# REQUEST: if Planetary Computer re-ingests io-lulc-annual-v02 the key is unchanged and the stale
# cache is served. That is precisely the drift this issue exists to catch. The resolved item ids
# are the content pin, and drift has attached them as `attr(result, "stac_items")` since its first
# commit, so this needs no upstream change.
#
# Three things this has to get right, each measured against the live collection:
#
#   1. GROUP BY start_datetime, NOT datetime. io-lulc items carry properties$datetime = NULL and
#      use start_datetime/end_datetime. Grouping by `datetime` yields empty groups SILENTLY, and
#      an empty group is indistinguishable from a year the AOI does not cover. provenance-check.R
#      reports a zero-id year for exactly this reason.
#   2. KEEP ONLY THE REQUESTED YEARS. drift searches min(years)-01-01/max(years)-12-31, so a
#      2017/2020/2023 fetch returns seven items and reads three. Recording all seven would claim
#      inputs that never reached the output.
#   3. RECORD WHETHER THE LIST IS COMPLETE. drift calls get_request() with no items_fetch(), so
#      this is ONE PAGE. Planetary Computer returns no numberMatched (measured: the response
#      carries type/links/features/numberReturned only), so the only honest completeness test is
#      the presence of a rel="next" link. A partial list published as complete is worse than none.
#
# NO HREFS, EVER. drift signs the items (rstac::items_sign) before attaching them, so every asset
# href carries a short-lived SAS token. Ids and the year only; provenance-check.R greps for a
# credential-shaped query parameter and fails if one reaches the file.
fp_prov_stac_items <- function(items, years) {
  years <- as.character(sort(unique(as.integer(years))))
  blank <- list(item_ids = stats::setNames(rep(list(character(0)), length(years)), years),
                item_hash = NA_character_, item_ids_complete = NA)
  feats <- items$features
  if (is.null(feats) || !length(feats)) return(blank)

  yr <- vapply(feats, function(f) {
    p <- f$properties
    dt <- p[["start_datetime"]] %||% p[["datetime"]] %||% ""
    if (nzchar(dt)) substr(dt, 1, 4) else NA_character_
  }, character(1))
  ids <- vapply(feats, function(f) as.character(f$id %||% NA_character_), character(1))

  by_year <- lapply(years, function(y) sort(unique(ids[!is.na(yr) & yr == y & !is.na(ids)])))
  names(by_year) <- years

  # One scalar a consumer can compare. Sorted and year-labelled so the hash is a function of the
  # content, never of the order the API happened to return.
  payload <- paste(unlist(lapply(years, function(y)
    paste0(y, "=", paste(by_year[[y]], collapse = ",")))), collapse = "\n")

  list(item_ids = lapply(by_year, function(v) if (length(v)) I(v) else character(0)),
       item_hash = paste0("sha256:", digest::digest(payload, algo = "sha256", serialize = FALSE)),
       item_ids_complete = !fp_stac_has_next(items))
}

# TRUE when the response advertises another page. Treated as "incomplete" only on a positive
# signal: an absent links array means no next link, which is a complete single page.
fp_stac_has_next <- function(items) {
  lk <- items$links
  if (is.null(lk) || !length(lk)) return(FALSE)
  any(vapply(lk, function(l) identical(l[["rel"]], "next"), logical(1)))
}

# --- Run-event block ---------------------------------------------------------------------------
# UTC and absolute, per #33. Every field here is free to vary between reruns; nothing here may
# leak into `inputs`, and provenance-check.R fails if it does.
fp_prov_run <- function(...) {
  c(list(datetime_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")), list(...))
}

# --- The raster toolchain, recorded in `run` and NOT in `inputs` --------------------------------
# terra, sf and GDAL are what actually write and read every raster and vector this pipeline
# produces, and until #64 none of them appeared in the record at all -- only link, flooded, drift
# and fresh. So when two machines produced identical rasters with different digests, the one
# difference that explained it was the one thing provenance did not carry.
#
# It goes in `run`, deliberately, and this is not a filing convenience. `inputs` is hashed. A terra
# version legitimately differs between two machines that agree on every cell, so putting it in
# `inputs` would move `inputs_hash` across machines -- reintroducing exactly the cross-machine churn
# #64 exists to remove, one field over. `run` is the run event and is not hashed: it makes a digest
# change DIAGNOSABLE without making it INEVITABLE. That is #33's inputs/run split doing its job.
fp_toolchain <- function() {
  ver <- function(p) tryCatch(as.character(utils::packageVersion(p)),
                              error = function(e) NA_character_)
  soft <- tryCatch(sf::sf_extSoftVersion(), error = function(e) character(0))
  pick <- function(k) if (k %in% names(soft)) unname(soft[[k]]) else NA_character_
  # GEOS and PROJ arrive in the same call for free, and the floodplain section's outputs ARE
  # geometry -- a PROJ change moves a reprojection the same way a GDAL change moves an encoder.
  list(terra = ver("terra"), sf = ver("sf"),
       gdal = pick("GDAL"), geos = pick("GEOS"), proj = pick("PROJ"))
}
