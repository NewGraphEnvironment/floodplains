# #104 floor check, arms 5, 3, 2 on BULK (co_ff04)

Produced by `scripts/floodplain_lcc/floodplain_probe-subset.R bulk` from the arms in `data/bulk/probe_whole_fwa/`, 2026-10-10 23:51 PDT. Formulas are floodplain_probe-report.R's sections 2 and 3. flooded 0.6.0, terra 1.9.50 (GDAL 3.13.0).

## Cost (DEM + delineation + blue-line attribution, per scenario; the rule's figures)

```
 arm segments blue_lines dem_min delin_min attr_min total_min peak_gib
   5     6858        428    37.2       2.7     47.4      87.2     19.6
   3    12533        601    37.2       4.8     75.9     117.9     18.3
   2    31631       2550    37.2       5.9    170.0     213.1     17.3
```

## Area on the common grid

```
   pair  a_ha  b_ha gained_ha lost_ha gained_share_of_b gained_outside_wb_share
 2_vs_3 66215 43827     23841    1453             0.544                   0.878
 2_vs_5 66215 38439     28909    1133             0.752                   0.837
 3_vs_5 43827 38439      5471      83             0.142                   0.676
```

## Supersession: the coho network's floodplain under each delineation

```
 arm reach_ha arm5_reach_ha gained_ha lost_ha moved_share
   3    38788         38153       718      83       0.021
   2    45709         38153      8683    1128       0.257
```
