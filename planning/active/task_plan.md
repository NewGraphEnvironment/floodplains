# Task: Probe: cost and difference of a whole-FWA floodplain on MORR (gates #104) (#110)

## Question

What does it cost to delineate a watershed group's **whole** FWA floodplain, and how does the result differ from today's species-cut floodplain? Today's step 2 takes 2–92 min per group (median ~14, three scenarios, read from provenance timestamps). The whole-network cost has never been measured.

**What we know going in** (measured 2026-10-03, `fresh.streams_vw_bcfp`):
- First-order lines are 56–63% of stream length.
- MORR has 6,753 blue lines in all, against 340 in today's coho network.
- #40 measured attribution at 0.39 s per extra watercourse on MORR (16.5M cells). Extrapolated, that is about 40 min per scenario for MORR's whole network by blk. **That number has not been measured.**

## Phase 1: Probe helpers + offline check
- [x] `scripts/floodplain_lcc/fp_whole_fwa.R`: arm definitions (one `WHERE` per arm: `order>=1`,
      `>=2`, `>=3`, `>=3 OR (order=1 AND stream_order_parent>=5)`, coho `access_co IN (1,2) AND
      order>=3`); the network SQL builder (01's SELECT verbatim, comment naming it as a deliberate
      copy guarded by anchor 1); waterbody read by the same `waterbody_key` rule as 01; pure
      overlap metrics on two aligned 0/1 rasters (intersect, lost, gained, ha).
- [x] `scripts/floodplain_lcc/floodplain_probe-check.R`: offline asserts with must-fail arms —
      arm predicates nest (1 ⊇ 2 ⊇ 3 ⊇ 5, 4 ⊇ 3), species/arm codes refused outside the
      whitelist (SQL-interpolated), overlap metrics on hand-built rasters incl. misaligned grids
      refused.

## Phase 2: Probe runner with anchors
- [x] `scripts/floodplain_lcc/floodplain_probe-whole-fwa.R <area> <arm>`: reads the scenario row
      from `config/<area>/flood_scenarios.csv` (`co_ff04`), builds the arm network, delineates
      with `fl_valley_confine()` using the row's parameters, times delineation and
      `fl_valley_attribute(group = "blue_line_key")` separately (`Sys.time()`), writes
      `data/<area>/probe_whole_fwa/arm<k>_{floodplain.tif,by_blk.gpkg,timing.json}`.
- [x] Mode `anchor` (arm 5 on its own DEM): stop unless network digest == provenance
      `streams_content_sha256`, DEM digest == `dem_content_sha256`, and floodplain digest ==
      `floodplain_content_sha256`. Each failure names which link moved (network / DEM / VCA).
- [x] Common grid: arm 1's DEM is written once to `probe_whole_fwa/dem_common.tif`; arms 2–5 are
      delineated on it, so all five compare cell-for-cell. Arm 5-on-common vs the on-disk baseline
      is reported as the extent effect.
- [x] Segment grain: arm 3 additionally attributed by a composite `(blue_line_key,
      downstream_route_measure)` key (not `id_segment`), timed; per-group slope reported so other
      floors are extrapolated from a measured rate, labelled as extrapolation.
- [x] `floodplain_probe-run.sh <area>`: runs anchor then arms 1–5 sequentially, each in its own
      process under `caffeinate -s /usr/bin/time -l` (peak RSS), one log per arm; gates on the
      in-band error count and output mtimes, not exit codes.
- [x] `.gitignore` covers `data/` already — confirm `probe_whole_fwa/` is not shipped (publish
      layer copies by explicit name).

## Phase 3: Run on MORR and measure
- [x] Run the anchor, then all arms (commit before the run; no edits to the script while it runs).
- [x] Summary script mode `report`: per arm km, segments, blks, delineation s, attribution s,
      peak RSS, floodplain km²; area vs baseline (intersect / lost / gained), and per-blk
      attributed area for the 340 coho blks vs the baseline's `co_ff04_by_blue_line_key`; arm 4's
      added area beyond arm 3; rearing (co, ch) and spawning km below each floor from
      `fresh.streams_vw_bcfp`.
- [x] Write `scripts/floodplain_lcc/logs/<yyyymmdd>_floodplain_probe-whole-fwa_morr.{csv,md}`.
- [x] Quality: a review gpkg (`probe_whole_fwa/review.gpkg`: order-1 and order-2 added valleys,
      arm-4 additions) plus a handful of hillshade panels to `probe_whole_fwa/` for your visual
      read; my own read recorded as preliminary, your verdict pending.

## Phase 4: Verdict, docs, hand-off
- [x] `research/whole_fwa_floodplain.md` (provenance line, question, method, results per arm,
      recommendation on floor and grain, open items) + row in `research/README.md`.
- [x] CLAUDE.md: one short bullet in Layout pointing at the probe and research file.
- [ ] Revise #104's body against the numbers (edit, not comment); update #110 body if scope moved.

## Validation

- [x] `floodplain_probe-check.R` passes; each must-fail arm shown to fire with the guard removed
- [x] Anchor passes on MORR (or its failure recorded and the fallback baseline stated)
- [ ] `/code-check branch` clean
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion, archive README carries Measurement + Evidence
