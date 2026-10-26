# Free reference on all_ff04: NECR (#148)

**Run:** 2026-10-23 · `reference_composition-wetland.R necr`, `reference_omission-disturbance.R necr`, `composition-check.R necr`

Recorded before the omission run (planning findings, commit 315477b): the `all_ff04` value of criterion 4 counts; the `ch_ff04` value (0.2549 over 92.0 ha) stays visible.

```
 all_ff04    fire 2018       3  1335.82     884.49            859.16
 all_ff04    fire 2021       1   145.46     104.22            103.09
 all_ff04    fire 2022       1     0.28       0.24              0.00
 omission_io omission_published
      0.1475             0.2342
      0.1375             0.1938
      0.1663             0.2984
      0.1238             0.2272
      0.1795             0.2969
      0.1342             0.1582
      0.3325             0.3505
      0.3379             0.3568
      0.2835             0.2913
      0.1429             1.0000

Criterion 4 (IO misses > 30% of in-window stand-replacing harvest area): omission_io = 0.147 over 481.5 ha -> does not hold

FWA wetland polygons touching the floodplain: 2646; cells inside them: 12809.0 ha
IO class share inside FWA wetlands, by year:
              class   2017   2018   2019   2020   2021   2022   2023
              Trees 0.6065 0.5832 0.5410 0.6106 0.5593 0.5798 0.5381
          Rangeland 0.3261 0.3451 0.3897 0.3156 0.3666 0.3603 0.3983
              Crops 0.0449 0.0492 0.0467 0.0464 0.0482 0.0409 0.0441
              Water 0.0118 0.0172 0.0172 0.0178 0.0210 0.0147 0.0162
        Bare Ground 0.0053 0.0002 0.0000 0.0000 0.0000     NA     NA
 Flooded Vegetation 0.0041 0.0044 0.0037 0.0064 0.0041 0.0037 0.0026
           Snow/Ice 0.0010 0.0000 0.0011 0.0026 0.0001 0.0000     NA
         Built Area 0.0004 0.0006 0.0005 0.0005 0.0007 0.0006 0.0006
```

`composition-check.R necr`: ALL PASS; check (5) `footprint in_wetland matches the accuracy module's FWA-wetland count (to 0.1 ha)` at 12809.04 vs 12809.04 ha.

**Correction (code review, 2026-10-23):** the criterion line above prints `0.147`, a second rounding of the stored 0.1475 (7,103 of 48,146 cells = 0.14753). The value is **0.148** to three places; the script now prints the stored four-place value.
