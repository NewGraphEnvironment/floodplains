# #104 floor check, arms 5, 3, 2 on MORR (co_ff04)

Produced by `scripts/floodplain_lcc/floodplain_probe-subset.R morr` from the arms in `data/morr/probe_whole_fwa/`, 2026-10-10 23:49 PDT. Formulas are floodplain_probe-report.R's sections 2 and 3. flooded 0.6.0, terra 1.9.50 (GDAL 3.13.0).

## Cost (DEM + delineation + blue-line attribution, per scenario; the rule's figures)

```
 arm segments blue_lines dem_min delin_min attr_min total_min peak_gib
   5     4877        340     0.9       1.2     13.8      15.9      9.3
   3     7606        401     0.9       1.4     17.6      19.9      8.9
   2    20812       1711     0.9       1.9     33.0      35.8      7.9
```

## Area on the common grid

```
   pair  a_ha  b_ha gained_ha lost_ha gained_share_of_b gained_outside_wb_share
 2_vs_3 47884 37478     10908     502             0.291                   0.803
 2_vs_5 47884 35654     12674     444             0.355                   0.792
 3_vs_5 37478 35654      1825       1             0.051                   0.735
```

## Supersession: the coho network's floodplain under each delineation

```
 arm reach_ha arm5_reach_ha gained_ha lost_ha moved_share
   3    34899         34344       556       1       0.016
   2    39168         34344      5267     443       0.166
```
