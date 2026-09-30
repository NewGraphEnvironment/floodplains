# Drought years from unregulated gauges — NECR (#93 phase 3)

**Run:** 2026-09-29 · `Rscript scripts/landcover_accuracy/drought_rank-gauges.R necr` · HYDAT 2026-07-17 release (refreshed from 2024-04-16 the same day via `tidyhydat::download_hydat()`) · tidyhydat 1.0.1

Per-gauge rows: `20260929_drought_rank-gauges_necr.csv`.

```
Aug–Sep mean flow, percentile rank in each gauge's record (0 = driest):
 station          role    record 2017 2018 2019 2020 2021 2022 2023
 08JB002  free-flowing 1929-2025 0.39 0.34 0.14 0.51 0.16 0.77 0.03
 08JE004  free-flowing 1976-2024 0.36 0.19 0.55 0.98 0.34 0.47 0.15
 08KC001  free-flowing 1953-2024 0.25 0.20 0.48 0.92 0.28 0.34 0.12
 08KG001  free-flowing 1953-2024 0.34 0.23 0.97 0.77 0.49 0.80 0.21
 08JB003 lake-buffered 1951-2025 0.47 0.28 0.29 0.76 0.25 0.83 0.03
 08JE001 lake-buffered 1930-2025 0.23 0.18 0.15 0.86 0.21 0.67 0.01
 08JC001     regulated 1915-2024 0.41 0.47 0.14 0.39 0.71 0.70 0.45

Free-flowing gauges; low = lowest quintile (pct_rank <= 0.20) at more than half:
 year n_gauges n_low median_pct low_year
 2017        4     0       0.35    FALSE
 2018        4     2       0.21    FALSE
 2019        4     1       0.52    FALSE
 2020        4     0       0.85    FALSE
 2021        4     1       0.31    FALSE
 2022        4     0       0.62    FALSE
 2023        4     3       0.14     TRUE

Low-flow years: 2023 
```
