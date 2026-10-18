# Habitat join on the published whole-network floodplain, BOWR (#104)

Produced by `scripts/floodplain_lcc/habitat_join-query.R bowr`, 2026-10-17 18:45 PDT. Floodplain `all_ff04` (`species: all`, order >= 2), attributed by `blue_line_key` (`all_ff04_by_blue_line_key`). Habitat flags from `habitat_link` (model `link:fresh`); segment geometry from `fresh.streams`, every order, matched on (blue_line_key, downstream_route_measure). flooded 0.8.2, terra 1.9.50.

Joins: **by blue line**, a blue line's whole floodplain takes any habitat on it (the contrast, not an answer); 
**by position**, each cell takes the nearest segment on each blue line that claims it, then **nearest** 
(one owner per cell; the rule for areas) or **any** (habitat if any claiming blue line says so; the connected view).

## Integrity

```
 floodplain_cells attributed_cells missing extra
           433322           433322       0     0
```

## Shared ground

```
 floodplain_cells floodplain_ha claiming_blue_lines share_claimed_by_2plus
           433322         38999                1083               0.732921
 mean_claims
     2.67163
```

## Habitat table against the schema's segments

```
 species habitat_rows schema_segments segments_matched habitat_rows_unmatched
      bt        36726           36726            36726                      0
      ch        36726           36726            36726                      0
      co        36726           36726            36726                      0
      sk        36726           36726            36726                      0
```

## Habitat km, and how much sits on a blue line with floodplain

```
 species spawning_km spawning_km_on_fp_blk rearing_km rearing_km_on_fp_blk
      bt    1046.273              1041.942  1618.8193            1612.3866
      ch     655.314               655.262   913.8771             910.9306
      co     929.742               926.473  1177.2447            1149.9201
      sk      21.518                21.518    82.4454              44.0162
 habitat_km_off_fp_blk_order1 habitat_km_off_fp_blk_order2plus
                      6.22496                         0.207765
                      2.94644                         0.000000
                     27.32458                         0.000000
                     38.42921                         0.000000
```

## Habitat floodplain (ha)

```
                 join species spawning_ha rearing_ha  both_ha spawn_only_ha
         by blue line      bt    37303.56   37702.17 37279.89         23.67
 by position, nearest      bt    18209.43   31400.64 18206.73          2.70
     by position, any      bt    23686.83   34299.00 23686.83          0.00
         by blue line      ch    33737.58   36089.46 33737.58          0.00
 by position, nearest      ch    12247.56   17035.02 12247.56          0.00
     by position, any      ch    17155.71   22109.49 17155.71          0.00
         by blue line      co    36704.52   37014.57 36704.52          0.00
 by position, nearest      co    16818.84   23890.05 16818.84          0.00
     by position, any      co    21988.35   27351.63 21988.35          0.00
         by blue line      sk    15936.57   16573.41 15936.57          0.00
 by position, nearest      sk      641.07    3095.73   218.88        422.19
     by position, any      sk      916.02    3665.16   362.16        553.86
 rear_only_ha tied_cells blk_without_segments
       422.28         NA                   NA
     13193.91        855                    0
     10612.17         NA                    0
      2351.88         NA                   NA
      4787.46        855                    0
      4953.78         NA                    0
       310.05         NA                   NA
      7071.21        855                    0
      5363.28         NA                    0
       636.84         NA                   NA
      2876.85        855                    0
      3303.00         NA                    0
```

Run time: 107 s.
