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
  library(yaml)
}))
source(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])),
                 "fp_provenance.R"))

# Root every path on THIS SCRIPT's own location, never on the working directory. This is a
# DELIBERATE divergence from the here::here() the rest of the repo uses, and the reason is the
# worktree-per-session convention: here::here() answers from the CWD's project root, so invoking
# one checkout's guard from inside another silently verifies the OTHER tree's provenance.json and
# passes, while the run you meant to check is never looked at. The script's own path is the one
# thing that cannot move out from under it. Measured: from /tmp, here::here() resolved to /tmp and
# the guard reported a missing file -- which reads as "that area has no provenance", not as "you
# are in the wrong place". The resolved root is printed below so a wrong-tree invocation is
# visible rather than silent.
fp_root <- local({
  f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(f)) normalizePath(file.path(dirname(sub("^--file=", "", f[1])), "..", ".."),
                               mustWork = FALSE) else here::here()
})

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
                         "anchor_order", "dem_resolver", "dem_crs_epsg", "dem_res_m", "dem_ncell",
                         "dem_buffer_m", "attribute_by", "subbasin_source", "crs_epsg",
                         "network_layer", "flooded")
KEYS_LANDCOVER      <- c("source", "stac_url", "collection", "asset", "res", "crs", "dt",
                         "aggregation", "resampling", "tile_size", "years", "change_interval",
                         "patch_area_min_m2", "item_ids", "item_hash", "item_ids_complete",
                         "classified_content_sha256", "floodplain_layer", "drift")

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
    # ABSOLUTE assertion first. An intersection test alone passes when `run` is absent, empty or
    # renamed -- a section that lost its whole run block is exactly the defect this check is for,
    # and set arithmetic on nothing is silent about it.
    c(if (!length(run)) sprintf("%s[%s] has no `run` block", e$section, e$key),
      if (length(run) && !"datetime_utc" %in% run)
        sprintf("%s[%s].run has no datetime_utc", e$section, e$key),
      if (!length(inp)) sprintf("%s[%s] has no `inputs` block", e$section, e$key),
      if (is.null(e$body[["inputs_hash"]])) sprintf("%s[%s] has no inputs_hash", e$section, e$key),
      if (length(intersect(inp, RUN_FIELDS)))
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
    have <- names(e$body[["inputs"]] %||% list())
    miss <- setdiff(want[[e$section]], have)
    # WHITELIST, not just a completeness check: an UNDECLARED key is reported too. A denylist grep
    # for secret-shaped strings can always be outrun by a new field; "only these keys may appear"
    # cannot.
    undeclared <- setdiff(have, want[[e$section]])
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
      if (length(undeclared)) sprintf("%s[%s].inputs has UNDECLARED key(s): %s", e$section, e$key,
                                      paste(undeclared, collapse = ", ")),
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
      # FALSE means drift's single-page fetch was truncated, so the raster was built from a
      # partial item set. That is a wrong raster, not a metadata note -- fail on it.
      if (isFALSE(inp[["item_ids_complete"]]))
        sprintf("landcover[%s] item list was TRUNCATED (item_ids_complete = false)", e$key),
      if (all(is.na(unlist(inp[["classified_content_sha256"]] %||% NA))))
        sprintf("landcover[%s] has no classified raster digest -- the only field that can move ",
                e$key),
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
      inputs = nul(KEYS_NETWORK_INPUTS), inputs_hash = "sha256:aa",
      link_log = nul(KEYS_LINK_LOG),
      run = list(datetime_utc = "2026-09-01T00:00:00Z"))),
    floodplain = list(co_ff04 = list(
      inputs = nul(KEYS_FLOODPLAIN), inputs_hash = "sha256:bb",
      run = list(datetime_utc = "2026-09-01T00:00:00Z"))),
    landcover = list(co_ff04 = list(
      # modifyList, NOT c(): `c()` APPENDS, so a key present in both halves lands twice and `$`
      # then returns the first one -- which is how a later assignment silently fails to take.
      inputs = utils::modifyList(
        nul(KEYS_LANDCOVER),
        list(item_ids = list(`2017` = list("09U-2017"), `2023` = list("09U-2023")),
             item_ids_complete = TRUE,
             classified_content_sha256 = list(`2017` = "sha256:11", `2023` = "sha256:22"))),
      inputs_hash = "sha256:cc",
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
  # ISSUE ACCEPTANCE CRITERION 2, and it has no other test: "changing the config, bumping a
  # package, or the remote landcover being reprocessed each produce a VISIBLY different block".
  # Byte-stability alone is satisfied by a writer that records nothing at all, so the positive
  # direction has to be asserted too.
  base <- fp_prov_hash(g$landcover$co_ff04$inputs)
  perturb <- function(f) { h <- g$landcover$co_ff04$inputs; fp_prov_hash(f(h)) }
  check(perturb(function(h) { h$res <- 20; h }) != base,
        "criterion 2: changing a model parameter MOVES inputs_hash")
  check(perturb(function(h) { h$drift <- list(version = "9.9.9"); h }) != base,
        "criterion 2: bumping a package version MOVES inputs_hash")
  check(perturb(function(h) { h$classified_content_sha256$`2017` <- "sha256:ff"; h }) != base,
        "criterion 2: a reprocessed landcover raster MOVES inputs_hash")
  check(perturb(function(h) h) == base, "an unchanged input does NOT move inputs_hash")
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
  # The absolute assertions: set arithmetic on an ABSENT run block is silent, so test it directly.
  b3 <- g; b3$floodplain$co_ff04$run <- NULL
  check(any(grepl("no `run` block", viol_split(b3))),
        "must-fail: a section that LOST its whole run block IS reported")
  b4 <- g; b4$network$co3$run <- list(host = "m1")
  check(any(grepl("no datetime_utc", viol_split(b4))),
        "must-fail: a run block without datetime_utc IS reported")
  b5 <- g; b5$landcover$co_ff04$inputs_hash <- NULL
  check(any(grepl("no inputs_hash", viol_split(b5))), "must-fail: a missing inputs_hash IS reported")
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
  x <- g; x$floodplain$co_ff04$inputs$surprise <- 1
  check(any(grepl("UNDECLARED", viol_keys(x))),
        "must-fail: an UNDECLARED key IS reported (whitelist, not just completeness)")
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
  tr <- g; tr$landcover$co_ff04$inputs$item_ids_complete <- FALSE
  check(any(grepl("TRUNCATED", viol_coverage(tr))),
        "must-fail: item_ids_complete = FALSE is a FAILURE, not a note")
  nh <- g; nh$landcover$co_ff04$inputs$classified_content_sha256 <- list(`2017` = NA, `2023` = NA)
  check(any(grepl("classified raster digest", viol_coverage(nh))),
        "must-fail: a landcover section with NO content digest IS reported")
}

# --- 5b. Database-shaped values -------------------------------------------------------------------
# NONE of the checks above could reach the bug that actually shipped. Every fixture here is
# hand-built, so no DBI value ever entered them, and `pq__text` -- the class RPostgres gives a
# `text[]` column -- was serialized by nothing until step 1 met a real log row. It failed with
# "No method asJSON S3 class: pq__text" AFTER the network had been built.
#
# So construct the database shapes offline. This is the fixture axis the rest of the file does not
# vary, and it is the one that matters: the guard runs without a database precisely because most
# runs of it will not have one.
cat("\n5b. Database-shaped values\n")
{
  # A pq__text column is NOT a list: is.list() is FALSE and length() is 1, which is why every
  # earlier type branch skipped it. The value inside is the RAW Postgres array literal.
  pq <- structure(list("{BT,CH,CO}"), class = "pq__text")
  check(!is.list(unclass(pq)[[1]]) && !is.list(pq[[1]]),
        "premise: the inner value is the raw array literal, not a vector")
  got <- fp_prov_scalar(pq)
  check(identical(as.character(got), c("BT", "CH", "CO")),
        "a pq__text column parses to a character vector, not one brace-wrapped string")
  check(is.na(fp_prov_scalar(structure(list("{}"), class = "pq__text"))),
        "an EMPTY pg array is recorded as absent, not as the literal \"{}\"")

  check(identical(as.character(fp_pg_array('{A,"with,comma",C}')), c("A", "with,comma", "C")),
        "a quoted element containing a comma survives the split")
  check(identical(as.character(fp_pg_array("{KISP}")), "KISP") &&
          inherits(fp_pg_array("{KISP}"), "AsIs"),
        "a one-element array keeps ARRAY shape (auto_unbox would collapse it to a scalar)")

  # timestamptz -> the session timezone must not reach the bytes.
  tz <- Sys.getenv("TZ"); on.exit(Sys.setenv(TZ = tz), add = TRUE)
  ts <- as.POSIXct("2026-09-02 00:18:57", tz = "UTC")
  Sys.setenv(TZ = "America/Vancouver"); a <- fp_prov_scalar(ts)
  Sys.setenv(TZ = "UTC");               b <- fp_prov_scalar(ts)
  check(identical(a, b) && grepl("Z$", a), "a timestamp serializes in UTC regardless of session TZ")

  # And the backstop: anything still unserializable is named by PATH, not by jsonlite's
  # class-only message.
  err <- tryCatch({ fp_prov_assert_serializable(list(inputs = list(nested = new.env())),
                                                "provenance"); "" },
                  error = function(e) conditionMessage(e))
  check(grepl("provenance\\$inputs\\$nested", err),
        "must-fail: an unserializable value IS reported, naming its path")
  check(tryCatch({ fp_prov_assert_serializable(
           list(inputs = list(a = 1, b = I(c("x", "y")), c = NA)), "provenance"); TRUE },
         error = function(e) FALSE),
        "a clean object is not a false alarm")
}

# --- 5c. The content digest is a CONTENT digest -------------------------------------------------
# The property #64 exists to establish: two writes of the SAME VALUES whose containers differ must
# produce the SAME digest. This is the guard that was missing -- the old field hashed the file, so
# it moved with whatever the writer's version put in the header, and nothing here could see it. It
# took two machines to notice; this fixture reaches it offline.
#
# The premise is asserted INLINE, not assumed. If a future terra stops writing the extra metadata
# the two files become byte-identical, the property passes for nothing, and the test quietly stops
# testing. Then the premise line fails instead, naming the real cause.
if (requireNamespace("terra", quietly = TRUE) && requireNamespace("digest", quietly = TRUE)) {
  cat("\n5c. Content digest is invariant to the container\n")
  d <- file.path(tempdir(), paste0("fp_prov_digest_", Sys.getpid()))
  dir.create(d, showWarnings = FALSE, recursive = TRUE)
  # NOT on.exit(): this is the top level of a script, so the "current frame" is the global
  # environment, which never exits -- the handler is registered and simply never called. Verified
  # while writing this: a marker directory survived the run. Clean up explicitly at the end of the
  # block instead. (CLAUDE.md, "`on.exit()` at a script's top level never fires".)
  a <- file.path(d, "a.tif"); b <- file.path(d, "b.tif")

  set.seed(1)
  r <- terra::rast(nrows = 40, ncols = 50, xmin = 0, xmax = 500, ymin = 0, ymax = 400,
                   crs = "EPSG:3005")
  # NAs on purpose: the nodata cells are where the two toolchains disagreed (NaN vs NA_integer_),
  # so a fixture with no missing values cannot reach the failure mode at all.
  terra::values(r) <- sample(c(1:5, NA), terra::ncell(r), replace = TRUE)
  terra::writeRaster(r, a, overwrite = TRUE, datatype = "INT1U")

  # Stand in for the other toolchain: identical values, extra container metadata -- the same
  # gdalcubes NetCDF attributes terra 1.9.11 carries into the header and 1.9.34 drops.
  r2 <- terra::rast(a)
  terra::metags(r2) <- c(crs.GeoTransform = "0 10 0 400 0 -10", data.scale_factor = "1",
                         data.add_offset = "0", data.grid_mapping = "crs")
  terra::writeRaster(r2, b, overwrite = TRUE, datatype = "INT1U")

  fa <- digest::digest(file = a, algo = "sha256")
  fb <- digest::digest(file = b, algo = "sha256")
  check(fa != fb, "premise: the two containers really do differ in bytes")
  check(identical(terra::values(terra::rast(a)), terra::values(terra::rast(b))),
        "premise: the two rasters carry identical cell values")
  check(identical(fp_raster_content_sha256(a), fp_raster_content_sha256(b)),
        "content digest AGREES across differing containers (the #64 property)")

  # ... and it must still be able to fail. A digest that never moves is worse than one that moves
  # too often, so both directions are exercised: a changed value, and a cell becoming nodata.
  rv <- terra::rast(a); v <- terra::values(rv)
  i <- which(!is.na(v))[1]; v[i] <- v[i] + 1; terra::values(rv) <- v
  cc <- file.path(d, "c.tif"); terra::writeRaster(rv, cc, overwrite = TRUE, datatype = "INT1U")
  check(!identical(fp_raster_content_sha256(a), fp_raster_content_sha256(cc)),
        "must-fail: ONE changed cell value MOVES the content digest")

  rn <- terra::rast(a); vn <- terra::values(rn)
  j <- which(!is.na(vn))[2]; vn[j] <- NA; terra::values(rn) <- vn
  dd <- file.path(d, "d.tif"); terra::writeRaster(rn, dd, overwrite = TRUE, datatype = "INT1U")
  check(!identical(fp_raster_content_sha256(a), fp_raster_content_sha256(dd)),
        "must-fail: ONE cell becoming nodata MOVES the content digest")

  # The old implementation, restored. It must FAIL the property above -- otherwise this whole
  # section is decoration and would have passed before the fix as happily as after it.
  old_file_sha <- function(path) paste0("sha256:", digest::digest(file = path, algo = "sha256"))
  check(!identical(old_file_sha(a), old_file_sha(b)),
        "restored defect: the OLD file hash disagrees on the same values (why this changed)")

  # block_rows is part of the contract, not a tuning knob. Assert the DEFAULT directly rather than
  # through a comparison: this fixture is 40 rows, so 512 and 256 both yield a single block and any
  # default above 40 would pass. That is the shape of a test whose fixture cannot reach the property
  # it names -- caught here by the assertion below going red on the first draft.
  check(identical(formals(fp_raster_content_sha256)$block_rows, 512L),
        "block_rows defaults to 512 -- changing it would invalidate every digest ever recorded")
  check(!identical(fp_raster_content_sha256(a, block_rows = 8L),
                   fp_raster_content_sha256(a, block_rows = 16L)),
        "premise: block_rows really does change the digest (sizes that actually split 40 rows)")

  unlink(d, recursive = TRUE)
  check(!dir.exists(d), "the fixture directory is cleaned up (on.exit would not have fired here)")
} else {
  bad("terra/digest unavailable -- the content-digest property was NOT checked (a skip is not a pass)")
}

# --- 6. Producer/guard key drift -----------------------------------------------------------------
# The guard's declared key sets are only worth their maintenance if they match what the STEPS
# actually write. A typo on either side would otherwise surface as a failure after a 30-minute
# pipeline run, and a key the producer stopped writing would surface as nothing at all.
#
# Parses the step scripts rather than grepping them. The first regex version of this reported 1 key
# where there are 9 -- loudly wrong, which was lucky; a scanner wrong in the reassuring direction
# would have reported MATCH for nothing. Hence the positive control below: the scanner must be
# shown able to FIND keys before "no mismatch" means anything.
cat("\n6. Producer/guard key drift\n")
find_calls <- function(expr, fname, acc = list()) {
  if (!is.call(expr)) return(acc)
  if (identical(as.character(expr[[1]])[1], fname)) acc[[length(acc) + 1L]] <- expr
  parts <- as.list(expr)
  for (i in seq_along(parts)) {
    # `row[1, ]` puts R EMPTY SYMBOL in the arg list. Binding it to a variable makes that
    # variable a MISSING ARGUMENT, so every later touch -- is.null(), is.call(), even the
    # tryCatch guard -- errors with "argument is missing". deparse() is the one operation that
    # handles it, returning "".
    if (!nzchar(paste(deparse(parts[[i]]), collapse = ""))) next
    if (is.call(parts[[i]])) acc <- find_calls(parts[[i]], fname, acc)
  }
  acc
}
prov_keys <- function(file, section) {
  calls <- unlist(lapply(parse(file), find_calls, fname = "fp_prov_set"), recursive = FALSE)
  for (cl in calls) {
    if (!identical(as.character(cl[[3]]), section)) next
    body <- cl[[5]]                                  # the list(inputs = ..., ...)
    inputs <- body[["inputs"]]
    # inputs may be `list(...)` or `c(list(...), other)`
    lists <- find_calls(inputs, "list")
    nm <- unlist(lapply(lists, function(l) names(as.list(l))))
    return(sort(unique(nm[nzchar(nm)])))
  }
  character(0)
}
{
  step <- function(f) file.path(dirname(sub("^--file=", "",
    grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), f)
  net <- prov_keys(step("01_network_extract.R"), "network")
  fpl <- prov_keys(step("02_floodplain_model.R"), "floodplain")
  # item_ids / item_hash / item_ids_complete are supplied by fp_prov_stac_items(), spliced into
  # `inputs` at the call site, so they are not literals in the step script.
  lcv <- sort(unique(c(prov_keys(step("03_lulc_classify.R"), "landcover"),
                       c("item_ids", "item_hash", "item_ids_complete"))))
  check(length(net) > 3, "premise: the scanner resolves keys at all (positive control)")
  drift1 <- function(label, got, want) {
    d <- c(setdiff(want, got), setdiff(got, want))
    check(length(d) == 0, sprintf("%s producer writes exactly the %d declared key(s)%s",
      label, length(want),
      if (length(d)) paste0(" -- differs: ", paste(d, collapse = ", ")) else ""))
  }
  drift1("network", net, KEYS_NETWORK_INPUTS)
  drift1("floodplain", fpl, KEYS_FLOODPLAIN)
  drift1("landcover", lcv, KEYS_LANDCOVER)
}

# --- 7. A real area, when one is named -----------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
if (length(args) >= 1 && nzchar(args[1])) {
  area <- args[1]
  path <- file.path(fp_root, "data", area, "provenance.json")
  cat("\n7. Real area: ", path, "\n", sep = "")
  cat("   (repo root resolved from this script: ", fp_root, ")\n", sep = "")
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

    # --- 7b. INVENTORY: every entry the config says should exist, does -----------------------------
    # The properties above are all of the form "every entry PRESENT is well-formed". None of them can
    # see an entry that is simply ABSENT, so a run that died partway -- after step 2 had written its
    # sections and before step 3 wrote its own -- produces a file every one of them passes. Measured:
    # a neexdzii run that aborted in step 3 left 3 entries of an expected 5 and this script exited 0.
    #
    # That also breaks the A/B's mtime gate, which is why this is an assertion and not a nicety: step
    # 2 bumps provenance.json's mtime, so `-nt` is satisfied by a run that never reached step 3. The
    # in-band error count catches it; nothing else did.
    #
    # The expectation is DERIVED FROM THE CONFIG, not hardcoded: a literal list would silently stop
    # covering a scenario the moment one was added. Mirrors run_area.R's own resolution, including the
    # FP_SPECIES / FP_PRIMARY_SCENARIO env overrides, so a non-default-species run asserts its own set.
    cfg_dir <- file.path(fp_root, "config", area)
    if (!dir.exists(cfg_dir)) {
      bad(sprintf("no config/%s -- cannot derive the expected entry set", area))
    } else {
      ay  <- yaml::read_yaml(file.path(cfg_dir, "area.yml"))
      sp  <- Sys.getenv("FP_SPECIES", "");           if (!nzchar(sp)) sp <- ay$species
      ps  <- Sys.getenv("FP_PRIMARY_SCENARIO", "");  if (!nzchar(ps)) ps <- ay$primary_scenario
      if (is.null(ps) || !nzchar(ps)) ps <- paste0(sp, "_ff04")
      # Read it with the PRODUCER's reader. utils::read.csv and readr::read_csv disagree on a cell
      # like " TRUE" -- readr trims it to logical TRUE, read.csv's type.convert leaves a string -- so a
      # guard using the other reader derives a different expected set from the same file, and then
      # excuses the surplus as an "extra". One fact, one derivation.
      sc <- readr::read_csv(file.path(cfg_dir, "flood_scenarios.csv"), show_col_types = FALSE)
      # 02 runs run==TRUE rows OF THIS SPECIES (#23); 03 runs the primary scenario only.
      # Mirror 02_floodplain_model.R: run == TRUE rows OF THIS SPECIES (#23). which() drops NA rows
      # rather than subsetting them in as NA ids.
      sel <- sc$run == TRUE & sc$species == sp
      run_ids <- sc$scenario_id[which(sel)]
      # paste0 recycles a ZERO-LENGTH vector against its constants and returns "floodplain[]" --
      # length one, not zero. Unguarded, a config with no matching row would expect a phantom entry
      # and the failure would name the wrong cause.
      if (!length(run_ids))
        bad(sprintf("no run==TRUE '%s' rows in config/%s/flood_scenarios.csv", sp, area))
      want <- c(paste0("network[", sp, ay$min_order, "]"),
                if (length(run_ids)) paste0("floodplain[", run_ids, "]"),
                paste0("landcover[", ps, "]"))
      got  <- vapply(prov_sections(prov), function(e) paste0(e$section, "[", e$key, "]"), "")
      miss <- setdiff(want, got)
      check(length(miss) == 0,
            sprintf("all %d config-derived entries present%s", length(want),
                    if (length(miss)) paste0(" -- MISSING: ", paste(miss, collapse = ", ")) else ""))
      # Not an error, but say so: an entry nothing in the config asks for means the config moved and
      # the file still carries the old run's work.
      extra <- setdiff(got, want)
      if (length(extra)) ok(paste0("note: entries not in the current config: ",
                                   paste(extra, collapse = ", ")))
    }
    if (n > 0) check(TRUE, "real file checked against all properties")
  }
}

cat("\n", if (FAILS == 0L) "PASS — all properties hold, and each was shown able to fail.\n"
         else sprintf("FAIL — %d problem(s).\n", FAILS), sep = "")
quit(status = if (FAILS == 0L) 0L else 1L)
