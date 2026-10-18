# Habitat join on the published whole-network floodplain, DUNC (#104)

Produced by `scripts/floodplain_lcc/habitat_join-query.R dunc`, 2026-10-17 19:24 PDT. Floodplain `all_ff04` (`species: all`, order >= 2), attributed by `blue_line_key` (`all_ff04_by_blue_line_key`). Habitat flags from `habitat_link` (model `link:fresh_default`); segment geometry from `fresh_default.streams`, every order, matched on (blue_line_key, downstream_route_measure). flooded 0.8.2, terra 1.9.50.

Joins: **by blue line**, a blue line's whole floodplain takes any habitat on it (the contrast, not an answer); 
**by position**, each cell takes the nearest segment on each blue line that claims it, then **nearest** 
(one owner per cell; the rule for areas) or **any** (habitat if any claiming blue line says so; the connected view).

## Integrity

```
 floodplain_cells attributed_cells missing extra
           205793           205793       0     0
```

## Shared ground

```
 floodplain_cells floodplain_ha claiming_blue_lines share_claimed_by_2plus
           205793       18521.4                1948               0.796844
 mean_claims
     2.86504
```

## Habitat table against the schema's segments

```
 species habitat_rows schema_segments segments_matched habitat_rows_unmatched
      bt        63067           63067            63067                      0
      rb        63067           63067            63067                      0
     wct        63067           63067            63067                      0
```

## Habitat km, and how much sits on a blue line with floodplain

```
 species spawning_km spawning_km_on_fp_blk rearing_km rearing_km_on_fp_blk
      bt     543.141               541.976   1017.241              888.968
      rb     543.103               541.938    978.801              849.218
     wct     474.456               473.291    865.825              738.262
 habitat_km_off_fp_blk_order1 habitat_km_off_fp_blk_order2plus
                      128.274                                0
                      129.583                                0
                      127.564                                0
```

## Habitat floodplain (ha)

```
                 join species spawning_ha rearing_ha  both_ha spawn_only_ha
         by blue line      bt    17005.86    17958.8 17005.86             0
 by position, nearest      bt     5139.36    16044.6  5139.36             0
     by position, any      bt     5954.76    16740.2  5954.76             0
         by blue line      rb    17004.51    17920.4 17004.51             0
 by position, nearest      rb     5139.36    16002.4  5139.36             0
     by position, any      rb     5954.76    16728.5  5954.76             0
         by blue line     wct    16701.30    17607.8 16701.30             0
 by position, nearest     wct     4840.83    15541.4  4840.83             0
     by position, any     wct     5569.56    16210.8  5569.56             0
 rear_only_ha tied_cells blk_without_segments
       952.92         NA                   NA
     10905.21        610                    0
     10785.42         NA                    0
       915.93         NA                   NA
     10863.00        610                    0
     10773.72         NA                    0
       906.48         NA                   NA
     10700.55        610                    0
     10641.24         NA                    0
```

Run time: 154 s.
