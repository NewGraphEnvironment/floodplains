# Code-check round 1 — #140 (branch 140-the-accuracy-module-reads-area-yml-s-sce vs main)

## Checklist read

- code-check-python.md: in full (no Python in the diff).
- code-check-r.md (177 KB): read "`$` on a list partial-matches", "`expect_false(identical(x, y))` cannot fail when the two are different types", "R's `yaml` returns a mixed int/float sequence as a list", "`tryCatch()` nests its handlers"; index lines for the rest. About 120 headings not read in full.
- code-check-spatial.md (155 KB): read the `terra::project()` grid/datum section, which covers `compareGeom()`'s sub-metre tolerance, and grepped for compareGeom/same.crs. All other headings not read in full.
- code-check-shell.md (124 KB): no shell in the diff. No sections read beyond the index.
- code-check.md (330 KB): the prose of all 14 H3s under `## Mechanisms`, table rows skipped. "Rules that stand alone" and "Security": index lines only.

## Clean

No issues found.

What I verified, so the verdict can be checked:

- **Callers of `fp_acc_area()`:** 17 scripts, `channel_probe-migration.R` among them. None reads `species`, `min_order` or `scenario` from area.yml behind the resolver. `channel_probe-migration.R:99` builds `streams_<sp><order>` from `cfg$species`/`cfg$min_order`, so on NECR it now reads `streams_ch3`. That is consistent with its anchor 2, which reads the design's `strata.csv`; the old code read `all_ff04` against a `ch_ff04` strata.csv.
- **No regression for areas without a design:** every `config/*/area.yml` `primary_scenario` has exactly one `flood_scenarios.csv` row, and its species and min_order equal area.yml's (all 24 areas checked). So the new `nrow(row) != 1` refusal does not fire anywhere today, and the area.yml path resolves the same values as before.
- **Partial matching (`$`):**
  - design.json keys today: seed, rng_kind, n_requested, census, r_version, terra_version, dims, extent, crs, area, n_per_stratum, causes, lookback, transition_layer, drift. None is a prefix sibling of `transition_layer`, `dims`, `extent` or `crs`.
  - area.yml keys: no key starts with `design`, so `cfg$design` stays NULL once removed. In the redesign branch, `cfg$design <- NULL` deletes the element.
- **`fp_acc_scenario()` branches:**
  - With no design or a redesign, `identical(x, NULL)` is FALSE, so the interval falls back to area.yml's.
  - With `FORCE=1` and no scenario argument, the design's scenario and interval are kept and its grid is dropped, which is intended.
  - The NOTE compares `as.integer(yml_int)` with the integer interval parsed from design.json.
- **Grid guard:** `fp_acc_design_grid()` reads `dims` as (nrow, ncol), and that matches NECR's design.json: an x range of 89,450 m / 10 m = 8,945 columns, and a y range of 62,880 m = 6,288 rows. The design json is written with `digits = NA`, so the extent round-trips. `compareGeom`'s sub-cell tolerance is a known property, and an accepted one: a sub-cell shift keeps each cell number on the same ground within a fraction of a cell, and the per-stage stratum, cell and map-class checks against the design still apply.
- **`reference_composition-wetland.R`:** `cbind(scenario = <chr>, <data.frame>)` dispatches to `cbind.data.frame`. Under R ≥ 4 the column is character, not a factor. `composition-check.R` is the only consumer of `wetland_composition.csv`, and it handles the legacy file with no scenario column as an INFO line.
- **`composition-check.R` (5):** `!scen %in% w$scenario` parses as `!(scen %in% …)`. The ha sum filters on scenario before zone and year.
- **`accuracy-check.R` new arms:**
  - `list(..., NULL, ...)` keeps the NULL element, so that arm runs. `write_json` serialises the NULL as `{}`, and the parser rejects it.
  - `modifyList(..., list(design = NULL))` removes `design`, so the must-fail arm really runs without a design.
  - In `sc_rast`, `f * 1000 + t` agrees with `fp_acc_grid`'s expectation (2011), so only the grid guard can refuse.

/Users/airvine/Projects/repo/floodplains/planning/active/review-round1.md
