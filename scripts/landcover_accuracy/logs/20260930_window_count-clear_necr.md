# window_count-clear.R necr run + derive — 2026-09-30

drift 0.20.0. Months 4–10 × 2017–2023 over NECR `ch_ff04` at res 100 (61,507 cells);
`aggregation = "count"` (distinct clear days), `bands = "red"`, `cloud_cover_max = 20`, `clip = TRUE`.

- **run:** 18:02:40–18:29:43 UTC, 27 min for 49 month-years (one cached from validate). 0 `failed`.
- **drift#87 gate:** `grep -c repoprted` returned 0 on the validate, run and derive logs, which
  are every log that filled the count cache.
- **Stats:** `20260930_window_count-clear_necr.csv`, a copy of
  `data/necr/accuracy/windows_clear_obs.csv`.

## Share of floodplain cells with ≥ 1 clear day

| year | Apr | May | Jun | Jul | Aug | Sep | Oct |
|---|---:|---:|---:|---:|---:|---:|---:|
| 2017 | 0 † | 0 † | 0.981 | 0 † | 0.852 | 0.999 | 0.838 |
| 2018 | 0.867 | 0.993 | 1.000 | 1.000 | 0.999 | 0.981 | 0.983 |
| 2019 | 0.906 | 0.999 | 0.811 | 0.180 | 0.999 | 0.974 | 0.957 |
| 2020 | 0.701 | 0.999 | 0.940 | 0.999 | 1.000 | 1.000 | 0.013 |
| 2021 | 0.994 | 0.991 | 1.000 | 1.000 | 0.999 | 0 † | 0.638 |
| 2022 | 0.730 | 0.988 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| 2023 | 0.900 | 1.000 | 0.999 | 1.000 | 1.000 | 1.000 | 1.000 |

† `empty`: no scene under 20% cloud anywhere on the floodplain.

## derive

- No month clears 0.95 in all seven years.
- Without 2017, May and August both pass in every year. August takes the tie on minimum share
  (0.9985 against 0.988), so **the span is August**.
- **2017:** the direct count of August is 0.852, so it fails. Widening adds September (0.999)
  ahead of July (0), and the direct count of **August–September is 1.000**, so it passes.
- `reference/necr/windows.csv`: 2017 `8-9`; 2018, 2020 and 2023 `8`. A second `derive`
  reproduced it byte-identical.
- First and last month clear everywhere, per year:

  | year | first | last |
  |---:|---:|---:|
  | 2017 | 6 | 9 |
  | 2018 | 5 | 10 |
  | 2019 | 5 | 10 |
  | 2020 | 5 | 9 |
  | 2021 | 4 | 8 |
  | 2022 | 5 | 10 |
  | 2023 | 5 | 10 |

  These are not necessarily contiguous: 2019 fails June and July.
