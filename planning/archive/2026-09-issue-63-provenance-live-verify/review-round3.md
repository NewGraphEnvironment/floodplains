# Review — round 3 (reviewing the round-2 fixes)

Scope: staged diff at `scripts/floodplain_lcc/{03_lulc_classify.R, provenance-check.R,
provenance_ab-compare.R}`. Every claim below was measured, not read.

Verdict: **round-2 fix #1 does not close the hole it was written for.** Fix #2 is structurally
sound but its stated scope is one path short. Fix #3's mitigation was implemented in one of the
two scripts and asserted in both.

---

## Findings

### 1. [bug] `03_lulc_classify.R:306` — `isTRUE(sf::st_delete(...))` is TRUE for a delete that FAILED

Round 2's premise ("st_delete returns FALSE rather than erroring") is only half true, and the
half that was missed is the realistic one.

`sf::st_delete` is `invisible(CPL_delete_ogr(dsn, layer, driver, quiet) == 0)`. `invisible()`
only suppresses auto-printing, so `isTRUE()` does see the value — that part of the fix is fine.
The problem is what `CPL_delete_ogr` returns. Measured on the installed sf 1.1.2:

| arm | GDAL behaviour | `st_delete` returns | guard |
|---|---|---|---|
| layer deleted | — | `TRUE` | ok |
| layer does not exist | — | `TRUE` | (unreachable; `%in%` guards it) |
| dsn cannot be opened for update (read-only **file**) | `Data source not found` | `FALSE` | **caught** |
| dsn opens, the DROP statements fail (read-only **dir**, lock, partial failure) | `Deleting layer 'gone' failed` + 4 `GDAL Error 1` | **`TRUE`** | **MISSED** |

Reproduction (verbatim output, GDAL error lines elided):

```
before: keep,gone
Deleting layer `gone' failed
st_delete returned: TRUE   isTRUE -> TRUE
after : keep,gone
VERDICT: layer still present? TRUE
```

So on the realistic failure — a lock, a read-only parent directory, a half-completed drop — the
code takes the `message("  Removed stale ", b_lyr, " -- no bridge written this run")` branch while
the orphan is still in the gpkg. That is exactly the affirmative-claim-the-code-never-checked
class the comment at 301–305 names, reproduced inside the fix for it.

Worse, the one arm the guard *does* catch is close to unreachable in this code path: two
expressions earlier, line 300 already established `file.exists(out_lc_gpkg)` **and** succeeded in
opening it with `sf::st_layers()`. A dsn that cannot be opened at all has largely been ruled out
by the condition guarding the block.

**Fix: measure the output, not the return.** The return value is the library telling you what it
thinks it did; `st_layers()` is the file telling you what happened.

```r
sf::st_delete(out_lc_gpkg, layer = b_lyr, quiet = TRUE)
if (!b_lyr %in% sf::st_layers(out_lc_gpkg)$name)
  message("  Removed stale ", b_lyr, " -- no bridge written this run")
else
  warning("could not remove stale layer ", b_lyr, " from ", basename(out_lc_gpkg),
          " -- it describes a relation this run did not find",
          call. = FALSE, immediate. = TRUE)
```

CLAUDE.md, *"Measure the output, not the input you handed in"* and *"A wrapper's exit 0 is not
'the work completed'"*.

---

### 2. [fragile] `03_lulc_classify.R:309` — the warning is invisible in exactly the runs that need it

`warning(..., call. = FALSE)` with no `immediate. = TRUE`, under `Rscript`'s default
`options(warn = 0)`. Two measured consequences:

- **Deferred to the end.** It prints *after* `message("\nDone. Scenario: ...")` at line 398,
  detached from the layer it is about, at the bottom of a long step-3 log.
- **Collapsed away entirely past 10 warnings.** Measured with 11 unrelated warnings pending:

  ```
  Done. Scenario: co_ff04 -- outputs in data/neexdzii
  There were 12 warnings (use warnings() to see them)
  ```

  The text never appears. This is not hypothetical in the failure case: the failing
  `CPL_delete_ogr` emitted **4 GDAL warnings of its own** in the reproduction above, so the run
  that trips this guard is the run most likely to be over the threshold.

And nothing downstream reads it. `run_region.R:199` computes
`status <- if (rc != 0) "FAIL(run)" else if (is.na(km)) ... else "ok"` — purely the subprocess
exit code and the network length. `warning()` does not move `rc`, so a failed cleanup is recorded
as `ok` in the coverage CSV and reaches the publish hint.

The file already establishes the right pattern: line 107–109 uses `immediate. = TRUE` for the
analogous "do not publish this run" warning. Add it here.

---

### 3. [fragile] `03_lulc_classify.R:216–221` vs `:160` — the hoist reaches three of four paths

The comment asserts completeness:

> Three different things mean "no bridge this run" ... The cleanup therefore has to sit where all
> three paths reach it.

There is a fourth, and the hoist does not clear it. The entire block 161–311 is still inside
`if (nrow(trans_all$summary) > 0)` at line 160. A run whose transition yields zero change patches
skips the cleanup altogether and leaves the previous run's `patch_watercourse_*` in place.

What makes it worth reporting rather than shrugging at:

- `fp_prov_set(cfg, "landcover", scenario_id, ...)` at line 370 runs **unconditionally**, so the
  run stamps a fresh provenance record over a gpkg whose transition and bridge layers are both
  from an older run. Provenance and artifact disagree, and provenance is the half that gets
  published.
- Nothing catches it. `bridge-check.R` reconciles the stale bridge against the equally stale
  transition layer and passes — a consistency check with no external reference, which is the
  *"cross-item consistency check cannot see a defect that hits every item"* class in CLAUDE.md.

Not a regression (the transition layer had the same gap before this diff). The defect is that the
comment states a completeness claim that is wrong, and the comment is what the next reader will
trust. Either move the cleanup above line 160 keyed off the same `lyr` construction, or amend the
enumeration to say the zero-patch path is knowingly out of scope and why.

---

### 4. [fragile] `provenance_ab-compare.R:54–55` — the comment claims a mitigation the file does not have

Both guard scripts received the same rewritten comment block, ending:

> The resolved root is printed below so a wrong-tree invocation is visible rather than silent.

That is true in `provenance-check.R` (the `cat("   (repo root resolved from this script: ", ...)`
at line 442). It is **false in `provenance_ab-compare.R`** — `fp_root` appears at line 56
(definition) and line 79 (`cfg_dir`) and is never printed. Confirmed by grepping every `cat()` in
the file.

This matters more here than in the script that got the print, because the failure is quieter:

- Round 2 accepted the script-relative-`fp_root` divergence **on the strength of that print**. In
  ab-compare the tradeoff is now unmitigated while the comment says it is mitigated.
- Under worktree-per-session, the other checkout is a clone of the same repo and **also has
  `config/<area>/`**. So the wrong-tree case does not hit the `bad("no config/%s ...")` branch at
  line 81 at all — it silently derives `want` from the *other* tree's `area.yml` and
  `flood_scenarios.csv` and reports PASS or FAIL against the wrong expected entry set, with
  nothing on screen naming which tree answered. That is the exact fail-toward-pass the comment
  claims to have made visible.

Fix: add the same one-line `cat` (unconditionally near the top, or beside the `cfg_dir` use at
line 79 so it also prints on the `no config` branch).

---

### 5. [fragile] `CLAUDE.md:91` now contradicts the code

> `bridge-check.R` asserts it. Absent `attribute_by` ⇒ no bridge, step 3 unchanged.

After the hoist, absent `attribute_by` is one of the paths that reaches the cleanup and **deletes**
a pre-existing `patch_watercourse_*` layer. Step 3 is no longer unchanged in that case. This is
deliberate per the round-2 decision, but `attribute_by` is region-owned (`FP_REGION_OWNED`), so a
region file that drops it clears it in every group's `area.yml` — and the next step-3 run then
removes every group's bridge. That consequence is worth stating where the invariant is documented.

---

## Verified correct — no action

- **`wrote_bridge` scoping.** Lines 161–311 sit inside `if (nrow(trans_all$summary) > 0)`, not a
  loop. The `for (yr in names(classified_all))` at 142 closes at 154, and `lyr` is reassigned at
  161 after it, so `b_lyr` at 222 is derived from the transition layer name and cannot refer to a
  `classified_*` layer. No cross-iteration leak is possible.
- **Multi-species coexistence (#23).** `b_lyr` is `patch_watercourse_<scenario_id>_<yr1>_<yr2>` and
  `scenario_id` is species-prefixed, so a `co_ff04` run cannot delete `ch_ff06`'s bridge.
  A non-primary-scenario run computes a `b_lyr` that was never written, and the
  `b_lyr %in% st_layers(...)$name` guard stops the delete. No data-loss path found here.
- **`invisible()` and `isTRUE()`.** `invisible()` affects auto-printing only; the value is returned
  normally and `isTRUE()` reads it correctly. The defect in finding 1 is in `CPL_delete_ogr`'s
  return, not in the `isTRUE` wrapper.
- **`fp_root` in `provenance-check.R`.** `normalizePath(<script dir>/../..)` resolves the repo root
  correctly, and the printed value at line 442 is the same object used at 440 and 475, so the print
  is accurate for that script. The comment edits are comment-only in both files and break nothing.
