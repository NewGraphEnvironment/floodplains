# Round 4 — stop-condition check for #77

**Verdict: the stop condition does NOT hold.** Nine (b) rows still neither read their artifact,
nor `stop()`, nor carry a stamp — and one of them is a live silent-failure bug, not a latent one.
Two of the nine were introduced by round 3's own fixes.

Everything below was measured on this tree (R 4.5.2, sf 1.1.2, ggplot2 4.0.3, rmarkdown 2.31,
knitr 1.51, pandoc 3.9.0.2, `data/bulk/` present). Tree restored afterwards — verified by
`shasum -c` against a pre-review baseline for `README.md`, `index.html` and both PNGs.

---

## What was enumerated

Round 3's "22 literals" is a curated set, not a population. The mechanical population, comments
stripped:

| file | literals |
|---|---|
| `scripts/readme_functions.R` | 110 string + 60 numeric |
| `scripts/readme_content-check.py` | 81 string (docstrings and comments removed) |
| `scripts/readme_determinism-check.sh` | 54 quoted tokens |
| `README.Rmd` | 11 R chunks: `setup` `source` `build` `figs` `badges` `fig-floodplain` `fig-attribution` `scenarios` `scenarios-run` `roster` `citekeys` (the prompt's 12 counts one twice) |

Filtering that population to literals **whose truth depends on another artifact** gives **29
substantive rows**, not 22. Round 3 undercounted by 7 — the seven it missed are the figure
titles/subtitles and the two `fig.alt` strings, i.e. every literal that lives inside a *string
that gets printed* rather than inside a *value that gets used*. That is the axis round 3's
partition did not cover, and it is where the class went on recurring.

### The partition

**(a) contracts this repo chose — correctly hardcoded (13)**

`FIG_DIR`, `FIG_AREA`, `FIG_INSET`, `PAL_*`, `UNATTRIBUTED`, the three config path roots,
`3005`, `TARGETS`, `CATALOGUE_FACTS`, `DOI_PREFIX`/`CROSSREF`, `FILES`, `num_word`'s word vector.
All fine.

**(b) facts about another artifact, and it `stop()`s or reads on divergence (7) — fine**

| row | artifact | behaviour on divergence |
|---|---|---|
| `FIG_SPECIES <- "co"` | `config/bulk/area.yml: species` | `fp_readme_scenarios()` stops: "no rows for species" ✓ |
| `"3"` in `streams_co3` (L196) | `area.yml: min_order` | `st_read` fails on a missing layer ✓ |
| `"_2017_2023"` (L253) | `cfg$change_interval` | `st_read` fails ✓ (measured: `Cannot open layer transition_co_ff06_2017_2023`) |
| gpkg filenames | steps 1–3 | `fp_fig_read` stops with a written explanation ✓ |
| `"Trees"` (L260) | drift class names | `if (!nrow(tl)) stop(...)` ✓ |
| region keys (L66) | `run_region.R` schema | explicit per-key `stop()` ✓ |
| `named` 3 citekeys (README.Rmd L340) | the CSV | explicit `stop()` ✓ |

**(b) unavoidable, stamped (2) — fine**

`stac-floodplains-bc` and `INBOUND_ANCHORS` both carry `SOURCE, verified 2026-09-04` naming the
exact file. Confirmed.

**(b) on the WRONG side (9) — below.**

---

## Findings

### 1. `[bug]` scripts/readme_functions.R:187,203 — `FIG_PRIMARY` is asserted to be a member of a set that is now derived, and nothing checks it. The overview panel loses the floodplain **silently**.

Round 3's fix #6 correctly derived `scen` from `flood_scenarios.csv`. `primary` was left as a
literal that must be a *member* of that derived set:

```r
scen    <- sprintf("ff%02d", sc$flood_factor)   # derived from the CSV, run == TRUE only
primary <- sub("^.*_", "", FIG_PRIMARY)         # a literal
ggplot2::geom_sf(data = ff[[primary]], ...)     # ff[["ff08"]] is NULL
```

`ff[[primary]]` returns `NULL` when `primary` is not in the run set, and `geom_sf(data = NULL)`
inherits the plot's (empty) data and produces a **zero-row layer with no error and no warning** —
measured directly:

```
geom_sf(data=NULL) over an empty base plot: built OK; layers=2, layer2 rows=0
```

Restored the bug end-to-end with `FIG_PRIMARY <- "co_ff08"` and rebuilt: **the figure wrote
successfully, 373,719 bytes, no error, no warning.** The left panel is the watershed group and the
stream network with the entire dark floodplain ribbon gone, under a subtitle that still reads
*"Bulkley group: the coho-accessible network, and its ff08 floodplain"* and a title that still
reads *"Where the model puts the floodplain"*. It would go straight into `README.md` and
`index.html`.

Two reachable paths, and the second is one the README **invites**:

- `config/bulk/area.yml` carries `primary_scenario: co_ff04`. Change it there (the pipeline reads
  it; `readme_functions.R` does not) and this fires.
- Flip `co_ff04`'s `run` column to `FALSE`. README.md line 131 says, in the repo's own words:
  *"Turning one on is a `run` column edit, not a code change."* Turning one off is the same edit.

The function's own comment at L176–179 states the reason for the derivation: *"the figure would
quietly stop matching its own caption."* That is precisely what still happens, one variable over.

**Fix:** derive `primary` and assert membership.

```r
primary <- sub("^.*_", "", FIG_PRIMARY)
if (!primary %in% scen) {
  stop("FIG_PRIMARY (", FIG_PRIMARY, ") is not among the scenarios with run = TRUE in config/",
       FIG_AREA, "/flood_scenarios.csv (", paste(scen, collapse = ", "), ") — the overview panel ",
       "would draw no floodplain and say nothing about it", call. = FALSE)
}
```

### 2. `[fragile]` scripts/readme_functions.R:269 — `fp_fig_attribution()` hardcodes `_ff04` seventeen lines after deriving the same scenario from `FIG_PRIMARY`.

```r
tr   <- fp_fig_read("floodplain_landcover.gpkg",
                    paste0("transition_", FIG_SPECIES, "_", sub("^.*_", "", FIG_PRIMARY), "_2017_2023"))
...
ff04 <- fp_fig_read("floodplain.gpkg", paste0(FIG_SPECIES, "_ff04"))   # <- literal
```

The patches come from `FIG_PRIMARY`; the floodplain drawn underneath them is always `ff04`. Today
they agree. Measured the divergence path: with `FIG_PRIMARY <- "co_ff06"` the transition read
fails first (`Cannot open layer transition_co_ff06_2017_2023`) so today it is loud — but that is
an accident of `data/bulk/` only having been run at `co_ff04`. `run_area.R` with
`FP_PRIMARY_SCENARIO=co_ff06` is documented in this same README, and once both transition layers
exist the map draws `co_ff04` under `co_ff06` patches with nothing to notice. Use `FIG_PRIMARY`;
the variable is even named `ff04`.

### 3. `[fragile]` scripts/readme_functions.R:303 — the bar's subtitle hardcodes "fire and harvest" against the source list the round-3 fix just made dynamic.

```r
src <- fp_readme_sources()   # reads config/disturbance.yml
...
subtitle = "fire and harvest are what config/disturbance.yml lists today — it takes any layer"
```

Fix #5's stated purpose (`readme_functions.R:40-43`) is that enabling the commented-out `pest`
source must not leave *"the caption still claim[ing] to describe that file"*. Uncomment `pest`
and the plot is now correct — three causes, three colours — while **this caption becomes false**.
The fix moved the defect out of the data and into the string beside it. One line closes it:
`sprintf("%s are what config/disturbance.yml lists today — it takes any layer", paste(src, collapse = " and "))`.

Same class, same figure: `README.Rmd:121` `fig.alt` says *"red for fire, yellow for harvest"* — a
copy of both `src` and `PAL_SOURCE`.

### 4. `[fragile]` README.Rmd:195 — round 3's fix #7 introduced a new hardcoded `config/bulk/` while the `citekeys` chunk 155 lines below derives the identical path from `FIG_AREA`.

```
L195 (prose, fix #7):  this table is read from `config/bulk/`, the group the figures above come from
L349 (citekeys chunk): cat(..., " more sit in the `citations` column of `config/", FIG_AREA, "/flood_scenarios.csv`")
```

This is the exact shape round 3 named: a fix replaced one literal and added another whose other
half lives in a file the code never opens. `` `r paste0("config/", FIG_AREA, "/")` `` costs
nothing and the file already demonstrates the pattern.

### 5. `[fragile]` scripts/readme_functions.R:186 — `sprintf("ff%02d", sc$flood_factor)` re-derives `scenario_id`, which the same frame already carries.

```
derived: ff02 ff04 ff06
csv    : ff02 ff04 ff06      (sub("^.*_", "", sc$scenario_id))
```

They agree today across all 23 `flood_scenarios.csv` (checked; `flood_factor` ∈ {1,2,4,6,8,12},
`run` ∈ {TRUE, FALSE} everywhere). But the CSV's authoritative column is `scenario_id`, and the
code reconstructs it from a *different* column plus a format string plus `paste0(FIG_SPECIES, "_", …)`.
Any scenario id that is not exactly `<sp>_ff<2-digit factor>` diverges. Using `sc$scenario_id`
directly also makes `primary` in finding 1 a plain `FIG_PRIMARY %in% sc$scenario_id`.

### 6. `[fragile]` README.Rmd:159-167 — the `access_gradient_max` table is a verbatim copy of a third-party file, with a source path but no date or version stamp.

Verified against the installed package — the table is **correct today**:

```
BT 0.25  CH 0.15  CM 0.15  CO 0.15  CT 0.25  DV 0.25  PK 0.15  RB 0.25  SK 0.15  ST 0.20  WCT 0.20
```
(`link/extdata/configs/bcfishpass/parameters_fresh.csv`, all 11 species accounted for.)

But this is a (b) row: the values live in `link`'s bundle, they can move with a `link` release,
and nothing in this repo would notice. Round 3's own stop condition is *"the two unavoidable ones
carry a source-and-date stamp"* — this is a third unavoidable one (reading it at render time would
make the README need `link` installed, which breaks the "no data, no database, no network"
promise) and it carries only the path. The measured-habitat table three paragraphs down does this
right (*"Measured 2026-09-03"*). Add `link` version + date.

### 7. `[fragile]` README.Rmd:87 — the `fig-floodplain` alt text hardcodes the scenario set the figure now derives.

> *"three flood-factor scenarios nested inside one another — ff02 the active channel margin, ff04
> the functional floodplain, ff06 the valley bottom"*

Three scenario ids, their count, and their `description` values — a fourth copy of a set that
`fp_readme_scenarios()` reads and that the README's own table renders eight lines further down.
Turn `co_ff08` on and the figure gains a fourth ring while the alt text still says three. Silent,
and it is the accessibility text, so nobody sees it go wrong. `fig.alt` accepts an R expression;
build it from `sc$scenario_id` / `sc$description`.

### 8. `[fragile]` scripts/readme_functions.R:208,284 — figure titles hardcode "Bulkley" and "2017–2023" beside variables that hold both.

`FIG_AREA` is `"bulk"`, `FIG_SPECIES` is `"co"`, and the change window is already spelled once at
L253. Three prose copies (`"Bulkley group: the coho-accessible network…"`,
`"Floodplain tree loss 2017–2023, Bulkley watershed group"`) plus the README's own
*"between 2017 and 2023"* (L82) and *"2017, 2020 and 2023"* (L104). Lowest-impact member of the
class, but it is the same axis as 3 and 7 and belongs in the same sweep — a WSG display name and
a `change_interval` string beside `FIG_AREA` would close all of it.

### 9. `[fragile]` config/disturbance.yml source ORDER is now silently load-bearing for the published percentages.

`for (nm in rev(src)) cause[isTRUE_col(...)] <- nm` makes the **first** entry in the YAML win.
That is `fire`, which is the right convention for salvage-after-fire, and the comment says so.
But the yml has no note that its list order decides the figure. Measured on BULK: 2 patches carry
both tags, and reversing the precedence moves **36.31 ha** between the buckets:

| precedence | fire | harvest | residual |
|---|---|---|---|
| fire wins (shipped) | 66.13 ha | 473.54 ha | 1025.40 ha |
| harvest wins | 29.82 ha | 509.85 ha | 1025.40 ha |

One line in `config/disturbance.yml` saying "order is precedence for single-cause reporting"
is the whole fix.

---

## Fixes 1–8: verified

| # | claim | result |
|---|---|---|
| 1 | `fp_readme_citekeys()` drops NA before `paste`; bulk 12, morr 12, kotl 0, ufra 0 | **confirmed exactly**, all four |
| 2 | `"Those three"` now derived via `num_word()` | confirmed — renders `Those three and 9 more` (README.md:247) |
| 3 | `num_word()` falls back to the numeral past its range | confirmed by reading: `w` is 11 long (0–10), `if (n >= 0 && n < length(w))` else `format(n)`; `n_run` maxes at 6 |
| 4 | `BYPRODUCTS` covers all five; arm 3 is the complement | **confirmed, and stronger than claimed** — see below |
| 5 | `fp_readme_sources()` reads the yml; builder stops on an untagged source; palette handles an unseen source | confirmed (`c("fire","harvest")`; `fp_cause_pal` falls back to `PAL_SOURCE[["other"]]`). Caption not fixed — finding 3 |
| 6 | `scen` + palette derived from the CSV | confirmed; palette ramped, subtitle counts. `primary` not derived — finding 1 |
| 7 | scenario table prose names `config/bulk/` | confirmed, and it introduced finding 4 |
| 8 | the two unavoidable literals carry source-and-date | confirmed, both `2026-09-04` |

**Fix 4, proved by restoring the bug.** Two runs, both with a `plot(1:10)` chunk injected into
`README.Rmd`:

- `BYPRODUCTS` shortened to the old three (`README_files index_files README.html`) — arm 2 FAILS
  (it names `README_files`), arm 3 FAILS reporting `!! README_files/`.
- `BYPRODUCTS` shortened so `README_files` is **not named** — arm 2 reports **`OK: rendering left
  no byproducts on disk`**, arm 3 FAILS with `+ !! README_files/`, script exits 1.

So arm 3 is a genuine complement and a stale `BYPRODUCTS` entry is no longer fatal. Bonus
property worth knowing: arm 1 also caught it, because `before_sha` is taken before the first
render — the check therefore also asserts *the committed artifacts match the current
`README.Rmd`*, which is not stated in the header and is worth a line there.

## The other requested checks

- **`ord <- rev(scen)` draw order.** Robust to CSV row order, and not by luck:
  `fp_readme_scenarios()` ends with `s[order(s$flood_factor), ]`, so `scen` is always ascending
  and `rev()` is always widest-first. Legend order is separately pinned ascending by
  `breaks = lab`. Confirmed in the rendered PNG: nested rings, legend reads
  `ff02 345 km² | ff04 387 km² | ff06 415 km²` — matching CLAUDE.md's 344.7 / 386.5 / 414.6.
  A differently-ordered CSV cannot break it.
- **Overview panel layer.** Draws `ff04`, correctly, today (see the image). The failure mode is
  finding 1, not the ordering.
- **`for (nm in rev(src))` precedence.** Correct as written — first yml entry wins, which is
  `fire`, which is the honest reading for salvage. The caption says "first matching source wins"
  and that is true. See finding 9 for the undocumented dependency.
- **Figure rebuild.** Rebuilt both from `data/bulk/` into a scratch directory: **byte-identical**
  to the committed PNGs (`9097f0da…` attribution, `730068c1…` floodplain). Percentages
  independently recomputed: **fire 66.130 ha / 4.23%, harvest 473.540 ha / 30.26%, residual
  1025.402 ha / 65.52%, total 1565.07 ha**, 2,101 `Trees →` patches. Matches the brief exactly.
- **Guards.** `readme_content-check.py` offline: `OK: anchors`, `OK: catalogue facts`.
  `CHECK_LINKS=1`: 9 of 10 URLs ok (2 DOIs via Crossref), one failure —
  `https://www.newgraphenvironment.com/floodplains/ -> HTTP 404`, the expected Pages-after-merge
  case and nothing else. `readme_determinism-check.sh`: all three arms OK in 4.1 s.
- **Re-render vs staged.** Both targets re-render **byte-identical** to the staged blobs
  (`3f7104ea…` README.md, `9b1efc2d…` index.html), and `git status` gained nothing.

## Minor, not filed as findings

- The canonical render invocation exists twice — `README.Rmd`'s `build` chunk (`eval=FALSE`
  documentation) and `readme_determinism-check.sh`'s `render()` (the executor). They agree today.
- `sc$run == "TRUE" | sc$run == TRUE` uses a raw logical index where the file defines `isTRUE_col()`
  ten lines earlier for exactly this hazard. An `NA` in a `run` cell would inject an all-`NA` row
  (verified). No shipped CSV has one — all 23 are `TRUE`/`FALSE` — and both consumers fail loudly
  (`ffNA` → `st_read` error; `num_word(NA)` → "missing value where TRUE/FALSE needed"), so this is
  a consistency note, not a defect.
- `planning/active/findings.md` carries an unstaged edit that predates this review (32 added
  lines, the round-3 mechanism write-up). Not mine, and not staged — worth a glance before commit.

## Restoration

`README.Rmd`, `scripts/readme_determinism-check.sh`, `README.md`, `index.html` and both PNGs all
restored and verified with `shasum -c` against the pre-review baseline. `README_files/` removed.
`git status` is identical to its pre-review state.
