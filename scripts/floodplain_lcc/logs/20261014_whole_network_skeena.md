# Whole-network floodplains, Skeena region (#125)

Run 2026-10-14 UTC by `caffeinate -s Rscript scripts/run_region.R skeena` (steps 1,2,3), the
first region run in `network: whole` mode. It ran from a frozen worktree at b4414eb with `data/`
symlinked to the main checkout, so commits made during the run could not reach the children.
Toolchain: flooded 0.7.0 (the pinned grid, #117), drift 0.20.0, terra 1.9.50, link installed
0.50.0. Run logs are gitignored under `data/logs/region_skeena_*_20261014_123741.log`, and the
coverage CSV is at `data/logs/region_skeena_20261014_123741.csv`.

The region file is `config/regions/skeena.yml`: `network: whole`, `network_source: fresh`,
groups BULK, MORR, KISP. Each group is `species: all`, `min_order: 2`, primary `all_ff04`, and
`attribute_by: blue_line_key`. The `area.yml` files were converted by hand first, so reconciliation
reported them `unchanged`; it appended the six `all_*` rows to each `flood_scenarios.csv`. `DRY=1`
beforehand printed exactly that and wrote nothing (md5 of every `config/*/area.yml` and
`flood_scenarios.csv` unchanged).

## Wall time and memory

| group | wall | peak RSS |
|---|---|---|
| BULK | 59.0 min (12:37:41 → 13:36:43) | 16.5 GiB |
| MORR | 15.7 min (→ 13:52:26) | 16.4 GiB |
| KISP | 24.0 min (→ 14:16:25) | 16.4 GiB |

Wall times are taken from the log mtimes. RSS is the sum over all R processes, sampled every
30 s; it is not `/usr/bin/time` per step, so it is an approximate upper envelope. BULK runs
`lulc_annual: true` (seven classified years). All three DEMs were cache misses (`dem_all2.tif` is
new) and fetched in 35.8 s, 18.6 s and 36.7 s. NRCan's bucket was fast on the day; #122 measured
~37 min for BULK on a slow day.

## Results

| | BULK | MORR | KISP |
|---|---|---|---|
| network, order ≥ 2 | 5,929.4 km | 3,471.1 km | 4,231.0 km |
| freshness vs bcfp (strict) | 0.0% | 0.0% | 0.0% |
| `habitat_link` rows | 525,834 (bt, ch, co, pk, sk, st) | 351,678 (same six) | 535,612 (adds cm) |
| `all_ff02` / `all_ff04` / `all_ff06` km² | 610.9 / 660.0 / 698.9 | 462.4 / 479.3 / 494.0 | 306.7 / 324.4 / 340.5 |
| blue lines with floodplain (`all_ff04`) | 2,392 | 1,635 | 1,887 |
| change patches ≥ 1 ha, 2017→2023 | 9,210 (5,584.9 ha) | 3,351 (1,747.2 ha) | 5,170 (2,099.4 ha) |
| gross tree loss | 2,793.4 ha in 2,922 patches | 659.5 ha in 842 | 350.5 ha in 863 |
| fire / harvest / not attributed (by area) | 3.8 / 40.0 / 57.7% | 13.9 / 31.8 / 54.3% | 13.4 / 26.3 / 72.6% |
| bridge union coverage | 0.942 (11 unbridged) | 0.953 (2) | 0.901 (17) |

Fire and harvest are additive (a salvage patch is both), so the three shares can sum past 100%.
These numbers replace nothing: the species items (BULK `co_ff04` 386.5 km², MORR `co_ff04`
357.7 km²) measured the accessible network at order ≥ 3, a different population.

## Checks

Run from the worktree, so against the config the run used:

| check | BULK | MORR | KISP |
|---|---|---|---|
| `provenance-check.R <area>` | PASS | PASS | PASS |
| `bridge-check.R <area> all_ff04` | PASS | PASS | PASS |
| `disturbance-check.R <area>`, `all_ff04` section | PASS | PASS | PASS |
| `composition-check.R <area> all_ff04` | 1 FAIL (+1.47%) | 1 FAIL (+4.40%) | 1 FAIL (+1.27%) |
| `dem_cache-check.R` (offline) | PASS | | |

Before the run, `provenance-check.R morr` and `kisp` were baselined from a worktree at 4995867:
both PASS.

**`disturbance-check.R` FAILs for MORR (4) and KISP (2) are on the retired species layers**
(`transition_co_ff04_*`, `transition_ch_ff06_*`, `transition_ch_ff04_*`). Those layers predate the
context and lookback overlays (#95, #103), which are forward-only and only arrive with a step 3 that
these items will never get again. The `all_ff04` sections pass.

**The `composition-check.R` bound breach is the #53 edge effect, measured.** Step 3 clips the
patches to the sub-basin (the group polygon); the composition counts every cell. Change cells
inside the group polygon equal the patch totals:

| group | change cells | inside polygon | outside | patches |
|---|---|---|---|---|
| BULK | 5,666.9 ha | 5,584.9 | 82.0 | 5,584.9 |
| MORR | 1,824.1 ha | 1,747.3 | 76.8 | 1,747.2 |
| KISP | 2,126.0 ha | 2,099.4 | 26.6 | 2,099.4 |

2.0% of BULK's `all_ff04` floodplain (1,318.2 of 65,999.2 ha) lies past the BULK polygon. DUNC
failed the same assertion at +4.7% for the same reason (`20261012_whole_network_dunc.md`). The
guard's 1% tolerance was measured on species networks; it was not loosened.

## What this does downstream

- The coverage CSV's `provenance` column shows the replaced species records' dates. The run's
  code predated the fix that re-reads the primary record after the child runs (e32f9b8).
- The publish hint printed the stac release sequence, but that sequence cannot stage these
  groups until NewGraphEnvironment/stac_floodplains_bc#75. Their `provenance.json` now carries
  `all_*` keys, which its key-shape check refuses.
