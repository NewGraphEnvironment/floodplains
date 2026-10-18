# Habitat join on the published whole-network floodplain, NECR (#104)

Produced by `scripts/floodplain_lcc/habitat_join-query.R necr`, 2026-10-17 18:37 PDT. Floodplain `all_ff04` (`species: all`, order >= 2), attributed by `blue_line_key` (`all_ff04_by_blue_line_key`). Habitat flags from `habitat_link` (model `link:fresh`); segment geometry from `fresh.streams`, every order, matched on (blue_line_key, downstream_route_measure). flooded 0.8.2, terra 1.9.50.

Joins: **by blue line**, a blue line's whole floodplain takes any habitat on it (the contrast, not an answer); 
**by position**, each cell takes the nearest segment on each blue line that claims it, then **nearest** 
(one owner per cell; the rule for areas) or **any** (habitat if any claiming blue line says so; the connected view).

## Integrity

```
 floodplain_cells attributed_cells missing extra
           843990           843990       0     0
```

## Shared ground

```
 floodplain_cells floodplain_ha claiming_blue_lines share_claimed_by_2plus
           843990       75959.1                1336               0.757817
 mean_claims
     2.56528
```

## Habitat table against the schema's segments

```
 species habitat_rows schema_segments segments_matched habitat_rows_unmatched
      bt        29951           29951            29951                      0
      ch        29951           29951            29951                      0
      co        29951           29951            29951                      0
      sk        29951           29951            29951                      0
```

## Habitat km, and how much sits on a blue line with floodplain

```
 species spawning_km spawning_km_on_fp_blk rearing_km rearing_km_on_fp_blk
      bt    989.8184              989.8184   1875.607             1874.338
      ch    515.9882              515.9882   1079.184             1079.184
      co    972.0870              972.0870   1701.761             1668.056
      sk     38.1545               38.1545    161.823              111.773
 habitat_km_off_fp_blk_order1 habitat_km_off_fp_blk_order2plus
                      1.26915                                0
                      0.00000                                0
                     33.70412                                0
                     50.04966                                0
```

## Habitat floodplain (ha)

```
                 join species spawning_ha rearing_ha  both_ha spawn_only_ha
         by blue line      bt    58670.01   63087.48 58597.83         72.18
 by position, nearest      bt    19436.85   44128.80 19410.21         26.64
     by position, any      bt    27340.92   53065.53 27340.92          0.00
         by blue line      ch    43695.27   58758.48 43695.27          0.00
 by position, nearest      ch    10067.04   22160.07 10067.04          0.00
     by position, any      ch    14792.49   29823.21 14792.49          0.00
         by blue line      co    58449.33   62219.43 58449.33          0.00
 by position, nearest      co    19275.57   35041.95 19275.57          0.00
     by position, any      co    27010.26   43408.44 27010.26          0.00
         by blue line      sk    14735.25   21236.31 14557.86        177.39
 by position, nearest      sk     1252.71    7247.52     0.00       1252.71
     by position, any      sk     1751.49    7992.18   370.62       1380.87
 rear_only_ha tied_cells blk_without_segments
      4489.65         NA                   NA
     24718.59        540                    0
     25724.61         NA                    0
     15063.21         NA                   NA
     12093.03        540                    0
     15030.72         NA                    0
      3770.10         NA                   NA
     15766.38        540                    0
     16398.18         NA                    0
      6678.45         NA                   NA
      7247.52        540                    0
      7621.56         NA                    0
```

Run time: 165 s.
