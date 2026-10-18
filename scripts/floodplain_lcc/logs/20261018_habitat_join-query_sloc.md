# Habitat join on the published whole-network floodplain, SLOC (#104)

Produced by `scripts/floodplain_lcc/habitat_join-query.R sloc`, 2026-10-17 19:21 PDT. Floodplain `all_ff04` (`species: all`, order >= 2), attributed by `blue_line_key` (`all_ff04_by_blue_line_key`). Habitat flags from `habitat_link` (model `link:fresh_default`); segment geometry from `fresh_default.streams`, every order, matched on (blue_line_key, downstream_route_measure). flooded 0.8.2, terra 1.9.50.

Joins: **by blue line**, a blue line's whole floodplain takes any habitat on it (the contrast, not an answer); 
**by position**, each cell takes the nearest segment on each blue line that claims it, then **nearest** 
(one owner per cell; the rule for areas) or **any** (habitat if any claiming blue line says so; the connected view).

## Integrity

```
 floodplain_cells attributed_cells missing extra
           171661           171661       0     0
```

## Shared ground

```
 floodplain_cells floodplain_ha claiming_blue_lines share_claimed_by_2plus
           171661       15449.5                1330               0.751522
 mean_claims
     2.71395
```

## Habitat table against the schema's segments

```
 species habitat_rows schema_segments segments_matched habitat_rows_unmatched
      bt        55730           55733            55720                     10
      rb        55730           55733            55720                     10
     wct        55730           55733            55720                     10
```

## Habitat km, and how much sits on a blue line with floodplain

```
 species spawning_km spawning_km_on_fp_blk rearing_km rearing_km_on_fp_blk
      bt     395.090               392.888    573.446              561.889
      rb     342.066               339.865    465.656              454.034
     wct     343.206               341.004    453.224              442.073
 habitat_km_off_fp_blk_order1 habitat_km_off_fp_blk_order2plus
                      11.5569                                0
                      11.6218                                0
                      11.1507                                0
```

## Habitat floodplain (ha)

```
                 join species spawning_ha rearing_ha  both_ha spawn_only_ha
         by blue line      bt    13960.71   14436.18 13960.71             0
 by position, nearest      bt     4213.17    5087.61  4213.17             0
     by position, any      bt     5035.59    5748.75  5035.59             0
         by blue line      rb    13706.10   14136.21 13706.10             0
 by position, nearest      rb     4029.93    4828.68  4029.93             0
     by position, any      rb     4825.53    5462.82  4825.53             0
         by blue line     wct    13813.29   13896.54 13813.29             0
 by position, nearest     wct     4072.32    4791.96  4072.32             0
     by position, any     wct     4870.26    5447.07  4870.26             0
 rear_only_ha tied_cells blk_without_segments
       475.47         NA                   NA
       874.44        324                    0
       713.16         NA                    0
       430.11         NA                   NA
       798.75        324                    0
       637.29         NA                    0
        83.25         NA                   NA
       719.64        324                    0
       576.81         NA                    0
```

Run time: 189 s.
