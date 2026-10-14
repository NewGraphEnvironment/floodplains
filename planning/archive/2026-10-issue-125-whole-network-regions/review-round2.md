# Code-check round 2 (#125): review of the round-1 fixes (f860c95)

Offline checks: `region_config-check.R` all PASS, `whole_network-check.R` PASS.

Fix 1 (`[[` in `fp_region_mode` / `fp_region_min_order`) is correct. The remaining `$` reads on
yaml lists in the diff (`reg$network_source`, `reg$species`, `reg$watershed_groups`,
`region_owned$species`, `area$targets`, `t$scenario`) either have the exact key guaranteed present
by an earlier validation, or have no longer sibling key to partial-match into in any config on disk.
No further partial-match defects found.

## Findings

- **[severity: bug]** scripts/run_region.R:197-213 with scripts/floodplain_lcc/fp_region.R:159-166
  (also `fp_region_cache_stale`, :167-172). The fix still loses the signal on a resume, in the
  common case. Both cache rules read records written at the START of the child pipeline: step 1
  writes `network[<sp><order>]` and step 2 writes `floodplain[<primary>]`. The resume marker they
  guard, `lulc_summary_<sp>_ff04.rds`, is unlinked only late in step 3
  (`03_lulc_classify.R:451`, after the STAC fetch and classification). So a group that runs
  step 1 under the new config and is then interrupted before 03:451 leaves this state: the network
  record matches the new config, the primary floodplain record is >= 0.7.0, and the summary on disk
  is still the OLD config's. On resume `moved` and `stale` are both FALSE, and the group is reported
  `ok(cached)` and handed to the publish hint with the old landcover. The window is roughly steps 2
  and 3: DEM fetch, VCA and STAC fetch, tens of minutes per group. That is the most likely place for
  an interruption to land.

  It hits the live case the fix names. DUNC joins columbia.yml (fresh -> fresh_default). Step 1
  writes `all2.read_schema = fresh_default` and step 2 writes `all_ff04` on flooded 0.7.0. The run is
  killed during step 3's fetch. `lulc_summary_all_ff04.rds` from 2026-10-12 (fresh, 0.6.5 grid) is
  still present. Reproduced purely:

  ```r
  prov <- list(network = list(all2 = list(inputs = list(read_schema = "fresh_default"))),
               floodplain = list(all_ff04 = list(inputs = list(flooded = list(version = "0.7.0")))))
  area <- list(species = "all", min_order = 2L, schema = "dunc", network_source = "fresh_default")
  fp_region_cache_moved(prov, area)          # FALSE
  fp_region_cache_stale(prov, "all_ff04")    # FALSE  -> group SKIPPED as complete
  ```

  A `min_order` change fails the same way. Step 1 writes the new `all3` entry, and the summary
  filename carries no order, so the order-2 summary passes as current.

  The CLAUDE.md sentence added in f860c95 ("read from the record ... because ... a resume would see
  no diff") states that this case is covered, and it is not.

  Smallest fix: when run_region.R decides to re-run a group because it is `stale`, `moved`, or
  `FORCE`, unlink `summary_rds` (and the shared `lulc_summary.rds`) BEFORE `system2()`. The decision
  then survives any interruption, because without the marker the next run re-runs the group. An
  alternative is to also require `landcover[<primary>].run` to be no older than the network and
  floodplain records. Caveat: DUNC's own record has the `all2` network stamp (01:29:39Z) later than
  its `all_ff04` floodplain stamp (01:25:14Z), so an ordering rule would also fire after a
  standalone step-1 re-run. That fails toward re-running, which is safe but noisy.
