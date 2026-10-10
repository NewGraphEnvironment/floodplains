# Review round 4 — #110, scoped to fed42be (round 3's fixes)

Read-only. DB probes were `information_schema`, `fresh.log`, `fresh.log_recompute` and VALUES CTEs
bound through RPostgres; nothing in the repo, `data/` or the database was written except this file.

## The four questions

**1. Window check.**
- Columns: `date_start` and `date_end` exist in both `fresh.log` and `fresh.log_recompute`, and
  both are `timestamptz`. The server zone is `Etc/UTC`.
- Binding: RPostgres binds the POSIXct `t0` (America/Vancouver, fractional seconds) as
  `timestamptz` with the instant intact. `$1::timestamptz` gave `2026-10-09 05:01:34` for a t0 of
  22:01:34 PDT.
- Overlap predicate, probed on a VALUES CTE:
  - a row ending before t0 is not counted;
  - a row starting 1 s before t0 and ending after it is counted;
  - an open row is counted.
- Live, it returns 0 / 0 for MORR.
- **But t0 can be later than a read it must cover. See finding 1.**

**2. Scenario mtime.** It fails closed. `git checkout` of a version with different content, an
edit, an edit-then-revert, and `git checkout -- file` all set mtime to now, so the report refuses.
Only an mtime-preserving write passes: `cp -p`, `rsync -t`, `touch -r`, or a tar extract. The csv
is 2026-08-28 against a t0 of 2026-10-08 22:01. The proxy is sound for what it covers. `area.yml`
is not covered (finding 5).

**3. Anchor fields.** `anchor.json` holds `network_match`, `dem_match_replay` and
`floodplain_match_replay` as JSON booleans, which `isTRUE` reads correctly. `scenario` is
`"co_ff04"`. `flooded`, `terra`, `terra_gdal` and `sf_gdal` are scalar strings, so the
`vapply(..., "")` comparison works: a missing key gives `character(0)`, and vapply then errors, so
it fails closed. There is no `sf` key, so the sf version is still not compared (finding 5).

**4. Research numbers.** Every number in Results, "The rule, applied" and the Recommendation
re-derives from `20261009_*_morr.md`. Checked:
- the 19.9, 35.8, 31.5 and 90.7 min costs;
- attribution's 87–96% share of cost (86.8–95.9%);
- 12–20% waterbody share of added area, and 3–11% of the reach gains;
- 452 ha / 1.3% lost, and 444 ha;
- 13.7 min fallback, 33 → 19.3 min, ~42%;
- 86, 61 and 31 min segment-grain estimates;
- habitat shares;
- step 1's date, 2026-09-03 (provenance `run.datetime_utc`).

The supersession readings follow from the rule. Two verdict sentences do not (findings 3 and 4).

## Findings

- **[bug — fails toward pass]** scripts/floodplain_lcc/floodplain_probe-report.R:92-96, 120-124
  with floodplain_probe-whole-fwa.R:143-146, 183-185.
  - **Mechanism.** The anchor's two likeliest failures, network ≠ step 1's record and DEM ≠ replay,
    `stop()` before `write_json()`. A failed anchor re-run therefore leaves the OLD `anchor.json`
    (all three matches TRUE) and the old `anchor_floodplain.tif`, so their digest tie holds. The
    runner has meanwhile re-touched `.anchor.start` to now.
  - **Two consequences.**
    - (a) The new verdict gate reads the stale passing verdict.
    - (b) `t0 = min(stamps)` moves from the anchor's real read time to the `dem` stamp.
  - **Sequence that passes.**
    1. The anchor runs.
    2. `fresh` MORR is rebuilt.
    3. `dem` and the arms run, all on the rebuilt network, so every count tie agrees.
    4. Someone re-runs the anchor to check, and it fails on the network.
    5. The report passes with no error. The rebuild row predates the new t0, and the gate reads
       the old TRUE.
  - **Why it matters.** Re-running the check that would have caught the problem is what erases the
    evidence.
  - **What else is unchecked.** The report never checks `anchor.log` for `PROBE_DONE`, and it never
    checks that any json is newer than its stamp. `rss()` does this only for the RSS figures, so
    `anchor` and `reach` have no check at all.
  - **Fix.** For every mode in `modes_read`, require the mode's json mtime > its `.start` stamp
    AND `PROBE_DONE <mode>` in `logs/<mode>.log`, which is the runner's own success criterion
    (`floodplain_probe-run.sh:45-46`). Otherwise stop: "the last run of <mode> failed; its outputs
    are from an earlier run".
  - **Current data passes.** Verified: every json in `modes_read` is newer than its stamp
    (anchor 22:05:24 > 22:01:34 … seg 02:06:30 > 01:34:58), and all 10 logs carry one
    `PROBE_DONE`.

- **[fails toward pass — proxy for the property]** floodplain_probe-report.R:97-111.
  - **Mechanism.** The window check is complete only for writers that log, and the comment's claim
    about link is not true of link's API.
    - `lnk_access(merge = TRUE)` is exported and is the surgical UPDATE of `streams_access`. It
      writes no `log_recompute` row itself. `.lnk_log_recompute_start` is called only from link's
      `data-raw/wsg_recompute_one.R` and `data-raw/habitat_variants_build.R` (grep over all link
      `.R`).
    - `lnk_pipeline_persist()`, which does a DELETE-WHERE-WSG + INSERT into `streams`, is exported
      and logs nothing on its own.
    - `lnk_pipeline_run(log = FALSE)` is a supported argument.
  - **What passes.** Any of these during the probe changes `access_co` or the value columns with no
    row. Arms 1–4 are tied across modes only by segment COUNT. `reach` reads the coho network for
    the supersession measure, and it has no network tie at all.
  - **Cheapest content check that needs no re-run.** At report time, read arm 5 and require
    `fp_table_content_sha256(s5, KEY, VAL) == anc$network`. That closes any persistent unlogged
    change to the network `reach` read. Round 3's per-mode digest is the full fix, but it needs the
    modes re-run.
  - **Comment.** Correct lines 97-99 either way: logging is a convention of link's drivers, not a
    property of link.

- **[verdict does not follow from the registered rule]** research/whole_fwa_floodplain.md:199-204.
  - **What it says.** "Under either reading … **Grain: blue line.**"
  - **What the rule says.** The registered grain rule is "segment grain is recommended only if [its
    scaled cost] stays ≤ 60 min … Otherwise the blue line."
  - **Where it breaks.** Under reading B the recommended floor is order ≥ 3, measured directly at
    31.5 min (7,606 segments). That is ≤ 60, so the rule's "otherwise" branch does not apply. The
    bullet then concedes "under reading B segment grain stays an open choice", which contradicts
    its own heading.
  - **Fix.** Move grain into each reading:
    - A: blue line, because segment grain is 86 min at order ≥ 2.
    - B: segment grain passes the registered bound (31 min). If the blue line is still preferred,
      say that is a departure from the rule and why: #104's range join.

- **[verdict overstated]** research/whole_fwa_floodplain.md:190.
  - **The sentence.** Under reading A, "The bypass also passes on its own."
  - **Why it does not hold.** Reading A is defined as criterion 3 per floor, so the bypass needs its
    own visual verdict. Nothing in reading A's condition supplies one: it names only the order-2
    panels. The preliminary read (:182) is that the largest bypass addition is "the same broad-flat
    class as order 1's largest", and order 1's read is "do not read as valley floor".
  - **What can be said.** The bypass passes criteria 1 and 2 only. Its criterion 3 is pending, and
    leans no.

- **[minor — guard correct by accident, wrong number in its message]** floodplain_probe-report.R:104-111.
  - **Cause.** `count(*)` arrives as `integer64` (probed: `class(...)$n == "integer64"`), and
    `vapply(..., numeric(1))` strips the class and keeps the raw bits.
  - **Probe.** A count of 2 became `9.881313e-324`. `any(ev > 0)` is TRUE only because that
    denormal is positive, and the stop message prints "has 1.976263e-323 row(s)". A later edit to
    `ev >= 1` would fail open with no error.
  - **Fix.** `as.numeric(...$n)` inside the function, or `SELECT count(*)::int`.

- **[minor — same mechanism, not in the round-3 disposition]**
  - (a) `area.yml` is read "now". It supplies `read_schema` (`network_source`/`schema`, and
    `run_region.R` rewrites those keys), `wsg` and `scen_id`. Only `flood_scenarios.csv` is tied to
    the window. `scen_id` is covered by the per-arm scenario check, but `read_schema` is not.
    - **What passes.** If `network_source` changed after the modes ran, the window query checks the
      new schema's log, not the one the arms read. A missing `log` table there errors (closed). A
      schema that has one passes.
    - **Fix.** Add `area.yml` to the mtime test, or record `read_schema` in every json.
  - (b) The anchor toolchain check omits `sf`, because `anchor.json` has no `sf` key and `akeys`
    drops it. Round 3 named this. The disposition says four keys were compared, but not that `sf`
    was dropped.
  - (c) `c(anc$scenario, ...)` silently drops a NULL `anc$scenario`. Not reached today.
  - (d) The scenario tie covers anchor and arms only. `reach` and `seg` run with whatever
    `args[3]` names. On MORR every `co_*` and `ch_*` row has max_width 2000 and cost_threshold
    2500, and the co and ch networks are identical, so no number can move today. State it rather
    than gate it.

Accepted tradeoffs not re-flagged.

## Disposition (main session) and the terminal enumeration

| finding | disposition |
|---|---|
| failed anchor re-run leaves a stale passing anchor.json; t0 moves | fixed: every mode the report reads must have its json newer than its `.start` stamp and exactly one `PROBE_DONE <mode>` in its log (the driver's criterion). Restore-the-bug: re-touching `.anchor.start` made the report stop; stamp restored |
| window sees only logging writers | partly fixed: arm 5 (the coho seeds) is re-digested at report time and must equal `anc$network`; the whole-group segment count must equal `dem.json`'s. Arms 1–4's non-coho segments are tied by count only; stated as a known limit in research |
| grain under reading B contradicts the rule | fixed: grain moved into each reading (A: blk, 86 min > 60; B: segment, 31.5 min ≤ 60) |
| bypass "passes" under reading A | fixed: passes criteria 1–2 only; criterion 3 pending, leaning no |
| `count(*)` as integer64 | fixed: `count(*)::int`, `vapply(integer(1))` |
| area.yml untied; sf absent from anchor toolchain; NULL anchor scenario | area.yml must predate t0 (it names the schema); NULL scenario refused; anchor.json records no `sf` version (not fixable without re-running the anchor) — sf_gdal is compared |

**Terminal enumeration.** The mechanism across rounds 1–4 is one: *a figure trusted because a file or
row with the right name exists, or because two mutable stores agree now*. Every read in
`fp_wf_report()`, and its tie after round 4:

| read | tie | kind |
|---|---|---|
| anchor.json | json newer than stamp + PROBE_DONE; verdict gated; toolchain (less sf) = dem's; scenario = report's | run event + content |
| anchor_floodplain.tif | digest = anchor.json | content |
| dem.json / dem_common.tif | newer than stamp + PROBE_DONE; tif digest = dem.json; every arm's DEM digest = it | content |
| arm<k>_timing.json / _floodplain.tif | newer than stamp + PROBE_DONE; tif digest = json; scenario = report's | content |
| arm<k>_waterbody.tif / _by_blk.gpkg | mtime order within the arm's process; by_blk rows = json | proxy (one process) |
| reach.json / arm<k>_coho_reach.gpkg | newer than stamp + PROBE_DONE; valley_cells = arm json; gpkg cells = reach_cells | content |
| seg_timing.json | newer than stamp + PROBE_DONE; n_groups = dem.json arm-3 count | count |
| logs/<mode>.log (RSS) | PROBE_DONE + log ≥ json | run event |
| the network each mode read | arm 5 digest now = anchor; group count now = dem; no log/log_recompute row in the window | content (arm 5), count (rest) — residual stated |
| flood_scenarios.csv, area.yml | mtime < t0 | proxy, fails closed |
| fresh.streams_vw_bcfp (habitat), network for panels | live reads, not compared with the run | stated |

Nothing above sits on a "now" comparison of two mutable stores except the two stated residuals.
The loop ends here, by enumeration, after 4 rounds (5 reviewer agents including the plan review).
