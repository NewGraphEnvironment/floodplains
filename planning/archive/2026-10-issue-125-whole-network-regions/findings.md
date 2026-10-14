# Findings — Whole-network floodplains for every region (#125)

## Issue context

**If we do it:** every region (Skeena, Fraser, Peace, Columbia) runs as whole-network floodplains (`species: all`, order >= 2, keyed by `blue_line_key`, #104) through `run_region.R`, and the publish layer picks its groups up from the region roster.
**If we never do:** whole-network areas run only standalone (`run_area.R`), none is published, and the catalogue stays on the per-species model we are moving away from.

Split out of #123 (its part 3). GeoParquet and the FWA-position habitat join stay in #123. Segments and habitat flags are not published from here (link's export, NewGraphEnvironment/link#308).

**Scope changed 2026-10-13.** This was Columbia only, with the other regions staying on their species and Columbia's `bt` items kept beside the new ones. Both are reversed by the decisions below.

## Decided

- **Whole network everywhere** (2026-10-13). Every region moves to `species: all`. DUNC (#120) already runs this way.
- **Species items are retired, not re-run** (2026-10-13). The published `co_*`, `ch_*` and `bt_*` items are removed from the catalogue as each group's `all` item replaces them. Removing them per group means the catalogue never loses a group. The removal is the publish layer's work, in NewGraphEnvironment/stac_floodplains_bc#76; the coupling stays one-way. Re-running them would cost compute to republish a product we are moving away from, and #117's grid change would move every one of them anyway.

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
   - **MCGR is still blocked**: it has no rows in `fresh.streams` (#76), and whole mode reads the same table.
   - **PINE**: its 10.8% shortfall (#76) was measured on the accessible network. Measure the whole network before running it.
   - Check what the GRAB freshness guard compares in whole mode. Its reference is per-species bcfp access, which has no meaning for `all`.
6. **Publish.** NewGraphEnvironment/stac_floodplains_bc#75 drops the key-shape whitelist that refuses `all_ff04`. NewGraphEnvironment/stac_floodplains_bc#76 retires the species items.

## Order

1. #117 first (flooded 0.7.0's fixed grid). Every step-2 output moves once, and that move should not land mixed in with this one.
2. #122 (cache the DEM per area). Every group is about to be re-run, BULK probably more than once.
3. This issue's code, then **Skeena** (BULK, MORR, KISP). It is the smallest region and BULK is the README's figure area (#128).
4. Fraser, Peace, Columbia.

**DUNC is cached on the old grid.** Its `lulc_summary_all_ff04.rds` and `provenance.json` exist from 2026-10-12, written with flooded 0.6.5 (`dem_res_m` 30.167632). `run_region.R`'s cache (`file.exists(summary_rds) && file.exists(prov_json)`) would report it complete and skip it. Run it with `FORCE=1`, or make the cache refuse a floodplain record whose `flooded` version is below 0.7.0 (#117).

`neexdzii` stays the coho parity fixture through #117. It is not published, so retiring species items does not touch it. Whether it gains a whole-network twin as the parity check for this mode is a plan-gate question here.

## Cost to expect

DUNC took 8.9 min for step 2 and 9.7 min for step 3, at 13.3 / 19.3 GB peak (`scripts/floodplain_lcc/logs/20261012_whole_network_dunc.md`). KOTL's order >= 2 network is 1.6x DUNC's km, LARL's 1.3x. BULK's DEM fetch alone took ~37 min uncached (#122).

## What this closes

A full whole-network re-run supersedes #58 and #59 (over-mapped species areas) and #73 (provenance rollout to species areas). Close each with a pointer here once its groups have run.

Relates: #104, #117, #120, #122, #123, #128, #53, #76



## Exploration measurements (2026-10-13, local fwapg)

Order >= 2 km per group (`sum(length_metre)` / 1000):

| wsg | fresh.streams | fresh_default.streams | fresh.streams_vw_bcfp | FWA |
|---|---|---|---|---|
| BULK | 5929 | 5929 | 5929 | 5924 |
| MORR | 3471 | 3471 | 3471 | 3475 |
| KISP | 4231 | 4231 | 4231 | 4231 |
| BOWR / MCGR / THOM / LNTH / UNTH | 2568 / 2833 / 2975 / 3705 / 3784 | absent | equal to fresh | ~equal |
| PCEA / PARS / PINE | 5494 / 5167 / 5768 | equal | equal | ~equal |
| KOTL / LARL / SLOC | absent | 5723 / 4540 / 2636 | equal to fresh_default | ~equal |
| DUNC | 3493 | 3493 | 3493 | 3493 |

- MCGR is present in `fresh.streams` (#76 measured 0 rows on 2026-09-03 on the accessible network).
- PINE whole network equals bcfp; #76's -10.8% was the bt-accessible network.
- Every group has `streams_habitat_<sp>` rows in its region's schema (fresh: bt/ch/co/... ; fresh_default adds rb/gr/ko).
- `fp_bcfp_km_sql("all", ...)` already compares total km, so the guard is meaningful in whole mode.

## Mutation table — Phase 3 guards (2026-10-14)

Each defect restored in a scratch copy of the repo, both checks run; red = non-zero exit or a FAIL line.

| mutation | region_config-check | whole_network-check |
|---|---|---|
| M0 none (baseline) | rc 0, 0 FAIL | rc 0, 0 FAIL |
| M1 whole region also refuses an existing whole area | rc 1 (aborts) | rc 1, 4 FAIL |
| M2 targets refusal removed | 1 FAIL | 0 |
| M3 cache compares version strings (`"0.10.0" < "0.7.0"`) | 2 FAIL | 0 |
| M4 whole mode accepts a species list | 1 FAIL | 0 |
| M5 plan skips `fp_whole_network_validate` | 0 | rc 1, 1 FAIL (after fixing the arm, below) |
| M6 whole min_order a double (yaml writes `2.0`) | 3 FAIL | 0 |
| M7 whole mode keeps the region's attribute_by | rc 1, 1 FAIL | rc 1, 3 FAIL |
| M8 citation carry removed (review G6) | rc 1, 1 FAIL | 0 |
| M9 whole min_order floor removed (review A2) | rc 1, 1 FAIL | 0 |
| M5 re-run after the gnis_name arm | 0 | rc 1, 2 FAIL |
| M10 `reg$network` again (code-check r1: partial-matches network_source) | rc 1, 1 FAIL | 0 |
| M11 cache_moved ignores read_schema | rc 1, 1 FAIL | 0 |
| M12 ordering rule never fires (code-check r3) | rc 1, 5 FAIL | 0 |
| M13 ordering ignores run.repairs | rc 1, 1 FAIL | 0 |

## Cache verdict: termination by enumeration (code-check r3, 2026-10-14)

Mechanism (r3): co-presence on disk was read as co-provenance. Steps 1, 2 and 3 write the records
the cache reads at different times. Every writer of those records:

| writer | record it moves | closed by |
|---|---|---|
| 01 `fp_prov_set(network)` | `network[<sp><ord>]` run stamp + `read_schema` | ordering + `fp_region_cache_moved` |
| 01 `fp_prov_set_sibling(habitat)` | sibling of network; not read by the cache | n/a |
| 02 `fp_prov_set(floodplain)` | primary floodplain stamp + `flooded` version | ordering + `fp_region_cache_stale` |
| 03 `fp_prov_set(landcover)` | the completion record, written before the summary | summary absent => re-run |
| `fp_composition` sibling | inside landcover; no stamp regression | n/a |
| `raster_strip-tags.R` `fp_prov_reconcile_late` | moves `datetime_utc`, appends `repairs` | step-3 time from `previous_datetime_utc` (M13) |

`fire_tag.R`, `attribute_tag.R`, `composition_build.R` write no record the cache reads.
r3 finding 3 (provenance-check 7c's "step 3 died in its composition" message now has a second cause)
accepted: unreachable for `all_*` records, which all carry a composition.

M5 first came back green on both. The arm "refuses 'all' from a region missing network_source" built
its owned list through `fp_region_owned()`, which calls `fp_region_mode()`, which refuses a species list
naming `all` -- so the error came from the mode check and the plan's own validation was never reached.
The arm now builds the list by hand, with a control that the same list plus a `network_source` plans.
The first counter also read an aborted script as 0 FAIL; it now reports the exit status too.

## Errors Encountered

| Error | Resolution |
|-------|------------|
