# Review round 2 — #63 (reviewing round 1's fixes)

Reviewed against `HEAD` = `38be063` plus the working-tree changes to three files
(`git diff HEAD` and `git diff --cached` are identical here). Every claim below was
measured, not read.

## Round 1's four fixes — verified

| # | fix | verdict |
|---|---|---|
| 1 | reader parity (`readr::read_csv` + `run == TRUE`) | **correct**, measured below |
| 2 | `st_delete` branch when `nrow(inter) == 0` | correct for the path it covers; two gaps, findings 1 and 2 |
| 3 | `fp_root` resolver | depth and all four realistic invocations correct; finding 3 |
| 4 | `hx_ok`/`hy_ok`/`dx_ok`/`dy_ok` flags | **correct**, measured below |

**Fix 1 measured.** Built a CSV with one ` TRUE` cell and ran all three derivations:

```
read.csv run class: character   values: ' TRUE','TRUE','FALSE'
readr    run class: logical
OLD guard (toupper == "TRUE"): co_ff04
NEW guard (readr, run == TRUE): co_ff02,co_ff04
PRODUCER (02_floodplain_model.R shape): co_ff02,co_ff04
```

Guard and producer now agree by construction — same reader, same comparison. The
`which()` change is also strictly safer than the producer: a tibble with an `NA` `run`
cell subsets an all-`NA` row in at `02_floodplain_model.R:138` and carries it through the
species filter (measured), where the guard drops it. That divergence fails toward a loud
producer crash, not toward a silent guard pass.

**Fix 4 measured.** Removed one `inputs_hash` from a copy of
`data/neexdzii/provenance.json` and ran the comparator:

```
  FAIL   floodplain[co_ff02]: inputs_hash absent or not a scalar string in B
FAIL — 1 problem(s).     (was 2 before the fix)
EXIT=1
```

Every failure path counted exactly once, checked by hand across all eight combinations of
(hash absent / present-and-equal / present-and-differing) x (datetime absent / moved /
static). The `else if` chains at `provenance_ab-compare.R:133-140` are two independent
chains, both reachable, and `FAILS <- FAILS + 1L` at top level inside the `for` assigns to
the same global `FAILS` that `bad()`'s `<<-` reaches. Exit status is non-zero for every
real failure (`A vs A` -> 5 problems, exit 1; `A vs B` -> exit 0).

**Fix 3 measured.** The `../..` depth is right and the resolver survives a relative
`--file=`, because `normalizePath` resolves the relative result against the same CWD the
relative `--file=` was written against:

```
abs path,   cwd=/tmp            -> /private/tmp/fakerepo
rel path,   cwd=repo root       -> /private/tmp/fakerepo
rel path,   cwd=repo parent     -> /private/tmp/fakerepo
bare name,  cwd=script dir      -> /private/tmp/fakerepo
```

`Rscript /path/to/provenance-check.R morr` from `/tmp` now resolves
`/Users/airvine/Projects/repo/floodplains/data/morr/provenance.json` and exits 1 on the
missing file; `neexdzii` passes and exits 0.

---

## Findings

### 1. `[fragile]` `st_delete`'s return value is discarded, and the message asserts a removal that may not have happened

`scripts/floodplain_lcc/03_lulc_classify.R:261-262`

```r
sf::st_delete(out_lc_gpkg, layer = b_lyr, quiet = TRUE)
message("  Removed stale ", b_lyr, " -- no watercourse overlap this run")
```

`sf::st_delete` is `invisible(CPL_delete_ogr(...) == 0)` — it **returns `FALSE`, it does
not error**, and with `quiet = TRUE` the only trace is a GDAL warning. Measured on a
read-only GeoPackage:

```
delete on RO file -> logical  value: FALSE
layers still: transition_x_2017_2023          <- the layer survived
```

So a delete blocked by permissions, a locked file, or a GDAL driver failure leaves the
stale bridge in place while the run prints `Removed stale patch_watercourse_...`. The
unconditional message is what makes this fail toward pass rather than being a silent
no-op: the log makes an affirmative claim the code never checked, which is the
"a wrapper's exit 0 is not the work completed" class in `code-check.md`.

Cheapest fix is to gate the message on the return:

```r
if (isTRUE(sf::st_delete(out_lc_gpkg, layer = b_lyr, quiet = TRUE)))
  message("  Removed stale ", b_lyr, " -- no watercourse overlap this run")
else
  warning("could not remove stale ", b_lyr, " from ", out_lc_gpkg)
```

Note `01_network_extract.R:228` has the same unchecked shape, but it prints no claim, so
it is a silent no-op rather than a false report. The new call is the one that speaks.

### 2. `[fragile]` The stale-bridge fix closes the rarer of two paths to the same orphan — and the other one is a supported one-line region edit

`scripts/floodplain_lcc/03_lulc_classify.R:214-216` (the gate) vs `253-263` (the fix)

The delete lives **inside** the block it is meant to protect:

```r
attr_lyr <- if (!is.null(cfg$attribute_by))
  paste0(scenario_id, "_by_", cfg$attribute_by) else NA_character_
if (!is.na(attr_lyr) && file.exists(fp_file) && attr_lyr %in% sf::st_layers(fp_file)$name) {
  ...
  if (nrow(inter) == 0 && ...) sf::st_delete(...)      # <- only reachable inside
```

There are three ways to reach "no bridge is written this run", and the fix covers one:

| path | covered |
|---|---|
| all intersection pairs round to 0.0000 ha | **yes** (the round-1 finding) |
| `cfg$attribute_by` is `NULL` | no — whole block skipped |
| the `<scenario>_by_<key>` layer is absent from `floodplain.gpkg` | no — whole block skipped |

The transition layer at line 195 is rewritten in all three cases, so paths 2 and 3 leave
exactly the artifact the fix's own comment describes: "an earlier run's bridge ... sitting
beside a freshly written transition layer, describing a relation this run did not find."

Path 2 is not exotic. `attribute_by` is in `FP_REGION_OWNED`
(`scripts/floodplain_lcc/fp_region.R:39-40`), and region-owned keys are **stripped and
re-applied, not merged** — the file's own comment says a dropped key "actually clears it
downstream". So deleting one line from `config/regions/fraser.yml` clears `attribute_by`
in all 10 groups' `area.yml` on the next region run, and every one of them then re-runs
step 3 keeping a `patch_watercourse_*` table that no longer corresponds to anything. All
17 area configs currently carry `attribute_by`, so all 17 are exposed.

Hoisting the cleanup out of the gate covers all three paths with the same code:

```r
b_lyr <- sub("^transition_", "patch_watercourse_", lyr)
wrote_bridge <- FALSE
if (!is.na(attr_lyr) && ...) { ... wrote_bridge <- nrow(inter) > 0 ... }
if (!wrote_bridge && file.exists(out_lc_gpkg) && b_lyr %in% sf::st_layers(out_lc_gpkg)$name) {
  ...delete...
}
```

`b_lyr` is safe to compute unconditionally: `lyr` is only ever assigned
`paste0("transition_", ...)` at line 161 within this block, so the `sub()` always
rewrites it and can never resolve back to the transition layer itself.

### 3. `[fragile]` `fp_root` roots the guards on the script's path while every producer roots on `here::here()` — and `provenance_ab-compare.R` now mixes the two

`scripts/floodplain_lcc/provenance-check.R:37-40, 436, 470`
`scripts/floodplain_lcc/provenance_ab-compare.R:49-53, 72`

The fix is right about the failure it targets (a CWD-relative `config/<area>` from a
foreign tree), and it is an improvement in the common case. But it makes the guards the
only scripts in the repo that do not use `here::here()`:

```
run_area.R:33,49        here::here("config"/"data", area)
run_region.R:145,152,159 here::here("data", ...)
attribute_tag.R:30,46   here::here(...)
fire_tag.R:21,32        here::here(...)
provenance-check.R      fp_root  <- <script dir>/../..
```

Two consequences worth knowing about:

**(a) The guard can verify a different checkout's data than the run produced.**
`here::here()` answers from the CWD's project root; `fp_root` answers from wherever the
script file lives. Under this repo's worktree-per-session convention those are different
directories. `cd ~/repo/floodplains-63 && Rscript ../floodplains/scripts/floodplain_lcc/provenance-check.R morr`
checks `~/repo/floodplains/data/morr/provenance.json` — the *other* checkout's file. If
that older copy is complete, the guard passes and the run that was actually being verified
is never looked at. Most cross-tree invocations fail loud with `no provenance.json`, so
this needs both checkouts to hold data, but that is the direction that fails toward pass.

**(b) `provenance_ab-compare.R` now resolves its two arguments and its config from
different roots.** `a[1]`/`a[2]` stay CWD-relative (line 33) while `config/<area>` is
`fp_root`-relative (line 72), so the same command can compare provenance from one tree
against the scenario set of another. Where the two configs differ, a scenario present in
the data but absent from the *other* config lands in `extra`/is simply not in `want`, and
the inventory check does not see the miss.

Measured edge case, for the record: invoked through a symlink outside the repo,
`fp_root` resolves to `/private` (`--file=/tmp/bin/probe.R` -> `dirname` -> `../..`). That
one fails loud (`no config/<area>`), so it is not a correctness risk, only a confusing
message.

Suggestion: keep `fp_root` but derive it the way the producers do when a project root is
findable, so the two agree — e.g. prefer `here::here()` and fall back to the script-path
form only when `here` cannot resolve. If the script-path form is kept deliberately, it is
worth a line in the comment saying it intentionally differs from `here::here()`, because
the comment currently reads as though CWD-rooting were simply wrong, which is what the
rest of the repo does.

Minor, related, not itself a defect: the `here::here()` fallback in `provenance-check.R`
is unreachable. It only fires when `commandArgs(FALSE)` carries no `--file=`, and the
`source(...fp_provenance.R)` at lines 28-29 builds its path from the same expression and
errors first in exactly those invocations (measured: `R -f script.R` and
`Rscript -e 'source(...)'` both yield no `--file=`). Fine as written, but the fallback has
never executed there, so it is unverified if that `source()` line ever moves.

---

## Not flagged (checked, and correct)

- `b_lyr` cannot collide with the transition layer: `lyr` is always `transition_*`
  (line 161), so `sub("^transition_", ...)` always rewrites it.
- `out_lc_gpkg` (line 138) and `lyr` (line 161) are both in scope at line 253.
- `st_delete` on a layer that does not exist returns `TRUE` and is a no-op, so the
  `%in% st_layers()$name` guard is belt-and-braces rather than load-bearing.
- `st_layers()` on the gpkg is safe there — `st_write` of the transition layer has already
  returned and closed its handle.
- `readr` and `here` are both installed and are already hard dependencies via `run_area.R`,
  so `::` without attaching is fine.
- `sc$run`/`sc$species` on a tibble do **not** partial-match (unlike the previous
  `read.csv` data.frame), which is a strict improvement: a renamed column now yields
  `NULL` and a loud `bad("no run==TRUE rows")` instead of silently matching a sibling.
- `grep("^--file=", commandArgs(FALSE))[1]` picks R's own `--file` even if a user passes a
  literal `--file=` argument, because R's copy precedes `--args`.
- `normalizePath(..., mustWork = FALSE)` is silent on a non-existent path (no warning).
- The `extra`-reported-with-`ok()` behaviour is the documented #23 tradeoff and was not
  re-examined.
