# Code-check round 2 — #108 composition table (staged diff + round-1 fixes, 2026-10-02)

Reviewer: subagent, read-only. No writes to data/ or the database. Read-only probes only: DB column
types (`fwa_wetlands_poly.waterbody_poly_id` integer, `oats_alr_polys.alr_poly_id` numeric with 3226
distinct of 3226 rows, so fix 2's raw-column digest accepts both). `is.numeric(integer64)` is TRUE, so
a bigint carry is not refused either. `data/morr/floodplain.gpkg` is EPSG:3005, so the live check's
`.dst_fetch(conn, s, fp, ...)` pads in metres, not degrees. Which areas have rasters but no
provenance.json: `mcgr` and `pine`.

Round-1 fixes that hold:
- Fix 2: digest over the bbox-fetched set from raw columns. Correct, and both live context keys are numeric.
- Fix 4: species from the scenario prefix. Correct.
- Fix 1 holds for a first-time failure. The ordering is now: stale layer deleted, then landcover
  record, then composition, then `lulc_summary*.rds`. A crash at any point leaves a state 7c reports.
  The exception is the re-run case below.

## Findings

- **[fragile] scripts/floodplain_lcc/fp_composition.R:224-228 (with provenance-check.R viol_composition,
  the `STALE: its floodplain` arm)** — fix 3 does not detect the case it was written for.
  - `floodplain_outputs_hash` is read from provenance.json **when the composition is built**, not
    from anything step 3 recorded. On the step-3 path the two are the same moment, so it adds nothing there.
  - On the backfill path the round-1 scenario runs: step 3, then step 2 re-run, then
    `composition_build.R`. The step 2 re-run has already replaced `floodplain[<scen>].outputs_hash`,
    so the composition records the NEW hash. `viol_composition` then compares it with the NEW hash
    and passes.
  - Meanwhile `in_floodplain` is rasterised from the new polygon and the classified rasters are
    masked to the old one. That is exactly the mismatch the comment says "is visible
    (provenance-check compares the two)". It is not visible.
  - The 3c must-fail arm only exercises the other direction: the floodplain moving AFTER the
    composition. That case is caught.
  - The landcover entry records only `floodplain_layer`, not which floodplain it consumed, so the
    builder has nothing correct to copy.
  - Cheapest fix: in `fp_composition_build`, refuse when `floodplain[<scen>].run.datetime_utc` is
    later than `landcover[<scen>].run.datetime_utc`. The floodplain was re-delineated after the
    rasters were masked, so step 3 must re-run.
  - Durable fix: step 3 records the floodplain `outputs_hash` it consumed in landcover `inputs`
    (forward-only). The composition copies it from there, and `viol_composition` compares it with
    the floodplain section.

- **[bug] scripts/floodplain_lcc/fp_composition.R:235 vs :237 (reached via composition_build.R)** —
  the table is written to `floodplain_landcover.gpkg` BEFORE `fp_prov_set_sibling()` refuses for a
  missing `landcover[<scenario>]` entry. So the refusal composition_build.R's header promises
  ("which it refuses to do for a scenario step 3 has not recorded") comes after the write.
  - **Reachable today:** `data/mcgr` (ch_ff04) and `data/pine` (bt_ff04) have rasters and no
    provenance.json.
  - `composition_build.R mcgr` does the full build, writes `composition_ch_ff04_2017_2023`, and
    only then stops with "no landcover[ch_ff04] entry".
  - The orphan stays in a gpkg the publisher copies whole. Nothing reports it: provenance-check's 7c
    needs a provenance.json to iterate, and these areas have none.
  - The same order also strands a written table whenever the sibling write fails on its mtime race
    guard.
  - Fix: `prov_now` is already read at :228. Check `prov_now$landcover[[scenario_id]]` there, before
    any computation or write. Also write the table only after the sibling record, or delete it on
    failure.

- **[fragile] scripts/floodplain_lcc/03_lulc_classify.R:494-495 (with :436-443)** — fix 1 moved the
  `lulc_summary*.rds` write after the composition. That only helps when no earlier file exists.
  - Take a **re-run** of a group that already has `lulc_summary.rds`: a `FORCE=1` region run, or
    `run_area.R <area> 3`. If it dies in `fp_composition_build`, the stale composition layer has been
    deleted and `landcover[<scen>]` has been replaced, with no sibling. The PREVIOUS run's
    `lulc_summary.rds` stays on disk.
  - The next non-FORCE `run_region.R` marks the group `ok(cached)`, since both `lulc_summary.rds`
    and provenance.json exist. provenance-check 7c then reports
    `ok ... no composition table yet (forward-only, #108)`.
  - That is round-1 finding (b)'s fail-toward-pass outcome on the re-run path. The per-scenario
    `lulc_summary_<scen>.rds` also now describes a different run from the landcover record.
  - Fix: `unlink()` both `lulc_summary_<scenario_id>.rds` and `lulc_summary.rds` at the point where
    the stale composition layer is deleted. Then the resume marker exists only when the current run
    finished.
