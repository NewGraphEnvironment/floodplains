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
  kept     <- if (is.null(existing)) list() else existing[setdiff(names(existing), FP_REGION_OWNED)]
  area     <- c(region_owned, kept)   # deterministic order: region keys first, then area-owned

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
      area_action <- paste0("update: ", paste(c(set_keys, paste0("-", rm_keys)), collapse = ", "))
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
