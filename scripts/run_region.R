#!/usr/bin/env Rscript
#
# run_region.R  —  run the pipeline over every watershed group in a region.
#
# Usage:
#   Rscript scripts/run_region.R <region> [steps]      # plan + reconcile configs + run
#   DRY=1 Rscript scripts/run_region.R <region>        # PREVIEW ONLY -- writes nothing at all
#
# Reads config/regions/<region>.yml (watershed_groups, ordered `species` preference OR
# `network: whole`, min_order, mergin_project). For each WSG it:
#   1. PRE-PASS. Species mode resolves ONE species — the first in the preference list modelled at
#      order >= min_order (province-wide fresh.streams_vw_bcfp). Whole mode (`network: whole`,
#      #125) has no species to resolve: every group is `species: all`, and the pre-pass counts the
#      group's segments in `network_source`.streams instead. Either way a WSG that would produce no
#      network is flagged LOUDLY and SKIPPED (never silently dropped).
#   2. RECONCILES config/<wsg>/ against the region file -- it does not regenerate it (#44). The
#      region owns FP_REGION_OWNED (species, min_order, network_source, attribute_by, ...); the area
#      owns everything else, so a second species' scenario rows, citations, hand-set area.yml keys
#      and break_points.csv all survive. flood_scenarios.csv is created when absent and appended to
#      when the resolved species has no rows; existing rows are never rewritten.
#   3. runs scripts/run_area.R <wsg> as a subprocess (per-WSG soft-fail + timestamped log).
#   4. POST-VERIFY: the extracted network must be non-empty; if the pre-pass promised a
#      species but the real run comes back empty, it is recorded as a FAILURE, not a pass.
# Prints and writes a coverage summary (data/logs/region_<region>_<ts>.csv).

suppressMessages({library(here); library(yaml); library(readr); library(fs); library(sf)})
source(here::here("scripts", "publish_hint.R"))    # fp_publish_hint (advisory publish handoff)
source(here::here("scripts", "fp_gpkg.R"))         # fp_gpkg_pin_date (byte-deterministic gpkg)
source(here::here("scripts", "floodplain_lcc", "fp_region.R"))  # fp_region_plan/_write (#44)
# Set here as well as in run_area.R: the per-WSG children inherit this process's environment,
# so a child is pinned even if its own call is ever removed (#45).
fp_gpkg_pin_date()
# run_area is invoked per-WSG as a subprocess and inherits this env, so the child stays quiet and
# the batch prints ONE hint at the end instead of one per group (8x for Fraser) (#32).
Sys.setenv(FP_NO_PUBLISH_HINT = "1")
sf::sf_use_s2(FALSE)
`%||%` <- function(a, b) if (is.null(a)) b else a

args   <- commandArgs(trailingOnly = TRUE)
region <- args[1]
steps  <- if (length(args) >= 2) args[2] else "1,2,3"
dry    <- nzchar(Sys.getenv("DRY"))
if (is.na(region)) stop("usage: Rscript scripts/run_region.R <region> [steps]", call. = FALSE)

reg_path <- here::here("config", "regions", paste0(region, ".yml"))
reg <- yaml::read_yaml(reg_path)
# Before the pre-pass: a species list naming `all` would interpolate access_all into SQL (#104), and
# a whole region with a species list is a contradiction (#125). Refused with no connection open.
mode      <- fp_region_mode(reg, paste0("config/regions/", region, ".yml"))
whole     <- identical(mode, "whole")
min_order <- fp_region_min_order(reg)
prefs     <- if (whole) FP_SPECIES_WHOLE else reg$species
wsgs      <- reg$watershed_groups
message("Region: ", region, " | groups: ", length(wsgs), " | mode: ", mode,
        if (whole) paste0(" (network_source ", reg$network_source, ")")
        else paste0(" | species preference: ", paste(prefs, collapse = ">")),
        " | min_order: ", min_order, if (dry) "  [DRY: plan only]" else "")

conn <- DBI::dbConnect(RPostgres::Postgres())

# --- Standard flood scenarios for a species (ff01..ff12; run ff02/04/06) ---
base_scenarios <- function(sp) data.frame(
  scenario_id = paste0(sp, c("_ff01","_ff02","_ff04","_ff06","_ff08","_ff12")),
  species = sp, min_order = min_order, anchor_order = 1,
  flood_factor = c(1, 2, 4, 6, 8, 12),
  slope_threshold = 9, max_width = 2000, cost_threshold = 2500,
  size_threshold = 5000, hole_threshold = 2500,
  lakes = TRUE, wetlands = TRUE, wetland_filter = "network",
  run = c(FALSE, TRUE, TRUE, TRUE, FALSE, FALSE),
  description = c("Bankfull channel extent", "Flood-prone width / active channel margin",
                 "Functional floodplain", "Valley bottom extent",
                 "Extended valley - large wood recruitment",
                 "Channel migration zone - full process width"),
  ecological_process = c("Active channel", "Active channel margin", "Functional floodplain",
                         "Valley bottom", "Extended valley / LWD recruitment",
                         "Channel migration zone"),
  citations = "", stringsAsFactors = FALSE)

# --- PRE-PASS: resolve species per WSG from the province-wide view ---
# count(*) is bigint; cast to int so RPostgres doesn't return a reinterpreted garbage double.
n_access <- function(wsg, sp) DBI::dbGetQuery(conn, sprintf(
  "SELECT count(*)::int FROM fresh.streams_vw_bcfp
   WHERE watershed_group_code = '%s' AND access_%s IN (1,2) AND stream_order >= %d",
  wsg, sp, min_order))[1, 1]
# Whole mode: the group's segments in the schema step 1 will actually READ, not the bcfp view -- a
# group the view carries and the source lacks (MCGR in `fresh` until link added it, #76) must SKIP
# here rather than die in step 1's freshness guard. The schema name is checked before it reaches SQL.
n_whole <- function(wsg) {
  src <- reg$network_source
  if (!grepl("^[a-z_][a-z0-9_]*$", src)) stop("bad network_source: ", src, call. = FALSE)
  DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*)::int FROM %s.streams WHERE watershed_group_code = '%s' AND stream_order >= %d",
    src, wsg, as.integer(min_order)))[1, 1]
}

message("\n=== Pre-pass: ", if (whole) paste0("whole-network segments in ", reg$network_source)
        else "species coverage", " (order >= ", min_order, ") ===")
plan <- lapply(wsgs, function(w) {
  cnts <- if (whole) c(all = n_whole(w)) else vapply(prefs, function(sp) n_access(w, sp), numeric(1))
  sel  <- prefs[which(cnts > 0)[1]]
  data.frame(wsg = w, species = ifelse(is.na(sel), NA_character_, sel),
             n_segments = ifelse(is.na(sel), 0, cnts[[which(cnts > 0)[1]]]),
             counts = paste(sprintf("%s=%.0f", prefs, cnts), collapse = " "),
             stringsAsFactors = FALSE)
})
plan <- do.call(rbind, plan)
for (i in seq_len(nrow(plan))) {
  p <- plan[i, ]
  if (is.na(p$species)) {
    if (whole) {
      message(sprintf("  ⚠ %-5s SKIP: no segments at order >= %s in %s.streams", p$wsg, min_order,
                      reg$network_source))
    } else {
      message(sprintf("  ⚠ %-5s SKIP: none of [%s] modelled (%s)", p$wsg,
                      paste(prefs, collapse = ","), p$counts))
    }
  } else {
    message(sprintf("  %-5s -> %s (%.0f segments; %s)", p$wsg, p$species, p$n_segments, p$counts))
  }
}
skipped <- plan[is.na(plan$species), ]
if (nrow(skipped) > 0)
  message("\n⚠ ", nrow(skipped), " group(s) will produce NO floodplain: ",
          paste(skipped$wsg, collapse = ", "))

# --- Reconcile configs for the runnable groups (#44) ---
# The region file owns FP_REGION_OWNED; the area owns everything else. Resolution is a PURE function
# (fp_region_plan) so this loop can report under DRY without writing, and so the rules are testable
# without the database connection this script holds open.
runnable <- plan[!is.na(plan$species), ]
plans <- lapply(seq_len(nrow(runnable)), function(i) {
  w <- runnable$wsg[i]; sp <- runnable$species[i]
  # The region-owned keys (network_source, attribute_by, ... and in whole mode species = all) are
  # built in ONE place, fp_region_owned(), which the offline checks exercise too.
  owned <- fp_region_owned(reg, w, sp)
  fp_region_plan(here::here("config", tolower(w)), owned, base_scenarios(sp))
})

message("\n=== Config reconciliation ===")
for (i in seq_along(plans)) {
  p <- plans[[i]]
  message(sprintf("  %-5s area.yml: %s | flood_scenarios.csv: %s | break_points.csv: %s",
                  runnable$wsg[i], p$area_action, p$scenarios_action, p$break_points_action))
}
n_changed <- sum(vapply(plans, function(p) isTRUE(p$changed), logical(1)))
DBI::dbDisconnect(conn)

# DRY is a PREVIEW and writes NOTHING -- not the pipeline, and not the config either. It previously
# wrote configs before this gate, so the safe-looking command destroyed hand-maintained files (#44).
if (dry) {
  message("\n[DRY] preview only -- nothing written. ", n_changed, " of ", length(plans),
          " group(s) would change; re-run without DRY=1 to apply.")
  quit(save = "no")
}

invisible(lapply(plans, fp_region_write))
message(n_changed, " of ", length(plans), " config(s) updated; the rest were already current.")

# --- Run each group as a subprocess (per-WSG soft-fail + log) ---
ts <- format(Sys.time(), "%Y%m%d_%H%M%S", tz = "UTC")
log_dir <- here::here("data", "logs"); fs::dir_create(log_dir)
results <- list()
for (i in seq_len(nrow(runnable))) {
  w <- runnable$wsg[i]; sp <- runnable$species[i]; area <- tolower(w)
  log <- file.path(log_dir, sprintf("region_%s_%s_%s.log", region, area, ts))
  # Resumable: a group whose primary scenario's summary already exists is complete — skip it so a
  # re-run after an interruption picks up where it left off. FORCE=1 redoes everything.
  #
  # Keyed on the PRIMARY scenario's own summary, not the shared lulc_summary.rds: that one is
  # last-writer-wins across species, so another species' successful step 3 would mark this group done
  # while this scenario's step 3 had died before its composition (#108), and been skipped thereafter.
  # Step 3 unlinks both files at the start of its record write and rewrites them last.
  summary_rds <- file.path(here::here("data", area), paste0("lulc_summary_", sp, "_ff04.rds"))
  # A cached group never runs the child, so its provenance record (#33) is whatever the last real
  # run wrote -- and the group still reports `ok` and still reaches the publish hint. Publishing a
  # stale block as the provenance of a current release is worse than publishing none, because
  # every presence check downstream passes. So an ABSENT provenance.json invalidates the cache:
  # the forward-only rollout then self-heals on the next region run instead of being frozen out by
  # the very cache. A PRESENT one is reported with its date, so staleness is a number on screen.
  prov_json <- file.path(here::here("data", area), "provenance.json")
  # The PRIMARY scenario's landcover record, the one the cache is keyed on. It used to be the max over
  # every landcover entry, which for a converted group reports a retired species record's date beside
  # the all_ff04 run. Read again after the child runs, so the coverage CSV states the record that run
  # wrote rather than the one it replaced. jsonlite is namespaced and this file does not source
  # packages.R, so an absent jsonlite degrades to "date unread" rather than aborting a region run.
  prov_date_of <- function() {
    if (!file.exists(prov_json)) return(NA_character_)
    tryCatch({
      e <- jsonlite::read_json(prov_json, simplifyVector = FALSE)[["landcover"]][[plans[[i]]$area$primary_scenario]]
      v <- e[["run"]][["datetime_utc"]]
      if (is.character(v) && length(v) == 1L) v else NA_character_
    }, error = function(e) NA_character_, warning = function(w) NA_character_)
  }
  prov_date <- prov_date_of()
  # Present files are not a finished run of THIS config (fp_region_cache_reason): a floodplain on a
  # pre-0.7.0 grid (#117; DUNC's 2026-10-12 run), a network read under another min_order or
  # network_source (DUNC going fresh -> fresh_default), or a landcover record older than the network
  # or floodplain beneath it (a direct partial run, or a step 3 killed in its fetch) all re-run.
  # Every test reads the records, never this run's reconciliation diff, so a resume still sees it.
  why <- NA_character_
  if (file.exists(summary_rds) && file.exists(prov_json)) {
    why <- tryCatch(
      fp_region_cache_reason(jsonlite::read_json(prov_json, simplifyVector = FALSE), plans[[i]]$area),
      error = function(e) paste0("its provenance.json could not be read (", conditionMessage(e), ")"))
  }
  stale <- !is.na(why)
  cached <- file.exists(summary_rds) && file.exists(prov_json) && !stale && !nzchar(Sys.getenv("FORCE"))
  if (cached) {
    message("\n### ", w, " -> ", sp, ": complete (", basename(summary_rds), " present) — SKIP (FORCE=1 to redo)",
            " [provenance ", if (is.na(prov_date)) "present, date unread" else prov_date, "] ###")
    rc <- 0L
  } else {
    if (file.exists(summary_rds) && !file.exists(prov_json)) {
      message("\n### ", w, " -> ", sp, ": outputs present but NO provenance.json — re-running (#33) ###")
    } else if (stale && !nzchar(Sys.getenv("FORCE"))) {
      message("\n### ", w, " -> ", sp, ": outputs present but ", why, " — re-running ###")
    } else {
      message("\n### ", w, " -> ", sp, " (steps ", steps, ") -> ", basename(log), " ###")
    }
    # Retire the resume marker the moment the group is chosen to re-run. Every signal above is read
    # from provenance.json, which steps 1 and 2 rewrite early, while step 3 replaces the summary
    # last: a run interrupted in between would leave new records beside the OLD summary, and the
    # next resume would read that as complete. With the summary gone, any interruption re-runs.
    if (file.exists(summary_rds) && !file.remove(summary_rds)) {
      stop("cannot remove ", summary_rds, " before re-running ", w, call. = FALSE)
    }
    rc <- system2("Rscript", c(here::here("scripts", "run_area.R"), area, steps),
                  stdout = log, stderr = log)
    prov_date <- prov_date_of()
  }
  # POST-VERIFY: network non-empty (guards pre-pass-said-yes / run-gave-empty)
  km <- NA_real_; fp_km2 <- NA_real_
  net <- file.path(here::here("data", area), "aquatic_network.gpkg")
  if (rc == 0 && file.exists(net)) {
    s <- tryCatch(sf::st_read(net, layer = paste0("streams_", sp, min_order), quiet = TRUE), error = function(e) NULL)
    if (!is.null(s) && nrow(s) > 0) km <- sum(as.numeric(sf::st_length(s))) / 1000
    fp <- file.path(here::here("data", area), "floodplain.gpkg")
    if (file.exists(fp)) {
      f <- tryCatch(sf::st_read(fp, layer = paste0(sp, "_ff04"), quiet = TRUE), error = function(e) NULL)
      if (!is.null(f)) fp_km2 <- sum(as.numeric(sf::st_area(f))) / 1e6
    }
  }
  status <- if (rc != 0) "FAIL(run)" else if (is.na(km)) "FAIL(empty network)" else if (cached) "ok(cached)" else "ok"
  if (!status %in% c("ok", "ok(cached)")) message("  ⚠ ", w, ": ", status, " — see ", basename(log))
  results[[i]] <- data.frame(wsg = w, species = sp, status = status,
                             network_km = round(km, 1), floodplain_km2 = round(fp_km2, 1),
                             # Carried into the coverage CSV so a reader can see WHEN a cached
                             # group's provenance was written without opening the file (#33).
                             provenance = prov_date,
                             log = if (cached) "" else basename(log), stringsAsFactors = FALSE)
}

# --- Coverage summary ---
summ <- do.call(rbind, c(results, list(
  # Every column the result rows carry, provenance included: rbind() refuses frames whose columns
  # differ, so a region with any SKIPPED group used to abort here, after every run had finished.
  if (nrow(skipped) > 0) data.frame(wsg = skipped$wsg, species = NA,
    status = if (whole) "SKIP(no network)" else "SKIP(no species)",
    network_km = NA, floodplain_km2 = NA, provenance = NA_character_, log = "",
    stringsAsFactors = FALSE))))
csv <- file.path(log_dir, sprintf("region_%s_%s.csv", region, ts))
readr::write_csv(summ, csv)
message("\n=== Region ", region, " coverage ===")
print(summ, row.names = FALSE)
ok <- sum(summ$status %in% c("ok", "ok(cached)"))
message(sprintf("\n%d/%d groups have a floodplain. Summary: %s", ok, nrow(summ), csv))

# One hint for the whole batch — the children were suppressed above. Unset first so this call
# prints even though the child-suppression flag is still set in this process (#32).
Sys.unsetenv("FP_NO_PUBLISH_HINT")
published <- summ$wsg[summ$status %in% c("ok", "ok(cached)")]
if (length(published)) fp_publish_hint(tolower(published))
