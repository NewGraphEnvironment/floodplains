# drought_rank-gauges.R — which change-window years were low-flow years, from unregulated gauges (#93).
#
# Phase 3 of #93: drought years for the composite windows are MEASURED. The metric is the
# August–September mean daily flow per year, ranked against each gauge's own long-term record
# (percentile rank, so gauges of very different size are comparable). A year is "low" at a gauge
# when it falls in the lowest quintile of that gauge's record.
#
# The only active gauge inside NECR, 08JC001 Nechako at Vanderhoof, is REGULATED (Kenney Dam
# releases; HYDAT hy_stn_regulation says so from 1952), so its low flow measures reservoir
# operations rather than drought. It is reported and never counted. Two gauges are lake-buffered
# (Nautley below Fraser Lake, Stuart below Stuart Lake), so a dry summer shows there late and
# damped. They are reported, but only the four free-flowing gauges decide whether a year is low.
#
# Needs a current HYDAT (tidyhydat::download_hydat()): the 2024-04-16 release ends most of these
# gauges in 2022, which is inside the window being ranked.
#
# usage: Rscript scripts/landcover_accuracy/drought_rank-gauges.R [area]
# Output: data/<area>/accuracy/drought_rank.csv (one row per gauge x year, window years only)

suppressMessages({library(tidyhydat); library(dplyr)})
source(here::here("scripts", "landcover_accuracy", "fp_accuracy.R"))

area <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(area)) area <- "necr"
cfg  <- fp_acc_area(area)

GAUGES <- data.frame(
  station = c("08KC001", "08JB002", "08JE004", "08KG001", "08JB003", "08JE001", "08JC001"),
  role    = c(rep("free-flowing", 4), rep("lake-buffered", 2), "regulated")
)
YEARS      <- seq(cfg$change_interval[1], cfg$change_interval[2])
MONTHS     <- 8:9
MIN_DAYS   <- 55    # of 61 Aug–Sep days; a year with more gaps than this is not ranked
LOW_PCTILE <- 0.20  # lowest quintile

cat("HYDAT release:", format(hy_version()$Date), "\n")

q <- hy_daily_flows(GAUGES$station) |>
  filter(as.integer(format(Date, "%m")) %in% MONTHS) |>
  mutate(year = as.integer(format(Date, "%Y")))

ann <- q |>
  group_by(station = STATION_NUMBER, year) |>
  summarise(n_days = sum(!is.na(Value)), flow_augsep = mean(Value, na.rm = TRUE),
            .groups = "drop") |>
  filter(n_days >= MIN_DAYS)

# percentile rank within each gauge's own complete-year record: 0 = driest year on record
ranked <- ann |>
  group_by(station) |>
  mutate(n_years = n(), record = sprintf("%d-%d", min(year), max(year)),
         pct_rank = (rank(flow_augsep, ties.method = "average") - 1) / (n() - 1)) |>
  ungroup() |>
  left_join(GAUGES, by = "station") |>
  mutate(low = pct_rank <= LOW_PCTILE)

win <- ranked |> filter(year %in% YEARS) |> arrange(role, station, year)

missing <- setdiff(GAUGES$station, unique(ranked$station))
if (length(missing)) stop("no ranked record for ", paste(missing, collapse = ", "), call. = FALSE)
gaps <- win |> count(station) |> filter(n < length(YEARS))
if (nrow(gaps)) message("window years with too few days (not ranked): ",
                        paste(gaps$station, collapse = ", "))

verdict <- win |>
  filter(role == "free-flowing") |>
  group_by(year) |>
  summarise(n_gauges = n(), n_low = sum(low), median_pct = median(pct_rank), .groups = "drop") |>
  mutate(low_year = n_low > n_gauges / 2)

dir.create(cfg$dir_acc, showWarnings = FALSE, recursive = TRUE)
utils::write.csv(win, file.path(cfg$dir_acc, "drought_rank.csv"), row.names = FALSE, na = "")

cat("\nAug–Sep mean flow, percentile rank in each gauge's record (0 = driest):\n")
print(as.data.frame(tidyr::pivot_wider(win, id_cols = c(station, role, record),
                                       names_from = year, values_from = pct_rank) |>
                      mutate(across(where(is.numeric), ~ round(.x, 2)))), row.names = FALSE)
cat(sprintf("\nFree-flowing gauges; low = lowest quintile (pct_rank <= %.2f) at more than half:\n",
            LOW_PCTILE))
print(as.data.frame(verdict |> mutate(median_pct = round(median_pct, 2))), row.names = FALSE)
cat("\nLow-flow years:", paste(verdict$year[verdict$low_year], collapse = ", "), "\n")
