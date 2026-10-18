# Habitat join on the published whole-network floodplain, LARL (#104)

Produced by `scripts/floodplain_lcc/habitat_join-query.R larl`, 2026-10-17 19:18 PDT. Floodplain `all_ff04` (`species: all`, order >= 2), attributed by `blue_line_key` (`all_ff04_by_blue_line_key`). Habitat flags from `habitat_link` (model `link:fresh_default`); segment geometry from `fresh_default.streams`, every order, matched on (blue_line_key, downstream_route_measure). flooded 0.8.2, terra 1.9.50.

Joins: **by blue line**, a blue line's whole floodplain takes any habitat on it (the contrast, not an answer); 
**by position**, each cell takes the nearest segment on each blue line that claims it, then **nearest** 
(one owner per cell; the rule for areas) or **any** (habitat if any claiming blue line says so; the connected view).

## Integrity

```
 floodplain_cells attributed_cells missing extra
           417232           417232       0     0
```

## Shared ground

```
 floodplain_cells floodplain_ha claiming_blue_lines share_claimed_by_2plus
           417232       37550.9                2052               0.760253
 mean_claims
     2.58882
```

## Habitat table against the schema's segments

```
 species habitat_rows schema_segments segments_matched habitat_rows_unmatched
      bt        91077           91090            91042                     35
      rb        91077           91090            91042                     35
     wct        91077           91090            91042                     35
```

## Habitat km, and how much sits on a blue line with floodplain

```
 species spawning_km spawning_km_on_fp_blk rearing_km rearing_km_on_fp_blk
      bt     563.165               556.680    844.838              832.261
      rb     330.463               329.172    478.700              469.902
     wct     560.511               554.402    739.326              726.878
 habitat_km_off_fp_blk_order1 habitat_km_off_fp_blk_order2plus
                     12.50641                        0.0705303
                      8.34116                        0.4567199
                     12.44844                        0.0000000
```

## Habitat floodplain (ha)

```
                 join species spawning_ha rearing_ha  both_ha spawn_only_ha
         by blue line      bt    31953.24   32184.99 31953.24             0
 by position, nearest      bt     6509.52    7898.67  6509.52             0
     by position, any      bt     7958.88    9099.00  7958.88             0
         by blue line      rb    28996.47   29373.66 28996.47             0
 by position, nearest      rb     4195.44    5158.26  4195.44             0
     by position, any      rb     5096.43    6239.70  5096.43             0
         by blue line     wct    33091.29   33273.00 33091.29             0
 by position, nearest     wct     7245.09    8387.01  7245.09             0
     by position, any     wct     8711.91    9617.04  8711.91             0
 rear_only_ha tied_cells blk_without_segments
       231.75         NA                   NA
      1389.15        610                    0
      1140.12         NA                    0
       377.19         NA                   NA
       962.82        610                    0
      1143.27         NA                    0
       181.71         NA                   NA
      1141.92        610                    0
       905.13         NA                    0
```

Run time: 314 s.
