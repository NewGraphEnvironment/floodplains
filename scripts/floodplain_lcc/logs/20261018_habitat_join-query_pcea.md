# Habitat join on the published whole-network floodplain, PCEA (#104)

Produced by `scripts/floodplain_lcc/habitat_join-query.R pcea`, 2026-10-17 18:55 PDT. Floodplain `all_ff04` (`species: all`, order >= 2), attributed by `blue_line_key` (`all_ff04_by_blue_line_key`). Habitat flags from `habitat_link` (model `link:fresh`); segment geometry from `fresh.streams`, every order, matched on (blue_line_key, downstream_route_measure). flooded 0.8.2, terra 1.9.50.

Joins: **by blue line**, a blue line's whole floodplain takes any habitat on it (the contrast, not an answer); 
**by position**, each cell takes the nearest segment on each blue line that claims it, then **nearest** 
(one owner per cell; the rule for areas) or **any** (habitat if any claiming blue line says so; the connected view).

## Integrity

```
 floodplain_cells attributed_cells missing extra
           937049           937049       0     0
```

## Shared ground

```
 floodplain_cells floodplain_ha claiming_blue_lines share_claimed_by_2plus
           937049       84334.4                2793                0.43153
 mean_claims
     2.32307
```

## Habitat table against the schema's segments

```
 species habitat_rows schema_segments segments_matched habitat_rows_unmatched
      bt       106079          106079           106079                      0
```

## Habitat km, and how much sits on a blue line with floodplain

```
 species spawning_km spawning_km_on_fp_blk rearing_km rearing_km_on_fp_blk
      bt      925.72               925.071    2023.48               2016.8
 habitat_km_off_fp_blk_order1 habitat_km_off_fp_blk_order2plus
                      6.69758                                0
```

## Habitat floodplain (ha)

```
                 join species spawning_ha rearing_ha  both_ha spawn_only_ha
         by blue line      bt    30199.23    62248.1 30168.81         30.42
 by position, nearest      bt     6538.50    47412.8  6533.73          4.77
     by position, any      bt     8181.18    53271.4  8181.18          0.00
 rear_only_ha tied_cells blk_without_segments
      32079.3         NA                   NA
      40879.1        535                    0
      45090.2         NA                    0
```

Run time: 75 s.
