# Code-check round 2 — #140 (diff 66b6263...HEAD -- scripts CLAUDE.md)

## Checklist read

- code-check-python.md: in full (nothing applies; the diff has no Python).
- code-check-r.md (177 KB, 111 H3s): read in full the sections for the tools and shapes this diff
  uses: `$` on a list partial-matches; `[[` on a named ATOMIC vector; `nzchar(NA)`; `paste()` with
  a zero-length argument; `identical()` on two reader results; CSV whitespace; `tryCatch(warning =)`
  discards the value; `tryCatch()` nests its handlers; `match()` treats NA as a value; `c()`
  dispatches on its first argument; `data.frame()` recycles a scalar; `ifelse()` with an all-NA
  test; `tempfile()` lives in the session tempdir; R's `yaml` mixed int/float; Rscript reads a
  script as it runs; `Rscript -e` supplies `--args`; `read.delim()` quotes by default. 17 read,
  94 not read.
- code-check-spatial.md (155 KB): read terra `align()` snap, "A shift measured on one grid",
  `terra::rast()` on a SpatRaster, and the `compareGeom()` tolerance paragraph (line 1886).
  4 read, the rest not.
- code-check-shell.md (124 KB): 0 headings read; the diff contains no shell.
- code-check.md (330 KB): the prose of every H3 under `## Mechanisms` (all 14), table rows
  skipped. Rules that stand alone: headings only.

## What I checked, beyond round 1

- **sample_draw-pilot.R redraw path, end to end.** Without FORCE, the design's scenario,
  interval and grid are used, and a scenario arg other than the design's is refused. With
  FORCE=1, `redesign` drops `cfg$design` (no grid guard), the scenario is the argument or else
  the design's, and the interval is the design's only when the scenario is unchanged. The draw
  writes `transition_layer = transition_<new scen>_<interval>`, `pts$species`/`pts$scenario`
  from the scenario row, and design.json last. The label/labels_b/review_key loop is skipped
  under FORCE=1, the same as before the diff. Without FORCE it still compares the labels with
  the new points through `fp_acc_design_check`.
- **The grid guard against real data** (temp copy, `data/necr` read through a symlink, nothing
  written): `fp_acc_area("necr")` resolves ch_ff04, 2017–2023, ch, order 3, `scenario_source =
  design`, and prints the NOTE. `compareGeom(transition.tif, fp_acc_design_grid(design))` is
  TRUE for `rasters/ch_ff04` (6288 x 8945) and FALSE for `rasters/all_ff04` (6832 x 9423). The
  WKT round trip through design.json compares equal.
- **accuracy-check.R offline** in a temp copy: 239 PASS, `ALL PASS`, rc 0.
- **After a #131 prune of the design's outputs:** each stage that reads them fails loudly. A
  missing tif fails in `terra::rast` (`fp_acc_grid`), and a missing layer fails in `st_read`
  (sample_draw, reference_*, wayback_coverage, window_count, review_build-qgis). No stage
  tests for existence and then silently skips. Stages that read only reference/ files
  (accuracy_estimate, labels_export, review_render-sheets, labels_import-model) do not touch
  the rasters.
- **composition-check (5):** the csv is written whole, with one scenario, by one writer, so
  `w$scenario == scen` is exact. A csv with several scenarios filters correctly. On the interval:
  no `config/*/area.yml` sets `change_interval` (top-level keys across all 24: `attribute_by`,
  `lulc_annual`, `min_order`, `name`, `network_source`, `primary_scenario`, `schema`, `species`,
  `subset`, `watershed_group`), so both sides are 2017–2023. A different interval reaching (5)
  would first need `composition_<scen>_<int>` to exist. Failing that, the "layer exists" arm
  FAILs before (5). Even then the reference holds every year of its interval.
- **Other readers of wetland_composition.csv:** none in scripts/, README.Rmd or research/. The
  only hits are composition-check.R and planning/log prose.
- **`$` partial matching on the new reads:** design.json's keys (`area causes census crs dims
  drift extent lookback n_per_stratum n_requested name r_version rng_kind seed terra_version
  transition_layer years`) and area.yml's keys have no prefix sibling of `design`,
  `transition_layer`, `scenario` or `change_interval`.
- **A caller outside the module:** `scripts/floodplain_lcc/channel_probe-migration.R` calls
  `fp_acc_area()` (round 1 did not list it). For NECR it now reads ch_ff04 with
  `streams_ch3`. That is the change it needs: its anchor 2 compares the unsieved change with
  `reference/necr/strata.csv`, which is on ch_ff04, and would stop on all_ff04. BULK has no
  design, so it is unchanged (`all_ff04`, `streams_all2`). Not a defect. Its header still says
  "one area's primary scenario".

## Findings

- **[severity: fragile]** scripts/landcover_accuracy/fp_accuracy.R:72-75. `fp_acc_scenario()`
  now requires the design scenario's row in `config/<area>/flood_scenarios.csv` in **every**
  accuracy stage, including those that never use species or min_order (accuracy_estimate.R,
  labels_export.R, review_render-sheets.R, labels_import-model.R). It is also required in
  channel_probe-migration.R. #131's body puts "decide whether the species rows in
  flood_scenarios.csv go" in scope, and its refusal names only the design's *outputs*
  (`fp_acc_design_scenario()`). It does not name that scenario's csv row. If #131 drops NECR's
  `ch_*` rows, every accuracy stage aborts with "scenario `ch_ff04` has 0 rows". That is loud,
  not silent. The remedy belongs in #131's body, not in this diff: the prune must keep the
  `flood_scenarios.csv` row of the scenario the design names.

Otherwise clean. Round 1's "Clean" holds on the paths it did not cover.

Side note, not a finding: `data/necr/accuracy/omission_disturbance.csv` has an mtime of
2026-10-23 11:45:14 PDT, which falls during this review. This review did not write it. My
only reads of `data/necr` were through a symlink in a temp copy, and none of those calls
writes. The symlink was removed before accuracy-check.R ran. Another process, probably the
parent session, wrote it.
