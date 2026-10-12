# Whole-network floodplain in the pipeline: DUNC pilot (#104, #120)

Run 2026-10-12 UTC (2026-10-11 evening PDT) on the commit that added whole-network mode
(`species: all`), by `scripts/run_area.R dunc <step>`, each step in its own process under
`/usr/bin/time -l`. Run logs are gitignored under `logs/runs/2026101[2]_*dunc*`. Toolchain:
flooded 0.6.5, terra 1.9.50, link installed 0.50.0. Config: `config/dunc/` (`species: all`,
`min_order: 2`, `network_source: fresh`, `attribute_by: blue_line_key`, scenarios
`all_ff02/04/06`, primary `all_ff04`).

DUNC is a new area, so there is no published item to supersede. It has no `fresh.log` row and no
`fresh.streams_access` rows, so it is the first area to record a null `link_log` (with its note) and
`link_config_name_source: unresolved` live.

## Step 1: network + habitat table

| | |
|---|---|
| wall / peak RSS | 6.8 s / 0.47 GB (re-run after review fixes: 7.6 s / 0.47 GB) |
| network | `streams_all2`: 13,023 segments, 3,493 km, 2,236 blue lines; 211 waterbodies |
| freshness | 3,493 km vs bcfp 3,493 km = 0.0% (guard strict) |
| habitat | `habitat_link`: 53,654 rows, bt 26,827 + wct 26,827 (every order, link `fresh`) |
| FWA version | `fwapg_sha` null (`unresolved`, no log row); `fwa_content_sha256` `sha256:049289d4…` |

## Step 2: delineation + blue-line attribution

DEM 4,034 x 4,465 = 18.0 M cells at 30.17 m (0.0910 ha per cell). Stage times are from output
mtimes (step 2 does not timestamp its stages).

| stage | wall |
|---|---|
| sub-basin + DEM fetch + precip + `all_ff02` VCA | 4.1 min (01:20:22 → 01:24:29) |
| `all_ff04` VCA | 0.7 min |
| `all_ff04` attribution by `blue_line_key`, 2,236 groups | ~3.3 min |
| `all_ff06` VCA | ~0.7 min |
| **total** | **8.9 min (534 s)**, peak RSS **13.3 GB** |

| scenario | valley cells | km² |
|---|---|---|
| `all_ff02` | 196,456 | 178.8 |
| `all_ff04` | 203,285 | 185.0 |
| `all_ff06` | 205,508 | 187.0 |

- **Attribution:** 1,942 of 2,236 blue lines carry floodplain; 294 reach no valley cell within the
  thresholds and are omitted (flooded's warning). 1,159 fallback cells were placed by nearest group.
  Rows overlap by design: they sum to 530.6 km² over a 185.0 km² floodplain (mean 2.87 claims per
  cell). 137 rows carry a `gnis_name`.
- **Cost against #110's measurements (flooded 0.6.0):** BULK's order ≥ 2 attribution took 170 min
  and MORR's (an 18.1 M-cell grid, like DUNC's) 33 min. DUNC's, on 0.6.5 with flooded#71 and #72 in,
  took ~3.3 min. The DEM fetch was fast this time (#122's slow S3 is intermittent).
- Warnings, not errors: flooded's `field` deprecation (twice; `area_field` is the new name, left for
  a separate change since it touches every area's call) and the 294 omitted groups. 0 errors.

## Step 3: land cover, transition, disturbance, composition, bridge

| | |
|---|---|
| wall / peak RSS | 9.7 min (580 s) / 19.3 GB |
| land cover | IO LULC 2017, 2020, 2023 (endpoints + midpoint; `lulc_annual` not set) |
| transition | `transition_all_ff04_2017_2023`: 1,282 change patches ≥ 1 ha, 710.1 ha |
| disturbance | fire, harvest; context wetland, ALR; lookback `fire_prior` |
| bridge | `patch_watercourse_all_ff04_2017_2023`: 4,088 pairs over 1,280 patches and 188 blue lines; union coverage 0.928, 2 patches unbridged |
| composition | `composition_all_ff04_2017_2023`: floodplain 18,485.7 ha (cell centres) of a 20,136.3 ha classified footprint (+8.9%; NECR +5.5%, BULK +6.3%); change 743.3 ha; wetland 633.5 ha (74.8 ha changed); ALR 3,399.8 ha (283.6 ha changed) |
| gross tree loss | 119.5 ha in 271 patches (to Rangeland 78.6, Water 32.0, Built Area 5.1 ha); fire 0%, harvest 32.6%, not attributed 67.4% by area |

The footprint ring is wider than on the species areas, which fits a network of narrower order-2
corridors with more edge per hectare.

Checks: `bridge-check.R dunc all_ff04` PASS; `provenance-check.R dunc` PASS, including the habitat
sibling reconciled against `habitat_link` (53,654 rows, digest equal) and the null `link_log`;
`composition-check.R dunc` **FAILS one assertion**:

> change ha >= the transition layer's sum(area_ha), by under 1% (sub-basin clipping only):
> cells 743.3 ha vs patches 710.1 ha, +4.67%

The direction is the expected one, and the cause is the one the check names. Step 3 clips the
patches to the sub-basin, here the DUNC group polygon, and the composition does not. The bound was
measured on three species networks (NECR +0.37%, BULK +0.34%, neexdzii +0.29%). The whole network
puts more floodplain past the group boundary: **205.4 ha of DUNC's 18,500.7 ha (1.1%) lies outside
the DUNC polygon**, and 41.2 ha of the raw 2017→2023 change (before the 1 ha sieve) sits there,
which covers the 33.2 ha gap. The guard was not loosened. Its tolerance is a measured property of
species-network areas, and whole-network areas need it re-derived on a second group. This is #53's
cross-boundary floodplain, measured on a whole-network area.

## Habitat join (consumer side)

`habitat_join-query.R dunc`, log `20261012_habitat_join-query_dunc.md`. Every floodplain cell is
attributed and none is outside the floodplain. `habitat_link` matches all 26,827 of the schema's
segments for both species. 99.8% of spawning km (bt and wct) sits on a blue line with floodplain,
and 99.3% (bt) / 99.7% (wct) of rearing km. The rest, 5.9 km (bt) and 1.6 km (wct), is all on
order-1 blue lines, which the floor leaves out.

| ha, `all_ff04` | bt spawning | bt rearing | wct spawning | wct rearing |
|---|---|---|---|---|
| by blue line (contrast) | 16,907 | 17,847 | 16,614 | 16,716 |
| by position, nearest (areas) | 5,101 | 15,111 | 4,809 | 5,280 |
| by position, any (connected) | 5,908 | 16,637 | 5,532 | 5,906 |

By blue line, 91% of the floodplain reads as bull trout spawning floodplain; by position, 28%.
This is the same contrast MORR showed (82% against 24% for chinook), so the join rule carries
across groups.

## Caveats

- **The grid will move when flooded#67 lands.** This run warped MRDEM on GDAL 3.13 (#117), so a
  re-run after the grid pin moves the DUNC areas by a fraction of a percent with no data change.
- **Only `all_ff04` is keyed by blue line** (02 attributes the primary scenario only).
- **DUNC is not staged for publishing.** `stac_floodplains_bc` stages from region rosters, and
  region runs refuse `species: all`. The publish hint printed after steps 2 and 3 does not apply.
