# Code-check round 1 — branch 125-region-acceptance-fraser-peace-columbia (48fae86...HEAD)

Reviewer: subagent, 2026-10-17. Read-only on the repo apart from this file. Probes ran in the
session scratchpad (`.../scratchpad/rv/`).

What I verified and found sound:
- Re-ran `region_acceptance-report.R fraser` and `peace columbia` read-only. Every group row of both
  tables in all three committed logs is **byte-identical** to the regenerated output (`diff` empty, 40 rows).
- The checks tables in all three logs match the per-check logs on disk (FAIL counts, which section each
  disturbance FAIL sits in, NECR's two composition FAILs, the bridge FAILs on PCEA/LARL/SLOC halting after
  every assertion ran).
- The report's change cells equal the composition table's `change_ha` exactly in all 23 groups (max |diff| 0).
- The outlier-screen statistics, PCEA `bt_ff04` 58.4% outside, the DEM fetch ranges (11–42 / 30–42 / 22–52 s),
  run status `ok` with no `Error`/`Execution halted` in any group log, the toolchain versions, DUNC's
  `link_log` (`config_name: default`, `link_sha` present, GRAB from `fresh_default`), freshness strings, and
  the prior `ch`/order-3 config for Fraser: all as stated.

## Findings

- **[bug — guard fails toward pass]** `scripts/floodplain_lcc/region_checks-run.sh:52-61` (`dst_section`) —
  a `disturbance-check.R` that **crashes or is killed inside the `transition_all_ff04` section** reports that
  section as **PASS**. The section's verdict is "no `FAIL` line between the header and the next header/summary",
  but a crash writes `Error ... / Execution halted` and no summary line, so `on` stays set to EOF with `n = 0`.
  In every one of the 23 logs the `all_ff04` layer is the **last** section (`st_layers` order, species layers
  first), so the crash also happens after the species FAILs were printed, and the row reads
  `FAIL(2) | PASS` — byte-for-byte the *expected* outcome the logs and CLAUDE.md treat as acceptance. DUNC
  (no species layer) would read `FAIL(0) | PASS`. Reproduced with a synthetic log (species section with 2 FAILs,
  then the all_ff04 header, one PASS, `Error in tr[[k]]`, `Execution halted`): awk prints `PASS`, whole-check
  column `FAIL(2)`. The mutation table in findings.md never planted this case (its "crash" row tests only the
  whole-check column). Fix: the section is PASS only if it is terminated by the next `  -- ` header or by the
  `ALL PASS`/`N FAIL` summary line; otherwise report e.g. `INCOMPLETE`. The committed results are not affected
  (every disturbance log on disk ends in its summary line), but the runner is the stated producer for future regions.

- **[fragile]** `scripts/floodplain_lcc/region_checks-run.sh:44` and `:81` — `grep -c '^ *FAIL '` also matches the
  **summary line** of `provenance-check.R` (`FAIL — 1 problem(s).`, provenance-check.R:2466) and
  `dem_cache-check.R` (`FAIL (1 failure)`, dem_cache-check.R:227), since `^ *` allows zero spaces. A provenance or
  dem_cache failure with one problem is tabulated `FAIL(2)`, and the summary line is listed under "FAIL lines"
  as if it were an assertion. Reproduced (`grep -c` gives 2 on a one-failure log of each shape). The verdict
  (FAIL) is still right; the count, which the header says distinguishes expected from new failures, is not.
  No committed table is affected (provenance and dem_cache passed everywhere). Anchor on two leading spaces
  (`'^  FAIL '`) — every per-assertion FAIL line in all five checks is indented.

- **[claim not supported]** `CLAUDE.md` new block, "**All four regions passed #125's acceptance 2026-10-17**" —
  #125's own per-region acceptance (findings.md "Per-region acceptance") includes `habitat_join-query.R <wsg>`
  running and reporting its match rate for every group. That is Phase 3 of task_plan.md, still unchecked, and
  the same CLAUDE.md block says the habitat join needs flooded > 0.7.2, which is not installed (0.7.0). None of
  the three new logs has a habitat-join section. As committed, the sentence says acceptance is complete when the
  #104 deliverable check has not run on any of the 20 new groups (and NECR's composition check 5 is an
  unexpected FAIL by that same acceptance definition). Either land Phase 3 before this sentence or scope it
  ("passed the per-group checks").

- **[claim not supported — placeholder references]** `CLAUDE.md` (#ACCURACY, #BRIDGE, #WATERBODY, #VISUAL),
  `logs/20261017_whole_network_fraser.md` (#ACCURACY), `..._peace.md` (#BRIDGE, #WATERBODY, #VISUAL),
  `..._columbia.md` (#BRIDGE) — committed text says "each with its own issue" / "Filed as #BRIDGE", but these are
  not issue numbers; nothing has been filed (GitHub is unreachable). Per feature-workflow "Cite an issue only after
  it exists", these must be replaced with real numbers (and their titles checked) before merge, or the sentences
  must not say "filed".

- **[claim — minor]** "Inside-polygon change cells equal the patch totals within ±0.1 ha" (CLAUDE.md new block;
  Fraser log "within ±0.1 ha in every group"; Columbia log; findings.md) — the measured range over the 23 groups is
  **−0.066 to +0.120 ha** (LSAL: 2,535.40 vs 2,535.28, `data/logs/region_acceptance_20261017_174646.csv`). The
  table shows `+0.1` only because it rounds. Say ±0.12 ha (or "to the 0.1 ha the table prints").

- **[claim — minor]** CLAUDE.md "Both reproduced the Skeena log before being trusted." — findings.md records that
  the report did **not** reproduce one Skeena figure (BULK outside-polygon 1,317.5 vs the log's 1,318.2 ha). The
  difference is accepted, but the sentence states full reproduction.

- **[claim — minor]** `planning/active/findings.md` (NECR composition section): "Its 6,436.64 ha equals the
  `co_ff04`-era composition". NECR was never coho: `config/necr/area.yml` was `species: ch`,
  `primary_scenario: ch_ff04` until 760b8d9, so the 2026-10-02 composition it cites is the `ch_ff04` one (which is
  what the Fraser log says). Wrong scenario name in the diagnosis that the new issue will be written from.

- **[claim — trivial]** `logs/20261017_whole_network_fraser.md:3` "ran 2026-10-15 00:17 to 05:18 UTC" — the last
  group log (UNTH) and the coverage CSV are stamped 05:19:27–05:19:28 UTC.

- **[fragile — low]** `scripts/floodplain_lcc/region_acceptance-report.R:66-76` (`coverage_csv`) — when the newest
  coverage CSV has a cached row (empty `log`), it silently falls back to the next-newest CSV whose rows all name a
  log. In this repo that can be a **species-era** run (e.g. `region_columbia_20260827_190638.csv`,
  `region_fraser_20260903_192303.csv`), whose wall times would then be printed in a whole-network log against
  outputs it did not produce. The CSV name is printed, so it is traceable, and today's newest CSVs are all
  complete, so nothing committed is affected. A check that the chosen CSV's `provenance` datetimes / `species`
  match the records being reported (or an NA wall time instead of a fallback) would close it.

/Users/airvine/Projects/repo/floodplains/planning/active/review-round1.md
