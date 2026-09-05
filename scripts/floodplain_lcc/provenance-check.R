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

# Declared keys ONE LEVEL UP, at the body. Until #65 there was no check here at all -- viol_keys
# whitelists `inputs` and nothing whitelists `inputs`'s SIBLINGS. That gap is how defect #1
# happened: `link_log` sits beside `inputs`, outside the hash and outside every property, and a
# live file was measured carrying 30 columns in it including `host` and `run_id` -- two members of
# RUN_FIELDS, invisible to the run-field guard because that guard reads names(inputs). Adding
# `outputs` as a third unguarded sibling would ratify the pattern, so close it in the same change.
KEYS_BODY <- c("inputs", "inputs_hash", "outputs", "outputs_hash", "run",
               "link_log", "link_log_note")

# The closed vocabulary fp_pkg_stamp() may report (#65). It used to interpolate the checkout PATH
# and the checkout VERSION into this string, inside hashed `inputs` -- measured live in
# data/neexdzii, and measured DIFFERING between m1 and m4 under #63 while every substantive field
# matched. A free-text field in the byte-stable half makes the cross-machine criterion unreadable.
SHA_SOURCES <- c("env", "RemoteSha", "git", "unresolved", "unresolved_version_mismatch")

# Declared keys for `run$toolchain`. The raster toolchain is the one thing #64 adds and the ONLY
# provenance field with no drift protection: the producer/guard drift check (§6) parses the
# `inputs = ...` argument of fp_prov_set and never looks at `run`, and viol_split only requires that
# `run` carry datetime_utc. So an edit dropping `toolchain = fp_toolchain()` would be silent and the
# record would quietly return to the state #64 calls undiagnosable. Sections that write rasters must
# carry it, populated -- an all-NA toolchain is the same absence wearing a key.
KEYS_TOOLCHAIN         <- c("terra", "sf", "gdal", "geos", "proj")
SECTIONS_WITH_RASTERS  <- c("floodplain", "landcover")
TOOLCHAIN_FIXTURE      <- list(terra = "1.9.34", sf = "1.1.2", gdal = "3.8.5",
                               geos = "3.12.1", proj = "9.3.1")

# Declared key sets. Present-with-null beats omitted: an absent key reads as "not implemented",
# a null one reads as "we looked and there was not one", and only the second is true.
KEYS_NETWORK_INPUTS <- c("watershed_group", "species", "min_order", "network_source",
                         "read_schema", "subset", "link_config_name", "link_config_name_source",
                         "network_content_sha256", "link", "fresh")
KEYS_LINK_LOG       <- c("run_uid", "config_hash", "config_name", "link_sha", "link_dirty",
                         "fwapg_sha", "bcfp_model_version", "bcfp_pin_source", "date_start",
                         "date_end")

# Declared keys for the `outputs` blocks (#65). Sections absent from this list are declared to write
# no outputs, and viol_keys reports one that appears anyway -- so the whitelist works in both
# directions the way the `inputs` one does.
KEYS_NETWORK_OUTPUTS    <- c("streams_layer", "streams_content_sha256", "n_segments")
KEYS_FLOODPLAIN_OUTPUTS <- c("floodplain_raster", "floodplain_content_sha256", "valley_cells")
KEYS_LANDCOVER_OUTPUTS  <- c("transition_raster", "transition_content_sha256",
                             "transition_patches")

# Sections absent from this list are declared to write NO outputs, and viol_keys reports a block
# that appears anyway -- so the whitelist works in both directions, like the `inputs` one. A
# top-level constant rather than a local, so the "a section that declares none" test can move the
# SCOPE (the thing that grants the exemption) instead of relying on a section that happens to have
# no outputs yet -- which stops being a test the moment that section gains one.
KEYS_OUTPUTS_BY_SECTION <- list(network = KEYS_NETWORK_OUTPUTS,
                                floodplain = KEYS_FLOODPLAIN_OUTPUTS,
                                landcover = KEYS_LANDCOVER_OUTPUTS)

# Which sections write an `outputs` block, as a JUDGEMENT, stated. Paired with a derivation from the
# producers in section 6 and asserted setequal, mirroring SECTIONS_WITH_RASTERS. Derived alone would
# go empty and silent the moment a producer dropped the block; declared alone would drift.
# Read from fp_provenance.R, not re-declared: provenance_ab-compare.R needs the same list and a
# second copy would be a literal pinned to nothing. Section 6 asserts it against the producers.
SECTIONS_WITH_OUTPUTS <- FP_SECTIONS_WITH_OUTPUTS

# The link config bundle 01 BUILDS with. Pinned to 01's own lnk_config() literal in section 6, which
# is the only EXTERNAL reference available for the BUILD branch -- comparing the recorded
# link_config_name against the log row it was assigned from could not disagree.
LNK_BUILD_CONFIG_EXPECTED <- "default"
KEYS_FLOODPLAIN     <- c("wsg", "species", "scenario", "flood_factor", "slope_threshold",
                         "max_width", "cost_threshold", "size_threshold", "hole_threshold",
                         "anchor_order", "dem_resolver", "dem_crs_epsg", "dem_res_m", "dem_ncell",
                         "dem_content_sha256",
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
    tc  <- e$body[["run"]][["toolchain"]]
    tc_problem <- if (e$section %in% SECTIONS_WITH_RASTERS) {
      if (is.null(tc)) sprintf("%s[%s] run has no toolchain block (terra/sf/gdal)", e$section, e$key)
      else if (length(setdiff(KEYS_TOOLCHAIN, names(tc))))
        sprintf("%s[%s] run$toolchain missing: %s", e$section, e$key,
                paste(setdiff(KEYS_TOOLCHAIN, names(tc)), collapse = ", "))
      else if (all(vapply(tc[KEYS_TOOLCHAIN], function(x) is.null(x) || is.na(x[1]), logical(1))))
        sprintf("%s[%s] run$toolchain is entirely NA -- the absence this field exists to remove",
                e$section, e$key)
    }
    # ABSOLUTE assertion first. An intersection test alone passes when `run` is absent, empty or
    # renamed -- a section that lost its whole run block is exactly the defect this check is for,
    # and set arithmetic on nothing is silent about it.
    out <- names(e$body[["outputs"]] %||% list())
    # FOUR arms, not one. `outputs` must not overlap `inputs` (which would fold an answer into the
    # ingredients question), must not overlap `run`, must not carry a run-event field (a timestamp
    # in `outputs` churns outputs_hash every run and the A/B then fails for a reason nobody can
    # read), and must be accompanied by its hash in BOTH directions -- a hash with no block is as
    # broken as a block with no hash, and only one of those is the obvious one.
    out_problem <- c(
      if (length(out) && is.null(e$body[["outputs_hash"]]))
        sprintf("%s[%s] has an `outputs` block but no outputs_hash", e$section, e$key),
      if (!length(out) && !is.null(e$body[["outputs_hash"]]))
        sprintf("%s[%s] has an outputs_hash with no `outputs` block", e$section, e$key),
      if (length(intersect(out, RUN_FIELDS)))
        sprintf("%s[%s].outputs carries run-event field(s): %s", e$section, e$key,
                paste(intersect(out, RUN_FIELDS), collapse = ", ")),
      if (length(intersect(out, inp)))
        sprintf("%s[%s] inputs/outputs key sets overlap: %s", e$section, e$key,
                paste(intersect(out, inp), collapse = ", ")),
      if (length(intersect(out, run)))
        sprintf("%s[%s] outputs/run key sets overlap: %s", e$section, e$key,
                paste(intersect(out, run), collapse = ", ")))
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
                paste(intersect(inp, run), collapse = ", ")),
      out_problem, tc_problem)
  }))
}

# The body-level whitelist. Same reasoning as viol_keys' undeclared-key arm, one level up: a
# denylist for "fields that should not be here" can always be outrun by a new one; "only these may
# appear" cannot.
viol_body <- function(prov) {
  unlist(lapply(prov_sections(prov), function(e) {
    und <- setdiff(names(e$body %||% list()), KEYS_BODY)
    if (length(und)) sprintf("%s[%s] has UNDECLARED body key(s): %s", e$section, e$key,
                             paste(und, collapse = ", "))
  }))
}

# Every package stamp inside `inputs` reports a sha_source from the closed vocabulary. Walks the
# nested stamps rather than naming link/fresh/flooded/drift, so a section that starts stamping a
# fifth package is covered without an edit here.
viol_sha_source <- function(prov) {
  unlist(lapply(prov_sections(prov), function(e) {
    inp <- e$body[["inputs"]] %||% list()
    unlist(lapply(names(inp), function(k) {
      v <- inp[[k]]
      if (!is.list(v) || is.null(v[["sha_source"]])) return(NULL)
      src <- as.character(v[["sha_source"]])
      if (!src %in% SHA_SOURCES)
        sprintf("%s[%s].inputs.%s.sha_source is free text, not one of {%s}: %s",
                e$section, e$key, k, paste(SHA_SOURCES, collapse = ", "), substr(src, 1, 70))
    }))
  }))
}

viol_keys <- function(prov) {
  want <- list(network = KEYS_NETWORK_INPUTS, floodplain = KEYS_FLOODPLAIN,
               landcover = KEYS_LANDCOVER)
  want_out <- KEYS_OUTPUTS_BY_SECTION
  unlist(lapply(prov_sections(prov), function(e) {
    have <- names(e$body[["inputs"]] %||% list())
    have_out <- names(e$body[["outputs"]] %||% list())
    wo <- want_out[[e$section]]
    out_problem <- if (is.null(wo)) {
      if (length(have_out))
        sprintf("%s[%s] writes an `outputs` block but none is declared for that section",
                e$section, e$key)
    } else {
      c(if (length(setdiff(wo, have_out)))
          sprintf("%s[%s].outputs missing: %s", e$section, e$key,
                  paste(setdiff(wo, have_out), collapse = ", ")),
        if (length(setdiff(have_out, wo)))
          sprintf("%s[%s].outputs has UNDECLARED key(s): %s", e$section, e$key,
                  paste(setdiff(have_out, wo), collapse = ", ")))
    }
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
      out_problem, extra)
  }))
}

# The config-name property, and it is the arm with an EXTERNAL reference (#65). A GRAB reads a
# network somebody else built, so the only honest source for the config that produced it is the log
# row -- a GRAB reporting `built_literal` is claiming a locally-assumed methodology for a network
# this machine did not build, which is exactly the defect measured live in data/neexdzii
# ("default" recorded beside a log row saying "bcfishpass").
#
# Asserting `link_config_name == link_log$config_name` is NOT that check: 01 assigns one from the
# other, so it cannot disagree, and whether it fires would depend on statement order rather than on
# truth. It is kept below as a second arm only because it would catch a FUTURE producer that
# decoupled them; it earns nothing on its own.
viol_config_name <- function(prov) {
  unlist(lapply(prov_sections(prov), function(e) {
    if (!identical(e$section, "network")) return(NULL)
    inp <- e$body[["inputs"]] %||% list()
    src <- inp[["link_config_name_source"]]
    nm  <- inp[["link_config_name"]]
    is_grab <- isTRUE(grepl("^GRAB", as.character(inp[["network_source"]] %||% "")))
    log_nm <- (e$body[["link_log"]] %||% list())[["config_name"]]
    c(if (is.null(src) || !as.character(src) %in%
            c("built_literal", "link_log", "unresolved"))
        sprintf("network[%s].inputs.link_config_name_source is not one of {built_literal, link_log, unresolved}: %s",
                e$key, substr(as.character(src %||% "<absent>"), 1, 40)),
      if (is_grab && identical(as.character(src), "built_literal"))
        sprintf("network[%s] GRABbed its network but reports link_config_name_source = built_literal -- it is asserting a config this machine did not run",
                e$key),
      if (identical(as.character(src), "link_log") && !is.null(log_nm) && !is.na(log_nm) &&
            !identical(as.character(nm), as.character(log_nm)))
        sprintf("network[%s] link_config_name '%s' disagrees with link_log.config_name '%s'",
                e$key, as.character(nm), as.character(log_nm)),
      if (identical(as.character(src), "unresolved") && !is.null(nm) && !is.na(nm))
        sprintf("network[%s] reports an unresolved config source but names a config anyway: %s",
                e$key, as.character(nm)))
  }))
}

# The schema version, and the reason it is a property at all (#65). Until now it was asserted
# NOWHERE -- it appeared only in the skeleton, in an unconditional overwrite on every read, and in a
# fixture. That overwrite is the sharp edge: `fp_prov_read` stamps the CURRENT version on whatever
# it reads, so bumping the constant and re-running only step 2 labels a file v2 while its network
# and landcover sections are still v1 content, and stac_floodplains_bc is downstream of that label.
#
# This check alone cannot see that -- a version equality is a claim about a number. What makes the
# label honest is this PAIRED with viol_keys, which now requires the v2 field set (`outputs` +
# `outputs_hash`) on every section declared to write one, so a v1 section under a v2 label is
# reported as a missing outputs block. Neither is sufficient alone; say so rather than let the
# version check look like it is doing the work.
viol_schema_version <- function(prov) {
  v <- prov[["schema_version"]]
  c(if (is.null(v)) "provenance.json has no schema_version",
    if (!is.null(v) && !identical(as.integer(v), as.integer(FP_PROV_SCHEMA_VERSION)))
      sprintf("schema_version is %s but this guard checks %s", as.character(v),
              FP_PROV_SCHEMA_VERSION))
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
      # PER YEAR, like the item_ids arm below. `all(is.na(unlist(x)))` cannot see ONE missing year:
      # all() needs every year absent, and unlist() DROPS a JSON null outright, so a year written as
      # null is not even a counted NA. Reachable -- fp_raster_content_sha256() returns NA whenever
      # the file is absent or 0 bytes, which is exactly "the writer produced nothing and the record
      # says it did". The old §5 fixture set every year to NA, so it could not tell all from any.
      if (is.null(inp[["classified_content_sha256"]]))
        sprintf("landcover[%s] has no classified raster digest at all", e$key),
      unlist(lapply(names(inp[["classified_content_sha256"]] %||% list()), function(y) {
        dy <- inp[["classified_content_sha256"]][[y]]
        if (is.null(dy) || !length(unlist(dy)) || all(is.na(unlist(dy))))
          sprintf("landcover[%s] year %s has no classified raster digest", e$key, y)
      })),
      # The digest year set must match the years actually modelled, or 2 digests for a 3-year run
      # passes every check above by being internally consistent.
      if (!is.null(inp[["years"]]) && !is.null(inp[["classified_content_sha256"]]) &&
          !setequal(as.character(unlist(inp[["years"]])),
                    names(inp[["classified_content_sha256"]])))
        sprintf("landcover[%s] digest years {%s} do not match modelled years {%s}", e$key,
                paste(names(inp[["classified_content_sha256"]]), collapse = ","),
                paste(unlist(inp[["years"]]), collapse = ",")),
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
      inputs = utils::modifyList(
        nul(KEYS_NETWORK_INPUTS),
        list(network_source = "GRAB from fresh", link_config_name = "bcfishpass",
             link_config_name_source = "link_log")),
      inputs_hash = "sha256:aa",
      outputs = stats::setNames(as.list(rep(NA, length(KEYS_NETWORK_OUTPUTS))),
                                KEYS_NETWORK_OUTPUTS),
      outputs_hash = "sha256:aa2",
      link_log = utils::modifyList(nul(KEYS_LINK_LOG), list(config_name = "bcfishpass")),
      run = list(datetime_utc = "2026-09-01T00:00:00Z"))),
    floodplain = list(co_ff04 = list(
      inputs = nul(KEYS_FLOODPLAIN), inputs_hash = "sha256:bb",
      outputs = nul(KEYS_FLOODPLAIN_OUTPUTS), outputs_hash = "sha256:bb2",
      run = list(datetime_utc = "2026-09-01T00:00:00Z", toolchain = TOOLCHAIN_FIXTURE))),
    landcover = list(co_ff04 = list(
      # modifyList, NOT c(): `c()` APPENDS, so a key present in both halves lands twice and `$`
      # then returns the first one -- which is how a later assignment silently fails to take.
      inputs = utils::modifyList(
        nul(KEYS_LANDCOVER),
        list(item_ids = list(`2017` = list("09U-2017"), `2023` = list("09U-2023")),
             item_ids_complete = TRUE,
             # `years` must agree with the digest year set, or the fixture is not a clean one --
             # it was NA here, which made the new year-set assertion fire on the good fixture.
             years = list(2017L, 2023L),
             classified_content_sha256 = list(`2017` = "sha256:11", `2023` = "sha256:22"))),
      inputs_hash = "sha256:cc",
      outputs = stats::setNames(as.list(rep(NA, length(KEYS_LANDCOVER_OUTPUTS))),
                                KEYS_LANDCOVER_OUTPUTS),
      outputs_hash = "sha256:cc2",
      run = list(datetime_utc = "2026-09-01T00:00:00Z", toolchain = TOOLCHAIN_FIXTURE))))
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
  # `[[` and an existence premise, not `$<-`. After the #64 rename this read `h$classified_sha256$...`
  # for a while: `$<-` CREATES a missing key, so the hash still moved and the check still passed --
  # having silently become "adding an arbitrary key moves inputs_hash", which is a different and
  # much weaker claim. Assert the key is there before perturbing it.
  check(!is.null(g$landcover$co_ff04$inputs[["classified_content_sha256"]][["2017"]]),
        "premise: the digest being perturbed below actually exists in the fixture")
  check(perturb(function(h) { h[["classified_content_sha256"]][["2017"]] <- "sha256:ff"; h }) != base,
        "criterion 2: a reprocessed landcover raster MOVES inputs_hash")
  check(perturb(function(h) h) == base, "an unchanged input does NOT move inputs_hash")

  # --- outputs_hash is a SECOND hash, not part of the first (#65) -----------------------------
  # Routed through fp_prov_set and read back off DISK, deliberately. Perturbing fp_prov_hash()
  # directly could not fail: that function is handed `value$inputs` and structurally cannot see
  # `outputs`, so the assertion would be true of a writer that folded outputs in as happily as of
  # one that did not. The mutant this guards is somebody writing `fp_prov_hash(value)` in
  # fp_prov_set, and only the written file can see it.
  cfg2 <- fixture_cfg()
  ent <- g$floodplain$co_ff04
  ent$outputs <- list(floodplain_content_sha256 = "sha256:aaa")
  fp_prov_set(cfg2, "floodplain", "co_ff04", ent)
  w1 <- jsonlite::read_json(fp_prov_path(cfg2), simplifyVector = FALSE)$floodplain$co_ff04
  ent$outputs <- list(floodplain_content_sha256 = "sha256:bbb")
  fp_prov_set(cfg2, "floodplain", "co_ff04", ent)
  w2 <- jsonlite::read_json(fp_prov_path(cfg2), simplifyVector = FALSE)$floodplain$co_ff04
  check(!is.null(w1[["outputs_hash"]]) && !is.null(w2[["outputs_hash"]]),
        "premise: fp_prov_set actually wrote an outputs_hash for both")
  check(identical(w1[["inputs_hash"]], w2[["inputs_hash"]]),
        "a changed OUTPUT does NOT move inputs_hash (the two questions stay separate)")
  check(!identical(w1[["outputs_hash"]], w2[["outputs_hash"]]),
        "a changed OUTPUT DOES move outputs_hash")

  # ... and absence stays absence. An unconditional assignment would stamp every entry with a null
  # outputs_hash -- fp_prov_hash(NULL) is NA_character_ -- and viol_split's "outputs_hash with no
  # outputs" arm could then never fire.
  cfg3 <- fixture_cfg()
  # Built by REMOVAL from the fixture, not by picking a section that happens to have no outputs --
  # every section gains one as the phases land, and a mutant built the other way silently stops
  # being a mutant.
  no_out <- g$floodplain$co_ff04; no_out$outputs <- NULL; no_out$outputs_hash <- NULL
  check(is.null(no_out[["outputs"]]), "premise: the mutant really has no outputs block")
  fp_prov_set(cfg3, "floodplain", "co_ff04", no_out)
  w3 <- jsonlite::read_json(fp_prov_path(cfg3), simplifyVector = FALSE)$floodplain$co_ff04
  check(!"outputs_hash" %in% names(w3),
        "an entry with no `outputs` gets NO outputs_hash key at all, not a null one")

  # An outputs-only write would blank `inputs` -- fp_prov_set REPLACES the whole entry -- and set
  # inputs_hash to NA. That is the shape #72's vector digest will arrive in, so refuse it now.
  check(tryCatch({ fp_prov_set(cfg3, "floodplain", "x", list(outputs = list(a = 1),
                                                             run = list(datetime_utc = "z")))
                   FALSE }, error = function(e) grepl("no `inputs` block", conditionMessage(e))),
        "must-fail: an outputs-only write IS refused (it would blank the inputs half)")
  # ... and the shape that DEFEATED that guard while it read with `$`. Partial matching resolves
  # `value$inputs` to `inputs_hash`, so an entry carrying the hash and no inputs block sailed
  # through the refusal written for exactly it. The premise is asserted so nobody tidies `[[` back.
  hash_only <- list(inputs_hash = "sha256:x", outputs = list(a = 1),
                    run = list(datetime_utc = "z"))
  check(is.null(hash_only[["inputs"]]) && !is.null(hash_only$inputs),
        "premise: `$` DOES partial-match inputs -> inputs_hash (why fp_prov_set uses `[[`)")
  check(tryCatch({ fp_prov_set(cfg3, "floodplain", "y", hash_only); FALSE },
                 error = function(e) grepl("no `inputs` block", conditionMessage(e))),
        "restored defect: an entry with ONLY an inputs_hash IS refused, not partial-matched")
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

  # The toolchain block. It is the one field #64 adds and the only one §6's producer/guard drift
  # check cannot see, so its three failure shapes are exercised here or it is not a guard at all.
  b6 <- g; b6$landcover$co_ff04$run$toolchain <- NULL
  check(any(grepl("no toolchain block", viol_split(b6))),
        "must-fail: a landcover run with NO toolchain IS reported")
  b7 <- g; b7$floodplain$co_ff04$run$toolchain$gdal <- NULL
  check(any(grepl("toolchain missing: gdal", viol_split(b7))),
        "must-fail: a toolchain missing one member IS reported")
  # All five present and all NA -- otherwise the "missing member" arm fires first and this stops
  # testing the arm it names. Derive it from KEYS_TOOLCHAIN so adding a member cannot rot it.
  b8 <- g
  b8$landcover$co_ff04$run$toolchain <- stats::setNames(
    as.list(rep(NA_character_, length(KEYS_TOOLCHAIN))), KEYS_TOOLCHAIN)
  check(any(grepl("entirely NA", viol_split(b8))),
        "must-fail: an all-NA toolchain IS reported (an absence wearing a key)")
  # ... and the network section, which writes no raster, must NOT be required to carry one. Setting
  # its toolchain to NULL is a NO-OP -- the fixture never had one, so that mutant is identical() to
  # the clean fixture and the check restates the clean-fixture assertion instead of exercising the
  # exemption. Exercise the exemption by moving the SCOPE, which is the thing that grants it.
  check(!any(grepl("toolchain", viol_split(g))),
        "the network section is not required to carry a toolchain (it writes no raster)")
  local({
    keep <- SECTIONS_WITH_RASTERS
    SECTIONS_WITH_RASTERS <<- c(keep, "network")
    fired <- any(grepl("network\\[co3\\] run has no toolchain", viol_split(g)))
    SECTIONS_WITH_RASTERS <<- keep
    check(fired, "must-fail: had network been in scope, its missing toolchain WOULD be reported")
  })

  # --- The `outputs` sibling (#65) -----------------------------------------------------------
  # Built LOCALLY rather than added to good_prov(): the declared outputs key sets arrive with their
  # producers in later phases, and a fixture carrying a block nothing declares yet would make §3
  # fail for a reason that is not a defect.
  o3 <- g   # the clean fixture already carries a well-formed outputs/outputs_hash pair
  check(!is.null(o3$floodplain$co_ff04[["outputs"]]) &&
          !is.null(o3$floodplain$co_ff04[["outputs_hash"]]),
        "premise: the fixture carries a well-formed outputs/outputs_hash pair")
  check(length(viol_split(o3)) == 0, "a well-formed outputs/outputs_hash pair passes")
  o <- g; o$floodplain$co_ff04$outputs_hash <- NULL
  check(any(grepl("no outputs_hash", viol_split(o))),
        "must-fail: an `outputs` block with no outputs_hash IS reported")
  o2 <- g; o2$floodplain$co_ff04$outputs <- NULL
  check(any(grepl("outputs_hash with no `outputs`", viol_split(o2))),
        "must-fail: an outputs_hash with no `outputs` block IS reported (the inverse)")
  o4 <- o3; o4$floodplain$co_ff04$outputs$datetime_utc <- "2026-09-01T00:00:00Z"
  check(any(grepl("outputs carries run-event field", viol_split(o4))),
        "must-fail: a run-event field in `outputs` IS reported")
  o5 <- o3; o5$floodplain$co_ff04$outputs$flood_factor <- 4
  check(any(grepl("inputs/outputs key sets overlap", viol_split(o5))),
        "must-fail: a key in BOTH inputs and outputs IS reported")
  o6 <- o3; o6$floodplain$co_ff04$outputs$toolchain <- list()
  check(any(grepl("outputs/run key sets overlap", viol_split(o6))),
        "must-fail: a key in BOTH outputs and run IS reported")

  # The body-level whitelist. `inputs` has had an undeclared-key rule since #33; its SIBLINGS never
  # did, which is the gap that let `link_log` carry two RUN_FIELDS unnoticed.
  check(length(viol_body(g)) == 0, "clean fixture declares every BODY key")
  bb <- g; bb$landcover$co_ff04$notes <- "a field nobody declared"
  check(any(grepl("UNDECLARED body key", viol_body(bb))),
        "must-fail: an undeclared SIBLING of `inputs` IS reported")
  check(length(viol_body(o3)) == 0, "outputs/outputs_hash are declared body keys")

  # sha_source is a closed vocabulary, and the check has an EXTERNAL reference: the live
  # fp_pkg_stamp() must itself report a value the constant admits, so the producer and the
  # vocabulary cannot drift apart silently.
  check(fp_pkg_stamp("terra")$sha_source %in% SHA_SOURCES,
        sprintf("fp_pkg_stamp() reports a declared sha_source (got: %s)",
                fp_pkg_stamp("terra")$sha_source))
  sg <- g; sg$floodplain$co_ff04$inputs$flooded <- list(version = "0.5.0", sha = NA,
                                                        sha_source = "unresolved_version_mismatch")
  check(length(viol_sha_source(sg)) == 0, "a closed-vocabulary sha_source passes")
  sb <- g
  # The EXACT string measured in data/neexdzii before the fix -- a $HOME path and a sibling
  # checkout version, inside the half that is hashed.
  sb$floodplain$co_ff04$inputs$flooded <- list(version = "0.5.0", sha = NA, sha_source =
    "unresolved (checkout at /Users/someone/Projects/repo/flooded is 0.6.0, installed is 0.5.0)")
  check(any(grepl("free text", viol_sha_source(sb))),
        "restored defect: the OLD free-text sha_source IS reported (why the vocabulary closed)")
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

  # The `outputs` whitelist works in both directions, like the `inputs` one (#65).
  om <- g; om$network$co3$outputs$n_segments <- NULL
  check(any(grepl("outputs missing: n_segments", viol_keys(om))),
        "must-fail: a dropped OUTPUTS key IS reported")
  ou <- g; ou$network$co3$outputs$surprise <- 1
  check(any(grepl("outputs has UNDECLARED", viol_keys(ou))),
        "must-fail: an undeclared OUTPUTS key IS reported")
  # A section that writes outputs while declaring none. Exercised by moving the SCOPE -- the thing
  # that grants the exemption -- rather than by naming a section that happens to have no outputs,
  # which would stop being a mutant the moment that section gained one.
  local({
    keep <- KEYS_OUTPUTS_BY_SECTION
    KEYS_OUTPUTS_BY_SECTION <<- keep["network"]
    fired <- any(grepl("none is declared for that section", viol_keys(g)))
    KEYS_OUTPUTS_BY_SECTION <<- keep
    check(fired, "must-fail: an outputs block in a section that declares none IS reported")
  })
  check(length(viol_keys(g)) == 0, "... and the scope is restored (the clean fixture still passes)")
}

# --- 3b. The config that produced the network -----------------------------------------------------
cat("\n3b. link_config_name — a GRAB may not assert a locally-assumed config\n")
{
  g <- good_prov()
  check(length(viol_config_name(g)) == 0, "clean fixture reports no config-name violation")
  # THE RESTORED DEFECT, in the exact shape measured live in data/neexdzii: a GRAB from `fresh`
  # recording link_config_name = "default" from this script's own literal, beside a log row saying
  # "bcfishpass". Every other property in this file passed on that file.
  b <- g
  b$network$co3$inputs$link_config_name <- "default"
  b$network$co3$inputs$link_config_name_source <- "built_literal"
  check(any(grepl("did not run", viol_config_name(b))),
        "restored defect: a GRAB claiming a built_literal config IS reported")
  # ... and a BUILD claiming it is fine, which is what stops the guard being "refuse everything".
  ok_build <- g
  ok_build$network$co3$inputs$network_source <- "BUILD into neexdzii"
  ok_build$network$co3$inputs$link_config_name <- LNK_BUILD_CONFIG_EXPECTED
  ok_build$network$co3$inputs$link_config_name_source <- "built_literal"
  check(length(viol_config_name(ok_build)) == 0,
        "a BUILD reporting its own literal is NOT a false refusal")
  b2 <- g; b2$network$co3$inputs$link_config_name_source <- "guessed"
  check(any(grepl("not one of", viol_config_name(b2))),
        "must-fail: an out-of-vocabulary config source IS reported")
  b3 <- g; b3$network$co3$inputs$link_config_name <- "something_else"
  check(any(grepl("disagrees with link_log", viol_config_name(b3))),
        "must-fail: a link_log-sourced name that disagrees with the log row IS reported")
  b4 <- g
  b4$network$co3$inputs$link_config_name_source <- "unresolved"
  check(any(grepl("names a config anyway", viol_config_name(b4))),
        "must-fail: an unresolved source that still names a config IS reported")
  b5 <- b4; b5$network$co3$inputs$link_config_name <- NA
  check(length(viol_config_name(b5)) == 0, "unresolved WITH a null name passes")

  # The schema version, and the PAIR that makes the label mean something.
  check(length(viol_schema_version(g)) == 0, "clean fixture carries the current schema_version")
  v1 <- g; v1$schema_version <- 1L
  check(any(grepl("schema_version is 1", viol_schema_version(v1))),
        "must-fail: a stale schema_version IS reported")
  v0 <- g; v0$schema_version <- NULL
  check(any(grepl("no schema_version", viol_schema_version(v0))),
        "must-fail: a missing schema_version IS reported")
  # The shape fp_prov_read actually produces: the version is REWRITTEN on every read, so a file
  # whose sections predate the bump still claims the new version. The version check cannot see that
  # -- viol_keys is what does, by requiring the v2 field set.
  vp <- g; vp$landcover$co_ff04$outputs <- NULL; vp$landcover$co_ff04$outputs_hash <- NULL
  check(length(viol_schema_version(vp)) == 0,
        "premise: a v1-content section under a v2 label passes the VERSION check (it cannot see it)")
  check(any(grepl("landcover\\[co_ff04\\].outputs missing", viol_keys(vp))),
        "... and viol_keys IS what reports it -- the two together, never the version alone")
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
  # ONE year, not all. The arm used to be all(is.na(unlist(x))), which needs EVERY year absent --
  # and unlist() drops a JSON null outright, so on a real file (fp_prov_write serializes NA as null)
  # even any() would have missed it. The fixture above sets every year NA, so it could not tell the
  # two apart; these two can.
  n1 <- g
  n1$landcover$co_ff04$inputs$classified_content_sha256 <- list(`2017` = "sha256:11", `2023` = NA)
  check(any(grepl("year 2023 has no classified raster digest", viol_coverage(n1))),
        "must-fail: ONE year missing its digest IS reported (not just all years)")
  # A NULL VALUE keeps its name -- list(a = 1, b = NULL) has length 2 -- so that shape is caught by
  # the per-year arm, not the year-set arm. It is the shape a JSON null parses back to, and the one
  # unlist() would have silently dropped.
  n2 <- g
  n2$landcover$co_ff04$inputs$classified_content_sha256 <- list(`2017` = "sha256:11", `2023` = NULL)
  check(any(grepl("year 2023 has no classified raster digest", viol_coverage(n2))),
        "must-fail: a NULL-valued year IS reported (unlist() would have dropped it)")
  # A year genuinely ABSENT from the map is what the year-set arm is for.
  n2b <- g
  n2b$landcover$co_ff04$inputs$classified_content_sha256 <- list(`2017` = "sha256:11")
  check(any(grepl("do not match modelled years", viol_coverage(n2b))),
        "must-fail: a year DROPPED from the digest map IS reported")
  n3 <- g; n3$landcover$co_ff04$inputs$years <- list(2017L, 2020L, 2023L)
  check(any(grepl("do not match modelled years", viol_coverage(n3))),
        "must-fail: 2 digests for a 3-year run IS reported")
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
  # Restore TZ EXPLICITLY. on.exit() here registers against the global environment, which never
  # exits, so the handler was never called and every later section ran under TZ=UTC -- silently, and
  # in a file whose whole subject is values that must not depend on the session. Same trap the §5c
  # fixture cleanup hit.
  tz <- Sys.getenv("TZ", unset = NA)
  ts <- as.POSIXct("2026-09-02 00:18:57", tz = "UTC")
  Sys.setenv(TZ = "America/Vancouver"); a <- fp_prov_scalar(ts)
  Sys.setenv(TZ = "UTC");               b <- fp_prov_scalar(ts)
  if (is.na(tz)) Sys.unsetenv("TZ") else Sys.setenv(TZ = tz)
  check(identical(a, b) && grepl("Z$", a), "a timestamp serializes in UTC regardless of session TZ")
  check(identical(Sys.getenv("TZ", unset = NA), tz), "the session TZ is restored (on.exit would not have)")

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

  # The serialization pin, exercised through the FUNCTION. digest() hashes R's serialized bytes and
  # `serializeVersion` is a base option any .Rprofile can set; version 3 embeds the native encoding
  # in the header, so an unpinned digest is locale- and R-version-dependent -- machine dependence,
  # in the one function that exists to remove it. Verified both ways: green as shipped, red with the
  # pin stripped from fp_raster_content_sha256().
  sv_before <- fp_raster_content_sha256(a)
  old_sv <- getOption("serializeVersion")
  options(serializeVersion = 3L)
  sv_after <- fp_raster_content_sha256(a)
  if (is.null(old_sv)) options(serializeVersion = NULL) else options(serializeVersion = old_sv)
  check(identical(sv_before, sv_after),
        "the digest is pinned to serializeVersion 2 -- a session option cannot move it")

  # --- The SpatRaster form (#65) --------------------------------------------------------------
  # flooded::fl_dem_aoi() returns the cropped DEM in memory and never writes it, so a path-only
  # digest would mean writing 6.5M cells out just to read them back -- putting an encoder back in
  # the path #64 removed. The premise is asserted INLINE: forcing the values into memory is what
  # makes this a different code path from reading the file, and if a future terra stops honouring
  # that, the premise fails and names the real cause rather than this passing for nothing.
  robj <- terra::rast(a); terra::values(robj) <- terra::values(robj)
  check(terra::inMemory(robj)[1] && !terra::inMemory(terra::rast(a))[1],
        "premise: one fixture is in memory and the other is file-backed (two real code paths)")
  check(identical(fp_raster_content_sha256(a), fp_raster_content_sha256(robj)),
        "the SpatRaster form AGREES with the path form (the #65 property)")
  check(!identical(fp_raster_content_sha256(robj), fp_raster_content_sha256(terra::rast(cc))),
        "must-fail: the object form still MOVES on a changed cell (it is not a constant)")

  # THE PRECONDITION, stated because the assertion above over-claimed without it. The two forms
  # agree when the file ROUND-TRIPS THE VALUES EXACTLY, and the Int8 fixture above cannot show that
  # is a condition rather than a law. Exercised on a float, which is what the DEM actually is:
  fa <- file.path(d, "f8.tif")
  rf <- terra::rast(nrows = 40, ncols = 50, xmin = 0, xmax = 500, ymin = 0, ymax = 400,
                    crs = "EPSG:3005")
  terra::values(rf) <- c(runif(terra::ncell(rf) - 2, 100, 900), NA, NaN)
  terra::writeRaster(rf, fa, overwrite = TRUE, datatype = "FLT8S")
  fobj <- terra::rast(fa); terra::values(fobj) <- terra::values(fobj)
  check(identical(fp_raster_content_sha256(fa), fp_raster_content_sha256(fobj)),
        "float: the two forms agree at FLT8S, where the file round-trips float64 exactly")
  # ... and where it does NOT round-trip, they legitimately differ. That is a LOSSY WRITE, not a
  # digest defect, and the distinction matters: the DEM is only ever digested as an OBJECT, so this
  # case cannot arise in production -- but the claim in fp_provenance.R has to be true as written.
  f4 <- file.path(d, "f4.tif")
  terra::writeRaster(rf, f4, overwrite = TRUE, datatype = "FLT4S")
  check(!identical(fp_raster_content_sha256(f4), fp_raster_content_sha256(rf)),
        "must-fail: at FLT4S the file and the float64 object DIFFER -- the agreement has a precondition")

  # ONE absence contract across both forms. viol_coverage reads a path-form NA as "the writer
  # produced nothing", so the object form must not invent a second meaning for NA.
  check(is.na(fp_raster_content_sha256(NULL)), "NULL digests to NA (the object form's absence)")
  check(is.na(fp_raster_content_sha256(file.path(d, "nope.tif"))), "an absent path digests to NA")
  check(is.na(fp_raster_content_sha256(NA_character_)), "an NA path digests to NA, it does not error")

  unlink(d, recursive = TRUE)
  check(!dir.exists(d), "the fixture directory is cleaned up (on.exit would not have fired here)")
} else {
  bad("terra/digest unavailable -- the content-digest property was NOT checked (a skip is not a pass)")
}

# --- 5d. The two normalizations, with no raster and no GDAL --------------------------------------
# §5c proves the digest survives a different CONTAINER. It cannot prove either normalization is
# needed, because it reads both fixtures with the same terra in the same process, so the storage
# type never varies -- measured, BOTH lines could be deleted from fp_norm_block() and every §5c
# assertion still passed. The axis that matters is a property of the vectors, so assert it on
# vectors: `terra::readValues()` returns integer+NA_integer_ or double+NaN for the same cells
# depending on whether GDAL read the .aux.xml sidecar.
cat("\n5d. Value normalization (the lines the fix turns on)\n")
vi <- c(1L, 2L, NA_integer_, 4L)   # what readValues gives with the PAM sidecar suppressed
vd <- c(1,  2,  NaN,         4)    # ... and what it gives with the sidecar present

# The premise: these two are indistinguishable by every comparison except identical(). If this ever
# stops holding, the normalization is being tested against the wrong thing.
check(isTRUE(all.equal(vi, vd)), "premise: all.equal() cannot tell the two shapes apart")
check(sum(vi != vd, na.rm = TRUE) == 0, "premise: `!=` with na.rm cannot tell them apart")
check(sum(is.na(vi)) == sum(is.na(vd)), "premise: the NA counts are equal")

only_storage <- function(v) as.double(v)
check(!identical(only_storage(vi), only_storage(vd)),
      "must-fail: storage.mode() ALONE leaves NaN != NA_real_ (why the second line exists)")
check(identical(fp_norm_block(vi), fp_norm_block(vd)),
      "both normalizations together make the two shapes identical")
check(!identical(digest::digest(only_storage(vi), algo = "sha256", serializeVersion = 2L),
                 digest::digest(only_storage(vd), algo = "sha256", serializeVersion = 2L)),
      "must-fail: the half-normalized vectors DIGEST differently")
check(identical(digest::digest(fp_norm_block(vi), algo = "sha256", serializeVersion = 2L),
                digest::digest(fp_norm_block(vd), algo = "sha256", serializeVersion = 2L)),
      "fully normalized, they digest the same")

# The cast's own job, stated even though it is currently subsumed. With no missing values there is
# nothing for the NA line to assign -- so if the sentinel ever stops being a double, THIS is the
# pair that starts failing, and the assertion is here to be the one that names it.
check(!identical(digest::digest(c(1L, 2L, 3L), algo = "sha256", serializeVersion = 2L),
                 digest::digest(c(1, 2, 3), algo = "sha256", serializeVersion = 2L)),
      "premise: integer and double digest differently when there are no NAs at all")
check(identical(fp_norm_block(c(1L, 2L, 3L)), fp_norm_block(c(1, 2, 3))),
      "an all-present integer block normalizes to the same thing as its double twin")

# The FLOAT axis (#65). Everything above comes from an Int8 file, where the integer/double split is
# supplied by GDAL's PAM sidecar. The DEM digest reads Float32 with NaN nodata, which returns double
# either way -- so none of the premises above say anything about it, and a reader would assume they
# do. The operative line for a float raster is the SECOND one, and only the second.
check(identical(fp_norm_block(c(1, NaN, 3)), fp_norm_block(c(1, NA_real_, 3))),
      "float: NaN and NA_real_ collapse (the Float32 nodata case the DEM actually hits)")
check(!identical(only_storage(c(1, NaN, 3)), only_storage(c(1, NA_real_, 3))),
      "must-fail: without the collapse, a float NaN and NA_real_ still digest apart")
# THE ONE THAT WENT RED. `identical(-0, 0)` is TRUE, so the natural assumption is that a signed zero
# cannot reach the digest -- and it does, because digest() hashes serialized BYTES and the two zeros
# do not share them. Written as a premise, measured as a defect, fixed with a third line in
# fp_norm_block. Unreachable for the Int8 landcover; live for the float rasters #65 adds.
check(identical(-0, 0), "premise: R treats -0 and 0 as identical() VALUES (which is why this looked safe)")
check(!identical(digest::digest(only_storage(c(-0, 1)), algo = "sha256", serializeVersion = 2L),
                 digest::digest(only_storage(c(0, 1)), algo = "sha256", serializeVersion = 2L)),
      "must-fail: un-normalized, a signed zero DOES move the digest (why the third line exists)")
check(identical(digest::digest(fp_norm_block(c(-0, 1)), algo = "sha256", serializeVersion = 2L),
                digest::digest(fp_norm_block(c(0, 1)), algo = "sha256", serializeVersion = 2L)),
      "float: normalized, a signed zero does NOT move the digest")
# ... and the collapse must not have eaten the ability to see a real zero-vs-something change.
check(!identical(fp_norm_block(c(0, 1)), fp_norm_block(c(1e-12, 1))),
      "must-fail: the zero collapse does NOT swallow a near-zero value")

# The serialization pin is asserted in §5c, against the real function. Hand-pinning two digest()
# calls here and comparing them would only prove that two identical vectors digest identically --
# which §5d has already proved twice -- while `fp_raster_content_sha256()` itself went unexercised.
# Measured: that version of this check stayed GREEN with the pin stripped from the function.

# --- 5e. The table content digest (the network segment set) --------------------------------------
# fp_table_content_sha256 is the non-geometric sibling of the raster digest (#65). Everything here
# runs with no database, no GDAL and no raster -- it is a property of a data frame and a format.
cat("\n5e. Table content digest\n")
{
  K <- c("blue_line_key", "downstream_route_measure")
  V <- c("length_metre", "stream_order", "upstream_area_ha", "map_upstream")
  df <- data.frame(blue_line_key = c(3L, 1L, 2L),
                   downstream_route_measure = c(10.5, 0, 7.25),
                   length_metre = c(100.1, 200.2, 300.3),
                   stream_order = c(3L, 4L, 5L),
                   upstream_area_ha = c(1.5, 2.5, NA),   # NA on purpose: the render must be explicit
                   map_upstream = c(500, 600, 700))
  h <- fp_table_content_sha256(df, K, V)

  # The digest is a function of the SET, not of the order a query happened to return rows in.
  check(identical(h, fp_table_content_sha256(df[c(3, 1, 2), ], K, V)),
        "row order does NOT move the digest (it is a set, not a sequence)")

  # ... and it must still be able to fail, in every direction that is a real change.
  check(!identical(h, fp_table_content_sha256(
          transform(df, length_metre = length_metre + 1e-5), K, V)),
        "must-fail: a 1e-5 m length change MOVES the digest")
  check(!identical(h, fp_table_content_sha256(df[1:2, ], K, V)),
        "must-fail: a DROPPED segment MOVES the digest")
  check(!identical(h, fp_table_content_sha256(rbind(df, df[1, ]), K, V)),
        "must-fail: an ADDED segment MOVES the digest")
  check(!identical(h, fp_table_content_sha256(
          transform(df, upstream_area_ha = upstream_area_ha * 2), K, V)),
        "must-fail: a changed upstream_area_ha MOVES it (it feeds the VCA, so it is not decoration)")
  check(!identical(h, fp_table_content_sha256(df, K, V[1:2])),
        "must-fail: a different COLUMN SET digests differently (the header carries it)")

  # An empty table is a real answer -- a species modelled nowhere in the group -- and must be
  # distinguishable from a one-row table, not collapse to the digest of an empty string.
  check(!identical(fp_table_content_sha256(df[0, ], K, V),
                   fp_table_content_sha256(df[1, ], K, V)),
        "an EMPTY table digests distinguishably from a one-row table")

  # `options(scipen)` decides whether a large number renders in scientific notation, so a digest
  # built with paste()/as.character() would depend on a .Rprofile -- the same class as the
  # serializeVersion trap in 5c. Exercised in BOTH directions: the naive render really does move,
  # and the shipped one does not.
  # NOT on.exit(): this is the top level of a script, so the handler would be registered against
  # the global environment and never called -- the same trap 5c documents. Restored explicitly
  # below. -9 rather than -10 because R clamps the range and warns.
  old <- getOption("scipen")
  big <- data.frame(blue_line_key = 1.23e15, downstream_route_measure = 0,
                    length_metre = 1, stream_order = 1L, upstream_area_ha = 1, map_upstream = 1)
  options(scipen = -9); naive_a <- as.character(big$blue_line_key); hb <- fp_table_content_sha256(big, K, V)
  options(scipen = 100);  naive_b <- as.character(big$blue_line_key); hc <- fp_table_content_sha256(big, K, V)
  options(scipen = old)
  check(!identical(naive_a, naive_b),
        sprintf("premise: as.character() IS scipen-dependent (%s vs %s)", naive_a, naive_b))
  check(identical(hb, hc), "the digest is scipen-immune (sprintf, never as.character)")

  # The ordering is radix, i.e. C-locale, so two machines with different LC_COLLATE cannot sort the
  # same rows differently. Currently DEFENSIVE rather than reachable -- every key column renders to
  # digits under "%.6f", and digits collate identically in every locale. The premise below pins why
  # the argument is there, so nobody deletes it as noise.
  check(!identical(order(c("a", "B", "b"), method = "radix"),
                   order(c("a", "B", "b"), method = "auto")) ||
          identical(Sys.getenv("LC_COLLATE"), "C"),
        "premise: radix and locale ordering CAN disagree (why method = 'radix' is pinned)")

  # An NA renders as the literal "NA", never as an empty string -- otherwise a missing
  # upstream_area_ha and a zero-length one would be indistinguishable.
  na1 <- fp_table_content_sha256(transform(df, upstream_area_ha = c(1.5, 2.5, NA)), K, V)
  na2 <- fp_table_content_sha256(transform(df, upstream_area_ha = c(1.5, 2.5, 0)), K, V)
  check(!identical(na1, na2), "an NA value is distinguishable from a zero")

  # A DUPLICATE composite key, and it is not hypothetical: uniqueness is measured on ONE area, which
  # is the unrepresentative-sample shape CLAUDE.md warns about for a key numbered per group. Sorting
  # by the key alone left ties in whatever order the query returned them -- and 01's SELECT has no
  # ORDER BY -- so the digest was a function of DATABASE ROW ORDER. Sorting the whole line removes
  # the need to be right about uniqueness at all.
  dup <- data.frame(blue_line_key = c(1L, 1L), downstream_route_measure = c(0, 0),
                    length_metre = c(10, 20), stream_order = c(3L, 4L),
                    upstream_area_ha = c(1, 2), map_upstream = c(5, 6))
  check(anyDuplicated(paste(dup$blue_line_key, dup$downstream_route_measure)) > 0,
        "premise: the fixture really does carry a duplicate composite key")
  check(identical(fp_table_content_sha256(dup, K, V),
                  fp_table_content_sha256(dup[2:1, ], K, V)),
        "row order does not move the digest even when the KEY is duplicated")
  check(!identical(fp_table_content_sha256(dup, K, V),
                   fp_table_content_sha256(transform(dup, length_metre = c(10, 21)), K, V)),
        "must-fail: ... and duplicate keys do not make it blind to a changed value")

  # A text column is REFUSED, not rendered by a second branch. RPostgres' `bigint=` has four modes
  # and one of them is "character", so a connection setting could otherwise take the other arm and
  # move the digest with no data change and nothing to see.
  chr <- transform(df, blue_line_key = as.character(blue_line_key))
  check(tryCatch({ fp_table_content_sha256(chr, K, V); FALSE },
                 error = function(e) grepl("not numeric", conditionMessage(e))),
        "must-fail: a text column IS refused (a driver setting must not pick the rendering)")

  # The HEADER, and the one case it uniquely buys. Both checks above pass without it -- a different
  # column set already produces different LINES. What only the header catches is two column sets
  # whose rendered lines are IDENTICAL, which is what happens when the swapped columns carry the
  # same values. Measured: without the `cols=` header these two digest the same.
  same_vals <- data.frame(blue_line_key = 1L, downstream_route_measure = 0,
                          length_metre = 7, stream_order = 7L,
                          upstream_area_ha = 7, map_upstream = 7)
  check(identical(fmt_probe <- c(same_vals$length_metre, same_vals$stream_order), c(7, 7)),
        "premise: the two columns being swapped carry identical values")
  check(!identical(fp_table_content_sha256(same_vals, K, c("length_metre", "stream_order")),
                   fp_table_content_sha256(same_vals, K, c("stream_order", "length_metre"))),
        "two column sets with IDENTICAL rendered values digest apart (only the header sees this)")
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
prov_keys <- function(file, section, part = "inputs") {
  calls <- unlist(lapply(parse(file), find_calls, fname = "fp_prov_set"), recursive = FALSE)
  for (cl in calls) {
    if (!identical(as.character(cl[[3]]), section)) next
    body <- cl[[5]]                                  # the list(inputs = ..., run = ..., ...)
    target <- body[[part]]
    if (is.null(target)) return(character(0))
    # may be `list(...)`, `c(list(...), other)`, or `fp_prov_run(...)`
    lists <- c(find_calls(target, "list"), find_calls(target, "fp_prov_run"))
    nm <- unlist(lapply(lists, function(l) names(as.list(l))))
    return(sort(unique(nm[nzchar(nm)])))
  }
  character(0)
}

# Which sections actually WRITE a raster, read off the producers rather than listed by hand. A
# literal set here would match the producers by coincidence and stop covering a section added
# later -- the scope-by-coincidence shape code-check.md warns about, in the guard for the one field
# that has no other protection.
# The link_log declared set has the same shape as every other literal here: a copy of a list that
# lives in the producer, with nothing comparing the two. 01 null-fills link_log from its own literal
# `c("run_uid", "config_hash", ...)`, so a field added there and not here is simply not required, and
# one removed there leaves the guard demanding a key nothing writes. Read the producer's list.
prov_link_log_keys <- function(file) {
  calls <- unlist(lapply(parse(file), find_calls, fname = "fp_prov_null_fill"), recursive = FALSE)
  for (cl in calls) {
    keys <- unlist(lapply(find_calls(cl, "c"), function(x) as.list(x)[-1]))
    keys <- vapply(keys, function(k) if (is.character(k)) k else NA_character_, "")
    keys <- keys[!is.na(keys)]
    if (length(keys)) return(sort(unique(keys)))
  }
  character(0)
}

prov_sections_writing_toolchain <- function(section_files) {
  secs <- names(section_files)
  secs[vapply(secs, function(sec)
    "toolchain" %in% prov_keys(section_files[[sec]], sec, part = "run"), logical(1))]
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
  drift1("network outputs", prov_keys(step("01_network_extract.R"), "network", part = "outputs"),
         KEYS_NETWORK_OUTPUTS)
  drift1("floodplain", fpl, KEYS_FLOODPLAIN)
  drift1("floodplain outputs",
         prov_keys(step("02_floodplain_model.R"), "floodplain", part = "outputs"),
         KEYS_FLOODPLAIN_OUTPUTS)
  drift1("landcover", lcv, KEYS_LANDCOVER)
  drift1("landcover outputs",
         prov_keys(step("03_lulc_classify.R"), "landcover", part = "outputs"),
         KEYS_LANDCOVER_OUTPUTS)

  # The `run` half. Until now this scanner read only `inputs`, which meant the toolchain block --
  # the one field #64 adds and the only one with no declared-key protection -- could be deleted from
  # both producers with every check still green. Measured: it was. The record would then quietly
  # return to the state #64 calls undiagnosable.
  # Every section fp_prov_set accepts, not just the two that write rasters today. Round 2 moved this
  # scope one level instead of removing it: the derivation was real but its CANDIDATE list was still
  # hand-written, so a network section that started writing a raster would have been invisible to
  # both this check and viol_split. fp_prov_set's own stopifnot closes the section set to these
  # three, so enumerating them is a complete candidate list rather than another coincidence.
  writers <- prov_sections_writing_toolchain(list(
    network    = step("01_network_extract.R"),
    floodplain = step("02_floodplain_model.R"),
    landcover  = step("03_lulc_classify.R")))
  # And what the block CONTAINS, not just which sections write one. Round 2 pinned the sibling
  # literal on the next line and left this one matched to its producer by coincidence -- measured,
  # renaming `gdal` to `gdal_version` in fp_toolchain(), or deleting it outright, left the whole
  # offline suite green. viol_split's "toolchain missing" arm only fires against a parsed file, i.e.
  # after a real area has already been re-run and the record written without it.
  ll <- prov_link_log_keys(step("01_network_extract.R"))
  check(length(ll) > 0, "premise: the link_log null-fill list is readable from the producer")
  check(setequal(ll, KEYS_LINK_LOG),
        sprintf("KEYS_LINK_LOG matches 01's null-fill list%s",
                if (setequal(ll, KEYS_LINK_LOG)) ""
                else paste0(" -- differs: ",
                            paste(union(setdiff(ll, KEYS_LINK_LOG),
                                        setdiff(KEYS_LINK_LOG, ll)), collapse = ", "))))
  check(setequal(names(fp_toolchain()), KEYS_TOOLCHAIN),
        sprintf("KEYS_TOOLCHAIN matches what fp_toolchain() returns (%s)",
                paste(names(fp_toolchain()), collapse = ", ")))
  # The `outputs` half of the same declare-or-fail pair. SECTIONS_WITH_OUTPUTS is a JUDGEMENT about
  # which steps must publish a digest of what they produced; the derivation is what stops it drifting
  # from the producers. Neither alone: derived-only goes empty and SILENT the moment a producer drops
  # the block, which is the hole section 6 exists to close for run$toolchain.
  out_writers <- names(Filter(function(f) length(f) > 0, list(
    network    = prov_keys(step("01_network_extract.R"), "network",    part = "outputs"),
    floodplain = prov_keys(step("02_floodplain_model.R"), "floodplain", part = "outputs"),
    landcover  = prov_keys(step("03_lulc_classify.R"),   "landcover",  part = "outputs"))))
  check(setequal(out_writers, SECTIONS_WITH_OUTPUTS),
        sprintf("every producer declared to write `outputs` still does (found: %s; declared: %s)",
                if (length(out_writers)) paste(out_writers, collapse = ", ") else "NONE",
                paste(SECTIONS_WITH_OUTPUTS, collapse = ", ")))
  # And the BUILD config literal, pinned to 01's own lnk_config() calls -- the only external
  # reference the BUILD branch has. A methodology change in 01 that left the recorded config name
  # describing the old bundle goes red here.
  lit <- unique(unlist(lapply(
    unlist(lapply(parse(step("01_network_extract.R")), find_calls, fname = "lnk_config"),
           recursive = FALSE),
    function(cl) { a <- as.list(cl)[-1]; unlist(lapply(a, function(x) if (is.character(x)) x)) })))
  # 01 names the bundle once, in LNK_BUILD_CONFIG, so the parsed literals are the ASSIGNMENT and
  # nothing else. A raw "default" reappearing at a call site would show up here as a second value.
  assign_lit <- unlist(lapply(parse(step("01_network_extract.R")), function(e)
    if (is.call(e) && identical(as.character(e[[1]])[1], "<-") &&
        identical(as.character(e[[2]]), "LNK_BUILD_CONFIG")) as.character(e[[3]])))
  check(length(assign_lit) == 1L && identical(assign_lit, LNK_BUILD_CONFIG_EXPECTED),
        sprintf("01's LNK_BUILD_CONFIG is '%s', matching the guard's expectation",
                paste(assign_lit, collapse = ", ")))
  check(length(lit) == 0L,
        sprintf("no lnk_config() call site names a bundle literally (found: %s)",
                if (length(lit)) paste(lit, collapse = ", ") else "none"))

  check(setequal(writers, SECTIONS_WITH_RASTERS),
        sprintf("every raster-writing producer still records run$toolchain (found: %s)",
                if (length(writers)) paste(writers, collapse = ", ") else "NONE"))
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
    for (f in list(viol_split, viol_keys, viol_body, viol_sha_source, viol_config_name,
                   viol_schema_version, viol_coverage)) {
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
    # --- 7c. RECONCILE: every published `outputs` value, re-derived from the artefact it names ----
    # THE GAP ROUND 3 MEASURED, and it is a property of the whole guard rather than of any one
    # check: every assertion above is about a KEY SET, a SHAPE or a VOCABULARY, and none reads a
    # VALUE. Measured -- all eight published `outputs` values in a real record were mutated one at a
    # time and this script printed PASS on all eight. That is exactly how `transition_patches`
    # shipped at 48 against 2032 actual patches: 42x wrong, inside `outputs_hash`, and invisible.
    # Three hand-written assertions would close three holes; this closes the class, because it
    # re-derives each value from the thing it claims to describe.
    #
    # HONEST ABOUT WHAT EACH ARM IS WORTH. The count and name arms are independent -- nothing in the
    # record produced the feature count. The DIGEST arms are semi-circular: they verify "the record
    # describes THIS file", not "this file is correct". That is still worth having, because it is
    # precisely what broke when a zero-transition run digested the previous run's raster.
    #
    # TWO VALUES CANNOT BE RECONCILED and are skipped rather than faked: `dem_content_sha256` (the
    # DEM is never written to disk) and, on a SUBSET area, `inputs.network_content_sha256` (taken
    # pre-subset, and only the post-subset layer is written). Both are reported as skipped so a
    # reader is not left thinking they were checked.
    if (requireNamespace("terra", quietly = TRUE) && requireNamespace("sf", quietly = TRUE)) {
      cat("\n7c. Reconcile — published `outputs` values against the artefacts they name\n")
      dd <- file.path(fp_root, "data", area)
      # The digest column lists are PARSED OUT OF 01, never copied. A literal here would be a second
      # copy pinned to nothing, and it is the list round 3 found incomplete.
      dig_cols <- function(nm) {
        for (e in parse(file.path(fp_root, "scripts", "floodplain_lcc", "01_network_extract.R"))) {
          f <- function(x) {
            if (!is.call(x)) return(NULL)
            if (identical(as.character(x[[1]])[1], "<-") && identical(as.character(x[[2]]), nm))
              return(as.character(as.list(x[[3]])[-1]))
            for (i in seq_along(as.list(x))) {
              pi <- as.list(x)[[i]]
              if (!nzchar(paste(deparse(pi), collapse = ""))) next
              if (is.call(pi)) { r <- f(pi); if (!is.null(r)) return(r) }
            }
            NULL
          }
          r <- f(e); if (!is.null(r)) return(r)
        }
        character(0)
      }
      KEYC <- dig_cols("NETWORK_DIGEST_KEY"); VALC <- dig_cols("NETWORK_DIGEST_VAL")
      check(length(KEYC) > 0 && length(VALC) > 0,
            sprintf("premise: the digest column lists parse out of 01 (key=%d, value=%d)",
                    length(KEYC), length(VALC)))
      eq <- function(got, want, what) check(isTRUE(all.equal(got, want)),
        sprintf("%s: recorded %s, artefact %s", what, format(got), format(want)))

      for (e in prov_sections(prov)) {
        o <- e$body[["outputs"]]; if (is.null(o)) next
        if (identical(e$section, "network")) {
          g <- file.path(dd, "aquatic_network.gpkg")
          lyr <- as.character(o[["streams_layer"]])
          if (!file.exists(g)) { bad(sprintf("network[%s]: no %s to reconcile against", e$key, basename(g)))
          } else if (!lyr %in% sf::st_layers(g)$name) {
            bad(sprintf("network[%s].outputs names layer '%s', which is not in %s",
                        e$key, lyr, basename(g)))
          } else {
            x <- sf::st_read(g, layer = lyr, quiet = TRUE)
            eq(as.integer(o[["n_segments"]]), nrow(x), sprintf("network[%s] n_segments", e$key))
            eq(as.character(o[["streams_content_sha256"]]),
               fp_table_content_sha256(x, KEYC, VALC),
               sprintf("network[%s] streams_content_sha256", e$key))
          }
          if (is.null(e$body[["inputs"]][["subset"]]))
            eq(as.character(e$body[["inputs"]][["network_content_sha256"]]),
               as.character(o[["streams_content_sha256"]]),
               sprintf("network[%s] whole-WSG area: pre- and post-subset digests agree", e$key))
          else
            ok(sprintf("network[%s] inputs.network_content_sha256 not reconcilable (pre-subset, never written)", e$key))
        }
        if (identical(e$section, "floodplain")) {
          f <- file.path(dd, as.character(o[["floodplain_raster"]]))
          if (!file.exists(f)) { bad(sprintf("floodplain[%s].outputs names %s, which does not exist",
                                             e$key, basename(f)))
          } else {
            r <- terra::rast(f)
            eq(as.numeric(o[["valley_cells"]]), sum(terra::values(r) == 1, na.rm = TRUE),
               sprintf("floodplain[%s] valley_cells", e$key))
            eq(as.character(o[["floodplain_content_sha256"]]), fp_raster_content_sha256(f),
               sprintf("floodplain[%s] floodplain_content_sha256", e$key))
          }
          ok(sprintf("floodplain[%s] dem_content_sha256 not reconcilable (the DEM is never written)", e$key))
        }
        if (identical(e$section, "landcover")) {
          np <- as.integer(o[["transition_patches"]])
          tr <- o[["transition_raster"]]
          # The NA/name pair must agree with the patch count in BOTH directions -- a named file on a
          # zero-patch run and an NA on a populated one are different defects.
          if (is.na(np) || np == 0L) {
            check(is.null(tr) || is.na(tr),
                  sprintf("landcover[%s] zero patches -> transition_raster is null, not a filename", e$key))
          } else {
            f <- file.path(dd, "rasters", e$key, as.character(tr))
            if (!file.exists(f)) bad(sprintf("landcover[%s].outputs names %s, which does not exist",
                                             e$key, f))
            else eq(as.character(o[["transition_content_sha256"]]), fp_raster_content_sha256(f),
                    sprintf("landcover[%s] transition_content_sha256", e$key))
            span <- unlist(e$body[["inputs"]][["change_interval"]])
            g <- file.path(dd, "floodplain_landcover.gpkg")
            lyr <- paste0("transition_", e$key, "_", span[1], "_", span[2])
            if (!file.exists(g) || !lyr %in% sf::st_layers(g)$name)
              bad(sprintf("landcover[%s]: no layer %s to reconcile transition_patches against",
                          e$key, lyr))
            else eq(np, nrow(sf::st_read(g, layer = lyr, quiet = TRUE)),
                    sprintf("landcover[%s] transition_patches", e$key))
          }
          # The CLASSIFIED years, reconciled against the ARTEFACTS (#79). Every other check on this
          # field is internal: viol_coverage asserts the digest year set equals inputs$years, and
          # both come from the same run, so they cannot disagree. Nothing read rasters/<scen>/ or
          # the gpkg layer list. So an area reverted from lulc_annual back to three years records
          # three years, passes green, and keeps four orphan classified_* layers and four orphan
          # .tifs describing years the record says were never modelled -- #55's orphan class, which
          # gpkg_prune-legacy.R's transition-only pattern does not sweep. This is the detector the
          # one-way door needs; without it the hazard is enforced by a comment.
          yrs_rec <- sort(as.integer(unlist(e$body[["inputs"]][["years"]])))
          rd      <- file.path(dd, "rasters", e$key)
          tifs    <- sort(as.integer(sub("^classified_([0-9]{4})\\.tif$", "\\1",
                     grep("^classified_[0-9]{4}\\.tif$", list.files(rd), value = TRUE))))
          if (!length(tifs)) {
            bad(sprintf("landcover[%s]: no classified_<yr>.tif under %s to reconcile years against",
                        e$key, rd))
          } else {
            check(identical(tifs, yrs_rec),
                  sprintf("landcover[%s] classified tif years reconcile (disk {%s} vs recorded {%s})",
                          e$key, paste(tifs, collapse = ","), paste(yrs_rec, collapse = ",")))
          }
          gl <- file.path(dd, "floodplain_landcover.gpkg")
          if (!file.exists(gl)) {
            bad(sprintf("landcover[%s]: no floodplain_landcover.gpkg to reconcile layer years", e$key))
          } else {
            pre  <- paste0("classified_", e$key, "_")
            lyrs <- sort(as.integer(sub(pre, "",
                    grep(paste0("^", pre, "[0-9]{4}$"), sf::st_layers(gl)$name, value = TRUE))))
            check(identical(lyrs, yrs_rec),
                  sprintf("landcover[%s] classified gpkg layer years reconcile (gpkg {%s} vs recorded {%s})",
                          e$key, paste(lyrs, collapse = ","), paste(yrs_rec, collapse = ",")))
          }
        }
      }
    } else {
      bad("terra/sf unavailable -- `outputs` values were NOT reconciled (a skip is not a pass)")
    }

    if (n > 0) check(TRUE, "real file checked against all properties")
  }
}

cat("\n", if (FAILS == 0L) "PASS — all properties hold, and each was shown able to fail.\n"
         else sprintf("FAIL — %d problem(s).\n", FAILS), sep = "")
quit(status = if (FAILS == 0L) 0L else 1L)
