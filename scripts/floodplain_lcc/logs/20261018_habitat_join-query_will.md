# Habitat join on the published whole-network floodplain, WILL (#104)

Produced by `scripts/floodplain_lcc/habitat_join-query.R will`, 2026-10-17 18:33 PDT. Floodplain `all_ff04` (`species: all`, order >= 2), attributed by `blue_line_key` (`all_ff04_by_blue_line_key`). Habitat flags from `habitat_link` (model `link:fresh`); segment geometry from `fresh.streams`, every order, matched on (blue_line_key, downstream_route_measure). flooded 0.8.2, terra 1.9.50.

Joins: **by blue line**, a blue line's whole floodplain takes any habitat on it (the contrast, not an answer); 
**by position**, each cell takes the nearest segment on each blue line that claims it, then **nearest** 
(one owner per cell; the rule for areas) or **any** (habitat if any claiming blue line says so; the connected view).

## Integrity

```
 floodplain_cells attributed_cells missing extra
           390272           390272       0     0
```

## Shared ground

```
 floodplain_cells floodplain_ha claiming_blue_lines share_claimed_by_2plus
           390272       35124.5                 861               0.750031
 mean_claims
     2.71814
```

## Habitat table against the schema's segments

```
 species habitat_rows schema_segments segments_matched habitat_rows_unmatched
      bt        26163           26163            26163                      0
      ch        26163           26163            26163                      0
      co        26163           26163            26163                      0
```

## Habitat km, and how much sits on a blue line with floodplain

```
 species spawning_km spawning_km_on_fp_blk rearing_km rearing_km_on_fp_blk
      bt    1052.180              1048.145    1690.35              1680.34
      ch     630.483               629.348    1029.73              1026.14
      co    1018.723              1015.657    1415.86              1380.46
 habitat_km_off_fp_blk_order1 habitat_km_off_fp_blk_order2plus
                     10.16134                                0
                      3.58563                                0
                     35.40304                                0
```

## Habitat floodplain (ha)

```
                 join species spawning_ha rearing_ha both_ha spawn_only_ha
         by blue line      bt     33702.6    34478.0 33593.4        109.17
 by position, nearest      bt     16057.7    27505.4 16053.8          3.87
     by position, any      bt     21668.7    31394.8 21668.7          0.00
         by blue line      ch     29796.9    33765.0 29796.9          0.00
 by position, nearest      ch     10421.2    16223.6 10421.2          0.00
     by position, any      ch     14948.2    21520.4 14948.2          0.00
         by blue line      co     33683.5    34521.7 33683.5          0.00
 by position, nearest      co     15837.7    23032.0 15837.7          0.00
     by position, any      co     21378.6    27545.6 21378.6          0.00
 rear_only_ha tied_cells blk_without_segments
       884.61         NA                   NA
     11451.60        271                    0
      9726.12         NA                    0
      3968.10         NA                   NA
      5802.39        271                    0
      6572.25         NA                    0
       838.17         NA                   NA
      7194.33        271                    0
      6166.98         NA                    0
```

Run time: 73 s.
