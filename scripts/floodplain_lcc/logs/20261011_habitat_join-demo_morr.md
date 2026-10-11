# Habitat join on the attributed floodplain, MORR ch (#104)

Produced by `scripts/floodplain_lcc/habitat_join-demo.R`, 2026-10-11 09:20 PDT. Floodplains: the probe's arm 2 (order >= 2) and arm 3 (order >= 3), `co_ff04` flood surface, attributed by `blue_line_key` (arm 3 also by segment), with flooded 0.6.0 and terra 1.9.50 (from the arms' `timing.json`). Habitat: link builds `fresh` and `morr`, `streams_habitat_ch`.

Joins: **blk**, a blue line's whole floodplain takes any habitat on that blue line; **range**, each floodplain cell takes the nearest segment (straight-line) on its own blue line; **segment**, segment-grain attribution. A cell several blue lines' floodplains share is habitat if any of them says so.

## Integrity: every floodplain cell attributed, nothing outside it

```
         floodplain_cells attributed_cells missing extra
arm2_blk           517087           517087       0     0
arm3_blk           404716           404716       0     0
arm3_seg           404716           404716       0     0
```

## Habitat km on a blue line that has floodplain (arm 2)

```
 build spawning_km spawning_km_on_fp_blk rearing_km rearing_km_on_fp_blk
 fresh     644.809               639.984    880.691              871.324
  morr     646.278               641.454   1171.326             1091.251
 habitat_km_off_fp_blk_order1 habitat_km_off_fp_blk_order2plus
                      9.36705                                0
                     80.07489                                0
```

## Arm 2: spawning vs rearing floodplain, ha

```
  join build spawning_ha rearing_ha both_ha spawn_only_ha rear_only_ha
   blk fresh     39507.4    43095.7 39507.4          0.00      3588.28
 range fresh     16321.0    20335.7 16321.0          0.00      4014.63
   blk  morr     39507.4    43434.1 39507.4          0.00      3926.75
 range  morr     16626.4    23255.2 16323.3        303.09      6931.81
 blk_without_segments
                   NA
                    0
                   NA
                    0
```

## Arm 3: range join vs segment grain, ha and per-cell agreement

```
                join build spawning_ha rearing_ha both_ha spawn_only_ha
   range (arm 3 blk) fresh     14166.3    16067.6 14166.3         0.000
 segment (arm 3 seg) fresh     19094.4    21367.3 19094.4         0.000
   range (arm 3 blk)  morr     14471.6    18309.2 14168.6       302.998
 segment (arm 3 seg)  morr     19333.2    22048.6 19101.6       231.601
 rear_only_ha seg_key_match agree_spawning agree_rearing
      1901.33            NA       0.866805      0.854510
      2272.85      1.000000             NA            NA
      4140.66            NA       0.868579      0.898781
      2947.00      0.999855             NA            NA
```

## Build diff, range join on arm 2

```
 rearing_fresh_ha rearing_morr_ha morr_only_ha fresh_only_ha
          20335.7         23255.2       2919.5             0
 spawning_changed_ha
             305.405
```

Distance from the cells whose rearing changed to the nearest segment whose rearing changed:

```
 changed_segments unmatched_morr_segments morr_only_cells median_m   max_m
             1696                       2           31527  91.3841 1012.35
```

## Shared ground: floodplain cells by number of blue lines claiming them (arm 2)

```
  cells share_claimed_by_2plus mean_claims
 517087               0.786299     3.28213
```

Figures: `20261011_habitat_join-demo_morr_fig1.png` (morr build, blk vs range, blue line 360880257), `20261011_habitat_join-demo_morr_fig2.png` (fresh vs morr rearing).

Run time: 88 s.
