# Code-check round 1: branch 145-check-bulk-s-change-against-dated-imager (base 033981a)

## Checklist read

- code-check-python.md: in full. Nothing in it applies, because the diff has no Python.
- code-check.md (329 KB): the prose of all 14 H3s under `## Mechanisms`, with the table rows skipped. I did not read the 23 H3s under "Rules that stand alone", "Security" and "Spreadsheets and PDFs".
- code-check-r.md (175 KB): I read 15 headings:
  - Read-back shape;
  - `on.exit()` at a script's top level;
  - `$` partial-match;
  - `nzchar(NA)`;
  - `paste()` zero-length;
  - `strsplit()` trailing empty;
  - `identical()` on reader results;
  - CSV whitespace;
  - `sort()`/`order()` collate;
  - scalar helper in `glue()`/`mutate()`;
  - `match()` NA;
  - `as.integer("NaN")`;
  - `unlist()` prefixes;
  - `[[` on atomic;
  - `data.frame()` recycles;
  - `tempfile()` session dir;
  - Rscript edit mid-run;
  - `ifelse()` all-NA.

  I did not read the other 96.
- code-check-spatial.md (154 KB): I read 9 headings:
  - `sf::gdal_utils()` does not raise;
  - gdalwarp writes into an existing destination;
  - `terra::rast()` on a SpatRaster;
  - `plot()`/`plotRGB()` 500,000 cells;
  - `terra::plot()` legend;
  - QGIS/Wayback (`-ovr NONE`, cache);
  - VRT composites over the mask;
  - `align()` snap;
  - drawn footprint.

  I did not read the other 83.
- code-check-shell.md (121 KB): I read no headings, because the diff has no shell.

Checked and not a finding:
- **Wayback warp without `-ovr NONE`.** NECR's `built.csv` uses zoom 17 and 18 only, so the 0.25 m output in `wb_panel` is finer than the native tiles and reads no overview.
- **B's 75-point working copy.** It holds 0 labels and is in `review_id` order.
- **B's `labelling_key.md`.** It carries the widened rule 5.
- **The prompt commit.** It was committed at 13:06Z, before the first batch at 13:14Z.

## Findings

- **[severity: bug]** scripts/landcover_accuracy/accuracy_estimate.R:79. The gate trigger `!synthetic && any(startsWith(as.character(lab$reviewer), FP_ACC_MODEL_PREFIX))` evaluates to `NA` when any `reviewer` cell is blank and none starts with `model:`.
  - `startsWith(NA, ...)` is `NA`, and `any(c(NA, FALSE))` is `NA`, so `if (NA)` aborts with "missing value where TRUE/FALSE needed". Reproduced on R 4.5.2.
  - `reviewer` is a free-text field in `labels_form.qml`, with no default, and `fp_acc_labels_frame()` never validates it. So any labels.csv made by a person with a blank reviewer now crashes the estimate, where before the branch it ran.
  - That covers a future area labelled by a person, and the relabelling fallback the research text names.
  - Fix: `any(startsWith(...) %in% TRUE)` or `isTRUE(any(..., na.rm = TRUE))`.

- **[severity: bug]** The gate and `publish` accept a partial `labels_b.csv`, which defeats both the audit and B's blindness. Files: `fp_accuracy.R` `fp_acc_model_gate` (~line 819), `labels_import-model.R:685-693`, `accuracy_estimate.R:73-92`.
  - `labels_export.R` works out B's role from all 75 rows of the working copy. It then keeps only the rows with a `label_status`, so exporting halfway through B's labelling writes a `labels_b.csv` of, say, 20 points.
  - `publish` checks only `file.exists(labels_b.csv)`, not that it is committed or complete. It then copies the model's labels into `reference/<area>/labels.csv` while the person is still labelling, which breaks the pre-registered "the person is blind to the model's labels".
  - `fp_acc_model_gate` never compares B's points with `key$second`, so kappa, change agreement and abstention are computed and can pass over whatever subset B has done.
  - That turns the 75-point audit into an n-of-anything audit. Before #145, labels_b was information only, so a partial file was harmless; now it gates the estimate.
  - Fix: in `publish` and in the gate, require B's labelled plus cannot_label rows to cover exactly `key$point_id[key$second]` (for example, setequal against the review key).

- **[severity: bug]** scripts/landcover_accuracy/review_render-sheets.R:962-1013 can leave a stale sheet map that maps labels to the wrong points.
  - The script deletes the batch directories and renders the new shuffle. It writes `sheet_map.csv`, `key.md` and `render.json` only after the loop.
  - If a re-render aborts mid-loop (a Wayback warp error, a crashed session), the previous run's `sheet_map.csv` stays beside the new sheets.
  - Sheet names and batch membership are a function of the counter `k` only (`fp_acc_sheet_plan`), not of the shuffle. So for every batch that finished rendering, `batch_prompt()`'s `setequal(sheets, sheet_map$sheet[batch == b])` and `fp_acc_sheet_dir_check()` both pass.
  - `extract` and `import` would then map those labels through the old shuffle's `review_id`/`cell`. `fp_acc_unblind` cannot catch this, because the cell comes from the same stale map.
  - The raw/ guard does not cover it, because no labels exist yet at this point.
  - Fix: `unlink()` `sheet_map.csv`, `render.json` and `key.md` before the first sheet is drawn, or write the map before rendering and record the render seed in each batch check.

- **[severity: fragile]** scripts/landcover_accuracy/labels_import-model.R:643-660 and `fp_acc_transcript_audit`. The audit refuses reads outside the batch but never checks that every sheet the reply labels was actually Read.
  - An agent that ran out of context, or skipped images, and filled the CSV for sheets it never opened passes `extract` and `import`.
  - `n_reads` is recorded in the audit json, but nothing compares it, or the set of Read paths, against `want`.
  - The NECR run happens to show 41 reads per batch, but the guard does not enforce it.
  - Fix: refuse unless the set of `basename(path)` over the Read calls inside the batch directory equals `want`, and key.md was read.

- **[severity: fragile]** fp_accuracy.R `fp_acc_model_wc`, the `num()` helper (~line 1010). `suppressWarnings(as.integer(v))` turns "2.5" into 2 and "11.9" into 11 with no NA, and 2 and 11 are valid IO codes. So the guard "a class that is not an integer code is refused" passes non-integer codes as a truncated class.
  - Fix: `x <- suppressWarnings(as.numeric(v)); bad <- !is.na(v) & (is.na(x) | x != round(x))`.
