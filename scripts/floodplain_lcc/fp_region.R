#!/usr/bin/env Rscript
#
# fp_region.R  —  batch helpers for running many watershed groups.
#
# fp_wsg_subbasin(conn, wsg, name_basin): the single whole-WSG "sub-basin" is just the
#   FWA watershed-group polygon itself — exact, robust, and needs no break point or
#   frs_watershed_split. (An earlier attempt derived a mainstem-outlet break point and
#   delineated upstream of it; that only works for headwater groups like MORR/UFRA —
#   for a tributary group with a large river passing through, delineating upstream of
#   the mainstem grabs the whole upstream basin, over-shooting the group by 2-40x.)
#   Returns a 1-row sf in the subbasins schema (name_basin + geometry, EPSG:3005).

fp_wsg_subbasin <- function(conn, wsg, name_basin = NULL) {
  name_basin <- if (is.null(name_basin) || !nzchar(name_basin)) wsg else name_basin
  g <- sf::st_read(conn, query = sprintf(
    "SELECT watershed_group_code, geom
     FROM whse_basemapping.fwa_watershed_groups_poly
     WHERE watershed_group_code = '%s'", wsg), quiet = TRUE)
  if (nrow(g) == 0) stop("watershed group not found: ", wsg, call. = FALSE)
  g$name_basin <- name_basin
  g[, c("name_basin", "watershed_group_code")]
}

# --- Whole-network mode (#104) --------------------------------------------------------------------
#
# `species: all` in area.yml is not a fish. It is the reserved token for the whole stream network at
# order >= min_order, with no access filter: one floodplain per group, attributed by blue_line_key,
# habitat joined afterwards rather than cut into the geometry. It sits in the species slot so every
# species-keyed name IN THIS REPO carries it without a schema change (streams_all2, all_ff04,
# network[all2], item key species = "all"; #23, #30). Not the publish layer's: stac_floodplains_bc's
# provenance reader refuses a scenario key that is not `^[a-z]{2}_ff[0-9]{2}$`, so `all_ff04` (like
# an existing `wct_ff04`) cannot publish until that changes (#123).
#
# ONE predicate, defined here, because the token reaches SQL: in species mode 01 interpolates
# `access_<species>` as a column name, and there is no `access_all`. Every caller that branches on
# the mode asks this function rather than comparing the string itself.
FP_SPECIES_WHOLE <- "all"
fp_whole_network <- function(cfg) identical(cfg$species, FP_SPECIES_WHOLE)

# What a whole-network area must also set. Without `attribute_by: blue_line_key` step 2 writes no keyed
# layer, which is the #104 deliverable (habitat joins to it). Without `network_source` step 1 would
# BUILD: drop the area schema and run link's access pipeline, which whole mode does not use and which
# has never been run in this mode. Called by 01 and 02, so either step refuses before it writes.
fp_whole_network_validate <- function(cfg) {
  if (!fp_whole_network(cfg)) return(invisible(cfg))
  if (!identical(cfg$attribute_by, "blue_line_key")) {
    stop("whole-network area '", cfg$name, "' needs attribute_by: blue_line_key (#104), got: ",
         if (is.null(cfg$attribute_by)) "NULL" else format(cfg$attribute_by), call. = FALSE)
  }
  if (is.null(cfg$network_source) || !nzchar(cfg$network_source)) {
    stop("whole-network area '", cfg$name, "' needs network_source (a schema holding the group's ",
         "streams and habitat tables, e.g. fresh); a BUILD is not supported in whole mode", call. = FALSE)
  }
  invisible(cfg)
}

# --- Region mode (#125) ---------------------------------------------------------------------------
#
# A region runs in one of two modes, and the region file says which:
#
#   species  (default)  an ordered `species:` preference, resolved per group by run_region.R's
#                       pre-pass from the access columns (first species modelled at >= min_order).
#   whole               `network: whole`. Every group is the whole network (`species: all`), so there
#                       is no pre-pass to run -- it would query access_all, which does not exist. The
#                       region owns species = all, attribute_by = blue_line_key and min_order (default
#                       2, the #110 floor) for every group it lists.
#
# `all` is refused in a SPECIES region's list: the pre-pass would interpolate it into SQL as a column
# name. And a species region may not reconcile an existing whole-network area, which would turn it
# back into a species item. A WHOLE region converting a species area is the point of the mode, so
# that direction is legal (fp_region_plan).
FP_WHOLE_MIN_ORDER <- 2L   # integer: yaml writes a double 2 as "2.0"

fp_region_refuse_whole <- function(species, where) {
  if (FP_SPECIES_WHOLE %in% species) {
    stop("species '", FP_SPECIES_WHOLE, "' (the whole network, #104) cannot be listed as a species: ",
         where, ". Set `network: whole` in the region file instead (#125).", call. = FALSE)
  }
  invisible(species)
}

# fp_region_mode(reg, where) -> "species" | "whole", refusing a region file that mixes the two.
# Pure: run_region.R calls it before it opens a connection, and the checks call it with no database.
fp_region_mode <- function(reg, where = "region file") {
  net <- reg$network
  if (!is.null(net) && !(is.character(net) && length(net) == 1L && identical(net, "whole"))) {
    stop(where, ": `network:` must be `whole` or absent, got: ", format(net), call. = FALSE)
  }
  if (is.null(net)) {
    if (!length(reg$species)) stop(where, ": a species region needs a `species:` list", call. = FALSE)
    fp_region_refuse_whole(reg$species, where)
    return("species")
  }
  # A species list beside `network: whole` is a contradiction, not a fallback: refuse it rather than
  # guess which of the two the author meant.
  if (!is.null(reg$species)) {
    stop(where, ": `network: whole` takes no `species:` (every group is species `all`)", call. = FALSE)
  }
  if (!is.null(reg$attribute_by) && !identical(reg$attribute_by, "blue_line_key")) {
    stop(where, ": a whole-network region is attributed by blue_line_key (#104), got: ",
         format(reg$attribute_by), call. = FALSE)
  }
  if (is.null(reg$network_source) || !nzchar(reg$network_source)) {
    stop(where, ": a whole-network region needs `network_source` (a BUILD is not supported in ",
         "whole mode)", call. = FALSE)
  }
  "whole"
}

# The region's min_order: what the file states, else the mode's default.
fp_region_min_order <- function(reg) {
  if (!is.null(reg$min_order)) return(reg$min_order)
  if (identical(fp_region_mode(reg), "whole")) FP_WHOLE_MIN_ORDER else 3L
}

# fp_region_owned(reg, wsg, sp) -> the region-owned key list for one group, the only place it is
# built. `sp` is the pre-pass's resolved species in species mode and is ignored in whole mode.
fp_region_owned <- function(reg, wsg, sp = NULL) {
  whole <- identical(fp_region_mode(reg), "whole")
  if (whole) sp <- FP_SPECIES_WHOLE
  owned <- list(name = tolower(wsg), watershed_group = wsg, species = sp,
                min_order = fp_region_min_order(reg), schema = tolower(wsg),
                primary_scenario = paste0(sp, "_ff04"))
  # network_source / network_guard: the REGION file is the source of truth for how the network is
  # obtained -- GRAB from an already-built schema vs BUILD the link pipeline per WSG. The env
  # overrides (FP_NETWORK_SOURCE/_GUARD) work for one run but leave the choice unreproducible, so it
  # is carried through from the region. attribute_by (#40) is region-wide for the same reason.
  for (k in c("network_source", "network_guard", "attribute_by")) {
    if (!is.null(reg[[k]])) owned[[k]] <- reg[[k]]
  }
  if (whole) owned$attribute_by <- "blue_line_key"
  owned
}

# fp_region_cache_stale(prov, scenario) -> TRUE when a cached group's floodplain predates flooded
# 0.7.0's pinned grid (#117), or carries no flooded version at all. run_region.R's cache is keyed on
# file presence, so without this DUNC's 2026-10-12 run on 0.6.5's grid would read as complete. Pure:
# `prov` is the parsed provenance.json (a list), so the check needs no data/.
FP_FLOODED_GRID_PIN <- "0.7.0"
fp_region_cache_stale <- function(prov, scenario) {
  v <- prov[["floodplain"]][[scenario]][["inputs"]][["flooded"]][["version"]]
  if (is.null(v) || !is.character(v) || length(v) != 1L || is.na(v) || !nzchar(v)) return(TRUE)
  pv <- tryCatch(package_version(v), error = function(e) NULL)
  is.null(pv) || pv < package_version(FP_FLOODED_GRID_PIN)
}

# --- Region-owned area config (#44) ---------------------------------------------------------------
#
# run_region.R used to REGENERATE config/<wsg>/area.yml and flood_scenarios.csv wholesale on every
# invocation, and delete break_points.csv. That silently destroyed hand-maintained config: the second
# species' scenario rows (undoing #23), every citation, and the break points. It did so under DRY=1
# too, so the safe-looking preview was as destructive as a real run.
#
# The tension underneath: the region file is the source of truth for SOME fields, the area config for
# others. Regeneration treated it as the source of truth for everything. FP_REGION_OWNED draws that
# line explicitly, in one place, so the runner and its check script cannot drift apart.
#
# Stale region-owned keys are CLEARED, not merely overwritten. A plain merge (modifyList) would leave
# `network_source: fresh_default` sitting in area.yml after someone deliberately removed it from the
# region file — a group would keep GRABbing when it was meant to BUILD. That would be a new silent
# divergence introduced by the fix for a silent loss, so: strip the owned set, then apply.
FP_REGION_OWNED <- c("name", "watershed_group", "species", "min_order", "schema",
                     "primary_scenario", "network_source", "network_guard", "attribute_by")

# fp_region_plan(cfg_dir, region_owned, base) -> a plan describing what WOULD change.
#
# Pure: reads the config dir, touches nothing, needs no database. That is what lets DRY=1 report
# instead of act, and what lets region_config-check.R assert #44's acceptance criteria without a
# Postgres connection (run_region.R itself opens one for its species pre-pass, which is part of why
# this code was never testable).
#
#   cfg_dir       config/<area>
#   region_owned  named list of the region file's values, keys drawn from FP_REGION_OWNED
#   base          base_scenarios(sp) — used ONLY when the csv is absent or lacks this species
fp_region_plan <- function(cfg_dir, region_owned, base) {
  stopifnot(is.list(region_owned), is.data.frame(base))
  unknown <- setdiff(names(region_owned), FP_REGION_OWNED)
  if (length(unknown)) {
    stop("region_owned carries key(s) outside FP_REGION_OWNED: ", paste(unknown, collapse = ", "),
         ". Add them there, or a region file that later drops one will leave it stale in area.yml.",
         call. = FALSE)
  }

  area_path <- file.path(cfg_dir, "area.yml")
  csv_path  <- file.path(cfg_dir, "flood_scenarios.csv")
  bp_path   <- file.path(cfg_dir, "break_points.csv")

  # --- area.yml: strip the region-owned set, then apply the region's current values ---
  existing <- if (file.exists(area_path)) yaml::read_yaml(area_path) else NULL
  # A whole region (species = all) may convert a species area; a species region may not reconcile a
  # whole-network area back into a species item (#125).
  whole_region <- identical(region_owned$species, FP_SPECIES_WHOLE)
  if (!whole_region) {
    fp_region_refuse_whole(region_owned$species, "the region resolves a species to it")
    if (!is.null(existing)) {
      fp_region_refuse_whole(existing$species, paste0(area_path, " is a whole-network area and ",
                                                      "the region is not `network: whole`"))
    }
  }
  kept     <- if (is.null(existing)) list() else existing[setdiff(names(existing), FP_REGION_OWNED)]
  area     <- c(region_owned, kept)   # deterministic order: region keys first, then area-owned
  # Refuse what step 1 would refuse, here, so DRY=1 reports it rather than a run dying in step 1.
  fp_whole_network_validate(area)
  # `targets` is area-owned (the publish layer's per-item list), so a region never rewrites it. In
  # whole mode a target naming a species scenario points at an item being retired (stac#76) and would
  # keep publishing it: refuse, and say what to do.
  if (whole_region && length(area$targets)) {
    tsc <- vapply(area$targets, function(t)
      if (is.null(t$scenario)) NA_character_ else as.character(t$scenario)[1], character(1))
    bad <- tsc[is.na(tsc) | !startsWith(tsc, paste0(FP_SPECIES_WHOLE, "_"))]
    if (length(bad)) {
      stop(area_path, ": `targets:` names species scenario(s) ", paste(bad, collapse = ", "),
           ", which a whole-network region retires (stac_floodplains_bc#76). Remove the block, or ",
           "list only all_* scenarios.", call. = FALSE)
    }
  }

  # all.equal, not identical: yaml reads `min_order: 3` back as integer while the runner's default is
  # numeric, and identical(3L, 3) is FALSE. Comparing with identical would report a spurious change
  # every run and rewrite the file for nothing.
  same <- function(a, b) isTRUE(all.equal(a, b))
  set_keys <- character(0); rm_keys <- character(0)
  if (is.null(existing)) {
    area_mode <- "create"; area_action <- paste0("create (", length(area), " keys)")
  } else {
    # Only the region-owned keys can change; area-owned ones are carried through untouched. Splitting
    # them into set/remove is what lets the writer edit those lines IN PLACE rather than re-emitting
    # the file (see fp_area_yml_edit -- yaml::write_yaml would discard every comment).
    set_keys <- FP_REGION_OWNED[vapply(FP_REGION_OWNED, function(k)
      !is.null(area[[k]]) && !same(area[[k]], existing[[k]]), logical(1))]
    rm_keys  <- FP_REGION_OWNED[vapply(FP_REGION_OWNED, function(k)
      is.null(area[[k]]) && !is.null(existing[[k]]), logical(1))]
    if (length(set_keys) == 0 && length(rm_keys) == 0) {
      area_mode <- "none"; area_action <- "unchanged"
    } else {
      area_mode <- "update"
      # paste0("-", character(0)) is "-", NOT character(0) -- a zero-length argument is treated as
      # "" rather than short-circuiting, so an unguarded paste prints a phantom removed key.
      removed <- if (length(rm_keys)) paste0("-", rm_keys) else character(0)
      area_action <- paste0("update: ", paste(c(set_keys, removed), collapse = ", "))
    }
  }

  # --- flood_scenarios.csv: create when absent, append when this species has no rows, never rewrite ---
  # Appending is additive and matches #23's coexistence model, so a region that changes species adds
  # rows rather than replacing a curated file. Existing rows — parameters, citations, another
  # species — are never touched.
  sp  <- region_owned$species
  cur <- if (file.exists(csv_path)) readr::read_csv(csv_path, show_col_types = FALSE) else NULL
  if (is.null(cur)) {
    scen <- base; scen_mode <- "create"
    scen_action <- paste0("create (", nrow(base), " rows, ", sp, ")")
  } else if (sp %in% cur$species) {
    scen <- NULL; scen_mode <- "none"
    scen_action <- paste0("unchanged (", nrow(cur), " rows, ",
                          paste(sort(unique(cur$species)), collapse = "+"), ")")
  } else {
    # Align to the header on disk before appending — readr::write_csv(append = TRUE) writes no
    # header, so a column-order difference would silently shift every value into the wrong column.
    extra <- setdiff(names(base), names(cur))
    if (length(extra)) {
      stop("cannot append ", sp, " rows to ", csv_path, ": it lacks column(s) ",
           paste(extra, collapse = ", "), ". Reconcile the schema by hand rather than losing data.",
           call. = FALSE)
    }
    for (m in setdiff(names(cur), names(base))) base[[m]] <- NA
    scen <- base[, names(cur), drop = FALSE]; scen_mode <- "append"
    scen_action <- paste0("append ", nrow(scen), " ", sp, " rows (", nrow(cur), " -> ",
                          nrow(cur) + nrow(scen), ")")
  }

  # --- break_points.csv: never touched. Its presence decides which sub-basin branch step 2 takes
  # (02_floodplain_model.R:54-58), so deleting it was a model change, not just a lost file.
  bp_action <- if (file.exists(bp_path)) {
    paste0("present, kept (", nrow(readr::read_csv(bp_path, show_col_types = FALSE)),
           " point(s) => interior sub-basins)")
  } else {
    "absent (whole-WSG group polygon)"
  }

  list(dir = cfg_dir, area = area, area_mode = area_mode, area_action = area_action,
       area_set = set_keys, area_remove = rm_keys,
       scenarios = scen, scenarios_mode = scen_mode, scenarios_action = scen_action,
       break_points_action = bp_action,
       changed = area_mode != "none" || scen_mode != "none")
}

# fp_region_write(plan): apply a plan from fp_region_plan(). The ONLY writer.
# Skips files the plan marked unchanged, so a no-op region run leaves `git status` clean rather than
# rewriting identical content and churning mtimes.
fp_region_write <- function(plan) {
  fs::dir_create(plan$dir)
  area_path <- file.path(plan$dir, "area.yml")
  if (plan$area_mode == "create") {
    yaml::write_yaml(plan$area, area_path)          # nothing on disk to preserve
  } else if (plan$area_mode == "update") {
    fp_area_yml_edit(area_path, plan$area[plan$area_set], plan$area_remove)
  }
  csv_path <- file.path(plan$dir, "flood_scenarios.csv")
  if (plan$scenarios_mode == "create") {
    readr::write_csv(plan$scenarios, csv_path)
  } else if (plan$scenarios_mode == "append") {
    readr::write_csv(plan$scenarios, csv_path, append = TRUE)
  }
  invisible(plan)
}

# fp_area_yml_edit(path, set, remove): change only the named top-level keys, in place.
#
# `yaml::write_yaml` round-trips the DATA and discards everything else — every comment in the file.
# On config/bulk/area.yml that is 8 lines of rationale ("never shared fresh.*, never neexdzii"); on
# config/morr/area.yml it is the publish-targets explanation and an open question. Losing those to a
# region run is the same class of silent damage as #44 itself, so the writer edits the lines it owns
# and leaves every other byte — comments, key order, `null` vs `~`, blank lines — exactly as found.
#
# Scope is deliberately narrow: top-level scalar keys only, which is all FP_REGION_OWNED contains.
# A key whose value is a nested block is refused rather than mangled.
fp_area_yml_edit <- function(path, set, remove) {
  lines <- readLines(path, warn = FALSE)
  find_key <- function(k) grep(paste0("^", k, ":"), lines)   # top-level: no leading whitespace

  render <- function(k, v) trimws(yaml::as.yaml(stats::setNames(list(v), k)))

  # Update in place, keeping any trailing comment on the line.
  for (k in names(set)) {
    i <- find_key(k)
    if (length(i) > 1) stop("duplicate top-level key '", k, "' in ", path, call. = FALSE)
    if (length(i) == 1) {
      if (grepl(paste0("^", k, ":\\s*(#.*)?$"), lines[i])) {
        stop("key '", k, "' in ", path, " has a nested value; refusing to rewrite it blind.",
             call. = FALSE)
      }
      trailing <- regmatches(lines[i], regexpr("\\s+#.*$", lines[i]))
      lines[i] <- paste0(render(k, set[[k]]), if (length(trailing)) trailing else "")
    } else {
      lines <- append(lines, render(k, set[[k]]), after = max(find_key_last(lines), 0L))
    }
  }
  # Drop removed keys in one pass so indices cannot shift underneath the loop.
  if (length(remove)) {
    drop <- unlist(lapply(remove, find_key))
    if (length(drop)) lines <- lines[-drop]
  }
  writeLines(lines, path)
  invisible(path)
}

# Where a newly-added key goes: after the last top-level key AND past any block it owns, so a new
# scalar never lands inside a `targets:` list. Falls back to end-of-file when there are no keys yet.
find_key_last <- function(lines) {
  i <- grep("^[A-Za-z_][A-Za-z0-9_]*:", lines)
  if (!length(i)) return(length(lines))
  j <- max(i)
  # advance past continuation lines: indented values, or list items belonging to that key
  while (j < length(lines) && grepl("^(\\s+\\S|- )", lines[j + 1])) j <- j + 1
  j
}
