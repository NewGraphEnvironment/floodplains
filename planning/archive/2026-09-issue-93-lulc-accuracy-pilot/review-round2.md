# Code-check review, round 2 (#93, scripts/landcover_accuracy + packages.R)

## Findings

- **[severity: bug]** scripts/landcover_accuracy/window_count-clear.R:52-58, 106-110. The round-1 fix assumes a NULL from `clear_count()` means the fetch failed. That is false for drift 0.19.0, so the fix now mislabels the other case.
  - The script calls `drift::dft_stac_composite()` with a **single** `years = year`.
  - drift treats a window with no scenes (`drift_no_items`) or no clear pixels (`drift_empty_cube`) as *"a result, not a failure"*. It warns, drops that year, and then aborts with "No year produced a composite." when every year was dropped (R/dft_stac_composite.R:239-255).
  - With one year per call, a genuinely empty month (no scene under `cloud_cover_max = 20`, or fully clouded) therefore arrives as an error. The `tryCatch` turns it into NULL, and it is now written as NA, the same row a transient STAC or Planetary Computer failure writes.
  - Before the fix both cases read as 0 (wrong for failures). After it both read as NA (wrong for genuine zeros). The CSV has no column that separates them.
  - That is the signal the script exists to measure: "no clear observation this month" is the answer that should rule a window out. A month with some NA years, summarised with `na.rm`, looks better than it is, which steers the window choice toward cloudy months. The most likely place for this is 2017, when Sentinel-2 L2A coverage was sparse.
  - The fix is to tell the two apart before collapsing to NULL:
    - Detect drift's "Skipping the … composite: no scenes / no clear pixels" warning, or the "No year produced a composite" abort. Record those as a real zero (`n_cells` = footprint cells, stats 0, `share_ge*` 0).
    - Keep NA for any other error.
    - Add a `status` column (`ok` / `empty` / `failed`) so the CSV says which.
  - The script is still blocked on drift#92, so no number is wrong today.

## Round-1 fixes, verified

- **Stable wetland (fix 1): correct.** `stab & (inw | (f == 4L))` is the same rule as the change branch `(f == 4) | (t == 4) | inw`: with `from == to`, `f == 4` is equivalent to `t == 4`. Precedence is also the same shape on both sides: wetland beats stable Trees, and wetland change beats the transition-class strata.
  - **Mutation test.** In a temp copy, reverting to `stab & inw` makes accuracy-check.R report `FAIL stable_FV_not_fwa -> stable wetland (got stable other)`. The unmodified tree reports ALL PASS.
  - **Committed sample re-derived.** I re-derived every non-cause point's stratum in reference/necr/sample.gpkg from its own `map_2017`, `map_2023`, `map_class` and `in_fwa_wetland`, using the pinned rules. **390 of 390 match.** The two stable 4004 points sit in "stable wetland" with `in_fwa_wetland = FALSE`, and "stable other" holds no 4004 and no FWA point.
- **Stratum 32 (moved cells): consistent.** Round 1 measured 1,769,802 cells and it now holds 1,765,406, a drop of exactly 4,396.
- **strata.csv (partition): consistent.** The change strata sum to 472,998, and all strata sum to 4,183,814 (the footprint). The stable strata weigh 0.862, which is the "86%" in the note.
- **Research-note table: consistent.** It matches strata.csv to rounding.
- **Cause-poly counts: confirmed.** "3 of 30 fire" and "17 of 30 harvest" outside their polygons hold in the redrawn sample.
- **Sync guard (fix 3): correct.** terra 1.9.50 uses three-valued logic: `TRUE | NA` is TRUE. So `!is.na(tr) & (is.na(expect) | (tr != expect))` counts a transition cell whose endpoint is NA. Probed on a 5-cell grid: 3 of 3 disagreements counted, the agreeing cell and the NA-transition cell not counted.
- **Old stratum name: none left.** Nothing in the repo still uses "stable in FWA wetland". I grepped *.R, *.md, *.csv, *.json and *.qml, the untracked accuracy_estimate.R and labels_form.qml included. The only matches are the round-1 review text and the log that describes the rename.
- **map_class: no gaps.** No point has NA `map_class`.
- **Sieved points: correct claim.** Every sieved point's `map_class` is `from*1000+from`, and every other non-cause point's is `from*1000+to`.
