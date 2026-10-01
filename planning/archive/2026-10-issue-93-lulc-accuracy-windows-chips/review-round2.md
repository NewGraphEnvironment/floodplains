# Code review, round 2 (#93 windows + chips, staged diff): the round-1 fixes

## Findings

- **[severity: fragile]** scripts/landcover_accuracy/window_count-clear.R:73-101 (`clear_count`),
  and the `run` → `derive` path. This is a silent path to a different `windows.csv`.
  - drift 0.20.0's `count` documents that a day whose chunk read failed "goes uncounted there, so
    where reads fail a count is a lower bound". gdalcubes reports such failures only on the
    console (dft_stac_composite.R:35-39, dft_stac_cube.R:499-505).
  - `clear_count` cannot see this, so the row gets `status = "ok"` with a lowered `share_ge1`.
    `count_stats` maps the NA cells to 0.
  - A month near the 0.95 bar can therefore drop out of the span, or 2017 can widen further than
    it needed, with no error. The fix-2 direct counts in `derive` go through the same `clear_count`
    and have the same blind spot.
  - Round 1 accepted this because it "errs toward failing a month". But the rule's own comment in
    fp_accuracy.R:373-374 says the opposite: "an unmeasured month is not a failed one, and
    treating it as either would move the span". That is the invariant this path breaks.
  - The evidence exists, because the live run sends stderr to
    `data/necr/accuracy/window_run_20260930.log`. Nothing reads it before `derive`.
  - Cheap remedy: before running `derive`, grep that log, and the `derive` console output for its
    direct counts, for gdalcubes read errors. If one appears, treat the month-year as `failed`.
    Upstream, the proper fix is drift reporting the failure (drift#87 class), not a local
    workaround.

No other defects found. The three round-1 fixes are correct.

## Round-1 fixes checked

1. **`colClasses = c(months = "character")`** (chip_build-composite.R:38). Reproduced in scratch:
   - `derive`'s own write (`quote = FALSE`) round-trips. `5-8,6-8,6-8,6-8` reads back as `chr`.
   - All-single-month `7,7,7,7` now reads back as `chr "7"`, and `months_of("7")` gives `7`.
   - `year` stays integer.
   - A file with no `months` column only warns ("not all columns named in 'colClasses' exist"),
     then the existing column check stops. That is still loud.
   - No other reader of `windows.csv` exists: repo grep, excluding data/ and archives.
     `review_build-qgis.R` reads only the `.vrt` names. `same_season_2017.vrt` becomes
     "S2 same season_2017", which is cosmetic and unaffected by the diff.
2. **Span first for 2017** (window_count-clear.R:173). `c(list(span), fp_acc_window_widen(...))`
   is a list whose first element is the span. When widen returns an empty list (the span is
   already 4:10), the list is just the span. Exercised against a fake `windows_clear_obs.csv`
   written as `run` writes it (`na = ""`, character months for ok rows, integer for an empty
   row). Results:
   - The read-back types are right.
   - All-years span: `integer(0)`.
   - Rest-years span: `6:8`.
   - Candidate order: `6:8, 5:8, 4:8, 4:9, 4:10`, with both ties going to the earlier month.
   - The span-first order also holds for the frozen copy the live run uses. The frozen file
     differs from the staged one only in this line, and `run` does not reach it.
3. **Prose amendment** (research/landcover_accuracy.md). It matches the code:
   - The span is counted first, only in the 2017 deviation.
   - The higher-share neighbour goes first, and a tie takes the earlier month.
   - Each window is accepted only on a direct count of the whole window.
   - The "pre-registered before any count ran" header still describes the original rule, and
     the amendment note says what changed and when.

## Also checked

- `accuracy-check.R`: ALL PASS. The window arms are right.
- drift's `clip` is `touches = TRUE`, the same as `count_stats`' rasterize, so edge cells are not
  systematically read as 0.
- The skip-warning regex still matches the multi-month label ("2017 May–Aug", with an en dash).
- `fp_accuracy.R` (mtime 10:57) predates the frozen run's launch (11:02), so the run has
  `fp_acc_months_str`.
- `packages.R`: the change is a comment inside `c()`, and nothing else.
