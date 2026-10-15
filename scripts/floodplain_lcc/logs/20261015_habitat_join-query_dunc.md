# Habitat join on the published whole-network floodplain, DUNC (#104)

Produced by `scripts/floodplain_lcc/habitat_join-query.R dunc`, 2026-10-14 18:31 PDT. Floodplain `all_ff04` (`species: all`, order >= 2), attributed by `blue_line_key` (`all_ff04_by_blue_line_key`). Habitat flags from `habitat_link` (model `link:fresh`); segment geometry from `fresh.streams`, every order, matched on (blue_line_key, downstream_route_measure). flooded 0.7.2, terra 1.9.50.

Joins: **by blue line**, a blue line's whole floodplain takes any habitat on it (the contrast, not an answer); 
**by position**, each cell takes the nearest segment on each blue line that claims it, then **nearest** 
(one owner per cell; the rule for areas) or **any** (habitat if any claiming blue line says so; the connected view).

## Integrity

```
 floodplain_cells attributed_cells missing extra
           203285           203285       0     0
```

## Shared ground

```
 floodplain_cells floodplain_ha claiming_blue_lines share_claimed_by_2plus
           203285       18500.7                1942               0.796734
 mean_claims
      2.8679
```

## Habitat table against the schema's segments

```
 species habitat_rows schema_segments segments_matched habitat_rows_unmatched
      bt        26827           26827            26827                      0
     wct        26827           26827            26827                      0
```

## Habitat km, and how much sits on a blue line with floodplain

```
 species spawning_km spawning_km_on_fp_blk rearing_km rearing_km_on_fp_blk
      bt     539.375               538.210    861.444              855.628
     wct     473.501               472.336    572.606              570.977
 habitat_km_off_fp_blk_order1 habitat_km_off_fp_blk_order2plus
                      5.92424                                0
                      1.62963                                0
```

## Habitat floodplain (ha)

```
                 join species spawning_ha rearing_ha  both_ha spawn_only_ha
         by blue line      bt    16906.76   17846.70 16844.87     61.885849
 by position, nearest      bt     5101.31   15110.52  5090.57     10.739015
     by position, any      bt     5908.46   16636.92  5908.19      0.273026
         by blue line     wct    16614.17   16716.00 16614.17      0.000000
 by position, nearest     wct     4809.26    5280.23  4809.26      0.000000
     by position, any     wct     5531.96    5906.09  5531.96      0.000000
 rear_only_ha tied_cells blk_without_segments
     1001.823         NA                   NA
    10019.956        590                    0
    10728.731         NA                    0
      101.839         NA                   NA
      470.970        590                    0
      374.136         NA                    0
```

Run time: 60 s.
