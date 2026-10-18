# Habitat join on the published whole-network floodplain, MORK (#104)

Produced by `scripts/floodplain_lcc/habitat_join-query.R mork`, 2026-10-17 18:40 PDT. Floodplain `all_ff04` (`species: all`, order >= 2), attributed by `blue_line_key` (`all_ff04_by_blue_line_key`). Habitat flags from `habitat_link` (model `link:fresh`); segment geometry from `fresh.streams`, every order, matched on (blue_line_key, downstream_route_measure). flooded 0.8.2, terra 1.9.50.

Joins: **by blue line**, a blue line's whole floodplain takes any habitat on it (the contrast, not an answer); 
**by position**, each cell takes the nearest segment on each blue line that claims it, then **nearest** 
(one owner per cell; the rule for areas) or **any** (habitat if any claiming blue line says so; the connected view).

## Integrity

```
 floodplain_cells attributed_cells missing extra
           741156           741156       0     0
```

## Shared ground

```
 floodplain_cells floodplain_ha claiming_blue_lines share_claimed_by_2plus
           741156         66704                3361                0.80212
 mean_claims
     3.11661
```

## Habitat table against the schema's segments

```
 species habitat_rows schema_segments segments_matched habitat_rows_unmatched
      bt       110510          110510           110510                      0
      ch       110510          110510           110510                      0
```

## Habitat km, and how much sits on a blue line with floodplain

```
 species spawning_km spawning_km_on_fp_blk rearing_km rearing_km_on_fp_blk
      bt     2434.23               2427.87    3397.59              3388.28
      ch     1556.47               1556.05    2225.04              2218.68
 habitat_km_off_fp_blk_order1 habitat_km_off_fp_blk_order2plus
                      8.89913                         0.411709
                      6.36005                         0.000000
```

## Habitat floodplain (ha)

```
                 join species spawning_ha rearing_ha both_ha spawn_only_ha
         by blue line      bt     64534.9    65623.7 64426.9        108.00
 by position, nearest      bt     39917.1    53014.4 39829.4         87.66
     by position, any      bt     50949.7    59700.3 50949.3          0.45
         by blue line      ch     58105.3    62979.8 58105.3          0.00
 by position, nearest      ch     28612.3    39280.9 28612.3          0.00
     by position, any      ch     40004.8    49016.6 40004.8          0.00
 rear_only_ha tied_cells blk_without_segments
      1196.73         NA                   NA
     13185.00        664                    0
      8751.06         NA                    0
      4874.49         NA                   NA
     10668.60        664                    0
      9011.79         NA                    0
```

Run time: 136 s.
