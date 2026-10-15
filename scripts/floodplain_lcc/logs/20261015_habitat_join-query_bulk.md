# Habitat join on the published whole-network floodplain, BULK (#104)

Produced by `scripts/floodplain_lcc/habitat_join-query.R bulk`, 2026-10-14 18:45 PDT. Floodplain `all_ff04` (`species: all`, order >= 2), attributed by `blue_line_key` (`all_ff04_by_blue_line_key`). Habitat flags from `habitat_link` (model `link:fresh`); segment geometry from `fresh.streams`, every order, matched on (blue_line_key, downstream_route_measure). flooded 0.7.2, terra 1.9.50.

Joins: **by blue line**, a blue line's whole floodplain takes any habitat on it (the contrast, not an answer); 
**by position**, each cell takes the nearest segment on each blue line that claims it, then **nearest** 
(one owner per cell; the rule for areas) or **any** (habitat if any claiming blue line says so; the connected view).

## Integrity

```
 floodplain_cells attributed_cells missing extra
           733324           733324       0     0
```

## Shared ground

```
 floodplain_cells floodplain_ha claiming_blue_lines share_claimed_by_2plus
           733324       65999.2                2392               0.714822
 mean_claims
     2.63523
```

## Habitat table against the schema's segments

```
 species habitat_rows schema_segments segments_matched habitat_rows_unmatched
      bt        87639           87639            87639                      0
      ch        87639           87639            87639                      0
      co        87639           87639            87639                      0
      pk        87639           87639            87639                      0
      sk        87639           87639            87639                      0
      st        87639           87639            87639                      0
```

## Habitat km, and how much sits on a blue line with floodplain

```
 species spawning_km spawning_km_on_fp_blk rearing_km rearing_km_on_fp_blk
      bt     1866.31               1846.23  3021.5078             2966.704
      ch     1260.25               1256.98  1730.1166             1708.058
      co     1782.10               1764.97  2215.5764             2159.775
      pk     1854.43               1836.12     0.0000                0.000
      sk       27.06                 27.06    64.5627               41.609
      st     1287.56               1284.29  2230.6634             2198.524
 habitat_km_off_fp_blk_order1 habitat_km_off_fp_blk_order2plus
                      55.5137                                0
                      22.0583                                0
                      55.8013                                0
                      18.3148                                0
                      22.9536                                0
                      32.1390                                0
```

## Habitat floodplain (ha)

```
                 join species spawning_ha rearing_ha  both_ha spawn_only_ha
         by blue line      bt    58242.15   60583.05 58186.80         55.35
 by position, nearest      bt    27450.81   45336.42 27444.06          6.75
     by position, any      bt    35676.72   51865.56 35676.72          0.00
         by blue line      ch    49393.08   56191.41 49393.08          0.00
 by position, nearest      ch    19188.90   26470.98 19188.90          0.00
     by position, any      ch    26445.51   33594.84 26445.51          0.00
         by blue line      co    57481.56   59355.81 57481.56          0.00
 by position, nearest      co    26937.45   36177.21 26937.45          0.00
     by position, any      co    34958.43   42494.58 34958.43          0.00
         by blue line      pk    57477.87       0.00     0.00      57477.87
 by position, nearest      pk    26870.58       0.00     0.00      26870.58
     by position, any      pk    34977.60       0.00     0.00      34977.60
         by blue line      sk    16705.26   17145.27 16479.63        225.63
 by position, nearest      sk      571.86    2296.08     8.37        563.49
     by position, any      sk     1046.07    2809.53   199.98        846.09
         by blue line      st    49583.79   58818.06 49583.79          0.00
 by position, nearest      st    19286.19   31281.03 19286.19          0.00
     by position, any      st    26612.73   39577.68 26612.73          0.00
 rear_only_ha tied_cells blk_without_segments
      2396.25         NA                   NA
     17892.36        674                    0
     16188.84         NA                    0
      6798.33         NA                   NA
      7282.08        674                    0
      7149.33         NA                    0
      1874.25         NA                   NA
      9239.76        674                    0
      7536.15         NA                    0
         0.00         NA                   NA
         0.00        674                    0
         0.00         NA                    0
       665.64         NA                   NA
      2287.71        674                    0
      2609.55         NA                    0
      9234.27         NA                   NA
     11994.84        674                    0
     12964.95         NA                    0
```

Run time: 282 s.
