# Habitat join on the published whole-network floodplain, LSAL (#104)

Produced by `scripts/floodplain_lcc/habitat_join-query.R lsal`, 2026-10-17 18:31 PDT. Floodplain `all_ff04` (`species: all`, order >= 2), attributed by `blue_line_key` (`all_ff04_by_blue_line_key`). Habitat flags from `habitat_link` (model `link:fresh`); segment geometry from `fresh.streams`, every order, matched on (blue_line_key, downstream_route_measure). flooded 0.8.2, terra 1.9.50.

Joins: **by blue line**, a blue line's whole floodplain takes any habitat on it (the contrast, not an answer); 
**by position**, each cell takes the nearest segment on each blue line that claims it, then **nearest** 
(one owner per cell; the rule for areas) or **any** (habitat if any claiming blue line says so; the connected view).

## Integrity

```
 floodplain_cells attributed_cells missing extra
           323205           323205       0     0
```

## Shared ground

```
 floodplain_cells floodplain_ha claiming_blue_lines share_claimed_by_2plus
           323205       29088.5                 466               0.716604
 mean_claims
     2.48949
```

## Habitat table against the schema's segments

```
 species habitat_rows schema_segments segments_matched habitat_rows_unmatched
      ch        11609           11609            11609                      0
```

## Habitat km, and how much sits on a blue line with floodplain

```
 species spawning_km spawning_km_on_fp_blk rearing_km rearing_km_on_fp_blk
      ch     312.601               312.553    617.595              617.547
 habitat_km_off_fp_blk_order1 habitat_km_off_fp_blk_order2plus
                    0.0479224                                0
```

## Habitat floodplain (ha)

```
                 join species spawning_ha rearing_ha  both_ha spawn_only_ha
         by blue line      ch    20936.25    27049.0 20936.25             0
 by position, nearest      ch     6035.85    10412.9  6035.85             0
     by position, any      ch     8547.84    13860.0  8547.84             0
 rear_only_ha tied_cells blk_without_segments
      6112.80         NA                   NA
      4377.06        344                    0
      5312.16         NA                    0
```

Run time: 19 s.
