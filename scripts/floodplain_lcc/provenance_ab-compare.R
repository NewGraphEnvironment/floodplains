#!/usr/bin/env Rscript
#
# provenance_ab-compare.R  —  the A/B that makes #33's inputs/run split checkable (#63).
#
# Usage:
#   Rscript scripts/floodplain_lcc/provenance_ab-compare.R <a.json> <b.json> [area] [label_a] [label_b]
#
# #33 splits every provenance section into `inputs` (a function of the inputs, byte-stable across
# reruns, summarised by `inputs_hash`) and `run` (the run event, free to vary). That is only a rule
# if something checks it against two real runs, which is what this does:
#
#   1. INVENTORY   both files carry every entry the area's config asks for
#   2. STABILITY   `inputs_hash` is IDENTICAL per entry across the two runs
#   3. LIVENESS    `run.datetime_utc` MOVED per entry -- proving the second run actually ran
#
# 3 is not decoration. Without it a comparison of a file against an untouched copy of itself passes
# 2 perfectly, which is exactly what a run that crashed before writing produces.
#
# `area` is optional and enables 1. Without it the check degrades to "the entries these two files
# happen to share", which cannot see an entry missing from BOTH -- the shape a partial run leaves.
#
# Exits non-zero on any failure. No database, no network.

suppressWarnings(suppressMessages({
  library(jsonlite)
  library(yaml)
}))
`%||%` <- function(a, b) if (is.null(a)) b else a

a <- commandArgs(trailingOnly = TRUE)
if (length(a) < 2) stop("usage: provenance_ab-compare.R <a.json> <b.json> [area] [label_a] [label_b]",
                        call. = FALSE)
# The two JSON arguments are user-supplied CLI paths and stay CWD-relative, which is what a caller
# typing them expects. Only `area` -- which names a config INSIDE this checkout -- resolves against
# fp_root. Different roots, deliberately, because they answer different questions.
for (f in a[1:2]) if (!file.exists(f)) stop("no such file: ", f, call. = FALSE)
area <- if (length(a) >= 3 && nzchar(a[3])) a[3] else NA_character_
la   <- if (length(a) >= 4) a[4] else "A"
lb   <- if (length(a) >= 5) a[5] else "B"

# `[[` throughout, never `$`. `$` on a parsed-JSON list PARTIAL MATCHES, so `e$inputs` would resolve
# to `inputs_hash` when only the hash is present, and `x$link_log` to `link_log_note`. Both shapes
# exist in this document.
A <- jsonlite::read_json(a[1], simplifyVector = FALSE)
B <- jsonlite::read_json(a[2], simplifyVector = FALSE)

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

# Print the resolved root. This is the mitigation the script-relative rooting rests on, and it
# matters more here than in provenance-check.R: under worktree-per-session the OTHER checkout also
# has config/<area>/, so a wrong-tree invocation never reaches the "no config" branch -- it quietly
# derives the expected entry set from the other tree's area.yml and reports against the wrong set.
if (!is.na(area)) cat("repo root resolved from this script: ", fp_root, "\n", sep = "")

FAILS <- 0L
ok  <- function(m) cat("  ok    ", m, "\n")
bad <- function(m) { FAILS <<- FAILS + 1L; cat("  FAIL  ", m, "\n") }
check <- function(cond, m) if (isTRUE(cond)) ok(m) else bad(m)

entries <- function(p) {
  out <- list()
  for (s in c("network", "floodplain", "landcover"))
    for (k in names(p[[s]] %||% list())) out[[paste0(s, "[", k, "]")]] <- p[[s]][[k]]
  out
}
ea <- entries(A); eb <- entries(B)

# --- 1. Inventory ------------------------------------------------------------------------------
# Derived from the config, never hardcoded: a literal list stops covering a scenario the moment one
# is added, and does so silently.
if (!is.na(area)) {
  cfg_dir <- file.path(fp_root, "config", area)
  if (!dir.exists(cfg_dir)) {
    bad(sprintf("no config/%s -- cannot derive the expected entry set", area))
  } else {
    ay <- yaml::read_yaml(file.path(cfg_dir, "area.yml"))
    sp <- Sys.getenv("FP_SPECIES", "");          if (!nzchar(sp)) sp <- ay$species
    ps <- Sys.getenv("FP_PRIMARY_SCENARIO", ""); if (!nzchar(ps)) ps <- ay$primary_scenario
    if (is.null(ps) || !nzchar(ps)) ps <- paste0(sp, "_ff04")
    # Read it with the PRODUCER's reader. utils::read.csv and readr::read_csv disagree on a cell
    # like " TRUE" -- readr trims it to logical TRUE, read.csv's type.convert leaves a string -- so a
    # guard using the other reader derives a different expected set from the same file, and then
    # excuses the surplus as an "extra". One fact, one derivation.
    sc <- readr::read_csv(file.path(cfg_dir, "flood_scenarios.csv"), show_col_types = FALSE)
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
    for (side in list(list(la, names(ea)), list(lb, names(eb)))) {
      miss <- setdiff(want, side[[2]])
      check(length(miss) == 0,
            sprintf("%s carries all %d config-derived entries%s", side[[1]], length(want),
                    if (length(miss)) paste0(" -- MISSING: ", paste(miss, collapse = ", ")) else ""))
    }
  }
} else {
  cat("  note   no area given -- inventory not checked (a shared absence is invisible)\n")
}

# --- 2/3. Stability and liveness ---------------------------------------------------------------
keys <- union(names(ea), names(eb))
if (!length(keys)) bad("neither file has any section -- nothing was compared")

cat("\n", sprintf("%-30s %-8s %-8s %s", "entry", "inputs", "datetime", "detail"), "\n", sep = "")
for (k in keys) {
  x <- ea[[k]]; y <- eb[[k]]
  if (is.null(x) || is.null(y)) {
    bad(sprintf("%-30s absent from %s", k, if (is.null(x)) la else lb)); next
  }
  hx <- x[["inputs_hash"]]; hy <- y[["inputs_hash"]]
  dx <- x[["run"]][["datetime_utc"]]; dy <- y[["run"]][["datetime_utc"]]
  # A field ABSENT from BOTH sides must not read as agreement. `identical(NULL, NULL)` is TRUE, so
  # a key that upstream renamed or dropped would compare "same" and the whole A/B would pass having
  # compared nothing -- the loudest possible pass on the emptiest possible evidence. Require the
  # value to actually be there before its equality means anything.
  #
  # Resolve presence ONCE, into flags, before anything is reassigned for display. Re-calling the
  # predicate further down reads as harmless and is not: substituting "<absent>" for a missing hash
  # so the table prints makes that same predicate answer TRUE afterwards, and the defect gets
  # counted a second time. Measured: one missing hash reported as two problems.
  scalar <- function(v) is.character(v) && length(v) == 1L && !is.na(v) && nzchar(v)
  hx_ok <- scalar(hx); hy_ok <- scalar(hy); dx_ok <- scalar(dx); dy_ok <- scalar(dy)
  same  <- hx_ok && hy_ok && identical(hx, hy)
  moved <- dx_ok && dy_ok && !identical(dx, dy)
  if (!hx_ok || !hy_ok)
    bad(sprintf("%s: inputs_hash absent or not a scalar string in %s", k,
                paste(c(la, lb)[c(!hx_ok, !hy_ok)], collapse = " and ")))
  else if (!same) FAILS <- FAILS + 1L
  if (!dx_ok || !dy_ok)
    bad(sprintf("%s: run.datetime_utc absent or not a scalar string in %s", k,
                paste(c(la, lb)[c(!dx_ok, !dy_ok)], collapse = " and ")))
  else if (!moved) FAILS <- FAILS + 1L
  hx_s <- if (hx_ok) hx else "<absent>"; hy_s <- if (hy_ok) hy else "<absent>"
  cat(sprintf("%-30s %-8s %-8s %s\n", k,
              if (same) "same" else "DIFFER", if (moved) "moved" else "SAME",
              if (same) substr(hx_s, 1, 24)
              else paste0(substr(hx_s, 1, 16), " vs ", substr(hy_s, 1, 16))))
}
cat("\n")
check(TRUE, sprintf("compared %d entr(ies) across %s and %s", length(keys), la, lb))

# Say what was actually checked. Without `area` no inventory ran, and claiming "every
# config-derived entry present" would be an affirmative statement about a check that did not
# happen -- the same class as announcing a delete nobody verified.
cat("\n", if (FAILS != 0L) sprintf("FAIL — %d problem(s).\n", FAILS)
    else if (!is.na(area))
      "PASS — every config-derived entry present in both, inputs_hash identical, run.datetime_utc moved.\n"
    else
      "PASS — inputs_hash identical and run.datetime_utc moved for the shared entries. NO INVENTORY CHECKED (no area given): an entry missing from BOTH files is invisible here.\n",
    sep = "")
quit(status = if (FAILS == 0L) 0L else 1L)
