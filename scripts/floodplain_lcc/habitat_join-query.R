# habitat_join-query.R — the #104 habitat join on an area's PUBLISHED whole-network layers, the way a
# consumer runs it: no re-delineation, no step re-run, one species question per query.
#
# Reads, for a whole-network area (`species: all`):
#   data/<area>/floodplain_<primary>.tif                  the floodplain (0/1)
#   data/<area>/floodplain.gpkg  <primary>_by_blue_line_key  its attribution by blue line
#   data/<area>/aquatic_network.gpkg  habitat_link        the habitat flags, keyed by FWA position
# plus segment GEOMETRY from the model's own `<schema>.streams` (all orders, as habitat_join-demo.R
# reads it), matched to habitat_link on (blue_line_key, downstream_route_measure). habitat_link carries
# position, not lines, and the position join needs lines: the nearest segment on each claiming blue
# line. The match rate is reported, so a habitat table that no longer describes the schema's segments
# cannot pass as a join.
#
# Joins (the rules are CLAUDE.md's "Habitat join on the blue-line floodplain"): by blue line (the
# contrast, fp_habitat_join.R), by position under `nearest` (areas) and `any` (connected view), from
# flooded::fl_valley_join() through fp_hj_join_position().
#
# Read-only on data/ and the database. Writes the committed log named below.
#
# usage: Rscript scripts/floodplain_lcc/habitat_join-query.R <area> [species ...]
#   species default: every species habitat_link carries for the area
t0 <- Sys.time()
suppressMessages({library(sf); library(terra); library(DBI); library(RPostgres)})
sf::sf_use_s2(FALSE)
`%||%` <- function(a, b) if (is.null(a)) b else a   # base R ships %||% only >= 4.4.0
terra::terraOptions(threads = 4, memfrac = 0.3, progress = 0)
lcc <- here::here("scripts", "floodplain_lcc")
source(file.path(lcc, "fp_region.R"))        # fp_whole_network
source(file.path(lcc, "fp_habitat_join.R"))  # claims, the by-blue-line contrast, summaries; shared with habitat_join-demo.R

args <- commandArgs(trailingOnly = TRUE)
area <- args[1]
if (is.na(area)) stop("usage: Rscript scripts/floodplain_lcc/habitat_join-query.R <area> [species ...]", call. = FALSE)
cfg <- yaml::read_yaml(here::here("config", area, "area.yml"))
if (!fp_whole_network(cfg)) stop("area '", area, "' is not a whole-network area (species: all)", call. = FALSE)
scen <- cfg$primary_scenario %||% paste0(cfg$species, "_ff04")
dd <- here::here("data", area)
tif <- file.path(dd, paste0("floodplain_", scen, ".tif"))
fp_gpkg <- file.path(dd, "floodplain.gpkg"); net_gpkg <- file.path(dd, "aquatic_network.gpkg")
attr_lyr <- paste0(scen, "_by_", cfg$attribute_by)
if (!file.exists(tif)) stop("missing ", tif, " (run step 2)", call. = FALSE)
if (!attr_lyr %in% sf::st_layers(fp_gpkg)$name) stop("missing layer ", attr_lyr, " in ", fp_gpkg, call. = FALSE)
if (!"habitat_link" %in% sf::st_layers(net_gpkg)$name) stop("missing habitat_link in ", net_gpkg, " (run step 1)", call. = FALSE)

hl <- sf::st_read(net_gpkg, layer = "habitat_link", quiet = TRUE)
model <- unique(hl$model)
if (length(model) != 1L || !grepl("^link:[a-z_][a-z0-9_]*$", model))
  stop("habitat_link carries no single link model (", paste(model, collapse = ", "), ")", call. = FALSE)
schema <- sub("^link:", "", model)
species <- if (length(args) > 1) args[-1] else sort(unique(hl$species), method = "radix")
miss_sp <- setdiff(species, hl$species)
if (length(miss_sp)) stop("habitat_link has no rows for: ", paste(miss_sp, collapse = ", "), call. = FALSE)

# --- segment geometry, every order, from the model's schema --------------------------------------
con <- dbConnect(Postgres())
seg <- st_zm(st_read(con, quiet = TRUE, query = sprintf("
  SELECT blue_line_key, downstream_route_measure AS drm, stream_order, length_metre, geom
    FROM %s.streams WHERE watershed_group_code = '%s'", schema, cfg$watershed_group)), drop = TRUE)
dbDisconnect(con)
for (k in c("blue_line_key", "drm", "stream_order", "length_metre")) seg[[k]] <- as.numeric(seg[[k]])
seg_key <- sprintf("%.0f:%.3f", seg$blue_line_key, seg$drm)

# --- the floodplain cells per claiming blue line, and integrity ----------------------------------
r <- rast(tif); v <- st_read(fp_gpkg, layer = attr_lyr, quiet = TRUE)
v[[cfg$attribute_by]] <- as.numeric(v[[cfg$attribute_by]])
g <- fp_hj_grid_cells(r, v, cfg$attribute_by, st_crs(seg))
if (any(g$check[c("missing", "extra")] != 0)) {
  print(g$check); stop("integrity check failed: floodplain and attribution disagree", call. = FALSE)
}
cell_ha <- prod(res(r)) / 1e4
n_claim <- tabulate(match(g$cells$cell, unique(g$cells$cell)))
shared <- data.frame(floodplain_cells = length(n_claim), floodplain_ha = length(n_claim) * cell_ha,
                     claiming_blue_lines = length(unique(g$cells$key)),
                     share_claimed_by_2plus = mean(n_claim >= 2), mean_claims = mean(n_claim))

# --- per species: match, km, joins -----------------------------------------------------------------
res <- list(); km <- list(); mt <- list()
for (sp in species) {
  h <- hl[hl$species == sp, ]
  hk <- sprintf("%.0f:%.3f", as.numeric(h$blue_line_key), as.numeric(h$downstream_route_measure))
  m <- match(seg_key, hk)
  mt[[sp]] <- data.frame(species = sp, habitat_rows = nrow(h), schema_segments = nrow(seg),
                         segments_matched = sum(!is.na(m)), habitat_rows_unmatched = sum(!hk %in% seg_key))
  hs <- seg[!is.na(m), ]
  hs$spawning <- !is.na(h$spawning[m[!is.na(m)]]) & as.logical(h$spawning[m[!is.na(m)]])
  hs$rearing  <- !is.na(h$rearing[m[!is.na(m)]])  & as.logical(h$rearing[m[!is.na(m)]])
  fb <- fp_hj_join_blk(g$cells, hs)
  fr <- fp_hj_join_position(r, v, hs, cfg$attribute_by)
  res[[sp]] <- rbind(fp_hj_summ(fb, "by blue line", sp, cell_ha),
                     fp_hj_summ(fr$nearest, "by position, nearest", sp, cell_ha),
                     fp_hj_summ(fr$any, "by position, any", sp, cell_ha))
  names(res[[sp]])[names(res[[sp]]) == "build"] <- "species"   # fp_hj_summ's second column
  res[[sp]]$tied_cells <- c(NA, fr$ties, NA)
  res[[sp]]$blk_without_segments <- c(NA, length(fr$no_segments), length(fr$no_segments))
  d <- st_drop_geometry(hs); on <- d$blue_line_key %in% g$cells$key
  blk_max <- tapply(d$stream_order, sprintf("%.0f", d$blue_line_key), max)[sprintf("%.0f", d$blue_line_key)]
  km[[sp]] <- data.frame(species = sp,
    spawning_km = sum(d$length_metre[d$spawning]) / 1e3,
    spawning_km_on_fp_blk = sum(d$length_metre[d$spawning & on]) / 1e3,
    rearing_km = sum(d$length_metre[d$rearing]) / 1e3,
    rearing_km_on_fp_blk = sum(d$length_metre[d$rearing & on]) / 1e3,
    habitat_km_off_fp_blk_order1 = sum(d$length_metre[(d$spawning | d$rearing) & !on & blk_max == 1]) / 1e3,
    habitat_km_off_fp_blk_order2plus = sum(d$length_metre[(d$spawning | d$rearing) & !on & blk_max >= 2]) / 1e3)
}

# --- the log -------------------------------------------------------------------------------------
fmt <- function(x) paste(utils::capture.output(print(x, digits = 6, row.names = FALSE)), collapse = "\n")
stamp <- format(Sys.time(), "%Y%m%d", tz = "UTC")
out <- file.path(lcc, "logs", paste0(stamp, "_habitat_join-query_", area, ".md"))
pdt <- format(Sys.time(), "%Y-%m-%d %H:%M %Z", tz = "America/Vancouver")
writeLines(c(
  paste0("# Habitat join on the published whole-network floodplain, ", toupper(area), " (#104)"), "",
  paste0("Produced by `scripts/floodplain_lcc/habitat_join-query.R ", paste(args, collapse = " "), "`, ", pdt,
         ". Floodplain `", scen, "` (`species: all`, order >= ", cfg$min_order, "), attributed by `",
         cfg$attribute_by, "` (`", attr_lyr, "`). Habitat flags from `habitat_link` (model `", model,
         "`); segment geometry from `", schema, ".streams`, every order, matched on (blue_line_key, ",
         "downstream_route_measure). flooded ", as.character(packageVersion("flooded")), ", terra ",
         as.character(packageVersion("terra")), "."), "",
  "Joins: **by blue line**, a blue line's whole floodplain takes any habitat on it (the contrast, not an answer); ",
  "**by position**, each cell takes the nearest segment on each blue line that claims it, then **nearest** ",
  "(one owner per cell; the rule for areas) or **any** (habitat if any claiming blue line says so; the connected view).", "",
  "## Integrity", "", "```", fmt(as.data.frame(t(g$check))), "```", "",
  "## Shared ground", "", "```", fmt(shared), "```", "",
  "## Habitat table against the schema's segments", "", "```", fmt(do.call(rbind, mt)), "```", "",
  "## Habitat km, and how much sits on a blue line with floodplain", "", "```", fmt(do.call(rbind, km)), "```", "",
  "## Habitat floodplain (ha)", "", "```", fmt(do.call(rbind, res)), "```", "",
  sprintf("Run time: %.0f s.", as.numeric(difftime(Sys.time(), t0, units = "secs")))), out)
message("Wrote ", out)
