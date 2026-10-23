# Code-check round 2 — #145 model labeller (branch diff 033981a...ad4892d)

## Checklist read

- `code-check-python.md` — in full (no Python in the diff; nothing applies).
- `code-check.md` — every H3 under `## Mechanisms` in prose, table rows skipped (14 of 14). Also
  "Test the cold/create path of idempotent code", "A preview flag is only safe if it previews",
  "Bare y/n... YAML 1.1", "Documentation Staleness". Not read: the other 25 H3s (Security, PDFs,
  shared-tree release, URL encoding, etc.; none touched by this diff).
- `code-check-r.md` — read: "Read-back shape must match write-back shape", "`on.exit()` at a
  script's top level never fires", "`$` on a list partial-matches", "`nzchar(NA)` is TRUE",
  "`paste()` with a zero-length argument", "`strsplit()` drops a trailing empty field",
  "`identical()` on two reader results", "CSV whitespace", "`R CMD check` rejects a filename with
  a space", "`sort()`/`order()` collate by LC_COLLATE", "`tryCatch(warning = )` DISCARDS the value",
  "`match()` treats NA as a matchable VALUE", "`as.integer("NaN")` is 0", "`unlist()` prefixes a
  `split()` group's name", "`[[` on a named ATOMIC vector", "`data.frame()` recycles a scalar
  against a zero-length column", "`tempfile()` lives in the session tempdir", "Rscript reads a
  script as it runs", "`sample.int(prob =)`...", "`read.delim()` quotes by default", "`tryCatch()`
  nests its handlers", "`readBin(size = 4)`...", "`ifelse()` with an all-NA test" (23). Not read: 79
  others (packages, testthat, DBI/duckdb/arrow, ggplot, Postgres, pak, roxygen; none applies to
  these scripts).
- `code-check-spatial.md` — read: "`terra::plot()` ... keyword-placed `legend()`", "`sf::gdal_utils()`
  does not raise", "`terra::rast()` on a SpatRaster returns an empty template", "gdalwarp writes
  INTO an existing destination", "GDAL caches a failed `/vsicurl/` open", "QGIS cannot draw Esri
  Wayback ...", "A VRT composites over a source's mask band", "`terra::project()` given only a CRS",
  "`terra::plot()` and `plotRGB()` draw at most 500,000 cells" (9). Not read: the rest (~90; bcdata,
  WFS, lidR, KML, pystac, etc.).
- `code-check-shell.md` — not read beyond the index: the diff has no shell.

## What was verified

- `accuracy-check.R` run in a throwaway worktree at ad4892d: ALL PASS (including every round-1 arm).
- Round-1 fixes re-read: (1) `%in% TRUE` trigger is correct and precedes the estimate; (2)
  `fp_acc_b_complete` uses set equality + duplicate check against `key$second`, and runs before the
  gate and in `publish`; (3) the map/render.json/key.md and batch dirs are unlinked after the `raw/`
  guard and before the first sheet; (4) `fp_acc_unread` compares against the sheet map's batch, plus
  the key; (5) `num()` refuses fractional, non-numeric and out-of-int-range codes (fails closed). No
  defect inside any of the five fixes beyond finding 2 below.
- `SHEETS_ONLY` previews into `model_test/` only, so it does not touch the frozen `model/`.
- `fp_acc_second_stable` is idempotent, draws only among non-subset points, and its own seed stream
  differs. The B working-copy "append at the end" path in `review_build-qgis.R` is not reachable for
  NECR (B's copy was rebuilt by hand, progress.md) and a new area draws the growth before its first
  working copy exists, so it is not reported.

## Findings

- **[fragile]** `scripts/landcover_accuracy/labels_import-model.R:143-154` (`publish`) — The
  pre-registration and this script's header say the model's labels enter the repository "once
  labels_b.csv is **committed**" and are "checked against the **committed** hash". The code checks
  neither: it requires only that `reference/<area>/labels_b.csv` exists in the working tree and is
  complete, and it compares `labels_model.csv` against whatever `labels_model.sha256` holds on disk
  (which `import` with `FORCE=1` rewrites). Nothing freezes B's labels either: after `publish` puts
  the model's labels into `reference/`, `REVIEWER=b FORCE=1 labels_export.R` can rewrite
  `labels_b.csv`, and `accuracy_estimate.R` gates on whatever it holds now. The blinding that the
  whole gate depends on (B never sees A) is therefore procedural, not enforced, in exactly the step
  that ends it. A check on `git ls-files --error-unmatch` plus `git diff --quiet HEAD --` for both
  `labels_b.csv` and `labels_model.sha256` in `publish` would make the stated ordering true; recording
  `labels_b.csv`'s SHA-256 at publish time (and having the gate compare it) would freeze B.

- **[fragile]** `scripts/landcover_accuracy/fp_accuracy.R:1011` (`fp_acc_unread`), called from
  `labels_import-model.R:102` — Round-1 fix 4 counts a sheet as read when a `Read` tool_use naming
  it exists, regardless of what the tool returned. `extract` keeps only assistant records
  (`labels_import-model.R`, the `Filter(... "assistant" ...)` line), so a Read whose `tool_result`
  came back `is_error: true` (or with no image) still satisfies "every sheet was read", and the
  model's label for a sheet it never saw is accepted. The fix's stated purpose is that the agent
  actually opened every labelled sheet; matching each Read's `tool_use_id` to a non-error
  `tool_result` in the user records would close it. (Did not affect NECR's 12 batches as far as the
  committed log shows, 41 reads each; it is a hole in the guard, not a measured failure.)

- **[fragile, minor]** `scripts/landcover_accuracy/labels_import-model.R:153` — `file.copy(out_csv,
  f, overwrite = TRUE)`'s FALSE return is ignored and the next line reports success. Consequence is
  bounded (if `labels.csv` is then missing, `accuracy_estimate.R` refuses; if it existed it had to
  equal the hash already), but the message can claim a publish that did not happen. Check the return
  or re-hash `f` after the copy.

- **[note, not blocking]** `research/landcover_accuracy.md:532` still says "a dated capture within
  +/-1 year supports `high` or `medium`", contradicting rule 5 as widened to ±2 years in this branch
  (line 276-278). It sits in "Review setup", outside the `## Labelling key` section that
  `fp_acc_labelling_key()` extracts, so neither labeller's key is affected; it is a stale sentence in
  the pre-registration document.

No security issues. No defect found in the gate arithmetic (kappa, change agreement, abstention
over B's labelled points), the sheet plan/blinding, the CSV extraction, or the transcript path audit.
