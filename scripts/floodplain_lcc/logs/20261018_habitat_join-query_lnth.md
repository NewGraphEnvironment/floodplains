# Habitat join on the published whole-network floodplain, LNTH (#104)

Produced by `scripts/floodplain_lcc/habitat_join-query.R lnth`, 2026-10-17 18:52 PDT. Floodplain `all_ff04` (`species: all`, order >= 2), attributed by `blue_line_key` (`all_ff04_by_blue_line_key`). Habitat flags from `habitat_link` (model `link:fresh`); segment geometry from `fresh.streams`, every order, matched on (blue_line_key, downstream_route_measure). flooded 0.8.2, terra 1.9.50.

Joins: **by blue line**, a blue line's whole floodplain takes any habitat on it (the contrast, not an answer); 
**by position**, each cell takes the nearest segment on each blue line that claims it, then **nearest** 
(one owner per cell; the rule for areas) or **any** (habitat if any claiming blue line says so; the connected view).

## Integrity

```
 floodplain_cells attributed_cells missing extra
           431735           431735       0     0
```

## Shared ground

```
 floodplain_cells floodplain_ha claiming_blue_lines share_claimed_by_2plus
           431735       38856.2                1558               0.782881
 mean_claims
     3.19621
```

## Habitat table against the schema's segments

```
 species habitat_rows schema_segments segments_matched habitat_rows_unmatched
      bt        64332           64332            64332                      0
      ch        64332           64332            64332                      0
      co        64332           64332            64332                      0
      pk        64332           64332            64332                      0
      sk        64332           64332            64332                      0
```

## Habitat km, and how much sits on a blue line with floodplain

```
 species spawning_km spawning_km_on_fp_blk rearing_km rearing_km_on_fp_blk
      bt    781.9389              781.4686  1238.8248            1234.1008
      ch    471.2928              470.8575   559.5442             559.0979
      co    553.9725              553.5262   614.5022             613.1101
      pk    581.2561              580.0689     0.0000               0.0000
      sk     17.2503               17.2503    42.6398              28.8527
 habitat_km_off_fp_blk_order1 habitat_km_off_fp_blk_order2plus
                     4.723993                                0
                     0.446283                                0
                     1.392107                                0
                     1.187283                                0
                    13.787075                                0
```

## Habitat floodplain (ha)

```
                 join species spawning_ha rearing_ha  both_ha spawn_only_ha
         by blue line      bt    32510.07   33786.36 32325.12        184.95
 by position, nearest      bt    14095.44   22198.68 14001.84         93.60
     by position, any      bt    19195.83   26748.36 19194.66          1.17
         by blue line      ch    27592.83   28160.28 27592.83          0.00
 by position, nearest      ch    10604.34   12068.28 10604.34          0.00
     by position, any      ch    14943.06   15902.91 14943.06          0.00
         by blue line      co    28304.91   28369.53 28304.91          0.00
 by position, nearest      co    11692.35   12913.47 11692.35          0.00
     by position, any      co    15918.93   16768.26 15918.93          0.00
         by blue line      pk    28577.88       0.00     0.00      28577.88
 by position, nearest      pk    11774.25       0.00     0.00      11774.25
     by position, any      pk    16029.81       0.00     0.00      16029.81
         by blue line      sk     4231.26    4371.39  3837.69        393.57
 by position, nearest      sk      368.28    1880.10     0.00        368.28
     by position, any      sk      533.16    2015.46   112.68        420.48
 rear_only_ha tied_cells blk_without_segments
      1461.24         NA                   NA
      8196.84       1111                    0
      7553.70         NA                    0
       567.45         NA                   NA
      1463.94       1111                    0
       959.85         NA                    0
        64.62         NA                   NA
      1221.12       1111                    0
       849.33         NA                    0
         0.00         NA                   NA
         0.00       1111                    0
         0.00         NA                    0
       533.70         NA                   NA
      1880.10       1111                    0
      1902.78         NA                    0
```

Run time: 180 s.
