# Whole-network floodplains, Columbia region: acceptance (#125)

`run_region.R columbia` (steps 1,2,3) ran 2026-10-15 17:14 to 18:50 UTC, chained after Peace, on the
same toolchain (flooded 0.7.0, drift 0.20.0, terra 1.9.50). All four groups were `ok` with no error in
their logs. The run log is `20261015_run_region_columbia.log`; the group logs and coverage CSV are
gitignored under `data/logs/region_columbia_*_20261015_171455*`. Reconciliation converted KOTL, LARL
and SLOC to `species: all` and moved DUNC's `network_source` from `fresh` to `fresh_default` (2dda619).
The cache redid DUNC because its floodplain record was below flooded 0.7.0 (`fp_region_cache_stale`).
The region reads `fresh_default` with `network_guard` strict, and every network matched bcfp to the
km. #37's divergence was an access-predicate difference and does not arise without one. Every DEM was
a cache miss and fetched in 22–52 s.

The acceptance checks ran 2026-10-17 on the same toolchain. **Peak RSS was not sampled.** Wall times
come from the log mtimes.


Produced by `Rscript scripts/floodplain_lcc/region_acceptance-report.R columbia`, 2026-10-17 18:40 UTC. Timings from `data/logs/region_columbia_20261015_171455.csv` (log mtimes).

## Results

| group | network km (order >= 2) | freshness | habitat_link rows | ff02 / ff04 / ff06 km2 | blue lines | patches >= 1 ha | gross tree loss | fire / harvest / unattributed | bridge union (unbridged) | wall min |
|---|---|---|---|---|---|---|---|---|---|---|
| KOTL | 5,722.7 | 0.0% dev | 439,804 (bt, ko, rb, wct) | 720.6 / 754.1 / 768.1 | 2,320 | 5,657 (3,248.6 ha) | 643.1 ha in 1,249 | 3.5 / 29.2 / 67.2% | 0.946 (5) | 48.6 |
| LARL | 4,540.0 | 0.0% dev | 273,231 (bt, rb, wct) | 368.3 / 375.5 / 382.5 | 2,052 | 2,936 (1,886.8 ha) | 379.4 ha in 754 | 23.0 / 26.5 / 54.9% | 0.889 (10) | 23.4 |
| SLOC | 2,635.9 | 0.0% dev | 167,190 (bt, rb, wct) | 152.1 / 154.5 / 156.6 | 1,330 | 1,179 (398.8 ha) | 119.7 ha in 323 | 2.0 / 9.9 / 89.6% | 0.894 (5) | 10.2 |
| DUNC | 3,493.0 | 0.0% dev | 189,201 (bt, rb, wct) | 179.1 / 185.2 / 187.2 | 1,948 | 1,299 (715.0 ha) | 116.9 ha in 270 | 0.0 / 30.1 / 69.9% | 0.927 (5) | 13.1 |

## Coverage and the #53 edge

| group | classified in floodplain / floodplain | change cells | inside polygon | outside | patches | inside - patches | floodplain outside polygon | km2 per km |
|---|---|---|---|---|---|---|---|---|
| KOTL | 75,354.9 / 75,414.2 ha (0.9992) | 3,390.9 | 3,248.5 | 142.4 | 3,248.6 | -0.1 | 923.3 of 75,414.2 ha (1.22%) | 0.1318 |
| LARL | 37,526.8 / 37,550.9 ha (0.9994) | 1,907.7 | 1,886.8 | 20.9 | 1,886.8 | +0.0 | 343.8 of 37,550.9 ha (0.92%) | 0.0827 |
| SLOC | 15,437.3 / 15,449.5 ha (0.9992) | 404.2 | 398.8 | 5.4 | 398.8 | +0.0 | 128.2 of 15,449.5 ha (0.83%) | 0.0586 |
| DUNC | 18,505.4 / 18,521.4 ha (0.9991) | 748.6 | 715.0 | 33.6 | 715.0 | -0.0 | 204.9 of 18,521.4 ha (1.11%) | 0.0530 |

DUNC's figures replace the 2026-10-12 run on flooded 0.6.5's pre-pin grid (`20261012_whole_network_dunc.md`:
185.0 km², 1,942 blue lines, 1,282 patches, 119.5 ha of tree loss). On the pinned grid they are
185.2 km², 1,948 blue lines, 1,299 patches and 116.9 ha.

## Checks

`bash scripts/floodplain_lcc/region_checks-run.sh columbia`, 2026-10-17. Full outputs are in
`data/logs/region_checks_columbia_20261017_175645/` (gitignored). `dem_cache-check.R` (offline) PASS.

| group | `provenance-check.R` | `composition-check.R` | `bridge-check.R` | `disturbance-check.R` (all layers) | `disturbance-check.R`, `all_ff04` section |
|---|---|---|---|---|---|
| KOTL | PASS | FAIL(1) | PASS | FAIL(2) | PASS |
| LARL | PASS | FAIL(1) | FAIL(1) | FAIL(2) | PASS |
| SLOC | PASS | FAIL(1) | FAIL(1) | FAIL(2) | PASS |
| DUNC | PASS | FAIL(1) | PASS | PASS | PASS |

- **`composition-check.R`, FAIL(1) in all four:** the #53 bound. Change cells inside the polygon equal
  the patch totals within 0.07 ha.
- **`disturbance-check.R`, FAIL(2) in KOTL, LARL and SLOC:** on the retired `bt_ff04` layers. DUNC has
  no species layer. The `all_ff04` section passes in all four.
- **`bridge-check.R` LARL (0.8886) and SLOC (0.8944):** the unweighted union-coverage proxy. Their true
  unions, area-weighted, are 0.9610 and 0.9363. Filed as #BRIDGE.
