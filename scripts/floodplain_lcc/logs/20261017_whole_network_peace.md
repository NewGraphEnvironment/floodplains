# Whole-network floodplains, Peace region: acceptance (#125)

`run_region.R peace` (steps 1,2,3) ran 2026-10-15 15:44 to 17:15 UTC, chained ahead of Columbia,
on the Fraser run's toolchain (flooded 0.7.0, drift 0.20.0, terra 1.9.50). All three groups were `ok`
with no error in their logs. The run log is `20261015_run_region_peace.log`; the group logs and
coverage CSV are gitignored under `data/logs/region_peace_*_20261015_154454*`. Reconciliation
converted PCEA, PARS and PINE to `species: all` with six `all_*` rows each. The region reads `fresh`,
and every network matched bcfp to the km (PINE 5,768 km: #76's species-network shortfall does not
arise in whole mode). Every DEM was a cache miss and fetched in 30–42 s.

The acceptance checks ran 2026-10-17 on the same toolchain. **Peak RSS was not sampled.** Wall times
come from the log mtimes.


Produced by `Rscript scripts/floodplain_lcc/region_acceptance-report.R peace`, 2026-10-17 20:08 UTC. Timings from `data/logs/region_peace_20261015_154454.csv` (log mtimes).

## Results

| group | network km (order >= 2) | freshness | habitat_link rows | ff02 / ff04 / ff06 km2 | blue lines | transition patches (< 1 ha) | gross tree loss | fire / harvest / unattributed | bridge union (unbridged) | wall min |
|---|---|---|---|---|---|---|---|---|---|---|
| PCEA | 5,493.9 | 0.0% dev | 106,079 (bt) | 840.2 / 843.3 / 846.6 | 2,793 | 1,565 (1,397); 754.4 ha | 227.7 ha in 286 | 52.2 / 45.8 / 39.8% | 0.898 (8) | 19.6 |
| PARS | 5,167.4 | 0.0% dev | 97,534 (bt) | 538.8 / 559.4 / 577.2 | 3,041 | 9,189 (8,074); 6,070.8 ha | 1,753.0 ha in 1,761 | 1.2 / 58.9 / 40.3% | 0.971 (9) | 32.8 |
| PINE | 5,767.8 | 0.0% dev | 113,305 (bt) | 460.7 / 488.9 / 515.3 | 3,061 | 9,604 (8,720); 4,107.5 ha | 1,033.0 ha in 1,971 | 1.0 / 30.8 / 68.2% | 0.947 (12) | 37.6 |

## Coverage and the #53 edge

| group | classified in floodplain / floodplain | change cells | inside polygon | outside | patches | inside - patches | floodplain outside polygon | km2 per km |
|---|---|---|---|---|---|---|---|---|
| PCEA | 84,270.0 / 84,334.4 ha (0.9992) | 2,454.6 | 754.4 | 1,700.3 | 754.4 | -0.0 | 35,196.9 of 84,334.4 ha (41.73%) | 0.1535 |
| PARS | 55,904.6 / 55,944.2 ha (0.9993) | 6,290.1 | 6,070.8 | 219.3 | 6,070.8 | +0.0 | 633.1 of 55,944.2 ha (1.13%) | 0.1083 |
| PINE | 48,857.3 / 48,887.3 ha (0.9994) | 4,212.4 | 4,107.5 | 105.0 | 4,107.5 | -0.0 | 986.7 of 48,887.3 ha (2.02%) | 0.0848 |

A transition patch is one row of the transition layer: one transition class within an 8-connected change region. Step 3's 1 ha sieve applies to the region, so most rows are smaller, and the count under 1 ha is in brackets. Step 3's log calls them "change patches >= 1 ha", which describes the region, not the row.

## PCEA is mostly Williston Reservoir

The outlier screen (`region_acceptance-report.R all`, rule in its header, fixed before these numbers
were read) flagged PCEA at 41.7% of its floodplain outside the group polygon. The 23-group median is
1.73% (IQR 1.12–2.42%).

- 83.6% of PCEA's `all_ff04` lies on reservoir or large lakes (FWA manmade waterbodies plus lakes over
  1,000 ha, by cell centre). Its ff02 / ff04 / ff06 areas are nearly flat (840 / 843 / 847 km²),
  because a reservoir floods whatever the factor.
- The outside share lies in PARA (Parsnip Arm) and FINA (Finlay Arm), the other arms of Williston,
  which is a single FWA polygon. No region lists either group.
- **This predates whole mode.** The retired `bt_ff04` was 92.1% reservoir and 58.4% outside.
- The land cover is not double-counted: change cells inside the polygon equal the patch total
  (754.4 ha).

Filed as #WATERBODY. PCEA is on the visual-review list (#VISUAL).

## Checks

`bash scripts/floodplain_lcc/region_checks-run.sh peace`, 2026-10-17. Full outputs are in
`data/logs/region_checks_peace_20261017_175253/` (gitignored). `dem_cache-check.R` (offline) PASS.

| group | `provenance-check.R` | `composition-check.R` | `bridge-check.R` | `disturbance-check.R` (all layers) | `disturbance-check.R`, `all_ff04` section |
|---|---|---|---|---|---|
| PCEA | PASS | FAIL(1) | FAIL(1) | FAIL(2) | PASS |
| PARS | PASS | FAIL(1) | PASS | FAIL(2) | PASS |
| PINE | PASS | FAIL(1) | PASS | FAIL(2) | PASS |

- **`composition-check.R`, FAIL(1) in all three:** the 1% change-vs-patch bound. PARS and PINE breach
  it by the #53 edge effect, as Fraser and Skeena do. PCEA breaches it by +225.4% (2,454.6 ha of
  change cells against 754.4 ha of patches). 1,700.3 ha of the change lies outside its polygon, and
  1,627.0 ha of that is on the network's waterbody polygons, by cell centre. That is the waterbody spill above (#WATERBODY), not the #53 edge. Inside the
  polygon, change and patches agree.
- **`disturbance-check.R`, FAIL(2) in all three:** on the retired `bt_ff04` layers. The `all_ff04`
  section passes.
- **`bridge-check.R` PCEA, FAIL(1):** `union coverage >= 0.90 mean`, 0.8980. This is the check's
  unweighted proxy. The true union, area-weighted, is 0.9405. Every other bridge assertion passes,
  including apportioned tree loss reconciling to the ungrouped total. Filed as #BRIDGE.
