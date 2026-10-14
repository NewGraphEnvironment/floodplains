# Code-check round 3 (#125, branch diff 71c0378...HEAD)

Offline checks run: `region_config-check.R` PASS, `whole_network-check.R` PASS. I also ran a pure
reconciliation pass (`fp_region_owned` + `fp_region_plan` + `fp_region_write`) over every group in all four
region files, on a temp copy of `config/`. It raised no errors, and every group came out `species: all`,
`min_order: 2`.

## Mechanism

Two different mechanisms produced the three earlier findings.

- **r1a (`reg$network`) is a separate class.** `$` partial-matched a sibling key. The `[[` sweep closes
  it. Every `$` left in the diff reads a key that either always exists in that branch or has no
  prefix sibling.
- **r1b and r2 share one assumption: co-presence means co-provenance.** The cache decides whether a
  group is "this config's complete run" from artifacts that different steps write at different
  moments:
  - the step-3 marker `lulc_summary_<sp>_ff04.rds`;
  - the step-1 `network[...]` record and the step-2 `floodplain[...]` record;
  - the gpkg layers.

  It treats whatever sits on disk together at check time as products of one finished run. r1b read
  the config fact from an ephemeral source, this run's diff. r2 found that the records the cache now
  reads are rewritten by steps 1-2 before step 3 replaces the marker.

Both fixes patch the **reader** in `run_region.R`. The marker is retired in only two writers:
`run_region.R` (before its own child) and `03_lulc_classify.R:451`, which runs *after* the STAC fetch
and classification. Steps 1 and 2 rewrite exactly the records the cache reads, and they never retire
the marker.

## Findings

- **[severity: bug]** `scripts/run_region.R:197-214` with `scripts/floodplain_lcc/01_network_extract.R`
  / `02_floodplain_model.R`. The r2 fix closes the hole only for `run_region.R`'s own children.
  - **What reopens it.** Any other run rewrites `network[<sp><order>]` and `floodplain[<sp>_ff04]` and
    leaves the old marker in place. Two common cases:
    - a `run_area.R <area>` whose step 3 dies in the STAC fetch, which is the commonest step-3
      failure and happens before 03:451 unlinks the marker;
    - a deliberate `run_area.R <area> 1,2`.

    Either way the group reads as `ok(cached)`, with its landcover, transition and composition built
    on the previous floodplain and network.
  - **Reproduced on DUNC's live record**, with the pure functions. I set `network.all2` to the
    `fresh_default` read and the floodplain records to flooded 0.7.0, which is what a direct
    `run_area.R dunc` writes before a fetch failure. Result: `lulc_summary_all_ff04.rds` present,
    `fp_region_cache_stale` FALSE, `fp_region_cache_moved` FALSE, so the group is `cached`. Its
    landcover record (2026-10-12T01:38:40Z) consumed the 0.6.5-grid floodplain. That is exactly the
    case the CLAUDE.md DUNC entry says `fp_region_cache_stale` "makes the region run redo".
  - **Steps are run independently by design.** "`run_area.R morr 3` is normal", and DUNC was run
    standalone. DUNC's own record shows `network.all2` written *after* its floodplain records (01:29:39
    vs 01:25:14), so earlier steps do get re-run on their own.
  - **Fix (writer side, preferred).** Retire the primary marker at the start of `fp_network()` and
    `fp_floodplain()`, as 03:451 does for step 3. That covers every entry point, and run_region's
    pre-removal becomes redundant but harmless.
  - **Fix (reader side, alternative).** Accept the cache only when the step-3 record is newer than
    both `network[...]` and `floodplain[<primary>]` `run.datetime_utc`, using
    `run.repairs[[1]].previous_datetime_utc` when present, because the #126 re-stamp moves
    `datetime_utc`. DUNC's live record satisfies that ordering (landcover 01:38:40 > 01:29:39 and
    01:25:14), so it would not misfire there.

- **[severity: fragile]** `scripts/run_region.R:186-193, 258`: the coverage CSV's `provenance` column
  is read **before** the child runs. This is pre-existing, and it is the same mechanism in the
  report.
  - **A group that just ran shows the previous record's date.** DUNC would print `2026-10-12...`
    (the pre-pin run) beside status `ok`, and a first run prints NA. A reader checking "did this
    group re-run on 0.7.0?" gets the wrong answer.
  - **It takes `max()` over every landcover entry, not the primary.** For a converted group
    (BULK/MORR/KISP) that is a species record's date. In whole mode the primary is always
    `all_ff04`, so the "MORR is ch_ff06" reason for reading every entry no longer applies.
  - **Fix.** Re-read the primary landcover entry (`landcover[[paste0(sp, "_ff04")]]`) after
    `system2()` returns.

- **[severity: fragile]** `scripts/floodplain_lcc/provenance-check.R:2436-2441` (7c), reached by the r2
  fix at `run_region.R:234`.
  - **The inference.** 7c reads "landcover record present + marker absent + no composition table" as
    "step 3 died in its composition", on the stated premise that only step 3 unlinks the marker. The
    pre-child removal adds a second cause: a re-run that dies in step 1 or 2. 7c then FAILs with the
    wrong diagnosis and the wrong remedy ("re-run step 3, or composition_build.R").
  - **Not reachable today.** In whole mode only `lulc_summary_all_ff04.rds` is ever removed, and the
    only `all_ff04` record (DUNC) has a composition.
  - **Reachable in any species region.** 19 of 23 landcover records on disk carry no composition
    (pre-#108).
  - **Fix.** Reword 7c, or have it accept "marker absent" only when the landcover record is newer
    than the floodplain record. It fails toward alarm, not pass.

## Where the mechanism reaches, and status

| place | status |
|---|---|
| `cached` verdict, after a `run_region.R` child is interrupted | CLOSED (r2: marker removed before `system2`) |
| `cached` verdict, after a direct `run_area.R` run, or a step subset that rewrites records 1-2 and dies before 03:451 | **OPEN** (finding 1) |
| `fp_region_cache_stale` (step-2 record, not what step 3 consumed) | closed for region children, open as above |
| `fp_region_cache_moved` (step-1 record) | closed for region children, open as above. The r1b "diff vs record" part is CLOSED |
| `run_area.R <area> 3` dying in the fetch (marker old, records old) | not a defect: the state is old but consistent |
| POST-VERIFY (`run_region.R:241-252`) | **Partly open, pre-existing.** It reads `streams_<sp><order>` / `<sp>_ff04` by name and trusts `rc`. A layer left by an earlier run satisfies it when the steps exclude 1 (accepted). It is also satisfied when an inherited `FP_SPECIES` / `FP_PRIMARY_SCENARIO` makes the child write keys other than the ones run_region reads, and that case is not accepted. `fp_km2 = NA` never fails the status, yet the summary line counts the group as "having a floodplain". |
| coverage CSV `provenance` column | **OPEN, reporting only** (finding 2) |
| 7c "marker absent" inference | **OPEN, unreachable in whole mode today** (finding 3) |
| `$` partial match (r1a class) | CLOSED. The remaining `$` reads (`reg$network_source`, `reg$species`, `region_owned$species`, `existing$species`, `area$targets`, `t$scenario`) all hit keys that exist in their branch, with no prefix siblings |

## Checked and clean

- **`fp_region_mode` and `fp_region_owned`.** No `$` partial matches, and both refuse a mixed region
  file. The whole-mode `min_order` floor holds. `network_guard` is stripped from the Columbia groups
  as intended.
- **Pre-pass `n_whole`.** The schema-name regex is checked before the name reaches SQL, `count(*)::int`
  comes back as an integer, and `sprintf("%.0f", <int>)` works.
- **`readme_functions.R` sourcing `fp_region.R`.** It defines functions and constants only, with no
  name collisions.
- **CLAUDE.md, README and region/area config prose.** Checked against the code. The one inaccurate
  claim is in finding 1: the CLAUDE.md DUNC line says `fp_region_cache_stale` makes the region run
  redo DUNC, and that holds only if no direct run has rewritten DUNC's records first.
