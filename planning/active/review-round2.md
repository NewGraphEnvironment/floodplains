# Code-check round 2 — branch 125-region-acceptance-fraser-peace-columbia (48fae86...HEAD, fixes in 45d9118)

Reviewer: subagent, 2026-10-17. Read-only on the repo apart from this file. Probes ran in the session
scratchpad (`.../scratchpad/rv2/`).

## The round-1 fixes, checked

- **dst_section (fix 1): sound.** Exercised the awk under `/usr/bin/awk` (BSD one-true-awk):
  - a FAIL in the section, closed by the summary, gives FAIL(1);
  - a crash after the header (`Error` / `Execution halted`, no summary) gives INCOMPLETE;
  - `ALL PASS` followed by a trailing `Warning message:` gives PASS;
  - CRLF line endings give INCOMPLETE, which fails closed.

  The summary regex matches what `disturbance-check.R:425` prints (`\nALL PASS` / `\n%d FAIL`), and
  the header matches `:356`'s `message("  -- ", lyr)`. Nothing after the layer loop prints a line that
  could be miscounted.
- **'^  FAIL ' (fix 2): sound.** Every per-assertion FAIL in the five checks starts with exactly two
  spaces then `FAIL ` (disturbance:33, composition:32, bridge:52, provenance:56 via `cat(" FAIL ", msg)`,
  dem_cache:25). Every summary line is at column 0 or begins with a digit. bridge-check's `stop()` prints
  `Error: n bridge check(s) FAILED`, which does not match. All five checks exit non-zero on failure, so
  the exit-status verdict holds.
- **coverage_csv / wall_times (fix 3): sound for what it fixed.** `run_region.R:160` stamps in UTC after
  the pre-pass, writes `log = ""` for cached rows (`:251`), and appends SKIP rows last. So the chain of
  mtimes skips exactly the rows that ran nothing.
- **Claims (fix 4):** I re-derived the figures from `data/logs/region_acceptance_20261017_174646.csv` and
  the check logs on disk. All of these hold:
  - inside − patches is −0.066 to +0.120 (LSAL), and Columbia's figure is within 0.07 (KOTL −0.066);
  - classified coverage is 0.9991–1.0001;
  - non-PCEA outside share is 0.81–3.25%;
  - IQR and medians as stated;
  - DUNC's composition bound is +4.70%;
  - Skeena wall times are 59.0 / 15.7 / 24.0;
  - every value in findings.md's bridge table (unweighted, area-weighted max, watercourses per patch for
    LARL, SLOC, PCEA, KISP and BULK), plus the WILL, MORR and FRAN second-correction figures;
  - the NECR binding: `fp_accuracy.R:18-20`, `composition-check.R:234-242`, `design.json`
    `transition_layer = transition_ch_ff04_2017_2023` on dims 6288 x 8945, and `sample_draw-pilot.R:136`;
  - the Fraser end time of 05:19 (UNTH log 05:19:27);
  - commits 2dda619 (DUNC `fresh` -> `fresh_default`; KOTL, LARL and SLOC converted) and 760b8d9.

  Every coverage CSV's `provenance` column for Fraser, Peace and Columbia equals the current
  `landcover[all_ff04].run.datetime_utc`, so the committed wall times describe the outputs on disk.

## Findings

- **[fragile — low]** `scripts/floodplain_lcc/region_checks-run.sh:89`. The line
  `grep -H '^  FAIL ' ... | sed ... || echo "  none"` never prints "none". With no `pipefail`, the
  pipeline's status is sed's, which is 0 even when grep matched nothing. Reproduced: an empty match
  printed nothing and `|| echo` did not fire. A region with no FAIL lines therefore prints a bare
  `FAIL lines (file: line):` header with nothing under it. That reads the same as a listing that broke.
  Fix: capture first, e.g. `fl=$(grep -H ... ) ; [ -n "$fl" ] && printf '%s\n' "$fl" | sed ... || echo "  none"`.

- **[fragile — low, one axis over from fix 3]** `scripts/floodplain_lcc/region_acceptance-report.R:67-90`.
  The newest CSV is no longer an *older* run's, but nothing ties it to the run that produced the outputs
  being reported. Suppose a group is re-run after the region run, by `run_area.R <wsg>` (which writes no
  coverage CSV) or by a later region run killed before it writes its CSV (the CSV is written only at the
  end, `run_region.R:261`). The report then prints the old run's wall time beside the new run's km²,
  patches and tree loss, with nothing flagged. The CSV already carries the comparison: its `provenance`
  column is the primary landcover `run.datetime_utc` after the child ran (`run_region.R:183-190, :250`).
  NA the wall time where it differs from `prov$landcover[[prim]]$run$datetime_utc` (or from
  `run.repairs[[1]].previous_datetime_utc` when #126 has re-stamped it). Caveat: Skeena's
  `region_skeena_20261014_123741.csv` holds pre-fix values in that column (2026-09-0x, the old
  max-over-entries rule). A strict comparison would therefore NA Skeena's times, and those are correct.
  So limit the comparison to CSVs whose column can be trusted, or treat that case as a warning. Nothing
  committed is affected today; I verified all 20 Fraser, Peace and Columbia rows match.

- **[claim not supported — minor]** `CLAUDE.md` new block, "Three FAILs are new, each with its own issue".
  The third bullet, the PCEA outlier flag, is not a FAIL of any check. The new FAIL lines are four:
  NECR composition (5), plus bridge on PCEA, LARL and SLOC, which make two classes. The screen flag is a
  separate kind of result. Say "Three new findings", or list two new FAIL classes plus the screen flag.

- **[claim inconsistent — minor]** `scripts/floodplain_lcc/logs/20261017_whole_network_peace.md`, Checks
  bullet 1, reads "`composition-check.R`, FAIL(1) in all three: the #53 bound, as on Fraser and Skeena".
  The same applies to CLAUDE.md's "Expected failures: composition-check.R's 1% bound in every group (#53)".
  PCEA's bound fails at **+225.39%** (`pcea_composition.log`: 2,454.6 ha of cells against 754.4 ha of
  patches), and 1,700.3 ha of that change lies outside the polygon in the Williston arms. findings.md
  says outright: "PCEA is a waterbody spill, not the #53 edge". The log's own PCEA section attributes
  the outside share to #WATERBODY. As written, the Checks bullet files a 225% overshoot under the
  expected #53 failure that elsewhere runs +1.1% to +7.8%, so a reader of the table would take it as
  routine. Name PCEA's magnitude and its cause (#WATERBODY) in that bullet.

No other issues found. The runner's `groups` parse requires a one-line flow list. All four region files
use one, and a block list fails closed (`no watershed_groups`). A flow list wrapped across lines would
silently drop groups, but none exists.

/Users/airvine/Projects/repo/floodplains/planning/active/review-round2.md
