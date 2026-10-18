# Code-check round 3: branch 125-region-acceptance-fraser-peace-columbia (48fae86...HEAD, fixes through 80f9810)

Reviewer: subagent, 2026-10-17. Read-only on the repo apart from this file. Probes ran in the session
scratchpad (`r3_*`, `ord.R`, `pcea.R`).

## The mechanism

Every earlier finding has one assumption behind it: **a value is taken to describe its subject because of
where it was found, not because the producer stamped it with an identity the reader checks.** "Where it was
found" has meant the following:
- the last section in a log, where a missing FAIL line was read as PASS (r1);
- a line's shape (`^ *FAIL `, r1);
- the newest file or the next-newest file (r1, r2);
- the last command of a pipeline (`grep | sed || echo`, r2);
- a number or class carried over from memory or from a nearby measurement (the prose findings in r1 and r2).

The same assumption also covers labels written from the producer's *intent* (a parameter's value) instead of
from the artifact. The remedy is the same each time: read the identity the producer recorded (exit status,
record datetime, digest, terminating line), or measure the artifact.

## Checked and sound

- I re-ran the **current** `region_acceptance-report.R peace columbia` (after the round-2 tie). All 18 table
  rows are byte-identical to the committed logs, and every wall time survives the tie.
- I re-derived, from the on-disk logs, every check cell in the three logs under the current rules (`'^  FAIL '`
  count; `dst_section` under `/usr/bin/awk`). They match: 23/23 `all_ff04` sections PASS, provenance last line
  PASS in all 23, 21 species-layer sections with the two context-column FAILs, three bridge union FAILs.
- I listed every composition FAIL line: the bound is +1.11% (LARL) to +7.81% (WILL) outside PCEA (+225.39%),
  and NECR's check (5) is 12,809.04 vs 6,436.64. CLAUDE.md, the logs and findings.md state these correctly.
- I recomputed the outlier screen from `region_acceptance_20261017_174646.csv`: `fp_out_pct` median 1.728,
  IQR 1.124–2.416, only PCEA flagged; `km2_per_km` nothing flagged.
- Record order in all 23 groups: network < floodplain (all `all_*`) < landcover, all inside each group's CSV
  window. So no committed row mixes runs today.
- The runner's default `all_ff04` equals every group's `primary_scenario` **by construction**:
  `fp_region_owned` sets `paste0(sp, "_ff04")` with `sp = all`.

## Findings

- **[claim not supported]** `scripts/floodplain_lcc/region_acceptance-report.R:229`, the column header
  `patches >= 1 ha`, and the same header in all three committed logs (and CLAUDE.md's DUNC bullet, which
  echoes the count). The label describes the sieve's *parameter* (`patch_min_m2 <- 10000`,
  `03_lulc_classify.R:60-66`), not the rows. In every group, **78–94% of the rows the column counts are
  under 1 ha** (sqlite over `transition_all_ff04_2017_2023`):
  - PCEA: 1,397 of 1,565;
  - LCHL: 8,241 of 9,396;
  - UFRA: 10,134 of 10,799 (93.8%);
  - THOM: 2,007 of 2,564 (78.3%).

  `patch_id` is unique per row, so the rows are not pieces of one larger patch. The sieve runs on the raster
  component before per-class vectorisation, so a surviving component splits into many sub-hectare rows. A
  reader of "9,396 patches ≥ 1 ha" infers about 9,400 change events of a hectare or more. Rename the column,
  e.g. "change patches (after the 1 ha sieve)". Skeena's merged log carries the same label (`≥ 1 ha`, line 40).

- **[claim not supported]** `CLAUDE.md`, new block: "`region_acceptance-report.R <region>|all` derives
  **every** figure in those logs from disk." It derives the tables only. Several figures in the logs come from
  no committed code:
  - the area-weighted "true union" 0.9405 / 0.9610 / 0.9363, and CLAUDE.md's "0.94–0.96". findings.md says
    "measured ad hoc in this session".
  - PCEA's "83.6% … reservoir or large lakes" and the retired `bt_ff04`'s "92.1%" and "58.4%".
  - The DEM fetch ranges (11–42 / 30–42 / 22–52 s).
  - "1,700.3 ha … on the reservoir" (next finding).

  These are the numbers a future issue (#BRIDGE, #WATERBODY) will be written from, and the sentence tells a
  reader they can regenerate them. Scope it to "every table". Then either commit the ad hoc measurements as
  scripts, or mark them ad hoc where they are stated.

- **[claim — minor]** `logs/20261017_whole_network_peace.md` Checks bullet 1 and findings.md (round-2
  section): "1,700.3 ha of that change lies on the reservoir outside its polygon". 1,700.3 ha is the change
  outside the polygon; the report never measures how much of it is reservoir. Measured
  (`scratchpad/pcea.R`): **1,652.9 ha** of it falls on `waterbodies_all2` polygons that are manmade or over
  1,000 ha. That is an any-touch mask, so it is an upper bound. At least 47 ha is the ordinary #53 edge. Say
  "nearly all of it (about 1,650 ha)".

- **[fragile — the mechanism, still open in the report]** `region_acceptance-report.R:159-161, 202-209`. The
  only tie between the outputs on disk and the run named in "Timings from …" is the **step-3** record time.
  Steps 1 and 2 write the rest of each row (network km, freshness, `habitat_link`, ff02/04/06 km², blue lines,
  `subbasins.gpkg`, `floodplain_<prim>.tif`, the outside share, km² per km, and the vector denominator of
  "classified / floodplain"). Nothing checks that those are older than that step 3.
  - CLAUDE.md names this exact case ("Files sitting together on disk are not one run … a direct
    `run_area.R <area> 1,2` … leaves new records beside the old summary"), and the repo already has the verdict
    (`fp_region_cache_reason()`, its unordered rule at `fp_region.R:187-189`).
  - After `run_area.R <wsg> 1,2`, the report prints the new floodplain km², outside share and coverage
    denominator beside the old patches, tree loss and composition. It also still prints a wall time, because
    the step-3 record is still in its window.
  - Similarly, `transition.tif`, the composition table and the transition layer are read without comparing
    them to `landcover[prim]`'s digests. `composition-check.R` does compare them, but in a separate process at
    a different time.
  - Not reached today: all 23 groups are ordered and inside their windows (verified).
  - Fix: blank (or refuse) a row where `fp_region_cache_reason(prov, cfg)` is non-NA, and not only its wall
    time.

- **[fragile — low]** `region_checks-run.sh:57-61` (`dst_section`). `closed` is set by *any* later non-matching
  header and never reset when a second matching header re-opens the section. Reproduced under `/usr/bin/awk`
  with this log:

  ```
  -- transition_all_ff04_2017_2023 / PASS
  -- transition_bt_ff04_… / FAIL
  -- transition_all_ff04_2018_2023 / PASS / Error / Execution halted
  ```

  It prints **PASS**. Two matching sections back to back correctly give INCOMPLETE, because rule 1's `next`
  consumes the header. It needs two `all_ff04` spans with another layer between them. `disturbance-check.R`
  iterates both spans, while the report would stop on them. Reset `closed = 0` in the header rule.

- **[fragile — low]** `region_acceptance-report.R:49-54, 69`. A malformed or misspelt `RUN_STAMP` entry
  silently falls back to the newest CSV. Two cases: `RUN_STAMP=fraser` gives `NA` and then the newest;
  `RUN_STAMP=Fraser=…` never matches the lower-case region. The printed CSV name is the only trace. Stop on an
  entry with no `=`, or on a key that names no region being reported.

## Enumeration: every input and verdict, and whether it is tied to its subject

### `region_checks-run.sh`

| # | input / output | tied to what it claims? | verdict |
|---|---|---|---|
| 1 | `config/regions/<r>.yml` `watershed_groups:` via awk `[ ]` split | One-line flow list only. Block list fails closed; a wrapped flow list drops groups (r2). All four files are one line. | tied today |
| 2 | `scen` arg, default `all_ff04` | Equals every group's region-owned `primary_scenario` by construction (`fp_region_owned`). | tied |
| 3 | `$out` = `data/logs/region_checks_<r>_<UTC stamp>/` | Fresh directory per run, so no stale log is read. | tied |
| 4 | `run()` verdict = Rscript exit status | All five checks exit non-zero on failure. bridge's `stop()` and a crash also exit non-zero. | tied |
| 5 | `run()` FAIL count, `grep -c '^  FAIL '` on that check's own log | Per-assertion lines only (r1 fix). A crash gives FAIL(0), which is still FAIL. | tied |
| 6 | args passed to each check | provenance `[area]`, composition `<area> [scenario]`, bridge `[area] [scenario]` (its defaults `morr co_ff04` are always overridden), disturbance `<area>`. | tied |
| 7 | `dst_section` header `"  -- transition_<scen>_"` (prefix) | Matches only `transition_<scen>_YYYY_YYYY` layers (`live_layers` regex). | tied |
| 8 | `dst_section` close: next `  -- ` header or `ALL PASS` / `N FAIL` summary | Correct for one matching section. With two matching sections and a layer between them, `closed` is sticky (finding). | **fragile (low)** |
| 9 | `dst_section` FAIL count inside the section | All output is `message()` (stderr only), so there is no stdout/stderr interleaving to misplace a FAIL. | tied |
| 10 | ABSENT / INCOMPLETE / FAIL(n) / PASS branches | ABSENT if no header; INCOMPLETE if never closed; otherwise by count. | tied (except #8) |
| 11 | `dem_cache-check.R` verdict | Offline, not per area; labelled so. | tied |
| 12 | FAIL listing, `grep -H` over `$out/*.log`, captured then tested | Prints "none" when there is none (r2 fix). The label carries no section, so the `dist:` column is what separates species from `all_ff04`. | tied |

### `region_acceptance-report.R`

| # | input / output | tied to what it claims? | verdict |
|---|---|---|---|
| 13 | region yml `watershed_groups` (yaml) | Parsed as YAML. | tied |
| 14 | `area.yml` `species`, `min_order`, `primary_scenario` | Current config; layer names are built from it, and a missing layer errors. | tied |
| 15 | `streams_<sp><ord>` length → network km | Step 1 gpkg; not ordered against the step-3 record. | **fragile (finding)** |
| 16 | `network[<sp><ord>].run.freshness` | From the record itself. | tied |
| 17 | `habitat_link` rows / species | Step 1 gpkg; same as #15. | fragile (same) |
| 18 | `<sp>_ffNN` areas, `<prim>_by_blue_line_key` blue lines | Step 2 gpkg; same as #15. | fragile (same) |
| 19 | `transition_<prim>_<span>`, exactly one, else stop | Layer is unique; not compared to the record's digest (composition-check does that, separately). | fragile (low) |
| 20 | causes / lookback from `config/disturbance.yml`, via `fp_disturbance_report` | One definition of tree loss; an absent column refuses. | tied |
| 21 | column label `patches >= 1 ha` | Written from the sieve parameter; 78–94% of rows are < 1 ha. | **claim false (finding)** |
| 22 | bridge `patch_watercourse_*`, union = mean of max `overlap_frac`, unbridged | Same definition as step 3 (`03:347-352`) and bridge-check. | tied |
| 23 | composition table → classified ha, `change_ha` | Read without a digest check against `landcover[prim].composition`. | fragile (low; same as #19) |
| 24 | `subbasins.gpkg` (single layer `subbasins`), `transition.tif`, `floodplain_<prim>.tif` | Steps 1–3 rasters; ordering as in #15. | fragile (same) |
| 25 | `landcover[prim].run.datetime_utc` / `repairs[[1]].previous_datetime_utc` | The step-3 time; parse failure gives NA, so no wall time (fails toward blank). | tied |
| 26 | `RUN_STAMP` env | A malformed or misspelt entry silently becomes the newest CSV. | **fragile (low, finding)** |
| 27 | newest `region_<r>_YYYYmmdd_HHMMSS.csv` | The pattern excludes `skeena_ch`-style prefixes. Now tied per group via #25. | tied (r2 fix) |
| 28 | CSV `wsg`, `log`; log mtimes chained from the CSV stamp | A cached row (log "") or a missing log gives NA, which propagates to the next diff (blank, not wrong). | tied |
| 29 | wall-time tie: step-3 time in [previous log mtime, own log mtime] | Ties only step 3 (see #15). | partial |
| 30 | "No wall time for …" message | Lists only groups whose time was blanked by the tie. | tied |
| 31 | outlier screen over `all` (quantiles of `km2_per_km`, `fp_out_pct`) | Recomputed; matches the logs. | tied |
| 32 | `region_acceptance_<UTC>.csv` output | New file per run. | tied |

### Committed prose

| # | claim | verdict |
|---|---|---|
| 33 | tables in all three logs | regenerated identically (Peace and Columbia under the current code; Fraser by r1/r2) |
| 34 | "derives every figure in those logs from disk" (CLAUDE.md) | **false**: the ad hoc figures listed above |
| 35 | "1,700.3 ha … on the reservoir" | **overstated**: ≤ 1,652.9 ha measured |
| 36 | "true union 0.94–0.96", "83.6%", "92.1%", "58.4%" | no committed producer; values not re-derivable here (the 58.4% was verified by r1) |
| 37 | composition range, FAIL classes, provenance and `all_ff04` PASS in 23, DUNC figures, median and IQR | verified |

/Users/airvine/Projects/repo/floodplains/planning/active/review-round3.md
