# Habitat join on the published whole-network floodplain, THOM (#104)

Produced by `scripts/floodplain_lcc/habitat_join-query.R thom`, 2026-10-17 18:49 PDT. Floodplain `all_ff04` (`species: all`, order >= 2), attributed by `blue_line_key` (`all_ff04_by_blue_line_key`). Habitat flags from `habitat_link` (model `link:fresh`); segment geometry from `fresh.streams`, every order, matched on (blue_line_key, downstream_route_measure). flooded 0.8.2, terra 1.9.50.

Joins: **by blue line**, a blue line's whole floodplain takes any habitat on it (the contrast, not an answer); 
**by position**, each cell takes the nearest segment on each blue line that claims it, then **nearest** 
(one owner per cell; the rule for areas) or **any** (habitat if any claiming blue line says so; the connected view).

## Integrity

```
 floodplain_cells attributed_cells missing extra
           285602           285602       0     0
```

## Shared ground

```
 floodplain_cells floodplain_ha claiming_blue_lines share_claimed_by_2plus
           285602       25704.2                1400               0.811181
 mean_claims
     3.35634
```

## Habitat table against the schema's segments

```
 species habitat_rows schema_segments segments_matched habitat_rows_unmatched
      bt        62152           62152            62152                      0
      ch        62152           62152            62152                      0
      co        62152           62152            62152                      0
      pk        62152           62152            62152                      0
      sk        62152           62152            62152                      0
      st        62152           62152            62152                      0
```

## Habitat km, and how much sits on a blue line with floodplain

```
 species spawning_km spawning_km_on_fp_blk rearing_km rearing_km_on_fp_blk
      bt    338.3366              337.7267    563.002             562.0850
      ch    203.2297              203.2297    209.511             209.5114
      co    212.5963              212.5963    215.060             215.0604
      pk    217.2874              217.2874      0.000               0.0000
      sk     25.8836               25.8836    158.711              78.6461
      st    229.5155              229.5155    319.035             319.0349
 habitat_km_off_fp_blk_order1 habitat_km_off_fp_blk_order2plus
                     0.916932                                0
                     0.000000                                0
                     0.000000                                0
                     0.000000                                0
                    80.064639                                0
                     0.000000                                0
```

## Habitat floodplain (ha)

```
                 join species spawning_ha rearing_ha  both_ha spawn_only_ha
         by blue line      bt    18990.72   19663.92 18531.72        459.00
 by position, nearest      bt     5028.93    9701.55  4840.74        188.19
     by position, any      bt     7037.28   13752.63  7037.19          0.09
         by blue line      ch    16152.75   16216.92 16152.75          0.00
 by position, nearest      ch     3567.87    3645.99  3567.87          0.00
     by position, any      ch     4757.67    4854.69  4757.67          0.00
         by blue line      co    16601.22   16607.52 16601.22          0.00
 by position, nearest      co     3693.60    3762.99  3693.60          0.00
     by position, any      co     4955.58    4962.06  4955.58          0.00
         by blue line      pk    16689.15       0.00     0.00      16689.15
 by position, nearest      pk     3708.63       0.00     0.00       3708.63
     by position, any      pk     4976.37       0.00     0.00       4976.37
         by blue line      sk    10082.43   11167.74  9012.87       1069.56
 by position, nearest      sk     1095.75    4820.58     0.00       1095.75
     by position, any      sk     1851.75    5187.60   143.64       1708.11
         by blue line      st    16868.88   17859.42 16868.88          0.00
 by position, nearest      st     3805.65    4585.05  3805.65          0.00
     by position, any      st     5162.31    6320.07  5162.31          0.00
 rear_only_ha tied_cells blk_without_segments
      1132.20         NA                   NA
      4860.81        561                    0
      6715.44         NA                    0
        64.17         NA                   NA
        78.12        561                    0
        97.02         NA                    0
         6.30         NA                   NA
        69.39        561                    0
         6.48         NA                    0
         0.00         NA                   NA
         0.00        561                    0
         0.00         NA                    0
      2154.87         NA                   NA
      4820.58        561                    0
      5043.96         NA                    0
       990.54         NA                   NA
       779.40        561                    0
      1157.76         NA                    0
```

Run time: 199 s.
