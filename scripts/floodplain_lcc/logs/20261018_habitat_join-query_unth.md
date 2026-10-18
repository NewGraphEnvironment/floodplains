# Habitat join on the published whole-network floodplain, UNTH (#104)

Produced by `scripts/floodplain_lcc/habitat_join-query.R unth`, 2026-10-17 18:54 PDT. Floodplain `all_ff04` (`species: all`, order >= 2), attributed by `blue_line_key` (`all_ff04_by_blue_line_key`). Habitat flags from `habitat_link` (model `link:fresh`); segment geometry from `fresh.streams`, every order, matched on (blue_line_key, downstream_route_measure). flooded 0.8.2, terra 1.9.50.

Joins: **by blue line**, a blue line's whole floodplain takes any habitat on it (the contrast, not an answer); 
**by position**, each cell takes the nearest segment on each blue line that claims it, then **nearest** 
(one owner per cell; the rule for areas) or **any** (habitat if any claiming blue line says so; the connected view).

## Integrity

```
 floodplain_cells attributed_cells missing extra
           261036           261036       0     0
```

## Shared ground

```
 floodplain_cells floodplain_ha claiming_blue_lines share_claimed_by_2plus
           261036       23493.2                1753               0.789726
 mean_claims
     2.94891
```

## Habitat table against the schema's segments

```
 species habitat_rows schema_segments segments_matched habitat_rows_unmatched
      bt        72922           72922            72922                      0
      ch        72922           72922            72922                      0
      co        72922           72922            72922                      0
```

## Habitat km, and how much sits on a blue line with floodplain

```
 species spawning_km spawning_km_on_fp_blk rearing_km rearing_km_on_fp_blk
      bt     544.449               543.288    719.295              717.350
      ch     429.826               429.060    470.929              470.163
      co     478.623               477.858    526.744              518.733
 habitat_km_off_fp_blk_order1 habitat_km_off_fp_blk_order2plus
                     1.944586                                0
                     0.765707                                0
                     8.010817                                0
```

## Habitat floodplain (ha)

```
                 join species spawning_ha rearing_ha  both_ha spawn_only_ha
         by blue line      bt    18521.55   18622.89 18487.62         33.93
 by position, nearest      bt     9637.65   11755.44  9632.34          5.31
     by position, any      bt    11429.64   12426.57 11429.64          0.00
         by blue line      ch    18198.63   18244.89 18198.63          0.00
 by position, nearest      ch     8456.85    9141.57  8456.85          0.00
     by position, any      ch    10703.52   10825.02 10703.52          0.00
         by blue line      co    18296.46   18307.44 18296.46          0.00
 by position, nearest      co     9301.59   10213.83  9301.59          0.00
     by position, any      co    11010.69   11246.22 11010.69          0.00
 rear_only_ha tied_cells blk_without_segments
       135.27         NA                   NA
      2123.10        545                    0
       996.93         NA                    0
        46.26         NA                   NA
       684.72        545                    0
       121.50         NA                    0
        10.98         NA                   NA
       912.24        545                    0
       235.53         NA                    0
```

Run time: 87 s.
