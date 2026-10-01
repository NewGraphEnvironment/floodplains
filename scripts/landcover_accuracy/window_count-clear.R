# window_count-clear.R — clear Sentinel-2 observations per month over an area's floodplain (#93).
#
# Phase 2 of #93: the composite windows for reference imagery are MEASURED, not chosen by hand.
# For each month and year, drift::dft_stac_composite(aggregation = "count") returns, per pixel,
# how many distinct clear DAYS fall in that window (drift >= 0.20.0, drift#92: same-day MGRS tiles
# count once, NA = no clear day, snow is masked as well as cloud). `cloud_cover_max` is the chips'
# own value (drift's default, 20), so the counts describe the scenes a review chip is built from.
#
#   validate  one month, three checks before trusting the coarse run:
#             (a) res 100 vs res 20 over a small sub-AOI -- the coarse grid must not move the count
#             (b) the per-pixel count vs an INDEPENDENT rstac item query (bbox, not drift's
#                 `intersects` path): no pixel can see more clear days than there are dates
#             (c) the same month over the WHOLE floodplain, timed, so `run` (49 such calls) is
#                 launched on a measured cost; it is cached, so `run` reuses it
#   run       months 4-10 x 2017-2023 over the whole primary floodplain at res 100
#   derive    windows_clear_obs.csv -> reference/<area>/windows.csv by the rule pre-registered in
#             research/landcover_accuracy.md (fp_acc_window_* in fp_accuracy.R). A year widened
#             past the span is accepted only on a DIRECT count of the widened window.
#
# Output: data/<area>/accuracy/windows_clear_obs.csv (per month/year stats) and, from derive,
# reference/<area>/windows.csv. The curated copy and the log go to scripts/landcover_accuracy/logs/
# by hand, with the date prefix.
#
# A failed gdalcubes chunk read is NOT visible here (drift#87): it prints
# "[WARNING] n out of m chunks have repoprted errors" (sic) on stderr, R cannot capture it, and
# drift caches the result. A partial failure comes back `ok` with a LOWER share; a total one reads
# as "no clear pixels", i.e. `empty`. Either moves the span. So:
#   - run EVERY mode with `> <log> 2>&1` (validate, run and derive all call drift, and derive's
#     direct 2017 counts decide a committed file), and grep every log that FILLED THE CACHE
#     before trusting windows.csv. A cache hit reads nothing and prints only "count ...: cached",
#     so a month's evidence lives only in the log of the process that first computed it.
#   - a hit: re-run that mode with FORCE=1 (drift's `force = TRUE` for every call, same cache
#     key), then re-run derive. The grep sees only what reaches the shell, so it is a check, not a
#     guarantee -- the guarantee is drift#87's.
#
# usage: Rscript scripts/landcover_accuracy/window_count-clear.R <area> validate|run|derive > <log> 2>&1
#        caffeinate -s Rscript scripts/landcover_accuracy/window_count-clear.R necr run > run.log 2>&1
#        grep -c repoprted <every log above>   # must be 0 (see below)

suppressMessages({library(sf); library(terra)})
sf::sf_use_s2(FALSE)
source(here::here("scripts", "landcover_accuracy", "fp_accuracy.R"))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2 || !args[2] %in% c("validate", "run", "derive"))
  stop("usage: window_count-clear.R <area> validate|run|derive", call. = FALSE)
area <- args[1]; mode <- args[2]

cfg  <- fp_acc_area(area)
fp   <- sf::st_read(file.path(cfg$dir_out, "floodplain.gpkg"), layer = cfg$primary_scenario,
                    quiet = TRUE)
# The transition grid's CRS, so a window's pixels line up with the map being assessed.
crs_grid <- fp_acc_epsg(file.path(cfg$dir_rast, "transition.tif"))
fp   <- sf::st_transform(fp, as.integer(sub("EPSG:", "", crs_grid)))

YEARS  <- 2017:2023
MONTHS <- 4:10
CC_MAX <- 20   # drift's composite default; the chips use the same
FORCE  <- identical(Sys.getenv("FORCE"), "1")   # recompute and overwrite cached counts (drift#87)
CHIP_YEARS <- c(2017L, 2018L, 2020L, 2023L)   # endpoints + drought-contrast years (research note)

# Per-pixel stats over the AOI's OWN cells. A pixel with no clear observation can come back NA
# rather than 0, so summarising only non-NA values would drop exactly the cells that make a month
# bad; cells the AOI touches (the clip rule drift uses) count as 0 when NA.
count_stats <- function(r, month, year, res, aoi, status = "ok") {
  month <- fp_acc_months_str(month)
  inside <- terra::values(terra::rasterize(terra::vect(sf::st_geometry(aoi)), r[[1]], touches = TRUE),
                          mat = FALSE)
  v <- terra::values(r[[1]], mat = FALSE)[!is.na(inside)]
  v[is.na(v)] <- 0
  data.frame(year = year, month = month, res = res, status = status, n_cells = length(v),
             median = if (length(v)) stats::median(v) else NA_real_,
             p10 = if (length(v)) unname(stats::quantile(v, 0.10)) else NA_real_,
             max = if (length(v)) max(v) else NA_real_,
             share_ge1 = if (length(v)) mean(v >= 1) else NA_real_,
             share_ge3 = if (length(v)) mean(v >= 3) else NA_real_)
}

# One window (a month, or a vector of months) in one year -> list(r, status). Three outcomes, and they must stay distinct:
#   ok      a raster of counts
#   empty   drift found no scenes or no clear pixels -- a REAL zero, the signal this script looks for.
#           drift reports it as a warning ("Skipping the ... composite: no scenes|no clear pixels")
#           and then, with one year per call, aborts "No year produced a composite."
#   failed  any other error (STAC, network, token): NA, never 0
# The empty case is recognised by drift's warning text. If that text changes, an empty month falls
# to `failed` (NA) -- the direction that asks for a re-run rather than inventing a number.
clear_count <- function(aoi, year, month, res) {
  lab <- paste0(year, "-", fp_acc_months_str(month))
  skipped <- FALSE
  out <- withCallingHandlers(
    tryCatch(
      drift::dft_stac_composite(aoi, years = year, months = month, bands = "red",
                                aggregation = "count", res = res, crs = crs_grid, clip = TRUE,
                                cloud_cover_max = CC_MAX, force = FORCE),
      error = function(e) {
        if (!skipped) message("  ", lab, " FAILED: ", conditionMessage(e))
        NULL
      }),
    warning = function(w) {
      if (grepl("^Skipping the .* composite: (no scenes|no clear pixels)", conditionMessage(w))) {
        skipped <<- TRUE
        invokeRestart("muffleWarning")
      }
    })
  if (is.null(out) || !length(out)) return(list(r = NULL, status = if (skipped) "empty" else "failed"))
  # A count is a whole number. drift <= 0.19.x passed `aggregation` straight to gdalcubes'
  # cube_view(), which has no "count", and returned reflectance without complaint (drift#92) --
  # values near 0.03 that read as "almost no clear scenes" if nobody checks. Kept as a guard: a
  # stale drift, or a cache written by one, must still be refused.
  v <- terra::values(out[[1]], mat = FALSE)
  v <- v[!is.na(v)]
  if (length(v) && any(abs(v - round(v)) > 1e-6))
    stop(sprintf("%s: aggregation = \"count\" returned non-integer values (max %.4f); ", lab, max(v)),
         "this drift does not count clear days (drift#92: needs drift >= 0.20.0)", call. = FALSE)
  list(r = out[[1]], status = "ok")
}

if (mode == "validate") {
  year <- 2021; month <- 7
  # Sub-AOI: a 6 km square on the floodplain's largest part, clipped to the floodplain.
  parts  <- sf::st_cast(sf::st_union(fp), "POLYGON")
  anchor <- sf::st_point_on_surface(parts[which.max(sf::st_area(parts))])
  box    <- sf::st_as_sfc(sf::st_bbox(sf::st_buffer(anchor, 3000)))
  sub    <- sf::st_sf(geometry = sf::st_intersection(sf::st_union(fp), box))

  r100 <- clear_count(sub, year, month, 100)$r
  r20  <- clear_count(sub, year, month, 20)$r
  if (is.null(r100) || is.null(r20)) stop("validation composite failed or was empty", call. = FALSE)
  s <- rbind(count_stats(r100, month, year, 100, sub), count_stats(r20, month, year, 20, sub))
  print(s)

  # (b) independent item query over the sub-AOI's bbox
  bb <- sf::st_bbox(sf::st_transform(sub, 4326))
  it <- rstac::stac("https://planetarycomputer.microsoft.com/api/stac/v1") |>
    rstac::stac_search(collections = "sentinel-2-l2a", bbox = as.numeric(bb),
                       datetime = sprintf("%d-%02d-01T00:00:00Z/%d-%02d-%02dT23:59:59Z", year, month,
                                          year, month, 31L), limit = 500) |>
    rstac::ext_filter(`eo:cloud_cover` <= {{CC_MAX}}) |>
    rstac::post_request() |> rstac::items_fetch()
  dts   <- vapply(it$features, function(f) substr(f$properties$datetime, 1, 10), "")
  tiles <- vapply(it$features, function(f) f$properties$`s2:mgrs_tile` %||% NA_character_, "")
  n_dates <- length(unique(dts))
  cat(sprintf("\nitems (cloud <= %d): %d over %d distinct dates; tiles: %s\n", CC_MAX,
              length(dts), n_dates, paste(sort(unique(tiles)), collapse = ",")))
  # drift counts DAYS (same-day tiles once), so the bound is distinct dates, not items
  cat(sprintf("max per-pixel clear days: res100 %s, res20 %s (must be <= distinct dates %d)\n",
              s$max[1], s$max[2], n_dates))
  if (max(s$max) > n_dates) stop("a pixel saw more clear days than there are dates", call. = FALSE)

  # (c) the whole floodplain, timed: the cost of one `run` call
  t0 <- Sys.time()
  cc <- clear_count(fp, year, month, 100)
  mins <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
  if (cc$status == "failed") stop("floodplain-wide validation month failed", call. = FALSE)
  if (cc$status == "ok") print(count_stats(cc$r, month, year, 100, fp))
  cat(sprintf("\nfloodplain-wide %d-%02d at res 100: %s in %.1f min; x %d calls = ~%.1f h for `run`\n",
              year, month, cc$status, mins, length(YEARS) * length(MONTHS),
              mins * length(YEARS) * length(MONTHS) / 60))
} else if (mode == "derive") {
  f_in <- file.path(cfg$dir_acc, "windows_clear_obs.csv")
  if (!file.exists(f_in)) stop("no ", f_in, ": run `window_count-clear.R ", area, " run` first", call. = FALSE)
  st <- utils::read.csv(f_in, stringsAsFactors = FALSE)
  st <- st[st$res == 100 & grepl("^[0-9]+$", st$month), ]   # per-month rows only
  st$month <- as.integer(st$month)
  wp <- fp_acc_window_pass(st, YEARS, MONTHS)
  cat("share of floodplain cells with >= 1 clear day (rows year, cols month):\n")
  print(round(wp$share, 3))

  span <- fp_acc_window_span(wp)
  widen <- character(0)
  if (!length(span)) {
    # the one pre-registered deviation: 2017 alone may be widened
    rest <- setdiff(as.character(YEARS), "2017")
    span <- fp_acc_window_span(wp, rest)
    if (!length(span))
      stop("no month is clear everywhere even without 2017; the pre-registered fallback is HLS ",
           "(drift#82)", call. = FALSE)
    widen <- "2017"
  }
  cat(sprintf("\nsame-season span (clear everywhere in every year%s): months %s\n",
              if (length(widen)) " but 2017" else "", fp_acc_months_str(span)))

  months_by_year <- stats::setNames(rep(list(span), length(CHIP_YEARS)), CHIP_YEARS)
  for (y in widen) {
    got <- NULL
    # the span itself first: its months can each fail in this year while their union passes
    for (m in c(list(span), fp_acc_window_widen(wp, y, span))) {
      cc <- clear_count(fp, as.integer(y), m, 100)
      if (cc$status == "failed") stop(y, " ", fp_acc_months_str(m), " failed; re-run derive", call. = FALSE)
      sh <- if (cc$status == "ok") count_stats(cc$r, m, as.integer(y), 100, fp)$share_ge1 else 0
      cat(sprintf("  %s months %s, direct count: share >= 1 clear day %.3f\n", y, fp_acc_months_str(m), sh))
      if (sh >= FP_ACC_WIN_THR) { got <- m; break }
    }
    if (is.null(got))
      stop(y, " has no window within months ", fp_acc_months_str(MONTHS), " clear everywhere; the ",
           "pre-registered fallback is HLS (drift#82)", call. = FALSE)
    months_by_year[[y]] <- got
  }

  win <- data.frame(window = "same_season", year = CHIP_YEARS,
                    months = vapply(months_by_year, fp_acc_months_str, ""), stringsAsFactors = FALSE)
  f_out <- file.path(cfg$dir_ref, "windows.csv")
  utils::write.csv(win, f_out, row.names = FALSE, quote = FALSE)
  print(win)
  cat("wrote", f_out, "\n")

  # early/late amplitude (reported, not chipped): the first and last month clear everywhere, per year
  amp <- data.frame(year = YEARS, t(vapply(as.character(YEARS), function(y) {
    m <- as.integer(colnames(wp$pass))[wp$pass[y, ]]
    c(early = if (length(m)) min(m) else NA_integer_, late = if (length(m)) max(m) else NA_integer_)
  }, integer(2))), row.names = NULL)
  cat("\nfirst and last month clear everywhere, per year:\n"); print(amp)
} else {
  rows <- list()
  for (yr in YEARS) for (m in MONTHS) {
    t0 <- Sys.time()
    cc <- clear_count(fp, yr, m, 100)
    rows[[length(rows) + 1]] <- if (cc$status == "ok") count_stats(cc$r, m, yr, 100, fp) else
      if (cc$status == "empty")   # a real zero: no scene, or no clear pixel, in the whole window
        data.frame(year = yr, month = m, res = 100, status = "empty", n_cells = NA_real_, median = 0,
                   p10 = 0, max = 0, share_ge1 = 0, share_ge3 = 0) else
        data.frame(year = yr, month = m, res = 100, status = "failed", n_cells = NA_real_,
                   median = NA_real_, p10 = NA_real_, max = NA_real_, share_ge1 = NA_real_,
                   share_ge3 = NA_real_)   # NA, never 0: re-run it
    message(sprintf("%d-%02d done in %.1f min", yr, m,
                    as.numeric(difftime(Sys.time(), t0, units = "mins"))))
  }
  res <- do.call(rbind, rows)
  if (any(res$status == "failed"))
    warning(sum(res$status == "failed"), " month-year(s) FAILED (NA); re-run before choosing windows",
            call. = FALSE)
  dir.create(cfg$dir_acc, showWarnings = FALSE)
  f <- file.path(cfg$dir_acc, "windows_clear_obs.csv")
  utils::write.csv(res, f, row.names = FALSE, na = "")
  print(res)
  cat("wrote", f, "\n")
}
