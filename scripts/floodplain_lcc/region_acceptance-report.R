# region_acceptance-report.R — the numbers #125's per-region acceptance asks for, derived from each
# group's outputs on disk rather than copied by hand from logs.
#
# Per group of a region (config/regions/<region>.yml), primary scenario from config/<wsg>/area.yml:
#   network km            streams_<sp><order> in aquatic_network.gpkg (run_region.R's coverage rule)
#   freshness             network[<sp><order>].run.freshness in provenance.json
#   habitat_link          rows and species in aquatic_network.gpkg
#   floodplain km2        every <sp>_ffNN polygon layer in floodplain.gpkg (the coverage rule again)
#   blue lines            distinct blue_line_key in <primary>_by_blue_line_key
#   patches, tree loss    transition_<primary>_<span>: one row per transition class within an
#                         8-connected change region; the 1 ha sieve is on the REGION, so most rows
#                         are smaller (the count under 1 ha is printed). Loss and its causes through
#                         fp_disturbance_report(), so "tree loss" has one definition
#   bridge                union coverage (mean of max overlap_frac per patch) and unbridged patches,
#                         step 3's own definition, from patch_watercourse_<primary>_<span>
#   classified coverage   composition: in_floodplain ha with both endpoints classified, over the
#                         floodplain polygon area
#   #53 edge              change cells (transition.tif, from != to) inside / outside the group polygon
#                         (subbasins.gpkg) by cell centre (fp_rast_cells), against the patch total;
#                         and the floodplain raster's share outside the polygon
#   km2 per km            primary floodplain km2 over network km
#   wall time             each group log's mtime minus the previous one (the run stamp for the
#                         first), from the region's coverage CSV in data/logs/
#
# Every group is first tied to its records: fp_region_cache_reason() (one finished run, in record
# order), and the floodplain and transition rasters and the composition table must digest as
# provenance.json says. A group that fails either stops the report.
#
# No database, no network. Read-only.
#
# usage: Rscript scripts/floodplain_lcc/region_acceptance-report.R <region> [region ...]
#        Rscript scripts/floodplain_lcc/region_acceptance-report.R all
#   `all` takes every config/regions/*.yml and adds the outlier screen (below).
#   RUN_STAMP=<region>=<yyyymmdd_HHMMSS>,... picks the coverage CSV; default is the newest. A cached
#   group in it (no log) gets no wall time.
#
# OUTLIER SCREEN (written before the Fraser, Peace and Columbia numbers were read, #125): over every
# group, flag one whose km2-per-km or outside-polygon share lies beyond 1.5 x IQR of all groups.
# A flag is a reason to look at the group over imagery, not a defect.

suppressPackageStartupMessages({ library(sf); library(terra) })
sf::sf_use_s2(FALSE)
terra::terraOptions(progress = 0)   # its progress bars write to stdout, which is the report
root <- here::here()
lcc  <- file.path(root, "scripts", "floodplain_lcc")
source(file.path(root, "scripts", "fp_raster.R"))      # fp_rast_cells
source(file.path(lcc, "fp_composition.R"))              # fp_composition_summary
source(file.path(lcc, "fp_disturbance.R"))              # fp_disturbance_report
source(file.path(lcc, "fp_provenance.R"))               # fp_raster_content_sha256
source(file.path(lcc, "fp_region.R"))                   # fp_region_cache_reason

a <- commandArgs(TRUE)
if (!length(a)) stop("usage: region_acceptance-report.R <region> [region ...] | all", call. = FALSE)
reg_dir <- file.path(root, "config", "regions")
regions <- if (identical(a, "all")) sub("\\.yml$", "", list.files(reg_dir, "\\.yml$")) else a

stamps <- local({
  s <- Sys.getenv("RUN_STAMP")
  if (!nzchar(s)) return(character())
  kv <- strsplit(strsplit(s, ",")[[1]], "=")
  bad <- !vapply(kv, function(x) length(x) == 2 && grepl("^[0-9]{8}_[0-9]{6}$", x[2]), logical(1))
  if (any(bad)) stop("RUN_STAMP must be <region>=<yyyymmdd_HHMMSS>[,...]: ", s, call. = FALSE)
  out <- setNames(vapply(kv, `[`, "", 2), vapply(kv, `[`, "", 1))
  unknown <- setdiff(names(out), regions)
  if (length(unknown)) stop("RUN_STAMP names a region not being reported: ",
                            paste(unknown, collapse = ", "), call. = FALSE)
  out
})

dst <- yaml::read_yaml(file.path(root, "config", "disturbance.yml"))
gpkg_layers <- function(f) if (file.exists(f)) sf::st_layers(f)$name else character()
read_attrs <- function(f, lyr, cols) {
  q <- sprintf('SELECT %s FROM "%s"', paste(sprintf('"%s"', cols), collapse = ", "), lyr)
  suppressWarnings(sf::st_read(f, query = q, quiet = TRUE))
}
km2 <- function(f, lyr) sum(as.numeric(sf::st_area(sf::st_read(f, layer = lyr, quiet = TRUE)))) / 1e6

# The coverage CSV a region's timings come from: RUN_STAMP if given, else the newest. Never an older
# one: falling back past a resumed run would print a different run's wall times (a species-mode CSV,
# say) against outputs it did not produce.
coverage_csv <- function(region) {
  d <- file.path(root, "data", "logs")
  if (!is.na(stamps[region])) {
    f <- file.path(d, sprintf("region_%s_%s.csv", region, stamps[region]))
    if (!file.exists(f)) stop("RUN_STAMP names no coverage CSV: ", f, call. = FALSE)
    return(f)
  }
  f <- sort(list.files(d, sprintf("^region_%s_[0-9]{8}_[0-9]{6}\\.csv$", region), full.names = TRUE))
  if (length(f)) f[length(f)] else NA_character_
}

# A cached group (no log) ran nothing, so it has no wall time; the chain of mtimes skips it. Each
# group's window is [previous log's mtime (the run stamp for the first), its own log's mtime].
wall_times <- function(region) {
  f <- coverage_csv(region)
  if (is.na(f)) return(list(csv = NA_character_, min = numeric(), from = numeric(), to = numeric()))
  cv <- utils::read.csv(f, stringsAsFactors = FALSE)
  st <- sub(sprintf("^region_%s_([0-9]{8}_[0-9]{6})\\.csv$", region), "\\1", basename(f))
  t0 <- as.POSIXct(st, format = "%Y%m%d_%H%M%S", tz = "UTC")
  ran <- !is.na(cv$log) & nzchar(cv$log)
  mt <- file.info(file.path(dirname(f), cv$log[ran]))$mtime
  out <- from <- to <- setNames(rep(NA_real_, nrow(cv)), tolower(cv$wsg))
  out[ran]  <- as.numeric(diff(c(t0, mt)), units = "mins")
  from[ran] <- as.numeric(c(t0, mt)[seq_len(sum(ran))])
  to[ran]   <- as.numeric(mt)
  list(csv = basename(f), start = t0, min = out, from = from, to = to)
}

group_report <- function(area) {
  cfg  <- yaml::read_yaml(file.path(root, "config", area, "area.yml"))
  dd   <- file.path(root, "data", area)
  sp   <- cfg$species; ord <- cfg$min_order; prim <- cfg$primary_scenario
  prov <- jsonlite::read_json(file.path(dd, "provenance.json"))
  # The outputs must be this config's finished run, in record order (the region cache's verdict),
  # and the rasters and table read below must be the ones the records digest. Otherwise a row could
  # mix a step-2 re-run with an older step 3.
  why <- fp_region_cache_reason(prov, cfg)
  if (!is.na(why)) stop(area, ": not one finished run -- ", why, call. = FALSE)
  same <- function(rec, path) {
    if (!identical(fp_raster_content_sha256(path), rec))
      stop(area, ": ", basename(path), " does not digest as its provenance record says", call. = FALSE)
  }
  net_gpkg <- file.path(dd, "aquatic_network.gpkg")
  fp_gpkg  <- file.path(dd, "floodplain.gpkg")
  lc_gpkg  <- file.path(dd, "floodplain_landcover.gpkg")

  streams <- sf::st_read(net_gpkg, layer = paste0("streams_", sp, ord), quiet = TRUE)
  net_km  <- sum(as.numeric(sf::st_length(streams))) / 1000
  hl <- if ("habitat_link" %in% gpkg_layers(net_gpkg)) read_attrs(net_gpkg, "habitat_link", "species") else NULL

  fp_lyrs <- grep(sprintf("^%s_ff[0-9]{2}$", sp), gpkg_layers(fp_gpkg), value = TRUE)
  fp_km2  <- vapply(fp_lyrs, function(l) km2(fp_gpkg, l), numeric(1))
  by_lyr  <- paste0(prim, "_by_blue_line_key")
  blk     <- if (by_lyr %in% gpkg_layers(fp_gpkg))
               length(unique(read_attrs(fp_gpkg, by_lyr, "blue_line_key")$blue_line_key)) else NA_integer_

  lc_lyrs <- gpkg_layers(lc_gpkg)
  tr_lyr  <- grep(sprintf("^transition_%s_[0-9]{4}_[0-9]{4}$", prim), lc_lyrs, value = TRUE)
  if (length(tr_lyr) != 1) stop(area, ": expected one transition_", prim, "_* layer, found ",
                                length(tr_lyr), call. = FALSE)
  span <- sub(sprintf("^transition_%s_", prim), "", tr_lyr)
  causes <- vapply(dst$sources, function(s) paste0("in_", s$name), "")
  lbk    <- vapply(dst$lookback, function(s) paste0("in_", s$name), "")
  pat <- read_attrs(lc_gpkg, tr_lyr, c("patch_id", "name_basin", "area_ha", "from_class", "to_class",
                                       causes, lbk))
  utils::capture.output(loss <- fp_disturbance_report(pat, dst$sources, area, lookback = dst$lookback))
  loss_ha <- sum(loss$area_ha)
  share   <- function(sel) if (loss_ha > 0) 100 * sum(loss$area_ha[sel]) / loss_ha else NA_real_
  any_c   <- Reduce(`|`, lapply(causes, function(ic) loss[[ic]] %in% TRUE), rep(FALSE, nrow(loss)))
  cause_share <- vapply(causes, function(ic) share(loss[[ic]] %in% TRUE), numeric(1))

  br_lyr <- paste0("patch_watercourse_", prim, "_", span)
  br <- if (br_lyr %in% lc_lyrs) read_attrs(lc_gpkg, br_lyr, c("patch_id", "name_basin", "overlap_frac")) else NULL
  pk_all <- paste(pat$name_basin, pat$patch_id, sep = "¦")
  if (!is.null(br)) {
    pk <- paste(br$name_basin, br$patch_id, sep = "¦")
    union_cov <- mean(tapply(br$overlap_frac, pk, max))
    unbridged <- sum(!pk_all %in% pk)
  } else { union_cov <- NA_real_; unbridged <- NA_integer_ }

  comp_lyr <- paste0("composition_", prim, "_", span)
  comp <- if (comp_lyr %in% lc_lyrs) suppressWarnings(sf::st_read(lc_gpkg, layer = comp_lyr, quiet = TRUE)) else NULL
  cs   <- if (!is.null(comp)) fp_composition_summary(comp) else NULL
  classified_fp_ha <- if (!is.null(comp))
    sum(comp$ha[comp$in_floodplain %in% TRUE & comp$status != "nodata"]) else NA_real_

  # The #53 edge: the group polygon on each grid, by cell centre (fp_rast_cells).
  if (!is.null(comp) && !identical(fp_composition_digest(comp),
                                   prov$landcover[[prim]]$composition$outputs$table_content_sha256))
    stop(area, ": ", comp_lyr, " does not digest as its provenance record says", call. = FALSE)
  sb  <- sf::st_read(file.path(dd, "subbasins.gpkg"), quiet = TRUE)
  tr_path <- file.path(dd, "rasters", prim, "transition.tif")
  same(prov$landcover[[prim]]$outputs$transition_content_sha256, tr_path)
  tr  <- terra::rast(tr_path)
  levels(tr) <- NULL
  chg <- terra::ifel(!is.na(tr) & (tr %/% 1000) != (tr %% 1000), 1L, NA)
  inside_tr <- fp_rast_cells(sb, chg)
  cell_ha <- function(r) prod(terra::res(r)) / 1e4
  n_cells <- function(r) { f <- terra::freq(r); if (is.null(f) || !nrow(f)) 0 else sum(f$count) }
  chg_ha    <- n_cells(chg) * cell_ha(chg)
  chg_in_ha <- n_cells(terra::mask(chg, inside_tr)) * cell_ha(chg)
  fp_path <- file.path(dd, paste0("floodplain_", prim, ".tif"))
  same(prov$floodplain[[prim]]$outputs$floodplain_content_sha256, fp_path)
  fpr <- terra::rast(fp_path)
  fp1 <- terra::ifel(fpr == 1, 1L, NA)
  fp_ha     <- n_cells(fp1) * cell_ha(fp1)
  fp_out_ha <- fp_ha - n_cells(terra::mask(fp1, fp_rast_cells(sb, fp1))) * cell_ha(fp1)

  # When step 3 last ran: run.repairs[[1]] holds it once an in-place repair re-stamped the record (#126).
  lrun  <- prov$landcover[[prim]]$run
  step3 <- if (length(lrun$repairs)) lrun$repairs[[1]]$previous_datetime_utc else lrun$datetime_utc
  nk <- paste0(sp, ord)
  data.frame(
    wsg = toupper(area), net_km = net_km,
    freshness = prov$network[[nk]]$run$freshness %||% NA_character_,
    habitat_rows = if (is.null(hl)) NA_integer_ else nrow(hl),
    habitat_species = if (is.null(hl)) NA_character_ else paste(sort(unique(hl$species)), collapse = ", "),
    km2_ff02 = fp_km2[paste0(sp, "_ff02")] %||% NA, km2_ff04 = fp_km2[paste0(sp, "_ff04")] %||% NA,
    km2_ff06 = fp_km2[paste0(sp, "_ff06")] %||% NA, km2_primary = fp_km2[prim],
    blue_lines = blk, patches = nrow(pat), patch_ha = sum(pat$area_ha),
    patches_under_1ha = sum(pat$area_ha < 1),
    loss_ha = loss_ha, loss_patches = nrow(loss),
    fire_pct = cause_share["in_fire"], harvest_pct = cause_share["in_harvest"],
    unattributed_pct = share(!any_c),
    union_cov = union_cov, unbridged = unbridged,
    classified_fp_ha = classified_fp_ha, floodplain_ha_vec = 100 * fp_km2[prim],
    classified_cov = classified_fp_ha / (100 * fp_km2[prim]),
    comp_change_ha = cs$change_ha %||% NA_real_,
    chg_ha = chg_ha, chg_in_ha = chg_in_ha, chg_out_ha = chg_ha - chg_in_ha,
    fp_ha = fp_ha, fp_out_ha = fp_out_ha, fp_out_pct = 100 * fp_out_ha / fp_ha,
    km2_per_km = fp_km2[prim] / net_km,
    span = span,
    step3_utc = as.numeric(as.POSIXct(step3 %||% NA_character_, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")),
    row.names = NULL, stringsAsFactors = FALSE)
}
`%||%` <- function(x, y) if (is.null(x) || (length(x) == 1 && is.na(x))) y else x

f1 <- function(x) formatC(x, format = "f", digits = 1, big.mark = ",")
md <- function(df) {
  cat("| ", paste(names(df), collapse = " | "), " |\n", sep = "")
  cat("|", paste(rep("---", ncol(df)), collapse = "|"), "|\n", sep = "")
  for (i in seq_len(nrow(df))) cat("| ", paste(unlist(df[i, ]), collapse = " | "), " |\n", sep = "")
  cat("\n")
}

all_rows <- list()
for (region in regions) {
  reg <- yaml::read_yaml(file.path(reg_dir, paste0(region, ".yml")))
  groups <- tolower(unlist(reg$watershed_groups))
  wt <- wall_times(region)
  rows <- do.call(rbind, lapply(groups, group_report))
  rows$wall_min <- unname(wt$min[tolower(rows$wsg)])
  # The CSV times a run; the outputs on disk may be a later one (a direct run_area.R, or a region run
  # killed before it wrote its CSV). A group's time counts only when its step-3 record lies in its
  # own window of that run.
  k <- tolower(rows$wsg)
  tied <- !is.na(rows$step3_utc) & !is.na(wt$from[k]) &
          rows$step3_utc >= wt$from[k] & rows$step3_utc <= wt$to[k]
  untied <- rows$wsg[!tied & !is.na(rows$wall_min)]
  rows$wall_min[!tied] <- NA
  rows$region <- region
  all_rows[[region]] <- rows

  cat(sprintf("\n## %s (%d groups)\n\n", region, nrow(rows)))
  cat(sprintf("Produced by `Rscript scripts/floodplain_lcc/region_acceptance-report.R %s`, %s UTC. ",
              region, format(Sys.time(), "%Y-%m-%d %H:%M", tz = "UTC")))
  cat(sprintf("Timings from `data/logs/%s` (log mtimes).", wt$csv %||% "<no coverage csv>"))
  if (length(untied)) cat(sprintf(" No wall time for %s: its step-3 record is not from that run.",
                                  paste(untied, collapse = ", ")))
  cat("\n\n")
  cat("### Results\n\n")
  md(data.frame(
    group = rows$wsg,
    `network km (order >= 2)` = f1(rows$net_km),
    freshness = sub("^.*= ([-0-9.]+% dev).*$", "\\1", rows$freshness),
    `habitat_link rows` = paste0(formatC(rows$habitat_rows, big.mark = ",", format = "d"),
                                 " (", rows$habitat_species, ")"),
    `ff02 / ff04 / ff06 km2` = paste(f1(rows$km2_ff02), f1(rows$km2_ff04), f1(rows$km2_ff06), sep = " / "),
    `blue lines` = formatC(rows$blue_lines, big.mark = ",", format = "d"),
    `transition patches (< 1 ha)` = sprintf("%s (%s); %s ha", formatC(rows$patches, big.mark = ",", format = "d"),
                                            formatC(rows$patches_under_1ha, big.mark = ",", format = "d"), f1(rows$patch_ha)),
    `gross tree loss` = sprintf("%s ha in %s", f1(rows$loss_ha), formatC(rows$loss_patches, big.mark = ",", format = "d")),
    `fire / harvest / unattributed` = sprintf("%s / %s / %s%%", f1(rows$fire_pct), f1(rows$harvest_pct), f1(rows$unattributed_pct)),
    `bridge union (unbridged)` = sprintf("%.3f (%d)", rows$union_cov, rows$unbridged),
    `wall min` = f1(rows$wall_min),
    check.names = FALSE))
  cat("### Coverage and the #53 edge\n\n")
  md(data.frame(
    group = rows$wsg,
    `classified in floodplain / floodplain` = sprintf("%s / %s ha (%.4f)", f1(rows$classified_fp_ha),
                                                      f1(rows$floodplain_ha_vec), rows$classified_cov),
    `change cells` = f1(rows$chg_ha), `inside polygon` = f1(rows$chg_in_ha), outside = f1(rows$chg_out_ha),
    patches = f1(rows$patch_ha),
    `inside - patches` = sprintf("%+.1f", rows$chg_in_ha - rows$patch_ha),
    `floodplain outside polygon` = sprintf("%s of %s ha (%.2f%%)", f1(rows$fp_out_ha), f1(rows$fp_ha), rows$fp_out_pct),
    `km2 per km` = sprintf("%.4f", rows$km2_per_km),
    check.names = FALSE))
}

if (identical(a, "all")) {
  x <- do.call(rbind, all_rows)
  cat(sprintf("\n## Outlier screen (%d groups; flag beyond 1.5 x IQR)\n\n", nrow(x)))
  for (m in c("km2_per_km", "fp_out_pct")) {
    q <- stats::quantile(x[[m]], c(0.25, 0.75), names = FALSE); iqr <- diff(q)
    lo <- q[1] - 1.5 * iqr; hi <- q[2] + 1.5 * iqr
    fl <- x[x[[m]] < lo | x[[m]] > hi, ]
    cat(sprintf("- `%s`: median %.4f, IQR %.4f-%.4f, fences %.4f / %.4f. Flagged: %s\n", m,
                stats::median(x[[m]]), q[1], q[2], lo, hi,
                if (nrow(fl)) paste(sprintf("%s (%.4f)", fl$wsg, fl[[m]]), collapse = ", ") else "none"))
  }
  out <- file.path(root, "data", "logs", sprintf("region_acceptance_%s.csv", format(Sys.time(), "%Y%m%d_%H%M%S", tz = "UTC")))
  utils::write.csv(x, out, row.names = FALSE)
  cat(sprintf("\nPer-group values: data/logs/%s\n", basename(out)))
}
