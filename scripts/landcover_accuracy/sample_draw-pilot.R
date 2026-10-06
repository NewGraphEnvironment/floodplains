# sample_draw-pilot.R — build the accuracy strata and draw the stratified reference sample (#93).
#
# Phase 5 of #93. Strata are built by fp_acc_strata() on the published transition grid, as defined
# in research/landcover_accuracy.md ("Strata"), and drawn by drift::dft_accuracy_sample()
# (Olofsson et al. 2014). Each point carries:
#   map_class                what the PUBLISHED map claims there (the transition, or "no change"
#                            where the 1 ha sieve removed IO's change): what the labels are scored against
#   map_2017 .. map_2023     IO's own class every year, shown to the reviewer
#   in_<cause>_poly          whether the cell lies in a cause polygon inside the change window, at
#                            cell level -- the reference side of criterion 2 needs it for EVERY point,
#                            and the published patch flags exist on changed patches only
#   in_fwa_wetland           cell inside an FWA wetland polygon
#   in_fire_prior_poly       cell inside a fire from the `lookback:` years before the interval (#103);
#                            what stratum 19 ("change in prior fire") is drawn from, at cell level
#   use = "accuracy"         never training (research note, "Accuracy labels and training labels never mix")
#
# PILOT -> FULL: keep SEED and raise N. drift draws each stratum from its own stream, so the first
# N points of a stratum at a larger N are exactly this pilot's, and their labels carry over.
#
# Writes the design record, which is committed and never edited by hand:
#   reference/<area>/sample.gpkg   points (layer `sample`), date-pinned (#45)
#   reference/<area>/strata.csv    per stratum: cells, area, weight, points drawn (dft_accuracy_estimate's `strata`)
#   reference/<area>/design.json   seed, RNG kinds, allocation, grid -- enough to redraw it
#
# usage: Rscript scripts/landcover_accuracy/sample_draw-pilot.R [area]

suppressMessages({library(sf); library(terra); library(DBI); library(RPostgres); library(yaml)})
sf::sf_use_s2(FALSE)
source(here::here("scripts", "floodplain_lcc", "fp_disturbance.R"))
source(here::here("scripts", "landcover_accuracy", "fp_accuracy.R"))
source(here::here("scripts", "fp_gpkg.R"))
fp_gpkg_pin_date()

if (utils::packageVersion("drift") < "0.19.0")
  stop("drift >= 0.19.0 is required for dft_accuracy_sample()", call. = FALSE)

SEED <- 930093L   # fixed for the life of the sample; changing it discards every label
N    <- 30L       # pilot, per stratum (plan gate 2026-09-29)

area <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(area)) area <- "necr"
cfg  <- fp_acc_area(area)
g    <- fp_acc_grid(cfg)

dst    <- fp_disturbance_validate(yaml::read_yaml(here::here("config", "disturbance.yml")))
causes <- vapply(dst$sources, `[[`, "", "name")          # precedence = list order
wet_src <- Filter(function(s) identical(s$name, "wetland"), dst$context)
if (length(wet_src) != 1) stop("config/disturbance.yml has no `wetland` context entry", call. = FALSE)
# Lookback (#103): only `fire_prior` has a stratum. Any other entry would be tagged on the patches and
# silently absent from the design, so it is refused until it has one.
lb_names <- vapply(dst$lookback, `[[`, "", "name")
if (length(setdiff(lb_names, FP_ACC_PRIOR_NAME)))
  stop("lookback entr(ies) ", paste(setdiff(lb_names, FP_ACC_PRIOR_NAME), collapse = ", "),
       " have no accuracy stratum; only `", FP_ACC_PRIOR_NAME, "` does (fp_accuracy.R)", call. = FALSE)
prior_src <- Filter(function(s) identical(s$name, FP_ACC_PRIOR_NAME), dst$lookback)

lc  <- file.path(cfg$dir_out, "floodplain_landcover.gpkg")
lyr <- sprintf("transition_%s_%d_%d", cfg$primary_scenario, cfg$change_interval[1], cfg$change_interval[2])
# promote_to_multi = FALSE: step 3 writes a POLYGON/MULTIPOLYGON mix (CLAUDE.md, fire_tag.R note)
patches <- sf::st_read(lc, layer = lyr, quiet = TRUE, promote_to_multi = FALSE)
cause_r <- fp_acc_cause_rasters(patches, causes, g$trans)

fp <- sf::st_read(file.path(cfg$dir_out, "floodplain.gpkg"), layer = cfg$primary_scenario, quiet = TRUE)
fp <- sf::st_transform(fp, terra::crs(g$trans))
conn <- DBI::dbConnect(RPostgres::Postgres())
wet  <- fp_acc_fetch(conn, wet_src[[1]], fp, cfg$change_interval)
cause_poly <- lapply(dst$sources, fp_acc_fetch, conn = conn, fp = fp, window = cfg$change_interval)
names(cause_poly) <- causes
# The CHANGE INTERVAL, not the lookback years: .dst_window() derives those from it.
prior <- if (length(prior_src)) fp_acc_fetch(conn, prior_src[[1]], fp, cfg$change_interval)
DBI::dbDisconnect(conn)
wet_r        <- fp_acc_rasterize(wet, g$trans)
cause_poly_r <- lapply(cause_poly, fp_acc_rasterize, template = g$trans)
prior_r      <- if (!is.null(prior)) fp_acc_rasterize(prior, g$trans)

st <- fp_acc_strata(g$from, g$to, g$trans, cause_r, wet_r, prior = prior_r)

# Coverage: the strata must partition the footprint, and every published change cell must be in a
# change stratum (a cell the patches missed falls through to its transition-class stratum, by design).
n  <- function(x) terra::global(x, "sum", na.rm = TRUE)[[1]]
foot_n  <- n(!is.na(g$from) & !is.na(g$to))
strat_n <- n(!is.na(st$strata))
if (strat_n != foot_n) stop("strata cover ", strat_n, " cells; footprint is ", foot_n, call. = FALSE)
message(sprintf("strata partition the footprint: %d cells (%.1f ha)", foot_n,
                foot_n * prod(terra::res(g$trans)) / 1e4))

map <- c(list(class = st$reported),
         stats::setNames(g$cls, g$years),
         stats::setNames(cause_poly_r, paste0(causes, "_poly")),
         list(fwa_wetland = wet_r),
         if (!is.null(prior_r)) stats::setNames(list(prior_r), paste0(FP_ACC_PRIOR_NAME, "_poly")))
s <- drift::dft_accuracy_sample(st$strata, n = N, seed = SEED, map = map)

# drift draws from the strata it finds cells for, so a configured stratum with no cells is simply
# absent from the design. Say so rather than let "19 is drawn" be assumed.
if (!is.null(prior_r) && !FP_ACC_STRATUM_PRIOR$stratum %in% s$strata$stratum)
  message("NOTE: `", FP_ACC_PRIOR_NAME, "` is configured but no published change lies in it here; ",
          "stratum ", FP_ACC_STRATUM_PRIOR$stratum, " is not drawn")

pts <- s$points
for (nm in c(paste0(causes, "_poly"), "fwa_wetland", if (!is.null(prior_r)) paste0(FP_ACC_PRIOR_NAME, "_poly"))) {
  pts[[paste0("in_", nm)]] <- !is.na(pts[[paste0("map_", nm)]])
  pts[[paste0("map_", nm)]] <- NULL
}
pts$use      <- "accuracy"
pts$wsg      <- cfg$watershed_group   # item key (#30)
pts$species  <- cfg$species
pts$scenario <- cfg$primary_scenario

# Labels were made on the existing design: a redraw that keeps an id but moves its point would leave
# them describing other cells. Growing the sample (same seed, larger N) passes; anything else is refused.
# The same holds for the second labeller's labels and for the review key (#111), which maps the blind
# review_ids to these points: a redraw under it would send both labellers' work to other cells.
for (lab_csv in file.path(cfg$dir_ref, c("labels.csv", "labels_b.csv", "review_key.csv"))) {
  if (!file.exists(lab_csv) || identical(Sys.getenv("FORCE"), "1")) next
  labs <- utils::read.csv(lab_csv, stringsAsFactors = FALSE, colClasses = c(point_id = "character"))
  gone <- setdiff(labs$point_id, pts$point_id)   # a smaller n, or a stratum that no longer exists
  if (length(gone)) stop(length(gone), " point(s) in ", lab_csv, " are not in the new draw (",
                         paste(utils::head(gone, 3), collapse = ", "), "); FORCE=1 redraws anyway",
                         call. = FALSE)
  fp_acc_design_check(labs, sf::st_drop_geometry(pts),
                      paste(lab_csv, "(FORCE=1 redraws anyway and orphans it)"))
}

strata_tbl <- merge(s$strata, st$table[, c("stratum", "kind")], by = "stratum", sort = TRUE)
dir.create(cfg$dir_ref, showWarnings = FALSE, recursive = TRUE)
out_gpkg <- file.path(cfg$dir_ref, "sample.gpkg")
if (file.exists(out_gpkg)) unlink(out_gpkg)   # a fresh write is the byte-deterministic one (#45)
sf::st_write(pts, out_gpkg, layer = "sample", quiet = TRUE)
utils::write.csv(strata_tbl, file.path(cfg$dir_ref, "strata.csv"), row.names = FALSE, na = "")
# lookback: the entry the prior-fire stratum was drawn from, with the years it covered, or null.
# accuracy_estimate.R refuses a config that no longer matches it, as it does for causes.
lookback <- if (length(prior_src)) list(name = FP_ACC_PRIOR_NAME, lookback = prior_src[[1]]$lookback,
                                        years = .dst_window(prior_src[[1]], cfg$change_interval))
design <- c(s$design, list(area = area, n_per_stratum = N, causes = causes, lookback = lookback,
                           transition_layer = lyr, drift = as.character(utils::packageVersion("drift"))))
jsonlite::write_json(design, file.path(cfg$dir_ref, "design.json"), auto_unbox = TRUE, pretty = TRUE,
                     digits = NA, null = "null", na = "null")

message(sprintf("%d points over %d strata -> %s", nrow(pts), nrow(strata_tbl), cfg$dir_ref))
print(as.data.frame(strata_tbl)[, c("stratum", "stratum_label", "kind", "n_cells", "area", "weight", "n")],
      row.names = FALSE)
