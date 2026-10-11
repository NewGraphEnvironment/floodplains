# floodplain_probe-subset.R — #104's floor check on a second group with arms 5, 3 and 2 only.
#
# floodplain_probe-whole-fwa.R's `reach` and `report` modes need all five arms, and arm 1 (every FWA
# stream) is the expensive one: 91 min per scenario on MORR. The order >= 2 decision needs only arms
# 5 (the species network), 3 and 2, so this applies `report`'s own formulas to those three:
#   cost         arm 2's delineation and attribution timing and peak RSS (from the run's logs)
#   area         2_vs_3 and 2_vs_5 overlap, gained share and the waterbody split (report section 2)
#   supersession coho-reachable floodplain of arms 2 and 3 against arm 5's (report section 3:
#                moved_share = (gained + lost) / arm 5's coho-reachable area)
# Read-only on the arms' outputs; writes only the committed log named below.
#
# usage (after floodplain_probe-run.sh <area> anchor dem 5 3 2):
#   Rscript scripts/floodplain_lcc/floodplain_probe-subset.R <area>
suppressMessages({library(sf); library(terra); library(DBI); library(RPostgres)})
sf::sf_use_s2(FALSE)
terra::terraOptions(threads = 4, memfrac = 0.3, progress = 0)
`%||%` <- function(a, b) if (is.null(a)) b else a
lcc <- here::here("scripts", "floodplain_lcc")
source(file.path(lcc, "fp_whole_fwa.R"))   # fp_wf_read_network, fp_wf_keep, fp_wf_overlap
source(file.path(lcc, "fp_provenance.R"))  # fp_raster_content_sha256, fp_table_content_sha256

area <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(area) || !grepl("^[a-z0-9_]+$", area)) stop("usage: floodplain_probe-subset.R <area>", call. = FALSE)
cfg <- yaml::read_yaml(here::here("config", area, "area.yml"))
scen_id <- cfg$primary_scenario %||% paste0(cfg$species, "_ff04")
sc <- utils::read.csv(here::here("config", area, "flood_scenarios.csv"), stringsAsFactors = FALSE)
sc <- sc[sc$scenario_id == scen_id, , drop = FALSE]
if (nrow(sc) != 1L) stop("scenario '", scen_id, "' not found once", call. = FALSE)
read_schema <- if (!is.null(cfg$network_source) && nzchar(cfg$network_source)) cfg$network_source else cfg$schema

dir_out <- here::here("data", area, "probe_whole_fwa")
p_out <- function(...) file.path(dir_out, paste0(...))
arms <- c(5L, 3L, 2L)
need <- c(p_out("anchor.json"), p_out("dem.json"), p_out("dem_common.tif"), p_out("arm", arms, "_floodplain.tif"),
          p_out("arm", arms, "_waterbody.tif"), p_out("arm", arms, "_by_blk.gpkg"), p_out("arm", arms, "_timing.json"))
if (any(!file.exists(need))) stop("missing: ", paste(basename(need[!file.exists(need)]), collapse = ", "),
                                  " -- run floodplain_probe-run.sh ", area, " anchor dem 5 3 2 first", call. = FALSE)

# The report's guards (floodplain_probe-report.R section 0 and the probe window), all of them except
# those on files this script does not read (reach.json, seg_timing.json, by_blk rows,
# anchor_floodplain.tif). Ported whole rather than chosen one by one: two review rounds found each
# hand-picked subset missing a guard that could print a wrong number.
rd <- function(f) jsonlite::read_json(f, simplifyVector = TRUE)
anc <- rd(p_out("anchor.json")); dmj <- rd(p_out("dem.json"))
tm <- setNames(lapply(arms, function(k) rd(p_out("arm", k, "_timing.json"))), arms)
wsg <- cfg$watershed_group
# One DEM, one toolchain. Section 3 attributes in this session, so the session joins the comparison
# (the report's equivalent is reach.json's versions).
if (length(unique(c(dmj$dem_content_sha256, vapply(tm, `[[`, "", "dem_content_sha256")))) != 1L)
  stop("arms were delineated on different DEMs", call. = FALSE)
vkeys <- c("flooded", "terra", "sf", "terra_gdal", "sf_gdal")
vsig <- function(x) paste(vapply(vkeys, function(k) as.character(x[[k]]), ""), collapse = "/")
now <- list(flooded = as.character(packageVersion("flooded")), terra = as.character(packageVersion("terra")),
            sf = as.character(packageVersion("sf")), terra_gdal = terra::gdal(),
            sf_gdal = unname(sf::sf_extSoftVersion()[["GDAL"]]))
v <- unique(c(vsig(dmj), vapply(tm, vsig, ""), vsig(now)))
if (length(v) != 1L) stop("arms, dem and this session differ in toolchain: ", paste(v, collapse = " | "), call. = FALSE)
# Each output tied to the run that produced it, by content.
for (k in arms) {
  tk <- tm[[as.character(k)]]
  if (!identical(fp_raster_content_sha256(p_out("arm", k, "_floodplain.tif")), tk$floodplain_content_sha256))
    stop("arm", k, "_floodplain.tif no longer matches arm", k, "_timing.json: re-run that arm", call. = FALSE)
  if (!identical(as.numeric(dmj$arm_segments[k]), as.numeric(tk$n_segments)))
    stop("arm ", k, " read ", tk$n_segments, " segments but the `dem` mode counted ", dmj$arm_segments[k],
         ": the network changed between modes", call. = FALSE)
  # floodplain, waterbody, by_blk, timing are written in that order by one process.
  if (is.unsorted(file.mtime(p_out("arm", k, c("_floodplain.tif", "_waterbody.tif", "_by_blk.gpkg", "_timing.json")))))
    stop("arm ", k, "'s outputs are not from one run (mtimes out of order): re-run that arm", call. = FALSE)
}
if (!identical(fp_raster_content_sha256(p_out("dem_common.tif")), dmj$dem_content_sha256))
  stop("dem_common.tif no longer matches dem.json", call. = FALSE)
# The probe window: every mode read must have finished after its last start, and nothing it depended
# on may have moved since the earliest start (t0).
modes_read <- c("anchor", "dem", as.character(arms))
mode_json <- function(m) switch(m, anchor = p_out("anchor.json"), dem = p_out("dem.json"), p_out("arm", m, "_timing.json"))
stamps <- p_out("logs/.", modes_read, ".start")
if (any(!file.exists(stamps))) stop("missing driver start stamps (run every mode through floodplain_probe-run.sh): ",
                                    paste(basename(stamps[!file.exists(stamps)]), collapse = ", "), call. = FALSE)
for (m in modes_read) {
  j <- mode_json(m); lg <- p_out("logs/", m, ".log")
  if (!file.exists(j) || file.mtime(j) <= file.mtime(p_out("logs/.", m, ".start")) ||
      !file.exists(lg) || sum(readLines(lg, warn = FALSE) == paste("PROBE_DONE", m)) != 1L)
    stop("mode `", m, "`: its output is not newer than its last start, or its log does not record it ",
         "finishing -- the last run of that mode failed; re-run it", call. = FALSE)
}
t0 <- min(file.mtime(stamps))
for (f in c(here::here("config", area, "flood_scenarios.csv"), here::here("config", area, "area.yml")))
  if (file.mtime(f) >= t0) stop(basename(f), " was modified after the probe began", call. = FALSE)
if (length(anc$scenario) != 1L) stop("anchor.json records no scenario", call. = FALSE)
scen_seen <- c(anc$scenario, vapply(tm, `[[`, "", "scenario"))
if (any(scen_seen != scen_id)) stop("modes ran different scenarios: ", paste(unique(scen_seen), collapse = ", "),
                                    " (this check is for ", scen_id, ")", call. = FALSE)
if (!isTRUE(anc$network_match) || !isTRUE(anc$dem_match_replay) || !isTRUE(anc$floodplain_match_replay))
  stop("the anchor did not pass: the probe is not shown to reproduce step 2", call. = FALSE)
akeys <- c("flooded", "terra", "terra_gdal", "sf_gdal")
if (!identical(vapply(akeys, function(k) as.character(anc[[k]]), ""), vapply(akeys, function(k) as.character(dmj[[k]]), "")))
  stop("the anchor ran on a different toolchain from the arms", call. = FALSE)

dem <- terra::rast(p_out("dem_common.tif"))
ha_cell <- prod(terra::res(dem)) / 1e4
fp <- setNames(lapply(arms, function(k) terra::rast(p_out("arm", k, "_floodplain.tif"))), arms)
wb <- setNames(lapply(arms, function(k) terra::rast(p_out("arm", k, "_waterbody.tif"))), arms)

# The report's rule: a log's RSS counts only if that log records the arm finishing and is no older
# than the json, so a failed re-run's smaller figure is never reported against an earlier success.
rss_gib <- function(m) {
  m <- as.character(m); f <- p_out("logs/", m, ".log")
  if (!file.exists(f) || file.mtime(f) < file.mtime(mode_json(m))) return(NA_real_)
  l <- readLines(f, warn = FALSE)
  if (!any(l == paste("PROBE_DONE", m))) return(NA_real_)
  fp_wf_peak_rss_gb(l)
}

# --- 1. cost ------------------------------------------------------------------------------------
# The rule's figures (report section 5): cost includes the shared DEM stage, and peak is max(arm, dem),
# NA when either is unmeasured.
cost <- do.call(rbind, lapply(arms, function(k) {
  tk <- tm[[as.character(k)]]; a <- rss_gib(k); d <- rss_gib("dem")
  data.frame(arm = k, segments = tk$n_segments, blue_lines = tk$n_blk, dem_min = round(dmj$t_dem_s / 60, 1),
             delin_min = round(tk$t_delin_s / 60, 1), attr_min = round(tk$t_attr_blk_s / 60, 1),
             total_min = round((dmj$t_dem_s + tk$t_delin_s + tk$t_attr_blk_s) / 60, 1),
             peak_gib = if (is.na(a) || is.na(d)) NA_real_ else round(max(a, d), 1))
}))

# --- 2. area: report section 2's formula, for the pairs these arms allow --------------------------
area_pair <- function(a, b) {
  o <- fp_wf_overlap(fp[[as.character(a)]], fp[[as.character(b)]])
  va <- terra::values(fp[[as.character(a)]], mat = FALSE); vb <- terra::values(fp[[as.character(b)]], mat = FALSE)
  gained <- !is.na(va) & va == 1 & !(!is.na(vb) & vb == 1)
  g_wb <- sum(gained & terra::values(wb[[as.character(a)]], mat = FALSE) == 1, na.rm = TRUE) * ha_cell
  g <- o$ha[o$metric == "a_only"]
  data.frame(pair = paste0(a, "_vs_", b), a_ha = round(o$ha[o$metric == "a"]), b_ha = round(o$ha[o$metric == "b"]),
             gained_ha = round(g), lost_ha = round(o$ha[o$metric == "b_only"]),
             gained_share_of_b = round(g / o$ha[o$metric == "b"], 3),
             gained_outside_wb_share = if (g > 0) round(1 - g_wb / g, 3) else NA_real_)
}
area_tab <- rbind(area_pair(2, 3), area_pair(2, 5), area_pair(3, 5))

# --- 3. supersession: report section 3, coho-reachable floodplain per arm ---------------------------
# `reach` mode's call: the species network alone, one group, complete = FALSE. The seeds are a live
# read, so they are tied to the arms as the report ties them: link's run logs show nothing for this
# group inside the window, arm 5 digests as it did at the anchor, and the whole-group count is the
# `dem` mode's. The digest columns are the driver's NETWORK_DIGEST_KEY / _VAL, copied.
if (!grepl("^[a-z_][a-z0-9_]*$", read_schema) || !grepl("^[A-Z]{4}$", wsg)) stop("bad schema or group name", call. = FALSE)
conn <- DBI::dbConnect(RPostgres::Postgres())
ev <- vapply(c("log", "log_recompute"), function(tb) DBI::dbGetQuery(conn, sprintf(
  "SELECT count(*)::int AS n FROM %s.%s WHERE watershed_group_code = '%s'
     AND (date_start >= $1 OR date_end >= $1 OR date_end IS NULL)", read_schema, tb, wsg),
  params = list(t0))$n, integer(1))
all <- fp_wf_read_network(conn, read_schema, wsg, sc$species)
DBI::dbDisconnect(conn)
s5 <- all[fp_wf_keep(all, 5L, as.integer(sc$min_order)), ]
dig <- fp_table_content_sha256(s5, c("blue_line_key", "downstream_route_measure"),
                               c("length_metre", "stream_order", "upstream_area_ha", "map_upstream",
                                 "channel_width", "waterbody_key"))
if (!identical(dig, anc$network)) stop("arm 5's network digests differently now than at the anchor", call. = FALSE)
if (!identical(as.numeric(nrow(all)), as.numeric(dmj$arm_segments[1])))
  stop("the whole-group read has ", nrow(all), " segments now, ", dmj$arm_segments[1], " at the `dem` mode", call. = FALSE)
if (any(ev > 0)) stop(read_schema, " ", paste(names(ev)[ev > 0], collapse = "/"), " has ", sum(ev), " row(s) for ", wsg,
                      " started, ended or still open since the probe began: the network may have changed under it",
                      call. = FALSE)
s5$coho_net <- 1L
reach_r <- setNames(lapply(arms, function(k) {
  x <- flooded::fl_valley_attribute(fp[[as.character(k)]], s5, group = "coho_net", dem = dem,
                                    max_width = sc$max_width, cost_threshold = sc$cost_threshold,
                                    complete = FALSE)
  r <- if (nrow(x)) terra::rasterize(terra::vect(x), dem, field = 1, background = 0, touches = FALSE)
       else terra::rast(dem, vals = 0)
  # The `reach` mode's guard: with complete = FALSE the reached and fallback cells partition the valley.
  fb <- attr(x, "fl_fallback_cells") %||% NA_integer_
  n_reach <- sum(terra::values(r, mat = FALSE) == 1, na.rm = TRUE)
  if (is.na(fb) || n_reach + fb != tm[[as.character(k)]]$valley_cells)
    stop("arm ", k, ": reached ", n_reach, " + fallback ", fb, " != valley ", tm[[as.character(k)]]$valley_cells,
         " -- the coho-reach attribution is not partitioning the valley", call. = FALSE)
  r
}), arms)
reach_tab <- do.call(rbind, lapply(c(3L, 2L), function(k) {
  o <- fp_wf_overlap(reach_r[[as.character(k)]], reach_r[["5"]])
  g <- o$ha[o$metric == "a_only"]; l <- o$ha[o$metric == "b_only"]; b <- o$ha[o$metric == "b"]
  data.frame(arm = k, reach_ha = round(o$ha[o$metric == "a"]), arm5_reach_ha = round(b),
             gained_ha = round(g), lost_ha = round(l), moved_share = round((g + l) / b, 3))
}))

# --- log -----------------------------------------------------------------------------------------
log <- here::here("scripts", "floodplain_lcc", "logs",
                  paste0(format(Sys.Date(), "%Y%m%d"), "_floodplain_probe-subset_", area, ".md"))
tab <- function(d) c("```", utils::capture.output(print(d, row.names = FALSE)), "```")
writeLines(c(
  paste0("# #104 floor check, arms 5, 3, 2 on ", toupper(area), " (", scen_id, ")"), "",
  paste0("Produced by `scripts/floodplain_lcc/floodplain_probe-subset.R ", area, "` from the arms in ",
         "`data/", area, "/probe_whole_fwa/`, ", format(Sys.time(), "%Y-%m-%d %H:%M %Z"),
         ". Formulas are floodplain_probe-report.R's sections 2 and 3. flooded ", tm[["5"]]$flooded,
         ", terra ", tm[["5"]]$terra, " (GDAL ", tm[["5"]]$terra_gdal, ")."), "",
  "## Cost (DEM + delineation + blue-line attribution, per scenario; the rule's figures)", "", tab(cost), "",
  "## Area on the common grid", "", tab(area_tab), "",
  "## Supersession: the coho network's floodplain under each delineation", "", tab(reach_tab)
), log)
message("wrote ", log)
print(cost); print(area_tab); print(reach_tab)
