# Code-check round 1, #148 (d4a3101...bff176c)

## Checklist read

- code-check-python.md: in full.
- code-check.md (330,698 B): every H3 under `## Mechanisms` read in prose (table rows skipped): all 14
  (guard fails toward pass, fixture cannot reach, proxy, verification reads own output, guard scope /
  escape hatches / remedies, fix in one of two callers, restore the bug, shared working tree, wrapper's
  exit, zero-length/empty/unset, probe broken, written data outlives the fix, serialization, one fact
  derived twice). Rules-that-stand-alone and Security/Spreadsheets: index only (none names a tool or
  shape this diff uses beyond "A preview flag is only safe if it previews", which does not apply).
- code-check-r.md (177,187 B): full sections read: "Read-back shape must match write-back shape",
  "`$` on a list partial-matches", "`match()` treats NA as a matchable VALUE", "`strsplit()` drops a
  trailing empty field", "`nzchar(NA)` is TRUE", "Rscript reads a script as it runs", "CSV whitespace",
  "`paste()` with a zero-length argument", "R's `yaml` returns a mixed int/float sequence", "`[[` on a
  named ATOMIC vector". The remaining ~95 headings: index only.
- code-check-shell.md (124,118 B): index only (diff has no shell); 0 sections in full.
- code-check-spatial.md (155,517 B): index only (diff touches no terra/sf call); 0 sections in full.

## What was checked (all by running, not reading)

- Every reader/writer of `windows.csv` / `windows_clear_obs.csv` in the repo (grep over *.R, *.sh, *.py,
  *.Rmd): writers are `window_count-clear.R` derive and run; readers are chip_build-composite.R,
  review_build-qgis.R, review_render-sheets.R and derive. All four go through the new readers. None missed.
- `fp_acc_windows_read("reference/necr/windows.csv", "all_ff04")` returns months as character
  ("8-9","8","8","8"), year integer; `"ch_ff04"` is refused. Read-back shape matches derive's
  `quote = FALSE` write. `fp_acc_window_obs_read()` on data/necr/accuracy/windows_clear_obs.csv: 49 rows,
  all `all_ff04`; the curated log copy is byte-identical to it.
- `%in%` edge cases: empty frame refused by `!nrow()`; an all-blank scenario column reads as logical NA,
  and `NA %in% "all_ff04"` is FALSE, so refused. `cfg$primary_scenario` cannot be NA/NULL/length > 1
  (fp_acc_design_scenario's regex, fp_acc_scenario's one-row lookup), so the NA-matches-NA hole is unreachable.
- Title regex: groups balanced; passes all six legitimate shapes, refuses "July", "Jul-Sep-Oct", "NA",
  empty month, a trailing "stratum 4", an embedded `|17_00009`, and two titles concatenated. The month
  span is per year, identical for every point, so it carries no design information.
  `month_lab()` (sheets) and `fp_acc_months_str()` (derive) and `months_of()` (chips) agree on "a-b".
- Reference files against sample.gpkg (480 points, all scenario `all_ff04`): review_key.csv,
  imagery.csv and wayback.csv each list exactly the sample's points with 0 cell / stratum / map_class
  disagreements; review_id 1..480, 75 second-labeller points with the same per-stratum split as before;
  strata.csv sums to 8,078,287 cells; design.json's dims/extent equal data/necr/rasters/all_ff04/transition.tif.
- research/landcover_accuracy.md numbers against the 20261023 logs and reference files: criterion 4
  (223, 481.5, 0.147, 0.234, 85.3%, 0.12-0.18 over 84-113 ha, +9 points), fire row, wetland table and
  ranges (2,646 / 12,809.0 / 80,783; Trees 0.538-0.611 wetlands, 0.510-0.545 overall), the full strata
  table (ha and weights), 1,019,347 change and 204,033 sieved cells (17% in CLAUDE.md = 16.7%), 1 and 17
  points outside fire/harvest polygons, 85% stable, imagery table (136 / 28.3%, 4.41 m, 2019: 12,
  1996/2000 at 480), 161 hits / 15 collar (same "point-tile hits" line the script printed for the first
  draw), 160 same-capture points, Wayback shares 80% / 65% / both 49.8% / neither 4.6% and the
  3.2x and one-ninth ratios, 960 chips / 766 MB / 14.5 min. All agree.
- Pre-registered passages: the only edit inside a pre-registered section is the dated *(Amended
  2026-10-23 ...)* note in "Model labeller"; the original sentence around it is unchanged except for a
  line wrap. The Strata section's "18%" (ch_ff04-era) was correctly left alone.
- The criterion-4 commitment (315477b, 14:03:02 PDT) precedes the omission run (14:08:44 PDT).
- labels_import-model.R freeze/publish and accuracy_estimate.R read the hash file's LAST commit, so a
  replaced labels_model.sha256 passes them; no history check counts its commits.

## Findings

No code defect found: the guard, its four call sites, derive's writer and the regex are correct.
Three prose findings, all in research/landcover_accuracy.md or the model-labels log:

- **[fragile]** research/landcover_accuracy.md:389-395 (the dated amendment inside the pre-registered
  "Model labeller" section) and scripts/landcover_accuracy/logs/20261023_model_labels_necr.md:3 state as
  done what HEAD has not done. The amendment says "The sheets were rendered afresh for the new draw and the
  model labelled them again ... so the second hash replaces the first", and the log says the hash "was
  replaced". At bff176c, reference/necr/labels_model.sha256 does not exist (git rm'd in 7f5e7e9), and
  task_plan Phase 4 is unchecked. The status line at :10 ("chips built and in the review project") is also
  false while the chip build runs. If Phase 4 lands as planned these become true. But this text sits in a
  pre-registered section that can only be amended, never edited, so a Phase 4 that changes course (a gate
  stop, a re-render) would leave a false sentence there permanently. Until a hash is committed,
  accuracy_estimate.R's `fp_acc_labels_hashed()` returns FALSE (no sha file), so model labels are again
  recognised only by their reviewer column. Commit the new hash before merging; the alternative is
  wording the amendment as what will happen.
- **[stale]** research/landcover_accuracy.md "Composite windows", the "Measured 2026-09-30" block
  (around :640-659), and "Review setup" around :455-467 still give the ch_ff04 counts as the section's
  results. Meanwhile windows.csv, and the "Dated imagery" bullet at :511 ("Only a redraw re-measures
  it"), say the windows were re-measured on all_ff04, and the all_ff04 counts differ:
  - August 2017 alone: 0.852 stated, all_ff04 0.869;
  - July 2019: 0.180 stated, all_ff04 0.149; June 2019: 0.811 stated, all_ff04 0.840;
  - August's tie over May: stated "0.9985 against 0.988", all_ff04 0.999 against 0.963;
  - first month clear everywhere: stated "May in five (April in 2021)", all_ff04 May in six (2021 is
    May);
  - last month clear everywhere: stated "October in four (September in 2017 and 2020)", all_ff04
    October in three (September in 2017, 2019, 2020);
  - "direct count of 1.000", all_ff04 0.999.

  The windows themselves are the same, so the verdict holds. But the file is revised in place, and it
  now reports the old floodplain's numbers with no all_ff04 measurement beside them. This is the
  unchecked Phase 5 item at task_plan.md:88 ("update ... the windows").
- **[unverified claim]** research/landcover_accuracy.md:131, "223 polygons, most a few ha of floodplain
  Trees". Nothing committed measures this. The logs give only the total (481.46 ha, a mean of 2.2 ha
  per polygon), and the replaced ch_ff04 wording ("most under 1 ha") had a mean of 1.2 ha. With a
  skewed size distribution, the median, which is what "most" claims, is likely below the mean. Measure
  it, or state the mean.
