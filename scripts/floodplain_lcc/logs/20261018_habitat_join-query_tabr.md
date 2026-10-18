# Habitat join on the published whole-network floodplain, TABR (#104)

Produced by `scripts/floodplain_lcc/habitat_join-query.R tabr`, 2026-10-17 18:33 PDT. Floodplain `all_ff04` (`species: all`, order >= 2), attributed by `blue_line_key` (`all_ff04_by_blue_line_key`). Habitat flags from `habitat_link` (model `link:fresh`); segment geometry from `fresh.streams`, every order, matched on (blue_line_key, downstream_route_measure). flooded 0.8.2, terra 1.9.50.

Joins: **by blue line**, a blue line's whole floodplain takes any habitat on it (the contrast, not an answer); 
**by position**, each cell takes the nearest segment on each blue line that claims it, then **nearest** 
(one owner per cell; the rule for areas) or **any** (habitat if any claiming blue line says so; the connected view).

## Integrity

```
 floodplain_cells attributed_cells missing extra
           296879           296879       0     0
```

## Shared ground

```
 floodplain_cells floodplain_ha claiming_blue_lines share_claimed_by_2plus
           296879       26719.1                 615                0.75811
 mean_claims
     2.65678
```

## Habitat table against the schema's segments

```
 species habitat_rows schema_segments segments_matched habitat_rows_unmatched
      bt        14652           14652            14652                      0
      ch        14652           14652            14652                      0
```

## Habitat km, and how much sits on a blue line with floodplain

```
 species spawning_km spawning_km_on_fp_blk rearing_km rearing_km_on_fp_blk
      bt     677.049               672.090   1035.420             1020.206
      ch     410.269               405.729    642.884              637.925
 habitat_km_off_fp_blk_order1 habitat_km_off_fp_blk_order2plus
                     15.32959                                0
                      4.95893                                0
```

## Habitat floodplain (ha)

```
                 join species spawning_ha rearing_ha  both_ha spawn_only_ha
         by blue line      bt    24451.65    25578.5 24251.85         199.8
 by position, nearest      bt    11728.89    18307.7 11667.69          61.2
     by position, any      bt    15555.78    21811.4 15555.78           0.0
         by blue line      ch    20487.24    23946.7 20487.24           0.0
 by position, nearest      ch     8654.94    12060.5  8654.94           0.0
     by position, any      ch    11590.38    15476.1 11590.38           0.0
 rear_only_ha tied_cells blk_without_segments
      1326.60         NA                   NA
      6640.02        137                    0
      6255.63         NA                    0
      3459.42         NA                   NA
      3405.60        137                    0
      3885.75         NA                    0
```

Run time: 38 s.
