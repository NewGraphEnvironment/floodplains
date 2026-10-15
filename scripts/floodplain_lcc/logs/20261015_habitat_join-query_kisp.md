# Habitat join on the published whole-network floodplain, KISP (#104)

Produced by `scripts/floodplain_lcc/habitat_join-query.R kisp`, 2026-10-14 18:40 PDT. Floodplain `all_ff04` (`species: all`, order >= 2), attributed by `blue_line_key` (`all_ff04_by_blue_line_key`). Habitat flags from `habitat_link` (model `link:fresh`); segment geometry from `fresh.streams`, every order, matched on (blue_line_key, downstream_route_measure). flooded 0.7.2, terra 1.9.50.

Joins: **by blue line**, a blue line's whole floodplain takes any habitat on it (the contrast, not an answer); 
**by position**, each cell takes the nearest segment on each blue line that claims it, then **nearest** 
(one owner per cell; the rule for areas) or **any** (habitat if any claiming blue line says so; the connected view).

## Integrity

```
 floodplain_cells attributed_cells missing extra
           360449           360449       0     0
```

## Shared ground

```
 floodplain_cells floodplain_ha claiming_blue_lines share_claimed_by_2plus
           360449       32440.4                1887               0.652137
 mean_claims
     2.24079
```

## Habitat table against the schema's segments

```
 species habitat_rows schema_segments segments_matched habitat_rows_unmatched
      bt        76516           76516            76516                      0
      ch        76516           76516            76516                      0
      cm        76516           76516            76516                      0
      co        76516           76516            76516                      0
      pk        76516           76516            76516                      0
      sk        76516           76516            76516                      0
      st        76516           76516            76516                      0
```

## Habitat km, and how much sits on a blue line with floodplain

```
 species spawning_km spawning_km_on_fp_blk rearing_km rearing_km_on_fp_blk
      bt  1261.14943            1258.99217  1962.7120            1954.8758
      ch   860.45486             859.19707  1050.5939            1048.6501
      cm  1162.70747            1160.55020     0.0000               0.0000
      co  1110.82842            1108.67116  1272.5041            1253.6371
      pk  1162.70747            1160.55020     0.0000               0.0000
      sk     7.14086               7.14086    98.3525              43.1875
      st   903.87417             902.61639  1347.7010            1344.2013
 habitat_km_off_fp_blk_order1 habitat_km_off_fp_blk_order2plus
                      7.82422                        0.0329789
                      1.94387                        0.0000000
                      2.15726                        0.0000000
                     18.86704                        0.0000000
                      2.15726                        0.0000000
                     55.16499                        0.0000000
                      3.49976                        0.0000000
```

## Habitat floodplain (ha)

```
                 join species spawning_ha rearing_ha  both_ha spawn_only_ha
         by blue line      bt    29585.70   30433.95 29520.18         65.52
 by position, nearest      bt    14814.00   24821.46 14801.85         12.15
     by position, any      bt    17951.31   26703.90 17951.31          0.00
         by blue line      ch    25953.66   28116.36 25953.66          0.00
 by position, nearest      ch    10338.66   12499.47 10338.66          0.00
     by position, any      ch    12761.10   14915.34 12761.10          0.00
         by blue line      cm    28895.40       0.00     0.00      28895.40
 by position, nearest      cm    13741.74       0.00     0.00      13741.74
     by position, any      cm    16437.96       0.00     0.00      16437.96
         by blue line      co    28830.15   29196.00 28830.15          0.00
 by position, nearest      co    13470.75   16370.19 13470.75          0.00
     by position, any      co    16239.87   18552.24 16239.87          0.00
         by blue line      pk    28895.40       0.00     0.00      28895.40
 by position, nearest      pk    13741.74       0.00     0.00      13741.74
     by position, any      pk    16437.96       0.00     0.00      16437.96
         by blue line      sk     5706.36    5980.50  2254.77       3451.59
 by position, nearest      sk      144.00    2950.92     0.00        144.00
     by position, any      sk      285.75    3123.45   123.93        161.82
         by blue line      st    25976.70   29334.60 25976.70          0.00
 by position, nearest      st    10551.24   14595.30 10551.24          0.00
     by position, any      st    13043.79   17406.99 13043.79          0.00
 rear_only_ha tied_cells blk_without_segments
       913.77         NA                   NA
     10019.61        385                    0
      8752.59         NA                    0
      2162.70         NA                   NA
      2160.81        385                    0
      2154.24         NA                    0
         0.00         NA                   NA
         0.00        385                    0
         0.00         NA                    0
       365.85         NA                   NA
      2899.44        385                    0
      2312.37         NA                    0
         0.00         NA                   NA
         0.00        385                    0
         0.00         NA                    0
      3725.73         NA                   NA
      2950.92        385                    0
      2999.52         NA                    0
      3357.90         NA                   NA
      4044.06        385                    0
      4363.20         NA                    0
```

Run time: 266 s.
