# Habitat join on the published whole-network floodplain, MORR (#104)

Produced by `scripts/floodplain_lcc/habitat_join-query.R morr`, 2026-10-14 18:36 PDT. Floodplain `all_ff04` (`species: all`, order >= 2), attributed by `blue_line_key` (`all_ff04_by_blue_line_key`). Habitat flags from `habitat_link` (model `link:fresh`); segment geometry from `fresh.streams`, every order, matched on (blue_line_key, downstream_route_measure). flooded 0.7.2, terra 1.9.50.

Joins: **by blue line**, a blue line's whole floodplain takes any habitat on it (the contrast, not an answer); 
**by position**, each cell takes the nearest segment on each blue line that claims it, then **nearest** 
(one owner per cell; the rule for areas) or **any** (habitat if any claiming blue line says so; the connected view).

## Integrity

```
 floodplain_cells attributed_cells missing extra
           532577           532577       0     0
```

## Shared ground

```
 floodplain_cells floodplain_ha claiming_blue_lines share_claimed_by_2plus
           532577       47931.9                1635               0.786624
 mean_claims
      3.2849
```

## Habitat table against the schema's segments

```
 species habitat_rows schema_segments segments_matched habitat_rows_unmatched
      bt        58613           58613            58613                      0
      ch        58613           58613            58613                      0
      co        58613           58613            58613                      0
      pk        58613           58613            58613                      0
      sk        58613           58613            58613                      0
      st        58613           58613            58613                      0
```

## Habitat km, and how much sits on a blue line with floodplain

```
 species spawning_km spawning_km_on_fp_blk rearing_km rearing_km_on_fp_blk
      bt     952.613               941.967   1829.894             1789.767
      ch     644.809               639.984    880.691              871.324
      co     915.965               907.059   1228.719             1191.590
      pk     966.417               953.488      0.000                0.000
      sk      54.812                54.812    442.330              260.829
      st     649.389               644.564   1159.866             1138.534
 habitat_km_off_fp_blk_order1 habitat_km_off_fp_blk_order2plus
                     40.21772                                0
                      9.36705                                0
                     37.12884                                0
                     12.92934                                0
                    181.50078                                0
                     21.33281                                0
```

## Habitat floodplain (ha)

```
                 join species spawning_ha rearing_ha  both_ha spawn_only_ha
         by blue line      bt    44540.01    46462.9 44490.33         49.68
 by position, nearest      bt    15331.23    37243.1 15320.79         10.44
     by position, any      bt    21454.02    42732.7 21450.42          3.60
         by blue line      ch    39560.31    43131.7 39560.31          0.00
 by position, nearest      ch    11444.40    14789.0 11444.40          0.00
     by position, any      ch    16349.49    20353.3 16349.49          0.00
         by blue line      co    44023.59    44728.3 44023.59          0.00
 by position, nearest      co    15097.86    20753.6 15097.86          0.00
     by position, any      co    21106.89    24881.2 21106.89          0.00
         by blue line      pk    44018.55        0.0     0.00      44018.55
 by position, nearest      pk    15235.20        0.0     0.00      15235.20
     by position, any      pk    21431.07        0.0     0.00      21431.07
         by blue line      sk    25872.48    28850.8 24344.37       1528.11
 by position, nearest      sk     1468.44    15304.9     0.00       1468.44
     by position, any      sk     2798.28    16890.9   788.85       2009.43
         by blue line      st    39681.63    44452.3 39681.63          0.00
 by position, nearest      st    11472.03    17664.0 11472.03          0.00
     by position, any      st    16447.41    23365.4 16447.41          0.00
 rear_only_ha tied_cells blk_without_segments
      1972.53         NA                   NA
     21922.29       1877                    0
     21282.30         NA                    0
      3571.38         NA                   NA
      3344.58       1877                    0
      4003.83         NA                    0
       704.70         NA                   NA
      5655.78       1877                    0
      3774.33         NA                    0
         0.00         NA                   NA
         0.00       1877                    0
         0.00         NA                    0
      4506.39         NA                   NA
     15304.86       1877                    0
     16102.08         NA                    0
      4770.72         NA                   NA
      6192.00       1877                    0
      6918.03         NA                    0
```

Run time: 280 s.
