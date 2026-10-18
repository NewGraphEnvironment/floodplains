# Task: Whole-network floodplains for every region: region mode for species: all, species items retired (#125)

Close-out of #125. The code shipped in PR #132 (v0.1.13) and Skeena was accepted 2026-10-14.
Fraser, Peace and Columbia ran 2026-10-14/15; this branch runs their per-region acceptance,
records it as Skeena's was, and closes #125 (decided at the plan gate: close on merge, with the
QGIS visual review filed as its own issue).

## Context

The #125 code merged in PR #132 (v0.1.13). Skeena ran and was accepted on 2026-10-14. Fraser
(13 groups), Peace (3) and Columbia (4, DUNC re-run on the pinned grid) ran 2026-10-14/15, all
`ok` with 0 errors in every group log, and their configs are committed (760b8d9, 2dda619). The
issue's **per-region acceptance has not been run on any of the 20**, and CLAUDE.md says so in two
places. This branch runs it, records it the way Skeena was recorded, and closes #125 (user
decision: close on merge, with the QGIS visual review as its own issue). The runs themselves are
not repeated.

What I found that shaped this:
- Installed flooded is **0.7.0**. `habitat_join-query.R` stops unless flooded > 0.7.2
  (`fp_habitat_join.R:56`); flooded 0.8.2 is the latest release. 0.7.1 can move DEM edge cells only
  where sf's PROJ takes a datum step (ours does not), so it matters for later runs, not these.
  So the checks that read the toolchain run **before** the install, the habitat join after it.
- DUNC's habitat-join log (`20261015_habitat_join-query_dunc.md`, produced 2026-10-14 18:31 PDT)
  predates DUNC's re-run (10-15 11:42 PDT), so it describes outputs that no longer exist. It is
  re-run with the others.
- **Peak RSS was not sampled** for these three runs; the logs say "not sampled", never a guess.
  Wall times come from the group log mtimes and the run stamp in each log's name (Skeena's method).
- Skeena's results table was derived by hand with no producer named. Doing that 20 times invites
  transcription errors, so one committed report script derives every number. It is checked by
  reproducing Skeena's committed figures.
- Every group has `subbasins.gpkg` (the group polygon), so the outside-polygon share is offline.

## Phase 1: Checks that read the current toolchain (flooded 0.7.0)

- [x] Add `scripts/floodplain_lcc/region_checks-run.sh <region>`. For each group in
      `config/regions/<region>.yml` it runs `provenance-check.R <wsg>`, `composition-check.R <wsg>
      all_ff04`, `bridge-check.R <wsg> all_ff04` and `disturbance-check.R <wsg>`, plus
      `dem_cache-check.R` once. Each output goes to `data/logs/region_checks_<region>_<wsg>_<check>_<stamp>.log`
      (gitignored). It prints a PASS/FAIL table from each check's exit status, and the `all_ff04`
      section's verdict separately for `disturbance-check.R`, whose species-layer FAILs are expected
      (Skeena log). One process loop, one invocation per region.
- [x] Run it for fraser, peace and columbia, then skeena again as a control: it should reproduce the
      Skeena table.
- [x] Every FAIL other than the known two (composition's 1% bound from #53, disturbance on the
      species layers) is diagnosed to `file:line` before going further. A real defect gets an issue
      or a fix on this branch, depending on size.

## Phase 2: Results report, derived by one script

- [x] Add `scripts/floodplain_lcc/region_acceptance-report.R <region>`. No database. It reads each
      group's `provenance.json`, `floodplain_all_ff0N.tif`, `floodplain.gpkg`
      (`all_ff04_by_blue_line_key`), the transition and composition layers, `subbasins.gpkg` and the
      group log, through the existing helpers: `fp_composition_summary()` (`fp_composition.R`),
      `fp_disturbance_report()` (`fp_disturbance.R`) and `fp_rast_cells()` (`scripts/fp_raster.R`).
      Per group it prints Skeena's columns: network km, freshness, `habitat_link` rows and species,
      `all_ff02/04/06` km², blue lines with floodplain, patches ≥ 1 ha, gross tree loss, fire /
      harvest / unattributed share, bridge union coverage, wall time. It adds four columns:
      - change cells inside vs outside the group polygon, against the patch total (the #53 read);
      - floodplain share outside the polygon;
      - km² of floodplain per km of network;
      - classified coverage over floodplain area, which is the "classified ≈ floodplain" criterion.
- [x] Verify it against Skeena: every figure in `20261014_whole_network_skeena.md` reproduces. A
      mismatch is resolved before any new region's numbers are trusted.
- [x] **Outlier rule, written down before any of the new numbers are read:** over all 23 groups, flag
      any whose km²/km or outside-polygon share lies beyond 1.5 × IQR of the 23. The flagged groups
      join BULK in the visual-review issue.

## Phase 3: Habitat join (the #104 deliverable as a consumer uses it)

- [x] Install released flooded (0.8.2) via `scripts/packages.R`. (It was already installed, from
      2026-10-17 11:00 UTC, before the Phase 1 checks ran; see findings.) Confirm `fl_valley_join` exists
      and `packageVersion("flooded") > "0.7.2"`, then re-run `dem_cache-check.R` (offline), which
      asserts `FP_DEM_SOURCE` still equals flooded's default.
- [x] Run `habitat_join-query.R <wsg>` for the 13 Fraser, 3 Peace and 4 Columbia groups (DUNC
      included, see above), sequentially, `> log 2>&1`, checking each for an in-band error. Each run
      writes its own committed `logs/2026101x_habitat_join-query_<wsg>.md`.
- [x] Record per group: integrity (missing/extra = 0) and `habitat_rows_unmatched`. Any non-zero
      value is a finding, not a footnote.

## Phase 4: Records

- [x] `scripts/floodplain_lcc/logs/2026101x_whole_network_{fraser,peace,columbia}.md`, in the Skeena
      log's shape: how it ran, wall time (RSS not sampled), results (pasted from the report script,
      which is named as their producer), checks table, the #53 inside/outside table, and the
      habitat-join match rates.
- [x] CLAUDE.md: replace "#125's per-region acceptance checks have not been run on it yet" (Fraser,
      Peace and Columbia paragraphs) with the outcome and log pointers. Fix any other sentence that
      the results contradict, found by grepping for it.
- [x] File the visual-review issue: BULK `all_ff04` order-2 headwaters over imagery, plus the
      flagged groups and the numbers that flagged them.
- [x] Edit #125's body: Status shows all four regions run and accepted, with "Left" reduced to the
      publish work in stac#75/#76 and the new review issue.
- [x] Close #58 (MCGR, PINE), #59 (its 13 areas), #73 (its 18 areas) and #76 (MCGR, PINE in whole
      mode), each with a pointer to #125 and the region log covering its groups. Before each,
      confirm every area it lists has an `all_ff04` that passed Phase 1. For #59, note that the
      retraction is stac#76's, and that the catalogue serves the old items until that release.
      Done as: every listed area verified against the 23 accepted groups (findings); they close
      through the PR's Closes line, so they close when the evidence reaches main, each with a
      pointer comment once the PR exists. stac_floodplains_bc#76 had closed 2026-10-15.

## Validation

- [x] Tests pass: `region_config-check.R`, `whole_network-check.R`, and the offline sections of the checks above
- [x] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [x] PWF checkboxes match landed work
- [x] `/planning-archive` on completion

## Verification

- The Skeena control: `region_checks-run.sh skeena` and `region_acceptance-report.R skeena`
  reproduce the committed Skeena log. This is the independent reference for both new scripts.
- Mutation check on the check runner: point one group at a deliberately broken check, or one that
  exits 1, and confirm the table reports FAIL rather than PASS.
- Each region log's numbers trace to a report-script invocation named in the log. Each closed
  issue's area list is checked against the coverage CSVs in `data/logs/region_*_20261015_*.csv`.
