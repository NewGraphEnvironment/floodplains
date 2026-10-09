# Whole-FWA floodplain probe: MORR, `co_ff04` (#110)

Report 2026-10-09 09:49 UTC. flooded 0.6.0, terra 1.9.50 (GDAL 3.13.0), sf 1.1.2 (GDAL 3.8.5). Produced by `scripts/floodplain_lcc/floodplain_probe-run.sh morr`; rule in `research/whole_fwa_floodplain.md`.

## Anchor

- arm 5 network vs step 1's record: MATCH
- arm 5 DEM vs `fp_floodplain()` replayed the same day: MATCH; floodplain: MATCH
- vs the published 2026-09-03 record: DEM DIFFERS, floodplain DIFFERS (35769.1 ha published, 35618.0 ha today, -0.42%)

## Cost and size per arm (common DEM: 18,087,342 cells, fetched in 0.9 min, 3.3 GiB peak)

| arm | label | segments | km | blue_lines | waterbodies | floodplain_km2 | waterbody_share | t_delin_min | t_attr_blk_min | attr_rows | fallback_cells | peak_rss_gb |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | all fresh.streams (order >= 1) | 58,613 | 9,033.096 | 6,753 | 3,666 | 651.917 | 0.416 | 2.813 | 87.015 | 5,817 | 1,309 | 9.020 |
| 2 | order >= 2 | 20,812 | 3,471.053 | 1,711 | 1,178 | 478.839 | 0.503 | 1.850 | 33.032 | 1,633 | 6,988 | 7.918 |
| 3 | order >= 3 | 7,606 | 1,650.897 | 401 | 478 | 374.780 | 0.563 | 1.405 | 17.640 | 397 | 14,171 | 8.872 |
| 4 | order >= 3 + first-order with parent >= 5 (bcfp bypass) | 14,641 | 2,835.318 | 1,195 | 989 | 454.493 | 0.504 | 1.698 | 28.925 | 1,108 | 3,692 | 9.123 |
| 5 | species network (baseline) | 4,877 | 1,295.578 | 340 | 412 | 356.542 | 0.578 | 1.222 | 13.832 | 339 | 14,170 | 9.305 |

Segment-grain attribution on arm 3: 7,606 segments, 31.5 min (0.248 s per segment), 6,908 rows, 2.7 GiB peak.

Blue-line attribution across the five arms: 790 s + 0.661 s per blue line (the slope is confounded with valley extent).

## Area on the common grid (ha; a = first arm, b = second)

| pair | both_ha | gained_ha | lost_ha | gained_in_waterbody_ha | gained_outside_wb_share | gained_share_of_b |
|---|---|---|---|---|---|---|
| 1_vs_2 | 47,059.09 | 18,132.630 | 824.817 | 2,494.082 | 0.862 | 0.379 |
| 2_vs_3 | 36,975.71 | 10,908.193 | 502.280 | 2,144.319 | 0.803 | 0.291 |
| 4_vs_3 | 37,169.90 | 8,279.373 | 308.091 | 996.873 | 0.880 | 0.221 |
| 3_vs_5 | 35,653.34 | 1,824.653 | 0.833 | 482.926 | 0.735 | 0.051 |
| 1_vs_5 | 35,202.27 | 29,989.450 | 451.904 | 5,324.406 | 0.822 | 0.841 |
| 2_vs_5 | 35,210.32 | 12,673.580 | 443.847 | 2,635.672 | 0.792 | 0.355 |
| 4_vs_5 | 35,394.51 | 10,054.762 | 259.659 | 1,486.003 | 0.852 | 0.282 |

Extent and regridding effect: arm 5 on the common grid 35654.2 ha vs on its own grid 35618.0 ha (+0.102%).

## The coho network's floodplain under each delineation, arm k vs arm 5 (ha)

Valley cells inside the zone the coho seeds reach (distance and cost from coho seeds only), so it carries the boundary move plus tributary-mouth valleys and waterbodies new seeds bring into that zone.

| arm | reach_ha | arm5_reach_ha | gained_ha | gained_in_waterbody_ha | lost_ha | moved_share |
|---|---|---|---|---|---|---|
| 1 | 44,004.94 | 34,343.84 | 10,111.342 | 1,010.208 | 450.237 | 0.308 |
| 2 | 39,168.37 | 34,343.84 | 5,267.177 | 601.550 | 442.643 | 0.166 |
| 3 | 34,899.36 | 34,343.84 | 556.360 | 16.391 | 0.833 | 0.016 |
| 4 | 37,217.68 | 34,343.84 | 3,132.858 | 326.519 | 259.011 | 0.099 |

Per-blk attributed area for the coho network's blue lines (includes added seeds, so not the supersession measure):

| arm | blk | ha_5 | ha_k | median_ratio | share_up_10pct | share_down_10pct |
|---|---|---|---|---|---|---|
| 1 | 339 | 69,319.88 | 93,804.62 | 1.591 | 0.850 | 0.003 |
| 2 | 339 | 69,319.88 | 82,185.61 | 1.271 | 0.708 | 0.006 |
| 3 | 339 | 69,319.88 | 71,555.22 | 1.004 | 0.212 | 0.000 |
| 4 | 339 | 69,319.88 | 76,668.96 | 1.083 | 0.469 | 0.009 |

## Habitat by order band (`fresh.streams_vw_bcfp`, modelled = codes 1, 2; km)

| order_band | bypass | km | rearing_co_km | rearing_ch_km | spawning_co_km | spawning_ch_km |
|---|---|---|---|---|---|---|
| 1 | FALSE | 4,377.6 | 34.5 | 5.5 | 2.1 | 0.3 |
| 1 | TRUE | 1,184.4 | 22.1 | 10.2 | 6.7 | 5.0 |
| 2 | FALSE | 1,820.2 | 251.8 | 140.1 | 129.1 | 25.5 |
| 3+ | FALSE | 1,650.9 | 916.4 | 723.6 | 773.5 | 612.9 |

Share below order 3: coho rearing 25.2%, chinook rearing 17.7%, coho spawning 15.1%, chinook spawning 4.8%.

## Pre-registered rule

| floor | arm | cost_min | peak_rss_gb | added_share_of_arm3 | outside_wb_share | affordable | adds_floodplain | visual | supersedes |
|---|---|---|---|---|---|---|---|---|---|
| order >= 2 (arm 2 vs 3) | 2 | 35.757 | 7.918 | 0.291 | 0.803 | TRUE | TRUE | pending | TRUE |
| order >= 1 (arm 1 vs 2) | 1 | 90.703 | 9.020 | 0.484 | 0.862 | FALSE | TRUE | pending | TRUE |
| bypass (arm 4 vs 3) | 4 | 31.498 | 9.123 | 0.221 | 0.880 | TRUE | TRUE | pending | TRUE |

Segment grain at the measured arm-3 rate:

| arm | segments | seg_attr_min_est | seg_affordable |
|---|---|---|---|
| 1 | 58,613 | 242.500 | FALSE |
| 2 | 20,812 | 86.106 | FALSE |
| 3 | 7,606 | 31.468 | TRUE |
| 4 | 14,641 | 60.574 | FALSE |
| 5 | 4,877 | 20.178 | TRUE |

Review layers: `data/morr/probe_whole_fwa/review.gpkg`; panels: `panel_1.png`, `panel_2.png`, `panel_3.png`, `panel_4.png`, `panel_5.png`, `panel_6.png`, `panel_order2_1.png`, `panel_order2_2.png`, `panel_order2_3.png`, `panel_order2_4.png`, `panel_bypass_1.png`, `panel_bypass_2.png`, `panel_bypass_3.png`, `panel_bypass_4.png`.
