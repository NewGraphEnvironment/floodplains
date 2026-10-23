# Code-check round 3 (#140)

Diff: `git diff 66b6263...HEAD -- scripts CLAUDE.md` (diff3.patch).

## Checklist read

- code-check-python.md (7 KB): in full. Not applicable; the diff has no Python.
- code-check.md (330 KB): the prose of all 14 H3s under `## Mechanisms` (table rows skipped). 23 other headings not read (Rules that stand alone, Security, Spreadsheets and PDFs). None of their index lines names a tool or shape this diff uses.
- code-check-r.md (177 KB): 6 headings read: "`$` on a list partial-matches", "`tryCatch()` nests its handlers", "`tryCatch(warning = )` DISCARDS", "`[[` on a named ATOMIC vector", "R's `yaml` returns a mixed int/float sequence", "`paste()` with a zero-length argument". 105 not read.
- code-check-spatial.md (156 KB): 1 heading read ("`terra::rast()` on a SpatRaster returns an empty template"). 92 not read. The diff's only terra use is `rast(nrows=…)` construction and `compareGeom`, and no other index line names either.
- code-check-shell.md (124 KB): 0 headings read (no shell in the diff). 67 not read.

## Mechanism

**The scenario is an implicit key.** Every accuracy artefact reaches its population by name: `rasters/<scen>/`, `floodplain.gpkg` layer `<scen>`, `transition_<scen>_<from>_<to>`, `streams_<sp><order>`. Every derived file the module writes carries that population only implicitly, as "whatever scenario the stage resolved when it ran". Before #140, design.json and area.yml agreed only by accident, and #125 broke that. The diff moves resolution to design.json and binds one artefact (transition.tif, and through it the classified series) to the design by geometry. It also stamps one derived file (`wetland_composition.csv`) with its scenario. Anywhere else a file's scenario is still implicit, two records agree only because nothing has rewritten either one since.

Where it reaches, and whether each place is covered:

| reach | covered? |
|---|---|
| `rasters/<scen>/transition.tif` + `classified_*.tif` (sample_draw, reference_omission, reference_composition-wetland, channel_probe via `fp_acc_grid`) | Yes. Geometry is checked against the design grid by `compareGeom`, and content by each stage's design check on point map class. Offline arms pass (ran the new section in a temp copy, 21/21 PASS). |
| `floodplain.gpkg` layer `<scen>` (sample_draw, reference_omission, reference_composition-wetland, window_count-clear, wayback_coverage-area) | By name only. A ch_ff04 step-2-only re-run would move the vector under unchanged rasters, and the grid guard would not see it. This predates the diff, and nothing re-runs a retired species today. Not a finding. |
| `transition_<scen>_<interval>` gpkg layer (sample_draw cause rasters, review_build-qgis patches) | By name. The name now derives from design.json's own `transition_layer`, so it cannot disagree with the design. Verified on disk: `necr_lulc_review_b/patches.gpkg` (rebuilt 11:37, after 26dedb3) holds 5,692 rows with the ch_ff04 schema. all_ff04 has 11,469 rows and carries `in_wsg`. |
| `aquatic_network.gpkg` `streams_<sp><order>` (channel_probe) | Yes. The species and order come from the scenario row (`streams_ch3`), and that layer exists in `data/necr/aquatic_network.gpkg`. |
| `flood_scenarios.csv` row | Loud failure if the row is absent or duplicated. All 24 areas have exactly one row for their area.yml primary, and every scenario id in every csv matches the parser's `[a-z]+_ff[0-9]+`. |
| `wetland_composition.csv` -> composition-check (5) | Yes. It is stamped and compared same-scenario only. On disk it holds 107 rows, all `ch_ff04`. Residual: (5) takes the year from area.yml's `change_interval`, not from the reference. If the two intervals ever diverged, (5) would FAIL loudly rather than pass. Not a finding. Note that (5) now runs only when called with `necr ch_ff04`; `region_checks-run.sh` passes `all_ff04`, so it reports INFO there. |
| `omission_disturbance.csv` -> `accuracy_estimate.R` criterion 4 | **No.** See the finding. |
| `reference/necr/windows.csv` (window_count-clear over the floodplain layer) | Implicit, but it was committed 2026-09-30, before #125, when area.yml was ch_ff04, so it was counted on the design's scenario. Only `derive` regenerates it. Not a finding. |

## Findings

- **[severity: fragile]** scripts/landcover_accuracy/accuracy_estimate.R:107-110 (consumer) and reference_omission-disturbance.R:62-64 (writer). `omission_disturbance.csv` records no scenario, and `accuracy_estimate.R` reads its harvest `omission_io` straight into pre-registered criterion 4 (`fp_acc_estimate(..., omission_harvest_io = omission)`). Nothing checks that the file was computed on the design's scenario or grid. This is the same implicit-scenario derived file this diff stamped for `wetland_composition.csv`, but the sibling feeding a verdict was left unstamped. It goes wrong silently in two cases:
  - a `FORCE=1` redraw onto a new scenario is followed by `accuracy_estimate.R` before `reference_omission-disturbance.R` is re-run;
  - a copy of the csv from the #125 -> #140 window (on any machine) is still present.

  Either way, criterion 4 is evaluated on another floodplain's footprint with no message. The file on disk now (2026-10-23 11:45, after 26dedb3) was regenerated on ch_ff04, so no current number is wrong.

  Fix:
  - prepend `scenario = cfg$primary_scenario` in reference_omission, as reference_composition-wetland now does;
  - in accuracy_estimate, refuse a file whose scenario is absent or differs from `cfg$primary_scenario`, or treat it as NA, rather than reading it.

No other defects found.
