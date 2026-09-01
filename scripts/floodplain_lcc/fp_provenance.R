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
  prov <- fp_prov_read(cfg)
  prov[[section]][[key]] <- value
  fp_prov_write(cfg, prov)
  message("Provenance: ", section, "[", key, "] -> ", basename(fp_prov_path(cfg)))
  invisible(prov)
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
#   text[] (species, wsg_upstream) -> a one-element list holding a character vector. Unwrapped to
#   the vector so it serializes as a JSON array rather than a nested one.
#
# `auto_unbox` would turn a length-1 vector into a scalar and a length-2 into an array, so a
# single-species area and a two-species area would disagree on the SHAPE of the same field. The
# array-valued fields are marked with I() to hold the array shape at every length.
fp_prov_scalar <- function(x) {
  if (inherits(x, c("POSIXct", "POSIXt"))) {
    return(if (is.na(x)) NA_character_ else format(x, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  }
  if (inherits(x, "Date")) return(if (is.na(x)) NA_character_ else format(x, "%Y-%m-%d"))
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
