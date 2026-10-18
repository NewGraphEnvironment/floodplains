# Habitat join on the published whole-network floodplain, LCHL (#104)

Produced by `scripts/floodplain_lcc/habitat_join-query.R lchl`, 2026-10-17 18:31 PDT. Floodplain `all_ff04` (`species: all`, order >= 2), attributed by `blue_line_key` (`all_ff04_by_blue_line_key`). Habitat flags from `habitat_link` (model `link:fresh`); segment geometry from `fresh.streams`, every order, matched on (blue_line_key, downstream_route_measure). flooded 0.8.2, terra 1.9.50.

Joins: **by blue line**, a blue line's whole floodplain takes any habitat on it (the contrast, not an answer); 
**by position**, each cell takes the nearest segment on each blue line that claims it, then **nearest** 
(one owner per cell; the rule for areas) or **any** (habitat if any claiming blue line says so; the connected view).

## Integrity

```
 floodplain_cells attributed_cells missing extra
           474236           474236       0     0
```

## Shared ground

```
 floodplain_cells floodplain_ha claiming_blue_lines share_claimed_by_2plus
           474236       42681.2                 998               0.725666
 mean_claims
     2.66763
```

## Habitat table against the schema's segments

```
 species habitat_rows schema_segments segments_matched habitat_rows_unmatched
      bt        21172           21172            21172                      0
      ch        21172           21172            21172                      0
      co        21172           21172            21172                      0
```

## Habitat km, and how much sits on a blue line with floodplain

```
 species spawning_km spawning_km_on_fp_blk rearing_km rearing_km_on_fp_blk
      bt     896.138               894.609   1550.641              1548.31
      ch     464.815               463.984    826.809               825.28
      co     829.716               828.187   1286.218              1264.61
 habitat_km_off_fp_blk_order1 habitat_km_off_fp_blk_order2plus
                      2.45453                                0
                      1.52904                                0
                     21.60608                                0
```

## Habitat floodplain (ha)

```
                 join species spawning_ha rearing_ha both_ha spawn_only_ha
         by blue line      bt     38545.5    40741.0 38201.7        343.80
 by position, nearest      bt     13827.3    28108.9 13816.1         11.25
     by position, any      bt     18500.3    33671.0 18500.3          0.00
         by blue line      ch     29443.0    36224.9 29443.0          0.00
 by position, nearest      ch      7402.5    12806.5  7402.5          0.00
     by position, any      ch     10151.2    17312.3 10151.2          0.00
         by blue line      co     36654.8    38826.4 36654.8          0.00
 by position, nearest      co     12811.4    21330.2 12811.4          0.00
     by position, any      co     17024.5    26407.5 17024.5          0.00
 rear_only_ha tied_cells blk_without_segments
      2539.35         NA                   NA
     14292.81        340                    0
     15170.67         NA                    0
      6781.86         NA                   NA
      5403.96        340                    0
      7161.12         NA                    0
      2171.61         NA                   NA
      8518.77        340                    0
      9383.04         NA                    0
```

Run time: 80 s.
