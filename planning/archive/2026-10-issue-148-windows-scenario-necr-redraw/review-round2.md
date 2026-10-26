# Code-check round 2, #148 (d4a3101...7bc4b15)

## Checklist read

- index_code-check*.md (all five): read in full.
- code-check-python.md (7,237 B): in full.
- code-check.md (330,698 B): the prose of all 14 H3s under `## Mechanisms`, table rows skipped (guard
  fails toward pass; fixture cannot reach; proxy; verification reads own output; guard scope / escape
  hatches / remedies; fix in one of two callers; restore the bug; shared working tree; wrapper's exit;
  zero-length / empty / unset; probe broken; written data outlives the fix; serialization; one fact
  derived twice). Rules-that-stand-alone, Security and Spreadsheets: index only (none names a tool or
  shape this diff uses).
- code-check-r.md (177,187 B): full sections read: "Read-back shape must match write-back shape",
  "`match()` treats NA as a matchable VALUE", "CSV whitespace", "Rscript reads a script as it runs",
  "`$` on a list partial-matches". The other ~100 headings: index only.
- code-check-shell.md (124,118 B): index only; the diff has no shell. 0 sections in full.
- code-check-spatial.md (155,517 B): index only; the diff changes no terra/sf call. 0 sections in full.

## What was checked

**Round 1's fixes, every number against the artifacts** (`logs/20261023_window_count-clear_necr.{md,csv}`,
the derive table, `FP_ACC_WIN_THR = 0.95`, and the 2026-09-30 `ch_ff04` log for the bracketed values):

- "Without 2017, only May and August pass in every year": true at 0.95. Over 2018-2023, May's minimum is
  0.963 (2022) and August's is 0.9987 (2021). Every other month fails at least one year: Apr 0.637, Jun
  0.840, Jul 0.149, Sep 0.000, Oct 0.011. Re-derived by running `fp_acc_window_pass` and
  `fp_acc_window_span` on a temp copy of the CSV: span = 8.
- "0.999 against 0.963": August's 0.99874 rounds to 0.999. Correct. Bracketed "0.9985 against 0.988"
  matches the ch_ff04 log.
- July 2019 0.149 (0.180), June 2019 0.840 (0.811), Aug 2017 0.869 (0.852), Sep 2017 0.998, direct
  Aug-Sep 0.999 (1.000): all match.
- Early: May in six of seven (2018-2023), June in 2017. Ch_ff04 had May in five, April 2021, June 2017. Correct.
- Late: October in three (2018, 2022, 2023), September in 2017, 2019, 2020, August in 2021. Ch_ff04 had
  October in four (2018, 2019, 2022, 2023). Correct.
- "Four month-years have no scene": the CSV's four `empty` rows are 2017-04, 2017-05, 2017-07, 2021-09. Correct.
- "No month is clear everywhere in all seven years": correct.
- "223 polygons, 2.2 ha ... on average": 481.46 / 223 = 2.16. Correct (harvest row only, as before).
- Amendment and model-log rewording now state the re-label as what will happen. 4072a24 is the commit
  that added `labels_model.sha256`.
- Committed `reference/necr/windows.csv` = derive's output (scenario `all_ff04`). The curated obs CSV is
  byte-identical to `data/necr/accuracy/windows_clear_obs.csv`.

**Code diff, each changed file read in full** (fp_accuracy.R readers and window functions,
window_count-clear.R, chip_build-composite.R, review_build-qgis.R, review_render-sheets.R 1-140,
accuracy-check.R arms):

- Exercised on temp copies. `fp_acc_window_obs_read` reads the real 49-row file, and `month` comes back
  integer. `fp_acc_windows_read` keeps months as character, refuses `ch_ff04`, and refuses a file with no
  months column (warning first, then the stop).
- No reader of `windows.csv` / `windows_clear_obs.csv` is missed (grep over *.R/*.sh/*.py/*.Rmd).
- Title regex: the alternation is enclosed, so it admits only `Mon` or `Mon-Mon`.

**The window with windows.csv deleted (14:36 to 15:16 PDT):** nothing left stale.

- review_build-qgis.R reads windows only to name S2 layers, and the 14:36 build found no chip VRTs ("no
  chips yet" in `review_build_a1.log`). So no S2 layer was added under a month-less name. A month-less
  layer would have survived the rebuild beside the named one, since a layer is added once by name.
- The qgs holds no dated or Wayback layers either: the dated VRTs are 14:38-14:51, after the build.
- `labels.gpkg` has 480 rows, 0 labels and `dated_imagery` all NULL. The Phase 3 rebuild will therefore
  rewrite it (`unlabelled && stale_cover`).
- `cells.gpkg` has no capture columns. It will be rewritten when `wb_ok()` returns rows.
- No other script built in that window (sample draw, imagery and Wayback index/build, omission, wetland)
  reads windows.
- The chip build refuses without windows, and it started at 22:18Z, after derive (15:16-15:18 PDT).

## Findings

No code defect. One wrong number in the restated research prose.

- **[fragile: wrong published number]** research/landcover_accuracy.md:134 and :137-138. Criterion 4's
  value is printed as **0.147**, and the prose says "IO labels 85.3% ... so it misses 14.7%". The
  exact value is 0.148, 85.2% and 14.8%.
  - The grid is 10 m (design.json: extent width 94,230 m over 9,423 columns), so a cell is exactly
    0.01 ha. From `omission_disturbance.csv`, denom = 48,146 cells and io_loss = 41,043 cells.
  - So omission_io = 7,103 / 48,146 = **0.147530**, which rounds to 0.148. IO's share is 85.247%, which
    rounds to 85.2%, not 85.3%.
  - The 0.147 comes from a double rounding in `reference_omission-disturbance.R`. Line 62 rounds to 4 dp
    (0.1475). Line 71 then prints `%.3f`, and 0.1475 sits just below the half in binary, so it prints
    0.147. The log faithfully shows that printed 0.147, and the research text copied it. 85.3% is
    1 - 0.147.
  - The verdict is unaffected: well under the 30% bar, and accuracy_estimate.R compares the stored
    0.1475. But this is the pre-registered criterion's published value, and it is off in the third digit.
  - The double rounding is pre-existing (#140-era code, not in this diff). This diff restates the
    number. The `ch_ff04` "0.255" beside it came through the same path and may carry the same artifact.
  - ("One fact derived twice": a published number has two derivations, the value and its printed form.)

All other code and prose checked this round: clean.
