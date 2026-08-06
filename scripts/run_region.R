#!/usr/bin/env Rscript
#
# run_region.R  —  run the pipeline over every watershed group in a region.
#
# Usage:
#   Rscript scripts/run_region.R <region> [steps]      # plan + generate configs + run
#   DRY=1 Rscript scripts/run_region.R <region>        # plan + generate configs only (no runs)
#
# Reads config/regions/<region>.yml (watershed_groups, ordered `species` preference,
# min_order, mergin_project). For each WSG it:
#   1. PRE-PASS resolves ONE species — the first in the preference list modelled at
#      order >= min_order (province-wide fresh.streams_vw_bcfp). A WSG where none of the
#      listed species is modelled is flagged LOUDLY and SKIPPED (never silently dropped).
#   2. generates config/<wsg>/ (area.yml + flood_scenarios.csv; no break_points.csv =>
#      whole-WSG polygon sub-basin).
#   3. runs scripts/run_area.R <wsg> as a subprocess (per-WSG soft-fail + timestamped log).
#   4. POST-VERIFY: the extracted network must be non-empty; if the pre-pass promised a
#      species but the real run comes back empty, it is recorded as a FAILURE, not a pass.
# Prints and writes a coverage summary (data/logs/region_<region>_<ts>.csv).

suppressMessages({library(here); library(yaml); library(readr); library(fs); library(sf)})
source(here::here("scripts", "publish_hint.R"))    # fp_publish_hint (advisory publish handoff)
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

reg <- yaml::read_yaml(here::here("config", "regions", paste0(region, ".yml")))
min_order <- reg$min_order %||% 3
prefs     <- reg$species
wsgs      <- reg$watershed_groups
message("Region: ", region, " | groups: ", length(wsgs), " | species preference: ",
        paste(prefs, collapse = ">"), " | min_order: ", min_order,
        if (dry) "  [DRY: plan only]" else "")

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

message("\n=== Pre-pass: species coverage (order >= ", min_order, ") ===")
plan <- lapply(wsgs, function(w) {
  cnts <- vapply(prefs, function(sp) n_access(w, sp), numeric(1))
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
    message(sprintf("  ⚠ %-5s SKIP: none of [%s] modelled (%s)", p$wsg,
                    paste(prefs, collapse = ","), p$counts))
  } else {
    message(sprintf("  %-5s -> %s (%.0f segments; %s)", p$wsg, p$species, p$n_segments, p$counts))
  }
}
skipped <- plan[is.na(plan$species), ]
if (nrow(skipped) > 0)
  message("\n⚠ ", nrow(skipped), " group(s) will produce NO floodplain: ",
          paste(skipped$wsg, collapse = ", "))

# --- Generate configs for the runnable groups ---
runnable <- plan[!is.na(plan$species), ]
for (i in seq_len(nrow(runnable))) {
  w <- runnable$wsg[i]; sp <- runnable$species[i]
  d <- here::here("config", tolower(w)); fs::dir_create(d)
  yaml::write_yaml(list(name = tolower(w), watershed_group = w, species = sp,
                        min_order = min_order, schema = tolower(w),
                        primary_scenario = paste0(sp, "_ff04")),
                   file.path(d, "area.yml"))
  readr::write_csv(base_scenarios(sp), file.path(d, "flood_scenarios.csv"))
  # whole-WSG batch groups use the group-polygon sub-basin; drop any stale break_points.csv
  bp <- file.path(d, "break_points.csv"); if (file.exists(bp)) fs::file_delete(bp)
}
message("Generated config/ for: ", paste(tolower(runnable$wsg), collapse = ", "))
DBI::dbDisconnect(conn)

if (dry) { message("\n[DRY] plan + configs written; no pipeline runs."); quit(save = "no") }

# --- Run each group as a subprocess (per-WSG soft-fail + log) ---
ts <- format(Sys.time(), "%Y%m%d_%H%M%S", tz = "UTC")
log_dir <- here::here("data", "logs"); fs::dir_create(log_dir)
results <- list()
for (i in seq_len(nrow(runnable))) {
  w <- runnable$wsg[i]; sp <- runnable$species[i]; area <- tolower(w)
  log <- file.path(log_dir, sprintf("region_%s_%s_%s.log", region, area, ts))
  # Resumable: a group whose lulc_summary.rds already exists is complete — skip it so a
  # re-run after an interruption picks up where it left off. FORCE=1 redoes everything.
  summary_rds <- file.path(here::here("data", area), "lulc_summary.rds")
  cached <- file.exists(summary_rds) && !nzchar(Sys.getenv("FORCE"))
  if (cached) {
    message("\n### ", w, " -> ", sp, ": complete (lulc_summary.rds present) — SKIP (FORCE=1 to redo) ###")
    rc <- 0L
  } else {
    message("\n### ", w, " -> ", sp, " (steps ", steps, ") -> ", basename(log), " ###")
    rc <- system2("Rscript", c(here::here("scripts", "run_area.R"), area, steps),
                  stdout = log, stderr = log)
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
                             log = if (cached) "" else basename(log), stringsAsFactors = FALSE)
}

# --- Coverage summary ---
summ <- do.call(rbind, c(results, list(
  if (nrow(skipped) > 0) data.frame(wsg = skipped$wsg, species = NA, status = "SKIP(no species)",
    network_km = NA, floodplain_km2 = NA, log = "", stringsAsFactors = FALSE))))
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
