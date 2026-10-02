# Code-check round 2: #103 lookback overlays (staged diff)

Reviewer: subagent, 2026-10-02. Scope: the staged diff only (config/disturbance.yml, fp_disturbance.R,
disturbance-check.R, fire_tag.R, 03_lulc_classify.R tagging block, run_area.R fp_read_config,
fire_load-prior.sh comment). Unstaged landcover_accuracy changes were ignored.

## Findings

- **[severity: fragile]** `scripts/floodplain_lcc/disturbance-check.R:337-340` (live section,
  `for (s in c(dst$context, dst$lookback))` → `ok("in_%s tagged something ...", sum(in_c %in% TRUE) > 0)`).
  Extending the "tagged something" arm from `context` to `lookback` makes the live check FAIL on
  correctly tagged areas that simply have no 2002–2016 fire in their floodplain. Wetlands are
  near-universal, but prior fires are not.
  - **Measured, read-only:** ran `.dst_fetch()` with the real `fire_prior` entry against the live DB,
    over the first transition layer of every area in `data/`. **9 of 23 areas hit zero patches**:
    bowr, lsal, mcgr, mork, sloc, tabr, ufra, unth and will.
    - The fetch itself returned polygons in each of those areas' bboxes (10–51 per area), so the
      zeros are real absences, not a missing load.
    - Hits elsewhere: necr 314, lchl 305, fran 190, pcea 101, lnth 99, pine 64, kotl 46, kisp 38,
      morr 36, bulk 26, thom 16, larl 11, pars 6 and neexdzii 5.
  - **Consequence:** once any of those 9 areas is re-run through step 3 or `fire_tag.R`, running
    `disturbance-check.R <area>` reports `1 FAIL` and exits 1 on correct output.
    - That is the verification gate for a re-tag. Either it gets ignored ("known false FAIL"), which
      trains people past a real failure, or it blocks a legitimate run.
  - The detection the arm wants is "the pre-2017 rows were never loaded". The layer cannot answer
    that, because an area with no prior fire looks identical to it.
  - **Fix options:**
    - keep the arm for `context` only, and for lookback assert DB-side that the table has rows in the
      derived window;
    - or downgrade the lookback arm to INFO.
  - The `carry set exactly where in_<name> is TRUE` and `typed, not Boolean` arms remain valid for
    zero-hit areas: the typed NA comes from the zero-row fetch.

## Verified (no issue)

- `Rscript scripts/floodplain_lcc/disturbance-check.R` (offline): **ALL PASS**. The worktree equals
  the index for every file under review.
- **The round-1 fix.**
  - `Inf`, `-Inf`, `1e10`, `NA_integer_`, `0`, `-5`, `2.5`, `"15"` and `c(10, 15)` are all refused
    by the classed config error.
  - `!is.finite()` sits before the comparisons, so `NA` short-circuits instead of raising a plain
    "missing value" error. Without it, the NA arm would go red, because `refused()` requires the
    class.
  - A YAML `lookback: [15]` parses to `15L` and is accepted, which is harmless.
- **The real config builds the expected SQL:**
  - `SELECT fire_year AS fire_prior_year, fire_number AS fire_prior_number, geom AS geom ... WHERE fire_year BETWEEN 2002 AND 2016`.
  - The sources are unchanged and carry no alias.
  - `lookback:`, `lookback: []` and `lookback: {}` all validate. A lookback written as a single map
    rather than a list is refused.
- **`.dst_window` and a source's `window` override.**
  - A lookback is derived from `min(change interval)`, never from a source override. It is therefore
    immune to an unsorted `change_interval`.
  - The validator refuses `window` on a lookback, and `lookback` on a source or context entry.
  - A future source override that reaches back into the lookback years could not double-count. The
    report computes the lookback share only over `!any_in`, the residual.
- **The report.**
  - `lookback = NULL` (no `lookback:` in the yml): `vapply(NULL, …, character(1))` is `character(0)`,
    so there is no error and no line.
  - A lookback entry passed as a source is refused. A lookback whose `in_` column is missing is
    refused, not read as 0 ha.
- **`fire_tag.R`.**
  - `cause_cols` is built from `sources:` only, so new lookback columns never trip compare-before-write.
  - The `fire` cause columns cannot move from the appended pre-2017 rows: its SQL is windowed to
    2017–2023, and the in-window md5 is proven unchanged in the committed log.
  - Item keys stay last.
- **Partial matching.** `cfg[["lookback_overlays"]]` / `cfg$lookback_overlays` collide with no other
  cfg key, and the sweep passes. Entry fields are read with `[[`. The committed readers of `in_*`
  columns use `[[` or `%in% names()`: readme_functions.R, fp_accuracy.R and sample_draw-pilot.R.
- **`fire_load-prior.sh`.** The staged change is comment-only, and the recovery `DELETE ... WHERE fire_year < 2017` is exact.
  - The script refuses to run when any `< 2017` row exists, so pre-load the count is 0 and the DELETE removes only what it added.
  - `pipefail` makes a bcdata failure abort the `bcdata | sed` pipeline under `set -e`.
  - The redaction regex covers the only URL form bcdata logged.
  - The committed log `scripts/fwapg/logs/20261002_000925_bc2pg_append_fire-prior.log` contains no
    credentials.

## Verdict

One fragile finding: the live check falsely fails on 9 of 23 current areas once they are re-tagged.
No bugs in the tagging, validation, SQL or report paths.
