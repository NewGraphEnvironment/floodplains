#!/usr/bin/env Rscript
#
# provenance-check.R  —  the control that makes #33's inputs/run split a RULE and not a convention.
#
# Usage:
#   Rscript scripts/floodplain_lcc/provenance-check.R [area]
#
# Runs entirely OFFLINE against synthetic fixtures. Pass an area to additionally check that area's
# real data/<area>/provenance.json. Exits non-zero on any failure.
#
# Five properties, and each one is proven able to FAIL before it is trusted -- a guard nobody has
# seen go red is decoration, and reading it will not tell you which kind you have. Every check
# below is run twice: once against input that must pass, once against input built to break it.
#
#   1. DETERMINISM     `inputs` serializes identically across two writes with identical content
#   2. SPLIT           `inputs` carries no run-event field; the two key sets are disjoint
#   3. DECLARED KEYS   every field is PRESENT, null where absent -- an absolute assertion, not a
#                      cross-section consistency check. A uniform loss (every section dropping the
#                      same key) has no variance, so a consistency validator passes loudest
#                      exactly when the whole file is wrong the same way.
#   4. NO CREDENTIALS  no SAS token anywhere. drift hands us items_sign()ed, so every asset href
#                      carries `?st=...&se=...&sig=...`. Ids only.
#   5. COVERAGE        item_ids_complete present, and every recorded year has >= 1 id

suppressWarnings(suppressMessages({
  library(jsonlite)
}))
source(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])),
                 "fp_provenance.R"))

FAILS <- 0L
ok   <- function(msg) cat("  ok   ", msg, "\n")
bad  <- function(msg) { FAILS <<- FAILS + 1L; cat("  FAIL ", msg, "\n") }
check <- function(cond, msg) if (isTRUE(cond)) ok(msg) else bad(msg)

# Run-event fields. Anything named here is forbidden inside `inputs`: a timestamp in the stable
# half re-introduces exactly the churn #45 removed from the GeoPackage, by hand this time and
# harder to spot because it looks like provenance rather than an artefact.
RUN_FIELDS <- c("datetime_utc", "run_date", "elapsed", "host", "operator", "run_id")

# Declared key sets. Present-with-null beats omitted: an absent key reads as "not implemented",
# a null one reads as "we looked and there was not one", and only the second is true.
KEYS_NETWORK_INPUTS <- c("watershed_group", "species", "min_order", "network_source",
                         "read_schema", "subset", "link_config_name", "link", "fresh")
KEYS_LINK_LOG       <- c("run_uid", "config_hash", "link_sha", "link_dirty", "fwapg_sha",
                         "bcfp_model_version", "bcfp_pin_source", "date_start", "date_end")
KEYS_FLOODPLAIN     <- c("wsg", "species", "scenario", "flood_factor", "slope_threshold",
                         "max_width", "cost_threshold", "size_threshold", "hole_threshold",
                         "anchor_order", "dem_source", "dem_buffer_m", "attribute_by",
                         "subbasin_source", "crs_epsg", "flooded")
KEYS_LANDCOVER      <- c("source", "stac_url", "collection", "asset", "res", "crs", "dt",
                         "aggregation", "resampling", "tile_size", "years", "change_interval",
                         "patch_area_min_m2", "item_ids", "item_hash", "item_ids_complete",
                         "cache_key", "drift")

# --- Property implementations ------------------------------------------------------------------
# Each takes a parsed provenance list and returns a character vector of problems (empty = pass), so
# the same function serves both the must-pass and the must-fail exercise below.

# NOTE ON `[[` vs `$` THROUGHOUT THIS FILE. `$` on a list does PARTIAL MATCHING, so
# `body$link_log` silently resolves to `link_log_note` when only the note is present, and
# `inp$item_ids` resolves to `item_ids_complete` when only the flag is present. Both were live
# here and the first cost a confusing failure three checks away from its cause. Every read of a
# parsed-JSON body below uses `[[`, which matches exactly.
prov_sections <- function(prov) {
  out <- list()
  for (s in c("network", "floodplain", "landcover")) {
    for (k in names(prov[[s]] %||% list())) {
      out[[length(out) + 1L]] <- list(section = s, key = k, body = prov[[s]][[k]])
    }
  }
  out
}

viol_split <- function(prov) {
  unlist(lapply(prov_sections(prov), function(e) {
    inp <- names(e$body[["inputs"]] %||% list())
    run <- names(e$body[["run"]] %||% list())
    c(if (length(intersect(inp, RUN_FIELDS)))
        sprintf("%s[%s].inputs carries run-event field(s): %s", e$section, e$key,
                paste(intersect(inp, RUN_FIELDS), collapse = ", ")),
      if (length(intersect(inp, run)))
        sprintf("%s[%s] inputs/run key sets overlap: %s", e$section, e$key,
                paste(intersect(inp, run), collapse = ", ")))
  }))
}

viol_keys <- function(prov) {
  want <- list(network = KEYS_NETWORK_INPUTS, floodplain = KEYS_FLOODPLAIN,
               landcover = KEYS_LANDCOVER)
  unlist(lapply(prov_sections(prov), function(e) {
    miss <- setdiff(want[[e$section]], names(e$body[["inputs"]] %||% list()))
    extra <- if (identical(e$section, "network")) {
      ll <- e$body[["link_log"]]
      # link_log NULL is legitimate (no log table in the source schema) but must say so.
      if (is.null(ll)) {
        if (is.null(e$body[["link_log_note"]]))
          sprintf("network[%s].link_log is null with no link_log_note", e$key)
      } else {
        m <- setdiff(KEYS_LINK_LOG, names(ll))
        if (length(m)) sprintf("network[%s].link_log missing: %s", e$key,
                               paste(m, collapse = ", "))
      }
    }
    c(if (length(miss)) sprintf("%s[%s].inputs missing: %s", e$section, e$key,
                                paste(miss, collapse = ", ")),
      extra)
  }))
}

# Anchored on the query-parameter form so a `sig` COLUMN or a word ending in "se" cannot trip it,
# while an actual token in any href does.
CRED_RE <- "[?&](sig|se|st|sv|sp|skoid|sktid)="
viol_creds <- function(txt) {
  hits <- grep(CRED_RE, txt, value = TRUE)
  if (length(hits)) sprintf("credential-shaped query parameter found (%d line(s)), first: %s",
                            length(hits), substr(hits[1], 1, 80))
}

viol_coverage <- function(prov) {
  unlist(lapply(prov_sections(prov), function(e) {
    if (!identical(e$section, "landcover")) return(NULL)
    inp <- e$body[["inputs"]] %||% list()
    ids <- inp[["item_ids"]]
    c(if (is.null(inp[["item_ids_complete"]]))
        sprintf("landcover[%s] has no item_ids_complete", e$key),
      if (!is.null(ids) && length(ids))
        unlist(lapply(names(ids), function(y)
          if (!length(ids[[y]])) sprintf("landcover[%s] year %s resolved 0 item ids", e$key, y))))
  }))
}

# --- Fixtures ------------------------------------------------------------------------------------
fixture_cfg <- function() {
  d <- file.path(tempdir(), paste0("fpprov", as.integer(runif(1, 1e6, 9e6))))
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  list(area = "fixture", watershed_group = "TEST", dir_out = d)
}

good_prov <- function() {
  nul <- function(keys) stats::setNames(as.list(rep(NA, length(keys))), keys)
  list(
    area = "fixture", wsg = "TEST", schema_version = FP_PROV_SCHEMA_VERSION,
    network = list(co3 = list(
      inputs = nul(KEYS_NETWORK_INPUTS),
      link_log = nul(KEYS_LINK_LOG),
      run = list(datetime_utc = "2026-09-01T00:00:00Z"))),
    floodplain = list(co_ff04 = list(
      inputs = nul(KEYS_FLOODPLAIN),
      run = list(datetime_utc = "2026-09-01T00:00:00Z"))),
    landcover = list(co_ff04 = list(
      # modifyList, NOT c(): `c()` APPENDS, so a key present in both halves lands twice and `$`
      # then returns the first one -- which is how a later assignment silently fails to take.
      inputs = utils::modifyList(
        nul(KEYS_LANDCOVER),
        list(item_ids = list(`2017` = list("09U-2017"), `2023` = list("09U-2023")),
             item_ids_complete = TRUE)),
      run = list(datetime_utc = "2026-09-01T00:00:00Z"))))
}

# --- 1. Determinism -------------------------------------------------------------------------------
cat("\n1. Determinism — `inputs` is byte-stable across two writes\n")
{
  cfg <- fixture_cfg()
  g <- good_prov()
  fp_prov_set(cfg, "landcover", "co_ff04", g$landcover$co_ff04)
  a <- readLines(fp_prov_path(cfg), warn = FALSE)
  # Rebuild the same content with the keys supplied in a DIFFERENT order: two runs must agree on
  # bytes because of the content, not because R happened to build the list the same way.
  shuffled <- g$landcover$co_ff04
  shuffled$inputs <- shuffled$inputs[rev(seq_along(shuffled$inputs))]
  fp_prov_set(cfg, "landcover", "co_ff04", shuffled)
  b <- readLines(fp_prov_path(cfg), warn = FALSE)
  check(identical(a, b), "two writes of identical content produce identical bytes")

  # MUST-FAIL: a run-event field inside `inputs` makes the two writes differ.
  drifted <- g$landcover$co_ff04
  drifted$inputs$datetime_utc <- "2026-09-01T00:00:00Z"
  fp_prov_set(cfg, "landcover", "co_ff04", drifted)
  c1 <- readLines(fp_prov_path(cfg), warn = FALSE)
  drifted$inputs$datetime_utc <- "2026-09-01T00:00:01Z"
  fp_prov_set(cfg, "landcover", "co_ff04", drifted)
  c2 <- readLines(fp_prov_path(cfg), warn = FALSE)
  check(!identical(c1, c2), "must-fail: a run-event field in `inputs` DOES break byte stability")
}

# --- 2. inputs/run split ---------------------------------------------------------------------------
cat("\n2. Split — `inputs` carries no run-event field\n")
{
  g <- good_prov()
  check(length(viol_split(g)) == 0, "clean fixture reports no split violation")
  b <- g
  b$floodplain$co_ff04$inputs$datetime_utc <- "2026-09-01T00:00:00Z"
  v <- viol_split(b)
  # Do not assert the COUNT: `datetime_utc` is also in `run`, so this one edit legitimately trips
  # both arms of the check. Asserting one violation would fail on correct behaviour.
  check(any(grepl("datetime_utc", v)),
        "must-fail: a run-event field in `inputs` IS reported")
  b2 <- g
  b2$network$co3$inputs$run_id <- "x"; b2$network$co3$run$run_id <- "x"
  check(length(viol_split(b2)) >= 1, "must-fail: an overlapping inputs/run key IS reported")
}

# --- 3. Declared keys -------------------------------------------------------------------------------
cat("\n3. Declared keys — present, null where absent\n")
{
  g <- good_prov()
  check(length(viol_keys(g)) == 0, "clean fixture declares every key")
  b <- g; b$landcover$co_ff04$inputs$item_hash <- NULL
  check(any(grepl("item_hash", viol_keys(b))), "must-fail: one dropped key IS reported")
  # The uniform case: EVERY section loses the same field. A cross-section consistency check has no
  # variance to see here and would pass; an absolute assertion does not.
  u <- g
  u$network$co3$link_log$run_uid <- NULL
  check(any(grepl("run_uid", viol_keys(u))),
        "must-fail: a UNIFORMLY dropped key IS reported (no variance to detect)")
  n <- g; n$network$co3$link_log <- NULL
  check(any(grepl("link_log_note", viol_keys(n))),
        "must-fail: a null link_log with no note IS reported")
  n2 <- n; n2$network$co3$link_log_note <- "no log table in source schema"
  check(length(viol_keys(n2)) == 0, "a null link_log WITH a note passes")
  # Pins the `$` partial-matching trap: read with `$`, `link_log` resolves to `link_log_note` and
  # this case reports a spurious 9-field violation. Read with `[[`, it does not.
  check(is.null(n2$network$co3[["link_log"]]) && !is.null(n2$network$co3$link_log),
        "premise: `$` DOES partial-match link_log -> link_log_note (why this file uses `[[`)")
}

# --- 4. No credentials --------------------------------------------------------------------------------
cat("\n4. Credentials — no SAS token reaches the file\n")
{
  cfg <- fixture_cfg()
  fp_prov_set(cfg, "landcover", "co_ff04", good_prov()$landcover$co_ff04)
  clean <- readLines(fp_prov_path(cfg), warn = FALSE)
  check(is.null(viol_creds(clean)), "clean fixture carries no credential-shaped parameter")
  # MUST-FAIL: prove the pattern can match before an empty result is read as clean. A search that
  # has never found anything has proven nothing.
  poisoned <- c(clean,
    '  "href": "https://x.blob.core.windows.net/y/z.tif?st=2026-09-01&se=2026-09-02&sig=AbC%3D"')
  check(!is.null(viol_creds(poisoned)),
        "must-fail: an actual SAS token IS matched")
  check(is.null(viol_creds('  "sig_column": "value", "sense": "x", "st": 1')),
        "a `sig`/`se`-prefixed WORD is not a false positive")
}

# --- 5. Coverage ---------------------------------------------------------------------------------------
cat("\n5. Coverage — completeness flag and non-empty year groups\n")
{
  g <- good_prov()
  check(length(viol_coverage(g)) == 0, "clean fixture reports full coverage")
  b <- g; b$landcover$co_ff04$inputs$item_ids_complete <- NULL
  check(any(grepl("item_ids_complete", viol_coverage(b))),
        "must-fail: a missing completeness flag IS reported")
  e <- g; e$landcover$co_ff04$inputs$item_ids[["2020"]] <- list()
  check(any(grepl("year 2020 resolved 0", viol_coverage(e))),
        "must-fail: an EMPTY year group IS reported (the `datetime` vs `start_datetime` trap)")
}

# --- 6. A real area, when one is named -----------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
if (length(args) >= 1 && nzchar(args[1])) {
  area <- args[1]
  path <- file.path("data", area, "provenance.json")
  cat("\n6. Real area: ", path, "\n", sep = "")
  if (!file.exists(path)) {
    # Absence is reported as absence, never as a pass. Forward-only (#33) means an area not yet
    # re-run legitimately has none -- but "there was nothing to check" must not read as "clean".
    bad(sprintf("no provenance.json for area '%s' (forward-only: has it been re-run?)", area))
  } else if (file.size(path) == 0) {
    bad(sprintf("%s is 0 bytes", path))
  } else {
    prov <- jsonlite::read_json(path, simplifyVector = FALSE)
    txt <- readLines(path, warn = FALSE)
    n <- length(prov_sections(prov))
    # A loop over nothing exits 0: zero sections and "everything checked out" would otherwise be
    # indistinguishable, so zero gets its own branch.
    if (n == 0) bad("provenance.json has ZERO sections — nothing was checked") else
      ok(sprintf("%d section(s) to check", n))
    for (f in list(viol_split, viol_keys, viol_coverage)) {
      v <- f(prov); if (length(v)) for (m in v) bad(m)
    }
    v <- viol_creds(txt); if (!is.null(v)) bad(v)
    if (n > 0) check(TRUE, "real file checked against all properties")
  }
}

cat("\n", if (FAILS == 0L) "PASS — all properties hold, and each was shown able to fail.\n"
         else sprintf("FAIL — %d problem(s).\n", FAILS), sep = "")
quit(status = if (FAILS == 0L) 0L else 1L)
