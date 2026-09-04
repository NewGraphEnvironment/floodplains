# readme_functions.R — sourced by README.Rmd.
#
# Two jobs, and the split between them is the point:
#
#   * the readers (`fp_readme_roster`, `fp_readme_scenarios`) run on EVERY render. They read
#     committed config, so they need no database, no `data/`, and no network — which is what
#     lets the README regenerate its own facts instead of restating them from memory. The two
#     numbers #77 was filed over ("20 items live", a Fraser roster of 10) were both true when
#     they were typed and nothing regenerated them.
#   * the figure builders run only under `params$update_figs`. They read `data/<area>/`, which
#     is gitignored, so on any other machine the gate must stay FALSE and the render pulls in
#     the committed PNG.
#
# Nothing here touches the STAC API. This repo owns the model; `stac_floodplains_bc` owns the
# catalogue, and neither states the other's numbers (floodplains#77).

FIG_DIR <- "fig"

# The figures are built from BULK, not from the `neexdzii` parity fixture. neexdzii is
# deliberately in no region roster (`config/regions/skeena.yml`: "NEEXDZII (subset of BULK)
# intentionally excluded"), so a figure of it would show ground the published catalogue does not
# carry. BULK is the whole Bulkley group, published, and coho at ff04 is its primary scenario.
FIG_AREA <- "bulk"
FIG_SPECIES <- "co"
FIG_PRIMARY <- "co_ff04"
# Display strings the figure titles need and cannot derive: a watershed-group code is not a name,
# and there is no committed file in this repo mapping one to the other. Keyed by the code rather
# than assigned flat, so pointing FIG_AREA at another group STOPS instead of titling MORR's
# figures "Bulkley" — the silent-caption failure this file has now produced twice.
FIG_LABELS <- list(area = c(bulk = "Bulkley"), species = c(co = "coho", ch = "chinook",
                                                           bt = "bull trout", wct = "westslope cutthroat"))
fp_label <- function(kind, key) {
  # `[` not `[[`: on a named character vector `[[` throws "subscript out of bounds" for a missing
  # name, which is a stop — but one that says nothing about what to do. Measured.
  v <- unname(FIG_LABELS[[kind]][key])
  if (is.na(v)) {
    stop("no display label for ", kind, " `", key, "` — add one to FIG_LABELS in ",
         "scripts/readme_functions.R, or the figure titles would name the wrong ", kind,
         call. = FALSE)
  }
  v
}
FIG_AREA_LABEL <- fp_label("area", FIG_AREA)
FIG_SPECIES_LABEL <- fp_label("species", FIG_SPECIES)
# Mirrors the pipeline's `cfg$change_interval`. Not stamped, because it is USED: it builds the
# transition layer name, so a divergence fails at `st_read` rather than mislabelling a figure.
FIG_SPAN <- c("2017", "2023")

# The detail window, in BC Albers. Chosen for a confluence where the three scenarios visibly
# differ; hardcoded because a "pick the widest reach" heuristic would move the figure every time
# the model moves, and a caption is not worth that.
FIG_INSET <- c(xmin = 983000, ymin = 1033000, xmax = 999000, ymax = 1051500)

# Ramped rather than listed, so the palette cannot go one short of the scenarios it colours.
PAL_FF_ENDS <- c("#1f5f92", "#dbe9f2")                 # narrowest -> widest
UNATTRIBUTED <- "not yet attributed"

# One row per cause, so the hex and the word a screen reader gets cannot drift apart. They were
# separate the first time and the alt text ended up saying "fire in #c1441e".
CAUSE_STYLE <- data.frame(
  source = c("fire",    "harvest", "pest",    "other",   UNATTRIBUTED),
  hex    = c("#c1441e", "#e0a30c", "#7b5aa6", "#2f7d5c", "#6f757d"),
  colour = c("red",     "amber",   "purple",  "green",   "grey"),
  stringsAsFactors = FALSE
)

#' The disturbance sources actually configured, from the file the pipeline reads
#'
#' Not a literal list. `config/disturbance.yml` is what `fp_disturbance_tag()` consumes, and it
#' carries a commented-out `pest` source; enabling it would add an `in_pest` column that a
#' hardcoded fire/harvest figure would silently fold into "not yet attributed" while the caption
#' still claimed to describe that file.
fp_readme_sources <- function(f = "config/disturbance.yml") {
  y <- yaml::read_yaml(f)
  vapply(y$sources, function(s) s$name, character(1))
}

# ---- readers (no data, no network) -------------------------------------------------------

#' Watershed groups the pipeline is configured to run, by region
#'
#' Read from `config/regions/*.yml`, which is what `run_region.R` itself consumes — so a group
#' added there shows up here on the next render.
#'
#' Deliberately returns codes and NO total. Four sets do not coincide and a single count
#' collapses them: configured (these, plus `neexdzii`), published, re-runnable at the current
#' `flooded`, and provenance-carrying. Counting YAML entries would let a group claim to be
#' modelled before a cell had been delineated — which is the failure #77 exists to fix,
#' reintroduced by the fix.
fp_readme_roster <- function(dir = "config/regions") {
  files <- sort(list.files(dir, pattern = "\\.yml$", full.names = TRUE))
  if (!length(files)) stop("no region files under ", dir, call. = FALSE)
  rows <- lapply(files, function(f) {
    y <- yaml::read_yaml(f)
    for (k in c("region", "species", "watershed_groups")) {
      if (is.null(y[[k]])) stop(basename(f), ": `", k, "` is missing", call. = FALSE)
    }
    data.frame(
      region = y$region,
      # The region's FIRST PREFERENCE, which is not always what a group resolves to: the
      # run_region pre-pass picks the first listed species actually modelled at >= min_order.
      # Every group resolves to the first entry today (columbia lists `wct` as a fallback that
      # never fires), so the column is labelled "species preference" rather than "species" —
      # a table stating the wrong species for one group, with nothing to notice, is the same
      # shape as the counts #77 was filed over.
      species = y$species[[1]],
      groups = paste(sort(unlist(y$watershed_groups)), collapse = ", "),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  # Two region files can share a `region:` label with different species (skeena.yml and
  # skeena_ch.yml), which is the documented way to model a second species. Keep them as
  # separate rows rather than merging: the species is what the row is about.
  out[order(out$region, out$species), , drop = FALSE]
}

#' The flood scenarios an area is configured with
#'
#' `config/<area>/flood_scenarios.csv` already carries what `ff0N` MEANS and what it is grounded
#' in, per scenario. Rendering it is how the README answers "what is a flood factor, and why is
#' this not a flood-frequency product" from a file that moves when the model moves.
fp_readme_scenarios <- function(area = FIG_AREA, species = FIG_SPECIES) {
  f <- file.path("config", area, "flood_scenarios.csv")
  s <- utils::read.csv(f, stringsAsFactors = FALSE)
  s <- s[s$species == species, , drop = FALSE]
  if (!nrow(s)) stop(f, ": no rows for species `", species, "`", call. = FALSE)
  s[order(s$flood_factor), , drop = FALSE]
}

#' Every citation key the configured scenarios rest on, deduplicated
#'
#' The keys were already in the CSV and nothing rendered them, so the repo cited the valley
#' confinement method nowhere at all.
fp_readme_citekeys <- function(area = FIG_AREA, species = FIG_SPECIES) {
  s <- fp_readme_scenarios(area, species)
  # Drop NA BEFORE `paste`, which stringifies it. Two empty shapes exist and they need different
  # handling: a partially empty `citations` column reads as `""`, and an ALL-empty one reads as a
  # logical NA column -- 20 of the 23 `config/*/flood_scenarios.csv` are in that state. `paste`
  # turns that NA into the literal `"NA"`, and `nzchar(NA)` is TRUE, so filtering afterwards
  # keeps it: `fp_readme_citekeys("kotl", "bt")` returned the bogus key "NA". One literal NA cell
  # in an otherwise-populated file is the silent case -- 13 keys where 12 are real, with the
  # `named %in% keys` guard in README.Rmd still passing.
  cit <- s$citations[!is.na(s$citations)]
  k <- unique(unlist(strsplit(paste(cit, collapse = ";"), ";")))
  k[nzchar(k)]
}

# ---- figure builders (gated: read gitignored data/) ---------------------------------------

fp_fig_path <- function(name) file.path(FIG_DIR, name)

#' TRUE where a tag column is TRUE, with NA read as "not tagged"
#'
#' The tag columns are logical today with no NAs, but `[<-` with an NA index assigns to the wrong
#' rows rather than erroring, so an NA would relabel patches silently.
isTRUE_col <- function(x) !is.na(x) & x

#' The scenarios configured to run, in ascending flood factor
#'
#' `isTRUE_col` rather than a raw index: an NA in the `run` column would inject an all-NA row,
#' which reaches `st_read` as layer `co_ffNA`.
fp_scenarios_run <- function(...) {
  sc <- fp_readme_scenarios(...)
  sc[isTRUE_col(sc$run == "TRUE" | sc$run == TRUE), , drop = FALSE]
}

#' `co_ff04` -> `ff04`
fp_scen_short <- function(x) sub("^.*_", "", x)

#' A colour per cause, with a stated colour for any source the palette has not met
fp_cause_style <- function(lv, col) {
  i <- match(lv, CAUSE_STYLE$source)
  fallback <- match("other", CAUSE_STYLE$source)
  i[is.na(i)] <- fallback                    # a source the table has not met still gets a colour
  stats::setNames(CAUSE_STYLE[[col]][i], lv)
}

fp_cause_pal <- function(lv) fp_cause_style(lv, "hex")

#' The colour WORD for each cause, for alt text
fp_cause_colour <- function(lv) fp_cause_style(lv, "colour")

#' Read a layer from the figure area and put it in BC Albers
fp_fig_read <- function(gpkg, layer) {
  f <- file.path("data", FIG_AREA, gpkg)
  if (!file.exists(f)) {
    stop(f, " is missing — figure rebuilds need a machine that has run the pipeline. ",
         "Render with params$update_figs = FALSE to use the committed PNGs.", call. = FALSE)
  }
  sf::st_transform(sf::st_read(f, layer, quiet = TRUE), 3005)
}

#' A plain scale bar, since ggspatial is not a dependency of this repo
fp_fig_scalebar <- function(bb, km) {
  x0 <- bb[["xmin"]] + 0.06 * (bb[["xmax"]] - bb[["xmin"]])
  y0 <- bb[["ymin"]] + 0.06 * (bb[["ymax"]] - bb[["ymin"]])
  list(
    ggplot2::annotate("segment", x = x0, xend = x0 + km * 1000, y = y0, yend = y0,
                      linewidth = 0.7, colour = "grey20"),
    ggplot2::annotate("text", x = x0 + km * 500, y = y0, label = paste0(km, " km"),
                      vjust = -0.6, size = 2.8, colour = "grey20")
  )
}

fp_fig_theme <- function() {
  ggplot2::theme(
    plot.title.position = "plot",
    plot.title = ggplot2::element_text(size = 11, face = "bold"),
    plot.subtitle = ggplot2::element_text(size = 9, colour = "grey30")
  )
}

#' fig/floodplain.png — where the floodplain goes, and what the flood factor changes
#'
#' Left: the whole group, its accessible network and the primary scenario. Right: one window at
#' all three scenarios, so the reader can see that the flood factor widens the same ground
#' rather than selecting a different return period. Areas are computed here and printed in the
#' legend, so the only copy of those numbers regenerates with the figure.
fp_fig_floodplain <- function(out = fp_fig_path("floodplain.png")) {
  # The scenarios come from the same CSV the README table renders, filtered to the ones actually
  # run. Listing them here would be a second copy of a set the README explicitly invites people
  # to edit (`run` is documented as a one-column change), and the figure would quietly stop
  # matching its own caption. `primary` is the widest-but-one convention this repo already uses
  # for the overview panel.
  sc <- fp_scenarios_run()
  if (nrow(sc) < 2) {
    stop("fig/floodplain.png needs at least two scenarios with run = TRUE; ",
         "config/", FIG_AREA, "/flood_scenarios.csv has ", nrow(sc), call. = FALSE)
  }
  # `scenario_id` is the CSV's own key. Rebuilding it as sprintf("ff%02d", flood_factor) was a
  # second derivation of a column already in the frame, and it diverges for any id that is not
  # exactly <sp>_ff<2-digit factor>.
  scen <- fp_scen_short(sc$scenario_id)                          # narrowest -> widest
  # FIG_PRIMARY has to be a MEMBER of a set that is now derived, and nothing checked it.
  # `ff[[primary]]` is NULL when it is not, and `geom_sf(data = NULL)` inherits the plot's empty
  # data and draws a zero-row layer with no error and no warning: the overview panel loses its
  # floodplain entirely under a subtitle still naming one. Reachable two ways, and the README
  # invites the second — `primary_scenario` moves in `area.yml`, or the `run` column is flipped
  # off, which this page describes as "a `run` column edit, not a code change".
  if (!FIG_PRIMARY %in% sc$scenario_id) {
    stop("FIG_PRIMARY (", FIG_PRIMARY, ") is not among the scenarios with run = TRUE in config/",
         FIG_AREA, "/flood_scenarios.csv (", paste(sc$scenario_id, collapse = ", "),
         ") — the overview panel would draw no floodplain and say nothing about it", call. = FALSE)
  }
  primary <- fp_scen_short(FIG_PRIMARY)
  ff <- lapply(paste0(FIG_SPECIES, "_", scen), fp_fig_read, gpkg = "floodplain.gpkg")
  names(ff) <- scen
  km2 <- vapply(ff, function(x) as.numeric(sum(sf::st_area(x))) / 1e6, numeric(1))
  lab <- sprintf("%s  %s km²", scen, format(round(km2), trim = TRUE))
  pal <- stats::setNames(
    grDevices::colorRampPalette(PAL_FF_ENDS)(length(scen)), lab)

  wsg <- fp_fig_read("subbasins.gpkg", "subbasins")
  net <- fp_fig_read("aquatic_network.gpkg", paste0("streams_", FIG_SPECIES, "3"))
  ins <- sf::st_bbox(FIG_INSET, crs = 3005)
  clip <- function(x) suppressWarnings(sf::st_crop(x, ins))

  overview <- ggplot2::ggplot() +
    ggplot2::geom_sf(data = wsg, fill = "grey97", colour = "grey60", linewidth = 0.3) +
    ggplot2::geom_sf(data = net, colour = "#a9cadb", linewidth = 0.15) +
    ggplot2::geom_sf(data = ff[[primary]], fill = PAL_FF_ENDS[1], colour = NA) +
    ggplot2::geom_sf(data = sf::st_as_sfc(ins), fill = NA, colour = "#c1441e", linewidth = 0.7) +
    fp_fig_scalebar(sf::st_bbox(wsg), 20) +
    ggplot2::coord_sf(expand = FALSE) + ggplot2::theme_void() + fp_fig_theme() +
    ggplot2::labs(title = "Where the model puts the floodplain",
                  subtitle = sprintf("%s group: the %s-accessible network, and its %s floodplain",
                                     FIG_AREA_LABEL, FIG_SPECIES_LABEL, primary))

  # Draw widest first, in ONE layer keyed by a factor whose level order is the draw order.
  # Two traps here, and both fail quietly to a panel that looks like a single scenario:
  # reversing the order paints ff06 over everything, and a `for` loop adding one layer per
  # scenario with `aes(fill = lab[i])` captures `i` lazily, so every layer ends up labelled
  # with the LAST scenario and the legend collapses to one entry.
  ord <- rev(scen)
  zdat <- do.call(rbind, lapply(ord, function(s) {
    g <- clip(ff[[s]])["geom"]
    g$scen <- lab[match(s, scen)]
    g
  }))
  zdat$scen <- factor(zdat$scen, levels = lab[match(ord, scen)])

  zoom <- ggplot2::ggplot() +
    ggplot2::geom_sf(data = zdat, ggplot2::aes(fill = scen), colour = NA) +
    ggplot2::geom_sf(data = clip(net), colour = "#12303f", linewidth = 0.3) +
    ggplot2::scale_fill_manual(values = pal, breaks = lab, name = NULL) +
    fp_fig_scalebar(ins, 5) +
    ggplot2::coord_sf(expand = FALSE) + ggplot2::theme_void() + fp_fig_theme() +
    ggplot2::theme(legend.position = "bottom",
                   panel.border = ggplot2::element_rect(colour = "#c1441e", fill = NA,
                                                        linewidth = 0.9)) +
    ggplot2::labs(title = "What the flood factor changes",
                  subtitle = sprintf("one window, %d scenarios", length(scen)))

  fp_fig_write(out, list(overview, zoom), nrow = 1, width = 1900, height = 1000)
}

#' fig/attribution.png — every change patch, and how much of it we can currently source
#'
#' The bar is the honest half: fire and harvest are the two overlays `config/disturbance.yml`
#' happens to list, not the limit of what it takes. The numbers live in the figure and nowhere
#' else, so they cannot go stale in prose the way #77's counts did.
fp_fig_attribution <- function(out = fp_fig_path("attribution.png")) {
  # The sources come from config/disturbance.yml, which is what the caption claims to describe.
  # Hardcoding fire and harvest would fold a newly enabled source (pest is sitting commented out
  # in that file) into "not yet attributed" while the caption still said the figure showed what
  # the file lists.
  src <- fp_readme_sources()
  lv <- c(src, UNATTRIBUTED)
  span <- paste(FIG_SPAN, collapse = "_")
  tr <- fp_fig_read("floodplain_landcover.gpkg",
                    paste0("transition_", FIG_PRIMARY, "_", span))
  missing <- setdiff(paste0("in_", src), names(tr))
  if (length(missing)) {
    stop("config/disturbance.yml lists sources the transition layer was not tagged with: ",
         paste(missing, collapse = ", "), " — re-run step 3, or the figure would report them ",
         "as unattributed", call. = FALSE)
  }
  tl <- tr[tr$from_class == "Trees", , drop = FALSE]
  if (!nrow(tl)) stop("no `Trees ->` transitions in the figure area", call. = FALSE)
  # First matching source wins for the plot; a patch can carry several tags (salvage after fire),
  # and the bar below sums area, so overlap must not be double-counted.
  cause <- rep(UNATTRIBUTED, nrow(tl))
  for (nm in rev(src)) cause[isTRUE_col(tl[[paste0("in_", nm)]])] <- nm
  tl$cause <- factor(cause, levels = lv)

  wsg <- fp_fig_read("subbasins.gpkg", "subbasins")
  # The SAME scenario the patches came from. A literal `co_ff04` here draws one scenario's
  # floodplain under another's patches the moment FIG_PRIMARY moves, with nothing to notice.
  fp <- fp_fig_read("floodplain.gpkg", FIG_PRIMARY)
  # Centroids, not polygons: at group scale a 1 ha patch is sub-pixel, and a map that drops the
  # small patches would show attribution as commoner than it is (the attributed ones are big).
  pts <- suppressWarnings(sf::st_centroid(tl))
  pts <- pts[order(pts$cause == UNATTRIBUTED), , drop = FALSE]

  map <- ggplot2::ggplot() +
    ggplot2::geom_sf(data = wsg, fill = "grey97", colour = "grey60", linewidth = 0.3) +
    ggplot2::geom_sf(data = fp, fill = "#cfe0ea", colour = NA) +
    ggplot2::geom_sf(data = pts, ggplot2::aes(colour = cause, size = area_ha), alpha = 0.85) +
    ggplot2::scale_colour_manual(values = fp_cause_pal(lv), name = NULL) +
    ggplot2::scale_size_area(max_size = 4.5, name = "patch (ha)", breaks = c(1, 5, 20)) +
    ggplot2::guides(colour = ggplot2::guide_legend(override.aes = list(size = 3))) +
    ggplot2::coord_sf(expand = FALSE) + ggplot2::theme_void() + fp_fig_theme() +
    ggplot2::theme(legend.position = "bottom", legend.box = "vertical") +
    ggplot2::labs(title = sprintf("Floodplain tree loss %s–%s, %s watershed group",
                                  FIG_SPAN[1], FIG_SPAN[2], FIG_AREA_LABEL),
                  subtitle = "every patch the model found, coloured by what it can be attributed to today")

  d <- sf::st_drop_geometry(tl)
  s <- stats::aggregate(area_ha ~ cause, data = d, FUN = sum)
  s <- s[order(match(s$cause, lv)), , drop = FALSE]
  s$pct <- 100 * s$area_ha / sum(s$area_ha)
  s$end <- cumsum(s$area_ha); s$start <- s$end - s$area_ha; s$mid <- (s$start + s$end) / 2

  bar <- ggplot2::ggplot(s) +
    ggplot2::geom_rect(ggplot2::aes(xmin = start, xmax = end, ymin = 0, ymax = 1, fill = cause)) +
    ggplot2::geom_text(ggplot2::aes(x = mid, y = -0.35, colour = cause,
                                    label = sprintf("%s\n%.0f ha  %.0f%%", cause, area_ha, pct)),
                       size = 3.1, lineheight = 1, vjust = 1) +
    ggplot2::scale_fill_manual(values = fp_cause_pal(lv), guide = "none") +
    ggplot2::scale_colour_manual(values = fp_cause_pal(lv), guide = "none") +
    ggplot2::scale_y_continuous(limits = c(-1.6, 1.1)) +
    ggplot2::theme_void() + fp_fig_theme() +
    ggplot2::labs(title = "Share of that loss, by attributed cause",
                  # Derived: fix #5 made the PLOT track config/disturbance.yml and left this
                  # string claiming to describe it, so enabling `pest` would have made the
                  # figure right and the caption false.
                  subtitle = sprintf(
                    "%s %s what config/disturbance.yml lists today — it takes any layer",
                    paste(src, collapse = " and "),
                    if (length(src) == 1) "is" else "are"))

  fp_fig_write(out, list(map, bar), nrow = 2, heights = c(4.3, 1), width = 1500, height = 1500)
}

#' Lay panels out and write the PNG
#'
#' `grid` viewports rather than patchwork/cowplot: neither is a dependency of this repo, and a
#' figure that only builds on the author's machine is the thing the gate exists to avoid.
fp_fig_write <- function(out, plots, nrow = 1, heights = NULL, width, height, res = 190) {
  dir.create(dirname(out), showWarnings = FALSE, recursive = TRUE)
  ncol <- if (nrow == 1) length(plots) else 1
  h <- if (is.null(heights)) rep(1, nrow) else heights
  grDevices::png(out, width = width, height = height, res = res)
  on.exit(grDevices::dev.off(), add = TRUE)
  grid::grid.newpage()
  grid::pushViewport(grid::viewport(
    layout = grid::grid.layout(nrow, ncol, heights = grid::unit(h, "null"))))
  for (i in seq_along(plots)) {
    vp <- if (nrow == 1) grid::viewport(layout.pos.col = i, layout.pos.row = 1)
          else grid::viewport(layout.pos.row = i, layout.pos.col = 1)
    print(plots[[i]], vp = vp)
  }
  invisible(out)
}

#' Both figures, or a clear refusal
fp_fig_build <- function() {
  fp_fig_floodplain()
  fp_fig_attribution()
}

#' A committed figure the render needs, or a stop
#'
#' A missing PNG must stop the render rather than produce a page with holes in it — the same
#' rule the sibling applies to its API cache.
fp_fig_require <- function(name) {
  p <- fp_fig_path(name)
  if (!file.exists(p)) {
    stop(p, " is missing — render once with params$update_figs = TRUE on a machine that has ",
         "run the pipeline for `", FIG_AREA, "`.", call. = FALSE)
  }
  p
}
