# Task: Measure IO LULC accuracy in our floodplains against dated imagery (#93) — windows + chips

Continuation of #93 after PR #101 (phases 1–6). Part of #93; labelling and the verdict stay open.

PR #101 delivered phases 1–6 of #93 and left it open. Two automated steps were blocked on
drift#92 (`aggregation = "count"` returned reflectance). drift 0.20.0 (merged 2026-09-30, PR
drift#97) fixes that: a count is now **distinct clear days** per pixel, INT2U, `NA` = no clear day,
snow masked too. This branch does the unblocked work and stops where a human has to label.

- Measure the windows.
- Build the chips.
- Put the chips in the review project.

It is again **Part of #93**. Labelling, `labels.csv`, the estimates and the verdict stay open.

What exploration found that shapes the plan:
- Installed drift is **0.19.0**, so it needs upgrading (a machine change).
- `window_count-clear.R`'s check (b) compares the per-pixel max against the **item** count. drift
  now counts days, with same-day MGRS tiles counted once, so the right bound is **distinct
  dates**. That check stays valid, and so does the integer guard. drift's skip warning text
  (`Skipping the … composite: no scenes|no clear pixels`) is unchanged, so the `empty` path still
  works.
- A floodplain-wide call is the drift#88 risk: a 3 h read that then failed. But that was 10 m and
  tiled; this is res 100 with one band. Its cost is **unmeasured**, so a timing gate goes before the
  49-call loop.
- `chip_build-composite.R` refuses to run without `reference/necr/windows.csv`
  (`window,year,months`), and nothing writes that file yet.
- `review_build-qgis.R` already adds one layer per `chips/*.vrt`, idempotently (lines 111–118).
- The research note already fixes the chip years: **2017, 2023** (endpoints; 2023 is the drought
  year), **2018** (borderline dry) and **2020** (wet). That is 4 windows × 450 points ≈ 1,800
  chips, about 22 h at 44 s each. The early/late amplitude comes **from the counts**, not from
  chips. Chips cache per point, so early/late chips can be added later without rebuilding.

## Phase 1: drift 0.20.0 and the window script
- [x] `pak::pak("NewGraphEnvironment/drift")` → 0.20.0 (machine change, stated in the PR). Update the
      drift floor comment in `scripts/packages.R` to name 0.20.0 for `aggregation = "count"`
- [x] `window_count-clear.R` validate (b): bound the max per-pixel count by **distinct dates**, not
      items. Keep the item count printed as a cross-check
- [x] Add a validate step (c) that **times one floodplain-wide month** at res 100 (2021-07, the
      same month as (a)). Print the minutes and the extrapolation to 49 calls, so `run` is
      launched on a measured cost
- [x] Add a `derive` mode: read `windows_clear_obs.csv` and write `reference/<area>/windows.csv`.
      The rule is pre-registered in the research note and committed **before** `run`:
      - A month is "clear everywhere" in a year when `share_ge1 >= 0.95`.
      - The same-season span is the longest run of contiguous months that is clear everywhere in
        all 7 years.
      - If 2017 alone fails, 2017 gets the nearest wider span that passes, and the note records
        the deviation. HLS (drift#82) is the fallback named if nothing passes.
      - It writes `same_season` rows for 2017, 2018, 2020 and 2023.
      - The early/late windows are reported in the note and CSV, not chipped.
- [x] Refresh the stale comments: drift#92 in `window_count-clear.R` and in
      `chip_build-composite.R` line 12, and the "no chips yet (drift#92)" message in
      `review_build-qgis.R`
- [x] `accuracy-check.R`: an offline arm for `derive` on a hand-built stats frame. A month below
      0.95 in one year breaks the span (must-fail), a `failed`/NA row refuses rather than passes,
      and 2017-only widening is taken only when it passes

## Phase 2: Measure the windows (live)
- [x] `Rscript window_count-clear.R necr validate` → checks (a) res 100 vs 20, (b) ≤ distinct dates,
      (c) timing. Log to `scripts/landcover_accuracy/logs/20260930_window_count-clear_necr_validate.md`
- [x] `caffeinate -s Rscript window_count-clear.R necr run` (background, gated on the validate
      timing). Before reading anything, gate on the output's mtime and the number of `failed` rows,
      never the wrapper's exit code. Re-run the failed month-years, since a cached month is free
- [x] `Rscript window_count-clear.R necr derive` → commit `reference/necr/windows.csv` plus the
      curated CSV/log under `logs/20260930_window_count-clear_necr.*`
- [x] Research note: replace "Composite windows (measurement held)" with the measured section.
      It covers the per-month table, the span, whether 2017 needed widening, and early vs late
      amplitude. Update the header Status and the "2017 summer imagery is thin" bullet

## Phase 3: Chips and the review project (live, ~22 h)
- [x] `caffeinate -s Rscript chip_build-composite.R necr` (background). Gate on `manifest.csv`
      mtime and the missing-chip count. Re-run for the missing ones (cached chips are free)
- [x] `Rscript review_build-qgis.R necr` → the 4 S2 layers added; re-run to confirm it is idempotent.
      Verify the layers in the `.qgs` XML (headless QGIS load fails here, per memory)
- [x] Research note: the chip counts, the build time, and missing chips per window-year. Log
      `logs/20260930_chip_build-composite_necr.md`

## Phase 4: Handoff
- [ ] `CLAUDE.md` #93 bullet: drop "Composite windows are held on drift#92". Say windows are
      measured and name `windows.csv` as a committed input
- [ ] Edit the #93 body's Status and Remaining list: steps 1–2 done. Remaining: label in QGIS →
      `labels_export.R` → `accuracy_estimate.R` → raise N → verdict → #92
- [ ] `/code-check` over the branch diff, `/planning-archive`, `/gh-pr-push` ("Part of #93")

## Validation

- [ ] Tests pass (`scripts/landcover_accuracy/accuracy-check.R`)
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
