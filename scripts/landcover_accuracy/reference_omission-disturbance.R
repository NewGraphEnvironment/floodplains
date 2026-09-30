# reference_omission-disturbance.R — how much known disturbance IO fails to map as tree loss (#93).
#
# Phase 4 of #93, the free reference: the fire and harvest polygons are evidence, independent of
# IO, that trees were removed. Inside the floodplain, the share of that area IO does NOT label as
# tree loss is a direct omission estimate that costs no review time. Criterion 4 reads the harvest
# row. The definitions are pinned in research/landcover_accuracy.md ("Free-reference omission"),
# committed before this script first ran; the filters below implement them and nothing else.
#
# Polygons are fetched with fp_disturbance.R's padded-bbox query (the same fetch step 3 tags
# with), with the extra filters added as the entry's `filter:`.
#
# usage: Rscript scripts/landcover_accuracy/reference_omission-disturbance.R [area]
# Output: data/<area>/accuracy/omission_disturbance.csv (pooled per source, plus per start year)

suppressMessages({library(sf); library(terra); library(DBI); library(RPostgres); library(yaml)})
sf::sf_use_s2(FALSE)
source(here::here("scripts", "floodplain_lcc", "fp_disturbance.R"))
source(here::here("scripts", "landcover_accuracy", "fp_accuracy.R"))

area <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(area)) area <- "necr"
cfg  <- fp_acc_area(area)
g    <- fp_acc_grid(cfg, years = cfg$change_interval)

dst  <- fp_disturbance_validate(yaml::read_yaml(here::here("config", "disturbance.yml")))
src  <- stats::setNames(dst$sources, vapply(dst$sources, `[[`, "", "name"))

# Qualifying events: standing for IO's first map, gone before its last one.
WINDOW <- c(cfg$change_interval[1] + 1L, cfg$change_interval[2] - 1L)   # 2018-2022
QUAL <- list(
  harvest = modifyList(src$harvest, list(
    carry  = c("harvest_start_year_calendar", "data_source", "percent_clearcut"),
    filter = sprintf(paste("data_source IN ('RESULTS', 'VRI') AND percent_clearcut >= 90",
                           "AND harvest_end_date IS NOT NULL AND harvest_end_date <= '%d-12-31'"),
                     WINDOW[2]))),
  fire = src$fire
)

fp <- sf::st_read(file.path(cfg$dir_out, "floodplain.gpkg"), layer = cfg$primary_scenario, quiet = TRUE)
fp <- sf::st_transform(fp, terra::crs(g$trans))

conn <- DBI::dbConnect(RPostgres::Postgres())
polys <- lapply(QUAL, fp_acc_fetch, conn = conn, fp = fp, window = WINDOW)
DBI::dbDisconnect(conn)

rows <- list()
for (nm in names(polys)) {
  p <- polys[[nm]]
  yc <- QUAL[[nm]]$year_col
  message(sprintf("%s: %d qualifying polygons touch the floodplain", nm, nrow(p)))
  pooled <- fp_acc_omission(g$from, g$to, g$trans, fp_acc_rasterize(p, g$trans))
  rows[[length(rows) + 1]] <- cbind(source = nm, year = "all", n_polys = nrow(p), pooled)
  for (y in sort(unique(p[[yc]]))) {
    py <- p[p[[yc]] == y, ]
    rows[[length(rows) + 1]] <- cbind(source = nm, year = as.character(y), n_polys = nrow(py),
                                      fp_acc_omission(g$from, g$to, g$trans,
                                                      fp_acc_rasterize(py, g$trans)))
  }
}
out <- do.call(rbind, rows)
num <- vapply(out, is.numeric, TRUE)
out[num] <- lapply(out[num], function(x) round(x, 4))

dir.create(cfg$dir_acc, showWarnings = FALSE, recursive = TRUE)
utils::write.csv(out, file.path(cfg$dir_acc, "omission_disturbance.csv"), row.names = FALSE, na = "")
print(out, row.names = FALSE)

h <- out[out$source == "harvest" & out$year == "all", ]
cat(sprintf(paste0("\nCriterion 4 (IO misses > 30%% of in-window stand-replacing harvest area): ",
                   "omission_io = %.3f over %.1f ha -> %s\n"),
            h$omission_io, h$denom_ha,
            if (is.na(h$omission_io)) "NOT EVALUABLE (no qualifying harvest)" else
              if (h$omission_io > 0.30) "HOLDS" else "does not hold"))
