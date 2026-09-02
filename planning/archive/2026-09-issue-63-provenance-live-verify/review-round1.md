# Review round 1 — #63 (stale bridge key + provenance completeness guard)

## Scope note (read this first)

The diff I was handed as "staged" was **committed mid-review** as `38be063`, and the
committed files are **newer than the staged version**. `git diff --cached` is now empty
and the working tree is clean. I re-reviewed against the committed state, which is what
ships.

Two findings I had against the staged version are **already fixed in `38be063`** and are
recorded here only so the parent knows they were checked, not as open items:

- `paste0("floodplain[", character(0), "]")` returns the length-1 phantom `"floodplain[]"`.
  Measured. Now guarded by the `if (length(run_ids))` conditional plus an explicit `bad()`.
- `identical(NA_character_, NA_character_)` is `TRUE`, so a hash absent from **both** files
  read as agreement. Measured. Now guarded by `scalar()`.

Everything below is against `38be063` as committed.

---

## Findings

### 1. `[fragile]` The inventory derives its expectation with a **different CSV parser** than the pipeline uses — and the disagreement fails toward PASS

`scripts/floodplain_lcc/provenance-check.R:468`
`scripts/floodplain_lcc/provenance_ab-compare.R:69`

```r
# read.csv, not readr: readr's trim_ws default silently strips meaningful whitespace, and the
# `run` column must be compared as the literal the file carries.
sc  <- utils::read.csv(file.path(cfg_dir, "flood_scenarios.csv"), stringsAsFactors = FALSE)
sel <- toupper(as.character(sc$run)) == "TRUE" & sc$species == sp
```

The producer reads the same file with a different reader. `scripts/run_area.R:39`
uses `readr::read_csv()`, and `scripts/floodplain_lcc/02_floodplain_model.R:138`
selects with `all_scenarios$run == TRUE`. So the expected set and the actual set are
**one fact derived twice, never reconciled** — the exact shape `code-check.md` records
under "One fact derived twice, never reconciled".

Two things are wrong here:

**(a) The stated rationale is factually inverted.** `read.csv` runs `type.convert()`, so
on every committed config the `run` column arrives as **`logical`**, not as the file's
literal. Measured across all 20 `config/*/flood_scenarios.csv`: `class(d$run)` is
`logical` in all 20. `as.character(sc$run)` is therefore reconstructing `"TRUE"`/`"FALSE"`
from a parsed logical — it is not "the literal the file carries", which is what the
comment says the choice buys. The comment is load-bearing (it explains why a future
reader must not switch to readr) and its premise does not hold.

**(b) The two parsers disagree on whitespace, and the disagreement is silent.** Measured:

```
scenario_id,species,run
co_ff02,co, TRUE          <- one leading space
co_ff04,co,TRUE
```
```
read.csv run class: character   values: ' TRUE', 'TRUE'
readr   run class: logical      values: TRUE, TRUE
check would expect: co_ff04
02 would run      : co_ff02, co_ff04
```

`02` runs and writes provenance for **two** scenarios; the guard expects **one**. The
extra entry lands in `extra` at `provenance-check.R:488`, which is reported with `ok()`,
not `bad()` — so the run reports `all 2 config-derived entries present` and **exits 0**.
A scenario the pipeline actually ran is invisible to the completeness guard that exists to
catch exactly that.

The mirror direction also exists and is loud rather than silent (`run` = `T`: `read.csv`
converts to `TRUE`, readr leaves character `"T"` which `== TRUE` is `FALSE`, so the guard
reports a false `MISSING`).

Latent today — no committed config has whitespace or a `T`/`Y` shorthand in `run`, and I
verified `read.csv` and `readr` produce identical `run_ids` for all 20 areas right now. But
this is a guard whose whole purpose is closing a fail-toward-pass hole, and it has one of
its own.

**Fix:** derive the expectation the same way the producer does — either `readr::read_csv()`
in both new call sites, or better, `source()` `run_area.R`'s `fp_read_config(area)` and read
`cfg$scenarios` / `cfg$species` / `cfg$primary_scenario` from it, so the guard cannot
re-implement the resolution at all. `§7b` currently re-derives the `FP_SPECIES` /
`FP_PRIMARY_SCENARIO` / `<sp>_ff04` chain by hand in two files; that is three copies of one
rule.

---

### 2. `[fragile]` The 03 fix widens the path on which a **stale `patch_watercourse_*` layer survives** in the gpkg

`scripts/floodplain_lcc/03_lulc_classify.R:249-253`

```r
ov_ha <- as.numeric(sf::st_area(inter)) / 1e4
keep  <- round(ov_ha, 4) > 0
inter <- inter[keep, , drop = FALSE]
ov_ha <- ov_ha[keep]
if (nrow(inter) > 0) {
```

The core fix is correct — I verified the edge cases rather than reasoning about them:

- `st_area()` on a 0-row `sf` returns a length-0 numeric, no error (previously this call
  was inside the `nrow > 0` guard and now runs unconditionally — safe).
- `inter[logical(0), , drop = FALSE]` -> 0 rows.
- all-`FALSE` `keep` -> 0 rows, `nrow(inter) > 0` skips.
- `keep` and `ov_ha` are filtered by the same vector in the same statement pair, so they
  cannot desynchronise the way `pk` did.
- The output is unchanged as claimed: zero-area rows contribute `overlap_ha = 0`, so
  removing them before `tapply(bridge$overlap_ha, pk, sum)` leaves `tot_ov` and therefore
  every `apportion_weight` identical.

The regression is in the skip: previously, when `inter` had rows but **all** of them were
zero-area, the code built `bridge`, filtered it to 0 rows, and still called
`st_write(..., delete_layer = TRUE)` — which **replaced** any `patch_watercourse_*` layer
left by an earlier run. Now that case exits at `nrow(inter) > 0` and writes nothing, so a
stale bridge layer from a prior run persists in `<area>_lulc.gpkg` beside a freshly-written
`transition_*` layer, silently mismatched.

This is the `#55` "legacy layers do not clean themselves up" class riding in on `#23`'s
per-layer write. Reachability is low (it needs every patch/watercourse pair to round to
0.0000 ha), but the fix moved the boundary in the direction that leaves stale data rather
than removing it.

**Fix:** if the intent is "no pairs => no bridge layer", delete any existing
`patch_watercourse_*` layer explicitly in that branch, so the gpkg cannot carry a bridge
that does not correspond to the transition layer next to it.

---

### 3. `[fragile]` Both new checks build repo paths relative to CWD while the rest of the repo uses `here::here()`

`provenance-check.R:459` (`file.path("config", area)`)
`provenance_ab-compare.R:61` (`file.path("config", area)`)

`run_area.R:34` and `:50` use `here::here("config", area)` / `here::here("data", area)`.
The new code does not, so both scripts only work with CWD at the repo root. The failure
direction is loud (`bad()` -> exit 1), so this is not a fail-toward-pass — but it will
misreport the cause as *"no config/<area> -- cannot derive the expected entry set"* when the
real cause is the working directory, and it is a one-word fix given `here` is already a
dependency. `§7`'s pre-existing `file.path("data", area, ...)` has the same shape.

Worth noting because the repo's own conventions prescribe worktree-per-session, which makes
"invoked from somewhere other than the checkout root" a routine rather than exotic case.

---

### 4. `[fragile]` `provenance_ab-compare.R` double-counts an absent hash, inflating the reported problem count

`scripts/floodplain_lcc/provenance_ab-compare.R:112-123`

An absent `inputs_hash` increments `FAILS` twice: once via `bad()` at line 113, and again
via `if (!same) FAILS <- FAILS + 1L` at line 122 (because `same` is `FALSE` whenever
`scalar(hx)` is). Same for `datetime_utc` at 115/123. The exit status is correct; only the
`FAIL — N problem(s)` line is wrong. Measured on a crafted pair: one defect on one entry
reported as `2 problem(s)`.

Minor, but a count that overstates trains people to discount it, and the repo's own
conventions treat reported counts as evidence.

---

## Checked and clean

- **`§7b` NA-safety** — `sel` is now wrapped in `which()`, so an `NA` in `run` or `species`
  cannot subset to an `NA` element. I confirmed the unguarded form does produce
  `floodplain[NA]` (`c("a","b")[c(TRUE, NA)]` -> `"a" NA`). No committed config has an NA
  today; the guard is correct for when one appears.
- **`prov_sections()` on a zero-section file** — `vapply(list(), ..., "")` returns
  `character(0)`, `setdiff(want, character(0))` is `want`, so `§7b` fails loudly rather than
  vacuously. `§7`'s explicit `n == 0` branch already covers the "loop over nothing exits 0"
  case.
- **The network key mirrors the producer** — `01_network_extract.R:283` writes
  `paste0(species, min_order)` using `cfg$min_order` from `area.yml`, which is exactly what
  `§7b` reconstructs. Note `flood_scenarios.csv` also carries a `min_order` column; the
  check correctly does **not** use it.
- **The landcover key mirrors the producer** — `03_lulc_classify.R:350` keys on
  `scenario_id`, and `§7b`'s `ps` resolution reaches the same value as `run_area.R:58-62`
  despite ordering the env override and the `<sp>_ff04` default differently.
- **No early `next` in 02's scenario loop** before `fp_prov_set()` at
  `02_floodplain_model.R:204`, so every selected scenario does get an entry — the inventory's
  expectation is not over-strict.
- **`[[` used throughout both new blocks**, never `$`, on parsed-JSON lists. The partial-match
  trap (`x$link_log` -> `link_log_note`) is genuinely avoided.
- **`substr()` on an absent value** — no longer reachable; `hx`/`hy` are replaced with
  `"<absent>"` before the `substr()` at line 121. (`substr(NA_character_, 1, 24)` would have
  returned `"NA"` rather than erroring anyway.)
- **`FAILS <- FAILS + 1L` inside the top-level `for` loop** — correct, a top-level `for` does
  not create a new environment, so this assigns in `globalenv()` alongside `bad()`'s `<<-`.
- **`round(ov_ha, 4) > 0`** preserves the previous filter exactly (`overlap_ha` was
  `round(ov_ha, 4)`), consistent with the 4311-row reproduction in the commit message.
- **No credentials, no secrets, no shell interpolation** in any of the three files.
