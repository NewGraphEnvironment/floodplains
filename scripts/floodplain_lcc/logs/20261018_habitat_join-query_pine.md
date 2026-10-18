# Habitat join on the published whole-network floodplain, PINE (#104)

Produced by `scripts/floodplain_lcc/habitat_join-query.R pine`, 2026-10-17 19:02 PDT. Floodplain `all_ff04` (`species: all`, order >= 2), attributed by `blue_line_key` (`all_ff04_by_blue_line_key`). Habitat flags from `habitat_link` (model `link:fresh`); segment geometry from `fresh.streams`, every order, matched on (blue_line_key, downstream_route_measure). flooded 0.8.2, terra 1.9.50.

Joins: **by blue line**, a blue line's whole floodplain takes any habitat on it (the contrast, not an answer); 
**by position**, each cell takes the nearest segment on each blue line that claims it, then **nearest** 
(one owner per cell; the rule for areas) or **any** (habitat if any claiming blue line says so; the connected view).

## Integrity

```
 floodplain_cells attributed_cells missing extra
           543192           543192       0     0
```

## Shared ground

```
 floodplain_cells floodplain_ha claiming_blue_lines share_claimed_by_2plus
           543192       48887.3                3061               0.745985
 mean_claims
     3.18333
```

## Habitat table against the schema's segments

```
 species habitat_rows schema_segments segments_matched habitat_rows_unmatched
      bt       113305          113305           113305                      0
```

## Habitat km, and how much sits on a blue line with floodplain

```
 species spawning_km spawning_km_on_fp_blk rearing_km rearing_km_on_fp_blk
      bt     1643.51               1639.52    2376.18               2366.8
 habitat_km_off_fp_blk_order1 habitat_km_off_fp_blk_order2plus
                      9.44218                                0
```

## Habitat floodplain (ha)

```
                 join species spawning_ha rearing_ha both_ha spawn_only_ha
         by blue line      bt     43470.7    44523.3 43401.2         69.48
 by position, nearest      bt     25277.9    32683.9 25229.7         48.24
     by position, any      bt     32438.9    37403.3 32438.4          0.45
 rear_only_ha tied_cells blk_without_segments
      1122.03         NA                   NA
      7454.16       1011                    0
      4964.85         NA                    0
```

Run time: 220 s.
