# Habitat join on the published whole-network floodplain, MCGR (#104)

Produced by `scripts/floodplain_lcc/habitat_join-query.R mcgr`, 2026-10-17 18:46 PDT. Floodplain `all_ff04` (`species: all`, order >= 2), attributed by `blue_line_key` (`all_ff04_by_blue_line_key`). Habitat flags from `habitat_link` (model `link:fresh`); segment geometry from `fresh.streams`, every order, matched on (blue_line_key, downstream_route_measure). flooded 0.8.2, terra 1.9.50.

Joins: **by blue line**, a blue line's whole floodplain takes any habitat on it (the contrast, not an answer); 
**by position**, each cell takes the nearest segment on each blue line that claims it, then **nearest** 
(one owner per cell; the rule for areas) or **any** (habitat if any claiming blue line says so; the connected view).

## Integrity

```
 floodplain_cells attributed_cells missing extra
           394812           394812       0     0
```

## Shared ground

```
 floodplain_cells floodplain_ha claiming_blue_lines share_claimed_by_2plus
           394812       35533.1                1647               0.860364
 mean_claims
     4.58753
```

## Habitat table against the schema's segments

```
 species habitat_rows schema_segments segments_matched habitat_rows_unmatched
      bt        49005           49005            49005                      0
      ch        49005           49005            49005                      0
```

## Habitat km, and how much sits on a blue line with floodplain

```
 species spawning_km spawning_km_on_fp_blk rearing_km rearing_km_on_fp_blk
      bt    1002.822               993.815   1460.174             1436.216
      ch     704.081               700.449    935.505              920.887
 habitat_km_off_fp_blk_order1 habitat_km_off_fp_blk_order2plus
                      24.7443                                0
                      14.6186                                0
```

## Habitat floodplain (ha)

```
                 join species spawning_ha rearing_ha both_ha spawn_only_ha
         by blue line      bt     33805.2    34003.3 33739.6         65.61
 by position, nearest      bt     19271.4    25165.7 19241.7         29.70
     by position, any      bt     26993.0    30329.3 26993.0          0.00
         by blue line      ch     32017.1    33018.1 32017.1          0.00
 by position, nearest      ch     16123.1    19195.9 16123.1          0.00
     by position, any      ch     24239.3    26090.5 24239.3          0.00
 rear_only_ha tied_cells blk_without_segments
       263.79         NA                   NA
      5923.98        971                    0
      3336.30         NA                    0
      1000.98         NA                   NA
      3072.78        971                    0
      1851.12         NA                    0
```

Run time: 78 s.
