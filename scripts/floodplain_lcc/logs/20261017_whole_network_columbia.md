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

The acceptance checks ran 2026-10-17, 17:56 to 18:04 UTC, read-only on the run's outputs. They ran on
flooded 0.8.2, installed at 11:00 UTC that day, not the run's 0.7.0. Of the five checks, only
`dem_cache-check.R` reads the installed flooded, and it passed against 0.8.2's default; the others
read the run's records. **Peak RSS was not sampled.** Wall times
come from the log mtimes.


Produced by `Rscript scripts/floodplain_lcc/region_acceptance-report.R columbia`, 2026-10-17 20:16 UTC. Timings from `data/logs/region_columbia_20261015_171455.csv` (log mtimes).

## Results

| group | network km (order >= 2) | freshness | habitat_link rows | ff02 / ff04 / ff06 km2 | blue lines | transition patches (< 1 ha) | gross tree loss | fire / harvest / unattributed | bridge union (unbridged) | wall min |
|---|---|---|---|---|---|---|---|---|---|---|
| KOTL | 5,722.7 | 0.0% dev | 439,804 (bt, ko, rb, wct) | 720.6 / 754.1 / 768.1 | 2,320 | 5,657 (5,091); 3,248.6 ha | 643.1 ha in 1,249 | 3.5 / 29.2 / 67.2% | 0.946 (5) | 48.6 |
| LARL | 4,540.0 | 0.0% dev | 273,231 (bt, rb, wct) | 368.3 / 375.5 / 382.5 | 2,052 | 2,936 (2,595); 1,886.8 ha | 379.4 ha in 754 | 23.0 / 26.5 / 54.9% | 0.889 (10) | 23.4 |
| SLOC | 2,635.9 | 0.0% dev | 167,190 (bt, rb, wct) | 152.1 / 154.5 / 156.6 | 1,330 | 1,179 (1,060); 398.8 ha | 119.7 ha in 323 | 2.0 / 9.9 / 89.6% | 0.894 (5) | 10.2 |
| DUNC | 3,493.0 | 0.0% dev | 189,201 (bt, rb, wct) | 179.1 / 185.2 / 187.2 | 1,948 | 1,299 (1,158); 715.0 ha | 116.9 ha in 270 | 0.0 / 30.1 / 69.9% | 0.927 (5) | 13.1 |

## Coverage and the #53 edge

| group | classified in floodplain / floodplain | change cells | inside polygon | outside | patches | inside - patches | floodplain outside polygon | km2 per km |
|---|---|---|---|---|---|---|---|---|
| KOTL | 75,354.9 / 75,414.2 ha (0.9992) | 3,390.9 | 3,248.5 | 142.4 | 3,248.6 | -0.1 | 923.3 of 75,414.2 ha (1.22%) | 0.1318 |
| LARL | 37,526.8 / 37,550.9 ha (0.9994) | 1,907.7 | 1,886.8 | 20.9 | 1,886.8 | +0.0 | 343.8 of 37,550.9 ha (0.92%) | 0.0827 |
| SLOC | 15,437.3 / 15,449.5 ha (0.9992) | 404.2 | 398.8 | 5.4 | 398.8 | +0.0 | 128.2 of 15,449.5 ha (0.83%) | 0.0586 |
| DUNC | 18,505.4 / 18,521.4 ha (0.9991) | 748.6 | 715.0 | 33.6 | 715.0 | -0.0 | 204.9 of 18,521.4 ha (1.11%) | 0.0530 |

A transition patch is one row of the transition layer: one 8-connected patch of a single transition code (drift's `dft_transition_vectors()`). Step 3's 1 ha sieve applies to the 8-connected change region around it, so most rows are smaller; the count under 1 ha is in brackets. Step 3's log calls them "change patches >= 1 ha", which describes the region, not the row. Blue lines, the bridge and the cause shares are read from layers whose writers record no digest (`attribute_tag.R` and `fire_tag.R` rewrite them in place), so they are those layers' state when the report ran. Every other figure is tied to `provenance.json` (see the report's header).

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
  unions, area-weighted, are 0.9610 and 0.9363. Filed as #139.

## Habitat join (2026-10-18)

`habitat_join-query.R <wsg>` for each group, on flooded 0.8.2 (`fl_valley_join()`), run sequentially from 2026-10-18 01:30 UTC. Each run wrote its own log, `scripts/floodplain_lcc/logs/20261018_habitat_join-query_<wsg>.md`, and this table is parsed from those. Habitat flags come from each group's `habitat_link` (model `link:fresh_default`), and segment geometry from the live schema, matched on (blue_line_key, downstream_route_measure). "Missing" and "extra" are floodplain cells the attribution layer lacks or adds; "unmatched" counts habitat rows with no segment at that position, per species (the same in every species).

| wsg | floodplain cells | missing | extra | species | habitat rows | rows = segments = matched | unmatched | blue lines without segments |
|---|---|---|---|---|---|---|---|---|
| KOTL | 837936 | 0 | 0 | bt,ko,rb,wct | 109951 | NO | 21 | 0 |
| LARL | 417232 | 0 | 0 | bt,rb,wct | 91077 | NO | 35 | 0 |
| SLOC | 171661 | 0 | 0 | bt,rb,wct | 55730 | NO | 10 | 0 |
| DUNC | 205793 | 0 | 0 | bt,rb,wct | 63067 | yes | 0 | 0 |

Every floodplain cell is attributed in all four groups. **KOTL, LARL and SLOC each have habitat rows the
live schema no longer has (0.02-0.04% of rows), and the cause is a rebuild, not these runs.** link 0.66.0
rebuilt `fresh_default` for all four groups on 2026-10-17 between 01:30 and 03:10 UTC (`fresh_default.log`,
`run_uid` 20261017_004619-3f4c713b). Step 1 wrote their `habitat_link` on 2026-10-15: KOTL, LARL and SLOC
from the 2026-08-27 build (link 0.45.1), DUNC from the 2026-10-12 build (link 0.63.1). Each group's
`network[all2].link_log` records its build; `fresh_default.log` now holds only the 2026-10-17 run, so
that record is the only place the older builds remain. The query reads segment geometry from the live
schema, so re-segmented reaches stop matching: KOTL now has 109,950 segments against 109,951 habitat rows,
LARL 91,090 against 91,077, SLOC 55,733 against 55,730. DUNC's segmentation did not move between its 2026-10-12 and 2026-10-17 builds. #123 already plans
cutting segment lines from FWA blue lines by route measure, which makes the join a function of
`habitat_link` alone; this measurement is recorded there. DUNC's
`20261015_habitat_join-query_dunc.md` predates its re-run on the pinned grid and is superseded by the
20261018 log.
