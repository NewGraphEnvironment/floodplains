# Free reference: disturbance omission — NECR (#93 phase 4)

**Run:** 2026-09-29 · `Rscript scripts/landcover_accuracy/reference_omission-disturbance.R necr` · drift 0.19.0 · terra 1.9.50 · sf 1.1.2 · fwapg `fresh-db` container

Definitions: `research/landcover_accuracy.md`, "Free-reference omission", committed in 0e2164e before this first ran. Rows: `20260929_reference_omission-disturbance_necr.csv`.

```
harvest: 79 qualifying polygons touch the floodplain
fire: 3 qualifying polygons touch the floodplain
  source year n_polys denom_ha io_loss_ha published_loss_ha omission_io
 harvest  all      79    92.05      68.59             54.24      0.2549
 harvest 2018      10    12.24       9.31              7.71      0.2394
 harvest 2019      22    22.63      16.09             11.15      0.2890
 harvest 2020      21    20.17      16.04             13.95      0.2048
 harvest 2021      14    23.93      18.34             14.69      0.2336
 harvest 2022      12    13.08       8.81              6.74      0.3265
    fire  all       3   635.16     435.54            425.73      0.3143
    fire 2018       2   634.87     435.28            425.73      0.3144
    fire 2022       1     0.29       0.26              0.00      0.1034
 omission_published
             0.4108
             0.3701
             0.5073
             0.3084
             0.3861
             0.4847
             0.3297
             0.3294
             1.0000
Criterion 4 (IO misses > 30% of in-window stand-replacing harvest area): omission_io = 0.255 over 92.0 ha -> does not hold
```
