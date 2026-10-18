# Habitat join on the published whole-network floodplain, PARS (#104)

Produced by `scripts/floodplain_lcc/habitat_join-query.R pars`, 2026-10-17 18:58 PDT. Floodplain `all_ff04` (`species: all`, order >= 2), attributed by `blue_line_key` (`all_ff04_by_blue_line_key`). Habitat flags from `habitat_link` (model `link:fresh`); segment geometry from `fresh.streams`, every order, matched on (blue_line_key, downstream_route_measure). flooded 0.8.2, terra 1.9.50.

Joins: **by blue line**, a blue line's whole floodplain takes any habitat on it (the contrast, not an answer); 
**by position**, each cell takes the nearest segment on each blue line that claims it, then **nearest** 
(one owner per cell; the rule for areas) or **any** (habitat if any claiming blue line says so; the connected view).

## Integrity

```
 floodplain_cells attributed_cells missing extra
           621602           621602       0     0
```

## Shared ground

```
 floodplain_cells floodplain_ha claiming_blue_lines share_claimed_by_2plus
           621602       55944.2                3041               0.871247
 mean_claims
     4.15212
```

## Habitat table against the schema's segments

```
 species habitat_rows schema_segments segments_matched habitat_rows_unmatched
      bt        97534           97534            97534                      0
```

## Habitat km, and how much sits on a blue line with floodplain

```
 species spawning_km spawning_km_on_fp_blk rearing_km rearing_km_on_fp_blk
      bt     1683.36                1673.5    2575.08              2548.43
 habitat_km_off_fp_blk_order1 habitat_km_off_fp_blk_order2plus
                      27.4966                                0
```

## Habitat floodplain (ha)

```
                 join species spawning_ha rearing_ha both_ha spawn_only_ha
         by blue line      bt     53305.7    54348.4 53179.2        126.45
 by position, nearest      bt     29687.8    41584.6 29667.3         20.43
     by position, any      bt     41287.3    49290.9 41286.9          0.45
 rear_only_ha tied_cells blk_without_segments
      1169.19         NA                   NA
     11917.26        633                    0
      8004.06         NA                    0
```

Run time: 213 s.
