# Habitat join on the published whole-network floodplain, KOTL (#104)

Produced by `scripts/floodplain_lcc/habitat_join-query.R kotl`, 2026-10-17 19:13 PDT. Floodplain `all_ff04` (`species: all`, order >= 2), attributed by `blue_line_key` (`all_ff04_by_blue_line_key`). Habitat flags from `habitat_link` (model `link:fresh_default`); segment geometry from `fresh_default.streams`, every order, matched on (blue_line_key, downstream_route_measure). flooded 0.8.2, terra 1.9.50.

Joins: **by blue line**, a blue line's whole floodplain takes any habitat on it (the contrast, not an answer); 
**by position**, each cell takes the nearest segment on each blue line that claims it, then **nearest** 
(one owner per cell; the rule for areas) or **any** (habitat if any claiming blue line says so; the connected view).

## Integrity

```
 floodplain_cells attributed_cells missing extra
           837936           837936       0     0
```

## Shared ground

```
 floodplain_cells floodplain_ha claiming_blue_lines share_claimed_by_2plus
           837936       75414.2                2320               0.657407
 mean_claims
     2.20336
```

## Habitat table against the schema's segments

```
 species habitat_rows schema_segments segments_matched habitat_rows_unmatched
      bt       109951          109950           109930                     21
      ko       109951          109950           109930                     21
      rb       109951          109950           109930                     21
     wct       109951          109950           109930                     21
```

## Habitat km, and how much sits on a blue line with floodplain

```
 species spawning_km spawning_km_on_fp_blk rearing_km rearing_km_on_fp_blk
      bt    1035.086               1034.28   1599.113             1579.312
      ko     166.243                166.19    568.633              434.867
      rb    1034.424               1033.61   1513.077             1490.266
     wct    1145.897               1142.36   1621.667             1594.541
 habitat_km_off_fp_blk_order1 habitat_km_off_fp_blk_order2plus
                      19.8015                                0
                     133.8190                                0
                      22.8113                                0
                      27.1252                                0
```

## Habitat floodplain (ha)

```
                 join species spawning_ha rearing_ha  both_ha spawn_only_ha
         by blue line      bt     53063.5    53717.7 53063.46          0.00
 by position, nearest      bt     19470.5    22709.5 19470.51          0.00
     by position, any      bt     24318.9    27118.6 24318.90          0.00
         by blue line      ko     36925.6    60711.6 33739.74       3185.82
 by position, nearest      ko     10446.8    44010.3    33.75      10413.00
     by position, any      ko     13947.3    46110.7  1760.67      12186.63
         by blue line      rb     53063.5    56396.8 53063.46          0.00
 by position, nearest      rb     19469.7    22761.9 19469.70          0.00
     by position, any      rb     24318.1    26911.6 24318.09          0.00
         by blue line     wct     54070.2    54662.8 54070.20          0.00
 by position, nearest     wct     20192.5    23387.7 20192.49          0.00
     by position, any     wct     25032.2    27517.0 25032.24          0.00
 rear_only_ha tied_cells blk_without_segments
       654.21         NA                   NA
      3239.01       1260                    0
      2799.72         NA                    0
     26971.83         NA                   NA
     43976.52       1260                    0
     44350.02         NA                    0
      3333.33         NA                   NA
      3292.20       1260                    0
      2593.53         NA                    0
       592.65         NA                   NA
      3195.18       1260                    0
      2484.81         NA                    0
```

Run time: 632 s.
