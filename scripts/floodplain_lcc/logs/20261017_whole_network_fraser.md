# Whole-network floodplains, Fraser region: acceptance (#125)

`caffeinate -s Rscript scripts/run_region.R fraser` (steps 1,2,3) ran 2026-10-15 00:17 to 05:19 UTC,
about 5 h, on flooded 0.7.0 (the pinned grid, #117), drift 0.20.0, terra 1.9.50 (GDAL 3.13.0 / PROJ 9.8.1),
and sf 1.1.2 (GDAL 3.8.5 / PROJ 9.5.1). Every group was `ok` with no error in its log. The run log is
`20261014_run_region_fraser.log`; the group logs and coverage CSV are gitignored under
`data/logs/region_fraser_*_20261015_001710*`. Reconciliation converted all 13 `area.yml` files to
`species: all` and appended the six `all_*` rows to each `flood_scenarios.csv` (760b8d9). The region
reads `fresh`, and every group's whole network matched bcfp to the km under the strict guard. Every DEM
was a cache miss (`dem_all2.tif` is new) and fetched in 11–42 s.

The acceptance checks ran 2026-10-17, read-only on the run's outputs and on the same toolchain.
**Peak RSS was not sampled for this run.** Wall times are differences of the group log mtimes,
starting from the run stamp.


Produced by `Rscript scripts/floodplain_lcc/region_acceptance-report.R fraser`, 2026-10-17 20:14 UTC. Timings from `data/logs/region_fraser_20261015_001710.csv` (log mtimes).

## Results

| group | network km (order >= 2) | freshness | habitat_link rows | ff02 / ff04 / ff06 km2 | blue lines | transition patches (< 1 ha) | gross tree loss | fire / harvest / unattributed | bridge union (unbridged) | wall min |
|---|---|---|---|---|---|---|---|---|---|---|
| LCHL | 2,459.9 | 0.0% dev | 63,516 (bt, ch, co) | 395.6 / 426.8 / 456.8 | 998 | 9,396 (8,241); 4,802.0 ha | 1,526.4 ha in 2,043 | 6.6 / 20.8 / 73.5% | 0.928 (13) | 12.4 |
| LSAL | 1,397.0 | 0.0% dev | 11,609 (ch) | 261.8 / 290.9 / 314.4 | 466 | 4,562 (3,909); 2,535.3 ha | 1,003.9 ha in 1,118 | 0.0 / 34.5 / 65.5% | 0.947 (5) | 8.2 |
| WILL | 2,296.2 | 0.0% dev | 78,489 (bt, ch, co) | 331.5 / 351.2 / 369.2 | 861 | 2,337 (1,918); 1,631.6 ha | 679.3 ha in 725 | 0.2 / 31.5 / 68.3% | 0.947 (3) | 12.7 |
| TABR | 1,544.4 | 0.0% dev | 29,304 (bt, ch) | 242.5 / 267.2 / 290.3 | 615 | 2,646 (2,206); 1,799.9 ha | 634.6 ha in 803 | 0.2 / 41.4 / 58.4% | 0.937 (6) | 8.4 |
| UFRA | 5,059.5 | 0.0% dev | 192,598 (bt, ch) | 282.7 / 301.7 / 311.9 | 2,613 | 10,799 (10,134); 3,037.2 ha | 827.2 ha in 2,544 | 0.0 / 13.1 / 86.9% | 0.940 (32) | 32.7 |
| NECR | 3,522.9 | 0.0% dev | 119,804 (bt, ch, co, sk) | 699.7 / 759.6 / 813.4 | 1,336 | 11,323 (9,386); 10,003.3 ha | 4,463.8 ha in 3,545 | 31.0 / 39.8 / 37.2% | 0.918 (24) | 30.9 |
| MORK | 6,790.1 | 0.0% dev | 221,020 (bt, ch) | 604.5 / 667.0 / 729.7 | 3,361 | 6,502 (5,734); 3,371.6 ha | 1,063.0 ha in 1,547 | 1.3 / 36.4 / 62.5% | 0.947 (6) | 50.2 |
| FRAN | 4,992.9 | 0.0% dev | 160,074 (bt, ch, sk) | 1,059.4 / 1,096.3 / 1,130.3 | 1,879 | 9,888 (7,884); 12,002.5 ha | 10,139.8 ha in 4,211 | 80.1 / 34.5 / 10.7% | 0.916 (11) | 40.8 |
| BOWR | 2,567.8 | 0.0% dev | 146,904 (bt, ch, co, sk) | 368.5 / 390.0 / 409.1 | 1,083 | 2,346 (1,984); 1,412.7 ha | 586.5 ha in 623 | 0.7 / 37.0 / 62.3% | 0.927 (6) | 16.3 |
| MCGR | 2,832.5 | 0.0% dev | 98,010 (bt, ch) | 328.4 / 355.3 / 372.0 | 1,647 | 4,063 (3,519); 2,426.5 ha | 776.7 ha in 658 | 0.0 / 53.3 / 46.7% | 0.956 (0) | 22.2 |
| THOM | 2,975.2 | 0.0% dev | 372,912 (bt, ch, co, pk, sk, st) | 248.4 / 257.0 / 265.3 | 1,400 | 2,564 (2,007); 2,709.0 ha | 1,169.1 ha in 561 | 80.4 / 15.9 / 17.2% | 0.911 (6) | 12.8 |
| LNTH | 3,704.5 | 0.0% dev | 321,660 (bt, ch, co, pk, sk) | 369.1 / 388.6 / 408.0 | 1,558 | 4,745 (4,124); 2,504.8 ha | 746.5 ha in 1,356 | 4.1 / 28.4 / 67.5% | 0.953 (6) | 33.1 |
| UNTH | 3,784.0 | 0.0% dev | 218,766 (bt, ch, co) | 226.5 / 234.9 / 242.2 | 1,753 | 4,544 (4,178); 1,441.1 ha | 672.9 ha in 1,329 | 0.0 / 26.5 / 73.5% | 0.949 (6) | 21.6 |

## Coverage and the #53 edge

| group | classified in floodplain / floodplain | change cells | inside polygon | outside | patches | inside - patches | floodplain outside polygon | km2 per km |
|---|---|---|---|---|---|---|---|---|
| LCHL | 42,647.6 / 42,681.2 ha (0.9992) | 5,002.4 | 4,802.0 | 200.4 | 4,802.0 | +0.0 | 1,388.6 of 42,681.2 ha (3.25%) | 0.1735 |
| LSAL | 29,064.6 / 29,088.5 ha (0.9992) | 2,629.4 | 2,535.4 | 94.0 | 2,535.3 | +0.1 | 615.9 of 29,088.5 ha (2.12%) | 0.2082 |
| WILL | 35,098.5 / 35,124.5 ha (0.9993) | 1,759.1 | 1,631.6 | 127.5 | 1,631.6 | -0.0 | 875.5 of 35,124.5 ha (2.49%) | 0.1530 |
| TABR | 26,698.4 / 26,719.1 ha (0.9992) | 1,854.6 | 1,799.9 | 54.7 | 1,799.9 | -0.0 | 846.3 of 26,719.1 ha (3.17%) | 0.1730 |
| UFRA | 30,170.8 / 30,173.2 ha (0.9999) | 3,071.7 | 3,037.2 | 34.5 | 3,037.2 | -0.0 | 374.4 of 30,173.2 ha (1.24%) | 0.0596 |
| NECR | 75,909.1 / 75,959.1 ha (0.9993) | 10,193.5 | 10,003.4 | 190.1 | 10,003.3 | +0.1 | 1,014.8 of 75,959.1 ha (1.34%) | 0.2156 |
| MORK | 66,677.2 / 66,704.0 ha (0.9996) | 3,466.3 | 3,371.6 | 94.7 | 3,371.6 | +0.0 | 1,152.8 of 66,704.0 ha (1.73%) | 0.0982 |
| FRAN | 109,638.8 / 109,630.9 ha (1.0001) | 12,275.5 | 12,002.5 | 272.9 | 12,002.5 | -0.0 | 1,223.5 of 109,630.9 ha (1.12%) | 0.2196 |
| BOWR | 38,975.1 / 38,999.0 ha (0.9994) | 1,456.6 | 1,412.8 | 43.9 | 1,412.7 | +0.0 | 1,033.0 of 38,999.0 ha (2.65%) | 0.1519 |
| MCGR | 35,517.4 / 35,533.1 ha (0.9996) | 2,506.2 | 2,426.4 | 79.8 | 2,426.5 | -0.1 | 1,072.2 of 35,533.1 ha (3.02%) | 0.1254 |
| THOM | 25,698.7 / 25,704.2 ha (0.9998) | 2,835.9 | 2,709.1 | 126.8 | 2,709.0 | +0.0 | 561.5 of 25,704.2 ha (2.18%) | 0.0864 |
| LNTH | 38,862.0 / 38,856.2 ha (1.0001) | 2,549.7 | 2,504.8 | 44.8 | 2,504.8 | +0.0 | 909.1 of 38,856.2 ha (2.34%) | 0.1049 |
| UNTH | 23,490.7 / 23,493.2 ha (0.9999) | 1,464.1 | 1,441.1 | 23.0 | 1,441.1 | +0.0 | 190.9 of 23,493.2 ha (0.81%) | 0.0621 |

A transition patch is one row of the transition layer: one 8-connected patch of a single transition code (drift's `dft_transition_vectors()`). Step 3's 1 ha sieve applies to the 8-connected change region around it, so most rows are smaller; the count under 1 ha is in brackets. Step 3's log calls them "change patches >= 1 ha", which describes the region, not the row. Blue lines, the bridge and the cause shares are read from layers whose writers record no digest (`attribute_tag.R` and `fire_tag.R` rewrite them in place), so they are those layers' state when the report ran. Every other figure is tied to `provenance.json` (see the report's header).

## Checks

`bash scripts/floodplain_lcc/region_checks-run.sh fraser`, 2026-10-17. Full outputs are in
`data/logs/region_checks_fraser_20261017_173748/` (gitignored). `dem_cache-check.R` (offline) PASS.

| group | `provenance-check.R` | `composition-check.R` | `bridge-check.R` | `disturbance-check.R` (all layers) | `disturbance-check.R`, `all_ff04` section |
|---|---|---|---|---|---|
| LCHL | PASS | FAIL(1) | PASS | FAIL(2) | PASS |
| LSAL | PASS | FAIL(1) | PASS | FAIL(2) | PASS |
| WILL | PASS | FAIL(1) | PASS | FAIL(2) | PASS |
| TABR | PASS | FAIL(1) | PASS | FAIL(2) | PASS |
| UFRA | PASS | FAIL(1) | PASS | FAIL(2) | PASS |
| NECR | PASS | FAIL(2) | PASS | PASS | PASS |
| MORK | PASS | FAIL(1) | PASS | FAIL(2) | PASS |
| FRAN | PASS | FAIL(1) | PASS | FAIL(2) | PASS |
| BOWR | PASS | FAIL(1) | PASS | FAIL(2) | PASS |
| MCGR | PASS | FAIL(1) | PASS | FAIL(2) | PASS |
| THOM | PASS | FAIL(1) | PASS | FAIL(2) | PASS |
| LNTH | PASS | FAIL(1) | PASS | FAIL(2) | PASS |
| UNTH | PASS | FAIL(1) | PASS | FAIL(2) | PASS |

The failures, every one read from its `FAIL` line:

- **`composition-check.R`, FAIL(1) in all 13:** the 1% change-vs-patch bound. This is the #53 edge
  effect. The "inside − patches" column above shows change cells inside the group polygon equal the
  patch totals within 0.12 ha in every group (LSAL +0.12).
- **`disturbance-check.R`, FAIL(2) in 12:** on the retired `ch_ff04` transition layers, which predate
  the context and lookback overlays (#95, #103). Those columns are forward-only, and these layers
  will not see another step 3. NECR has none of these failures because its species layer was
  re-tagged under #95. The `all_ff04` section passes in all 13.
- **`composition-check.R` NECR, second FAIL:** check (5), the accuracy module's wetland reference
  (12,809.04 vs 6,436.64 ha). That reference describes the species footprint, not `all_ff04`.
  NECR's #93 reference design is drawn on `ch_ff04`, while `fp_acc_area()` now resolves
  `area.yml`'s `all_ff04`. Filed as #140.

## Habitat join (2026-10-18)

`habitat_join-query.R <wsg>` for each group, on flooded 0.8.2 (`fl_valley_join()`), run sequentially from 2026-10-18 01:30 UTC. Each run wrote its own log, `scripts/floodplain_lcc/logs/20261018_habitat_join-query_<wsg>.md`, and this table is parsed from those. Habitat flags come from each group's `habitat_link` (model `link:fresh`), and segment geometry from the live schema, matched on (blue_line_key, downstream_route_measure). "Missing" and "extra" are floodplain cells the attribution layer lacks or adds; "unmatched" counts habitat rows with no segment at that position, per species (the same in every species).

| wsg | floodplain cells | missing | extra | species | habitat rows | rows = segments = matched | unmatched | blue lines without segments |
|---|---|---|---|---|---|---|---|---|
| LCHL | 474236 | 0 | 0 | bt,ch,co | 21172 | yes | 0 | 0 |
| LSAL | 323205 | 0 | 0 | ch | 11609 | yes | 0 | 0 |
| WILL | 390272 | 0 | 0 | bt,ch,co | 26163 | yes | 0 | 0 |
| TABR | 296879 | 0 | 0 | bt,ch | 14652 | yes | 0 | 0 |
| UFRA | 335258 | 0 | 0 | bt,ch | 96299 | yes | 0 | 0 |
| NECR | 843990 | 0 | 0 | bt,ch,co,sk | 29951 | yes | 0 | 0 |
| MORK | 741156 | 0 | 0 | bt,ch | 110510 | yes | 0 | 0 |
| FRAN | 1218121 | 0 | 0 | bt,ch,sk | 53358 | yes | 0 | 0 |
| BOWR | 433322 | 0 | 0 | bt,ch,co,sk | 36726 | yes | 0 | 0 |
| MCGR | 394812 | 0 | 0 | bt,ch | 49005 | yes | 0 | 0 |
| THOM | 285602 | 0 | 0 | bt,ch,co,pk,sk,st | 62152 | yes | 0 | 0 |
| LNTH | 431735 | 0 | 0 | bt,ch,co,pk,sk | 64332 | yes | 0 | 0 |
| UNTH | 261036 | 0 | 0 | bt,ch,co | 72922 | yes | 0 | 0 |

Every floodplain cell is attributed in all 13 groups, and every habitat row matches a `fresh.streams` segment.
