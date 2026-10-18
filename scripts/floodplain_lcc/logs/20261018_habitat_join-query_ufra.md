# Habitat join on the published whole-network floodplain, UFRA (#104)

Produced by `scripts/floodplain_lcc/habitat_join-query.R ufra`, 2026-10-17 18:35 PDT. Floodplain `all_ff04` (`species: all`, order >= 2), attributed by `blue_line_key` (`all_ff04_by_blue_line_key`). Habitat flags from `habitat_link` (model `link:fresh`); segment geometry from `fresh.streams`, every order, matched on (blue_line_key, downstream_route_measure). flooded 0.8.2, terra 1.9.50.

Joins: **by blue line**, a blue line's whole floodplain takes any habitat on it (the contrast, not an answer); 
**by position**, each cell takes the nearest segment on each blue line that claims it, then **nearest** 
(one owner per cell; the rule for areas) or **any** (habitat if any claiming blue line says so; the connected view).

## Integrity

```
 floodplain_cells attributed_cells missing extra
           335258           335258       0     0
```

## Shared ground

```
 floodplain_cells floodplain_ha claiming_blue_lines share_claimed_by_2plus
           335258       30173.2                2613                0.77738
 mean_claims
      3.2171
```

## Habitat table against the schema's segments

```
 species habitat_rows schema_segments segments_matched habitat_rows_unmatched
      bt        96299           96299            96299                      0
      ch        96299           96299            96299                      0
```

## Habitat km, and how much sits on a blue line with floodplain

```
 species spawning_km spawning_km_on_fp_blk rearing_km rearing_km_on_fp_blk
      bt     952.902               950.778   1239.836             1238.029
      ch     632.764               631.327    726.728              724.603
 habitat_km_off_fp_blk_order1 habitat_km_off_fp_blk_order2plus
                      2.16209                                0
                      2.12409                                0
```

## Habitat floodplain (ha)

```
                 join species spawning_ha rearing_ha both_ha spawn_only_ha
         by blue line      bt     26753.8    27350.5 26718.4         35.46
 by position, nearest      bt     16250.1    20407.7 16220.2         29.97
     by position, any      bt     19089.8    22306.3 19089.3          0.54
         by blue line      ch     24504.7    24853.6 24504.7          0.00
 by position, nearest      ch     11738.3    13759.7 11738.3          0.00
     by position, any      ch     14433.2    15816.4 14433.2          0.00
 rear_only_ha tied_cells blk_without_segments
       632.16         NA                   NA
      4187.52        345                    0
      3217.05         NA                    0
       348.93         NA                   NA
      2021.40        345                    0
      1383.21         NA                    0
```

Run time: 83 s.
