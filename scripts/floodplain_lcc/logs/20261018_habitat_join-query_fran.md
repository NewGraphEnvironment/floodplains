# Habitat join on the published whole-network floodplain, FRAN (#104)

Produced by `scripts/floodplain_lcc/habitat_join-query.R fran`, 2026-10-17 18:43 PDT. Floodplain `all_ff04` (`species: all`, order >= 2), attributed by `blue_line_key` (`all_ff04_by_blue_line_key`). Habitat flags from `habitat_link` (model `link:fresh`); segment geometry from `fresh.streams`, every order, matched on (blue_line_key, downstream_route_measure). flooded 0.8.2, terra 1.9.50.

Joins: **by blue line**, a blue line's whole floodplain takes any habitat on it (the contrast, not an answer); 
**by position**, each cell takes the nearest segment on each blue line that claims it, then **nearest** 
(one owner per cell; the rule for areas) or **any** (habitat if any claiming blue line says so; the connected view).

## Integrity

```
 floodplain_cells attributed_cells missing extra
          1218121          1218121       0     0
```

## Shared ground

```
 floodplain_cells floodplain_ha claiming_blue_lines share_claimed_by_2plus
          1218121        109631                1879               0.739313
 mean_claims
     2.65877
```

## Habitat table against the schema's segments

```
 species habitat_rows schema_segments segments_matched habitat_rows_unmatched
      bt        53358           53358            53358                      0
      ch        53358           53358            53358                      0
      sk        53358           53358            53358                      0
```

## Habitat km, and how much sits on a blue line with floodplain

```
 species spawning_km spawning_km_on_fp_blk rearing_km rearing_km_on_fp_blk
      bt    1150.920              1149.237   2834.021             2827.976
      ch     540.427               539.831    971.871              971.276
      sk     168.375               167.999    880.889              586.459
 habitat_km_off_fp_blk_order1 habitat_km_off_fp_blk_order2plus
                     6.045631                                0
                     0.595244                                0
                   294.805745                                0
```

## Habitat floodplain (ha)

```
                 join species spawning_ha rearing_ha  both_ha spawn_only_ha
         by blue line      bt    95553.00   101708.0 95515.74         37.26
 by position, nearest      bt    16910.19    76126.3 16908.39          1.80
     by position, any      bt    25877.34    90463.4 25877.34          0.00
         by blue line      ch    77587.56    88933.9 77587.56          0.00
 by position, nearest      ch     7893.54    15182.8  7893.54          0.00
     by position, any      ch    13176.09    23559.0 13176.09          0.00
         by blue line      sk    62628.57    77686.0 59816.07       2812.50
 by position, nearest      sk     3879.18    43701.2   765.54       3113.64
     by position, any      sk     6622.02    47828.9  3249.45       3372.57
 rear_only_ha tied_cells blk_without_segments
      6192.27         NA                   NA
     59217.93       1102                    0
     64586.07         NA                    0
     11346.30         NA                   NA
      7289.28       1102                    0
     10382.94         NA                    0
     17869.95         NA                   NA
     42935.67       1102                    0
     44579.43         NA                    0
```

Run time: 177 s.
