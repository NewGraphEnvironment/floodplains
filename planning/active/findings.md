# Findings — Whole-network floodplains for every region (#125)

## Issue context

**If we do it:** every region (Skeena, Fraser, Peace, Columbia) runs as whole-network floodplains (`species: all`, order >= 2, keyed by `blue_line_key`, #104) through `run_region.R`, and the publish layer picks its groups up from the region roster.
**If we never do:** whole-network areas run only standalone (`run_area.R`), none is published, and the catalogue stays on the per-species model we are moving away from.

Split out of #123 (its part 3). GeoParquet and the FWA-position habitat join stay in #123. Segments and habitat flags are not published from here (link's export, NewGraphEnvironment/link#308).

**Scope changed 2026-10-13.** This was Columbia only, with the other regions staying on their species and Columbia's `bt` items kept beside the new ones. Both are reversed by the decisions below.

## Decided

- **Whole network everywhere** (2026-10-13). Every region moves to `species: all`. DUNC (#120) already runs this way.
- **Species items are retired, not re-run** (2026-10-13). The published `co_*`, `ch_*` and `bt_*` items are removed from the catalogue as each group's `all` item replaces them. Removing them per group means the catalogue never loses a group. The removal is the publish layer's work, in NewGraphEnvironment/stac_floodplains_bc#76; the coupling stays one-way. Re-running them would cost compute to republish a product we are moving away from, and #117's grid change would move every one of them anyway.

## Status (2026-10-14)

- **Done on branch `125-whole-network-floodplains-for-every-regi`:**
  - Region mode `network: whole` (`fp_region_mode`, `fp_region_owned`, `fp_region_cache_reason`).
  - All four region files converted. KISP is folded into `skeena.yml`, DUNC joins `columbia.yml`, and Columbia's `network_guard: warn` is dropped.
  - **Skeena run** (BULK 660.0, MORR 479.3, KISP 324.4 km² at `all_ff04`). Log: `scripts/floodplain_lcc/logs/20261014_whole_network_skeena.md`.
- **Decided at the plan gate (2026-10-13):**
  - Species rows in `flood_scenarios.csv` and species outputs in `data/<wsg>/` stay until stac#76 and #128; pruning is #131.
  - No whole-network twin of neexdzii.
  - DUNC joins `columbia.yml`.
- **Left:** Fraser, Peace, Columbia runs. Each is `run_region.R <region>`. The cache re-runs DUNC: its floodplain record is on the pre-0.7.0 grid and its network record read `fresh`.
  - MCGR and PINE have whole networks matching bcfp (2,833 and 5,768 km, measured 2026-10-13); #76 was about their species networks.
  - Before Fraser publishes, `stac_floodplains_bc/scripts/stage_years-check.R` hardcodes `ufra` / `ch_ff04`.
- **Publishing is frozen** until NewGraphEnvironment/stac_floodplains_bc#75. Any `all_*` provenance key in a rostered group stops staging. Staging will copy only each item's own layers (decided 2026-10-14, recorded there), so the species layers left on disk do not reach an `all` item.
- **Cross-boundary floodplain: leave it and record it** (decided 2026-10-14, #53). That is why `composition-check.R` fails its 1% bound on every whole-network group. #53 holds what is still owed.

## Per-region acceptance

**Every group, after each `run_region.R <region>`:**
- `provenance-check.R`, `composition-check.R <wsg>` and `dem_cache-check.R` pass. The composition bound is an expected failure until #53 re-derives it, so read the inside-polygon change against the patch totals; they matched exactly on Skeena.
- Classified coverage ≈ floodplain area.
- `habitat_join-query.R <wsg>` runs and reports its match rate. This is the #104 deliverable as a consumer would use it. Skeena done 2026-10-14: every floodplain cell attributed, and all habitat rows in BULK, MORR and KISP matched schema segments (`logs/20261014_habitat_join-query_*`).
- km, km², gross tree loss, wall time and peak RSS go into the region's log.

**Once per mode change, before the region's first publish (Skeena now):**
- Look at BULK `all_ff04` in QGIS over imagery, mainly the order-2 headwater floodplains. No species run ever mapped these streams, so no number we already check describes them.
- Afterwards, look only at groups whose numbers stand out: km² of floodplain per km of network, or the outside-polygon share.

## Work

1. **A region mode key**, e.g. `network: whole`, that:
   - skips the species pre-pass (which would query `access_all`);
   - owns `species: all`, `min_order: 2` and `attribute_by: blue_line_key`.

   `fp_region_refuse_whole` and its `region_config-check.R` / `whole_network-check.R` arms change from "refuse" to "refuse unless the region is in whole mode". Keep the must-fail arm for a species region naming `all`.
2. **Where the `all` area lives.** Retiring the species items settles the earlier open question: `config/<wsg>/` becomes the whole-network area in place, as `config/dunc/` already is. No suffix, no rename. The species configs stay in git history. Reconciliation still appends the `all` rows to `flood_scenarios.csv` and leaves the species rows alone; decide at the plan gate whether to remove those rows, since nothing runs them.
3. **Species outputs left on disk.** `data/<wsg>/` keeps `streams_<sp><order>`, `<sp>_ff0N` and their landcover layers after a whole-network run (#23 coexistence). Once retired they are the orphan class #55 describes. Decide whether `gpkg_prune-legacy.R` learns an explicit pattern for them, or whether they are left until the catalogue no longer stages them.
4. **The region files.** `skeena_ch.yml` existed only because KISP's species differed from Skeena's. With no species there is nothing to differ, so KISP folds into `skeena.yml`. The same holds for any other per-species split.
5. **Network source per region.** A region reads one schema.
   - Skeena and Fraser GRAB from `fresh`; Columbia from `fresh_default`, which now holds DUNC (NewGraphEnvironment/link#328, closed).
   - ~~MCGR blocked / PINE short (#76)~~: superseded. Both whole networks match bcfp (Status above).
   - ~~What the freshness guard compares in whole mode~~: answered. It compares order >= 2 km with no access predicate (`fp_bcfp_km_sql("all", …)`).
6. **Publish.** NewGraphEnvironment/stac_floodplains_bc#75 drops the key-shape whitelist that refuses `all_ff04`. NewGraphEnvironment/stac_floodplains_bc#76 retires the species items.

## Order

1. #117 first (flooded 0.7.0's fixed grid). Every step-2 output moves once, and that move should not land mixed in with this one.
2. #122 (cache the DEM per area). Every group is about to be re-run, BULK probably more than once.
3. This issue's code, then **Skeena** (BULK, MORR, KISP). It is the smallest region and BULK is the README's figure area (#128).
4. Fraser, Peace, Columbia.

**DUNC is cached on the old grid** (flooded 0.6.5, 2026-10-12). Handled: `fp_region_cache_stale` refuses a floodplain record below flooded 0.7.0, so the Columbia run redoes it.

`neexdzii` stays the coho parity fixture through #117. It is not published, so retiring species items does not touch it. Whether it gains a whole-network twin as the parity check for this mode is a plan-gate question here.

## Cost to expect

DUNC took 8.9 min for step 2 and 9.7 min for step 3, at 13.3 / 19.3 GB peak (`scripts/floodplain_lcc/logs/20261012_whole_network_dunc.md`). KOTL's order >= 2 network is 1.6x DUNC's km, LARL's 1.3x. BULK's DEM fetch alone took ~37 min uncached (#122).

## What this closes

A full whole-network re-run supersedes #58 and #59 (over-mapped species areas) and #73 (provenance rollout to species areas). Close each with a pointer here once its groups have run.

Relates: #104, #117, #120, #122, #123, #128, #53, #76






## Errors Encountered

| Error | Resolution |
|-------|------------|

## Skeena control (2026-10-17)

`region_checks-run.sh skeena` reproduced the committed Skeena checks table exactly: provenance and
bridge PASS in all three groups, composition FAIL(1) each (the #53 bound, +1.47 / +4.40 / +1.27%),
disturbance FAIL(4) MORR and FAIL(2) KISP on the species layers, with the `all_ff04` section PASS in all three.
`dem_cache-check.R` PASS.

`region_acceptance-report.R skeena` reproduced every figure in `20261014_whole_network_skeena.md`
(network km, habitat rows, ff02/04/06 km², blue lines, patches, tree loss, cause shares, bridge
coverage, wall time, the inside/outside change table) except one: BULK floodplain outside its polygon
comes out at **1,317.5 ha**, against the log's hand-derived 1,318.2 ha (0.7 ha, ~8 cells of 30 m).
The script counts by cell centre (`fp_rast_cells`, the repo's rule). The hand derivation's method is
not recorded, so the script's figure is the one carried forward, and the difference is noted here.

## Runner mutation table

Stub checks under a sed-patched copy of the runner (`chk` pointed at the stubs), region skeena:

| planted | expected | got |
|---|---|---|
| check exits 1 with a FAIL line | FAIL(1) | FAIL(1) |
| check crashes (`stop()`), no FAIL line | FAIL(0) | FAIL(0) |
| dem_cache exits 1 | FAIL(0) | FAIL(0) |
| disturbance exits 0, FAIL inside the `all_ff04` section | PASS / FAIL(1) | PASS / FAIL(1) |
| disturbance has no `all_ff04` section | ABSENT | ABSENT |
| disturbance FAIL only in a species section | FAIL(1) / ABSENT or PASS | FAIL(1) / ABSENT (no all section in stub) |

## All-region report and the outlier screen (2026-10-17)

`region_acceptance-report.R all` over 23 groups (per-group values in
`data/logs/region_acceptance_20261017_174646.csv`). The rule was written into the script header
before the new regions' numbers were read.

- `km2_per_km`: median 0.1113, IQR 0.0837–0.1532. **Nothing flagged.**
- `fp_out_pct`: median 1.73%, IQR 1.12–2.42%. **PCEA flagged at 41.7%.**

**PCEA is a waterbody spill, not the #53 edge.** 35,197 of PCEA's 84,334 ha `all_ff04` floodplain lies
outside the PCEA polygon, almost all of it in PARA (Parsnip Arm) and FINA (Finlay Arm), the other
arms of Williston Reservoir. 83.6% of the floodplain is on reservoir or large lakes (FWA manmade
waterbodies plus lakes > 1,000 ha). Step 1 selects waterbodies by `waterbody_key` from the network
(`01_network_extract.R:305`), and step 2 puts their polygons into the floodplain with no spatial
filter, so Williston's single polygon reaches all three arms. ff02 / ff04 / ff06 are 840.2 / 843.3 /
846.6 km², nearly flat, because a reservoir surface floods whatever the factor.

**This predates whole mode.** The retired `bt_ff04` was worse: 92.1% on reservoir and 58.4%
outside the polygon. It also changes nothing in the inside-polygon change reconciliation: PCEA's
754.4 ha of change cells inside its polygon equal the patch total.

Every other group's outside share is 0.81–3.25%. Classified coverage of the floodplain is
0.9991–1.0001 everywhere. Inside-polygon change cells equal the patch totals within 0.12 ha in
all 23 groups (range −0.07 to +0.12, LSAL the largest).

## NECR composition FAIL(2): the accuracy module is still bound to area.yml's scenario (2026-10-17)

NECR's second composition FAIL is check (5), `composition-check.R:234-242`: "footprint in_wetland
matches the accuracy module's FWA-wetland count", 12,809.04 vs 6,436.64 ha. The reference,
`data/necr/accuracy/wetland_composition.csv`, carries no scenario. Its 6,436.64 ha equals the
`ch_ff04` composition (`logs/20261002_composition_build-rollout_necr-bulk.md:51`, "6,436.64 vs
6,436.64 (exact)"). The check binds it to the current `primary_scenario`, now `all_ff04`.

The cause is wider than the check. `fp_acc_area()` (`scripts/landcover_accuracy/fp_accuracy.R:18-20`)
takes the scenario from `area.yml`, so since #125 it resolves `all_ff04` for NECR. NECR's reference
sample was drawn on `ch_ff04`: `sample.gpkg` has `scenario = ch_ff04`, and `design.json` has
`transition_layer = transition_ch_ff04_2017_2023` on a 6,288 x 8,945 grid. The `all_ff04` grid is
6,832 x 9,423. `transition_layer` is recorded by `sample_draw-pilot.R:136` and compared nowhere.
This is not fixed here: it is the #93 module's binding, filed as its own issue.

## Bridge union coverage below 0.90 on PCEA, LARL, SLOC (2026-10-17)

`bridge-check.R:79` asserts `mean(tapply(overlap_frac, patch, max)) >= 0.90`, an UNWEIGHTED mean
over patches. It fails on PCEA (0.8980), LARL (0.8886) and SLOC (0.8944). KISP passed at 0.9015.
Every other bridge assertion passes in all 23 groups, including the apportioned tree loss
reconciling to the ungrouped total.

| group | max-proxy, unweighted | max-proxy, area-weighted | true union, area-weighted | watercourses per patch |
|---|---|---|---|---|
| LARL | 0.8886 | 0.9587 | 0.9610 | 2.82 |
| SLOC | 0.8944 | 0.9364 | 0.9363 | 3.09 |
| PCEA | 0.8980 | 0.9210 | 0.9405 | 3.66 |
| KISP | 0.9015 | 0.9497 | 0.9522 | 2.63 |
| BULK | 0.9421 | 0.9577 | 0.9625 | 3.25 |

True union is the patch ∩ st_union(`all_ff04_by_blue_line_key`), measured ad hoc in this session.

**Wrong turn, kept:** I first attributed the gap to patches spanning several blue lines, so that
the max under-reads the union. The area-weighted column refutes that for LARL, SLOC and KISP:
weighted, the max and the union agree within 0.003. The gap is the weighting. Small patches, built
on the 10 m grid, lie partly outside the 30 m attribution polygons. An unweighted mean counts each
1 ha patch as much as a 100 ha one, and whole-network groups add narrow headwater floodplains,
where those edge patches are common. PCEA keeps a 0.02 max-vs-union gap: it has the most
watercourses per patch, at 3.66.

No ground is lost that a passing group does not also lose: LARL's true union (0.961) is above KISP's
(0.952). The threshold was set on species networks (MORR 0.966), and it was not loosened here.
Filed as its own issue.

**Second correction (same day):** over all 23 groups, the area-weighted max is *lower* than the
unweighted one in some (WILL 0.947 -> 0.924, MORR 0.953 -> 0.942), and FRAN fails weighted at
0.8994, with a true union of 0.9235. So weighting explains the three failures, but it is not a fix.
The issue recommends asserting the true union, measured at 0.92-0.96 on eight groups.

## Code-check round 1 (branch, 2026-10-17)

`review-round1.md`, nine findings, all real:
- **Runner, guard failing toward pass:** a crash inside the `all_ff04` disturbance section read
  PASS. The section is the last in every log, and an error prints no summary line. It now reads
  INCOMPLETE unless the section closes.
- **Runner:** `'^ *FAIL '` also matched the column-0 summary lines of provenance-check
  (`FAIL — n problem(s).`) and dem_cache-check (`FAIL (n failure)`), double-counting. The pattern
  is now `'^  FAIL '`.
- **Report:** `coverage_csv()` fell back past a resumed run to an older CSV, possibly a species-mode
  one. It now takes the newest only, and a cached row gets no wall time.
- **Claims:** "passed acceptance" before the habitat join ran; "±0.1 ha" when the range is −0.07 to
  +0.12 (LSAL); "reproduced the Skeena log" without the 0.7 ha exception; `co_ff04` for NECR's
  reference, which is `ch_ff04`; Fraser's end time 05:18 for 05:19; placeholder issue numbers (to
  be replaced when GitHub answers; it timed out from ~18:25 UTC).

Mutation table, second pass (`scratchpad/mut2`): provenance with one FAIL plus its summary gives
FAIL(1); dem_cache likewise FAIL(1); a crash inside the `all_ff04` section gives INCOMPLETE; a FAIL
in the section closed by the next header gives FAIL(1). Re-parsing every real check log with the new
rules leaves every committed table unchanged.

## Code-check round 2 (2026-10-17)

`review-round2.md`. Round 1's three code fixes held: BSD awk with an in-section FAIL, a crash, a
warning after the summary, and CRLF (fails closed as INCOMPLETE). Four findings, all real. **One
sits inside a round-1 fix**, so only an enumeration ends the loop:
- **Report, one step on from fix 3:** nothing tied the newest coverage CSV to the run whose outputs
  are on disk. A group's wall time now counts only when its step-3 record time lies in that group's
  own window [previous log mtime, its log mtime]. The step-3 time is `run.repairs[[1]]` when #126
  re-stamped the record. The CSV's `provenance` column is not used: Skeena's holds pre-fix values.
  Mutation: `RUN_STAMP=columbia=20260827_190638` (a species-mode run) blanks KOTL, LARL and SLOC and
  names them. All 23 real groups keep their wall times.
- **Runner:** `grep | sed || echo none` never printed "none", because the pipeline's status is
  sed's. It is now captured, then tested.
- **Claims:** CLAUDE.md counted PCEA's outlier flag as a FAIL. PCEA's composition FAIL is
  +225.39% (1,700.3 ha of change on the reservoir outside its polygon), not the #53 edge. The other
  22 groups breach at +1.11% to +7.81% (WILL the highest).
