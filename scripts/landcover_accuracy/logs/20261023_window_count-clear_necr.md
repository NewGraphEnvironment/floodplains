# Composite windows on all_ff04: NECR (#148)

**Run:** 2026-10-23 · `window_count-clear.R necr validate|run|derive`, each `> log 2>&1` · drift 0.24.3

Counted over the `all_ff04` floodplain (drift caches by AOI, so no `ch_ff04` count was reused). `grep -c repoprted` is 0 in all five logs that filled the cache (validate, run, run again, derive, derive again).

- validate: floodplain-wide 2021-07 at res 100 in 2.3 min (~1.8 h for `run`).
- run: 2022-08 and 2022-09 FAILED with a transient Planetary Computer response (`HTTP content type response 'text/plain' not defined for this operation`); derive refused. `run` again: 47 months cached, both re-counted, 0 failed.
- derive: the 2017 Aug-Sep direct count hit the same transient error; derive again passed.

```
share of floodplain cells with >= 1 clear day (rows year, cols month):
         4     5     6     7     8     9    10
2017 0.000 0.000 0.984 0.000 0.869 0.998 0.809
2018 0.769 0.989 0.999 1.000 0.999 0.972 0.980
2019 0.855 0.999 0.840 0.149 0.999 0.974 0.938
2020 0.637 0.999 0.930 0.999 1.000 1.000 0.011
2021 0.937 0.985 1.000 1.000 0.999 0.000 0.631
2022 0.654 0.963 1.000 1.000 1.000 1.000 1.000
2023 0.815 1.000 0.999 1.000 1.000 1.000 1.000

same-season span (clear everywhere in every year but 2017): months 8
  count 2017 Aug: cached
  2017 months 8, direct count: share >= 1 clear day 0.869
Querying STAC: sentinel-2-l2a (2017-08-01T00:00:00Z/2017-09-30T23:59:59Z)...
  AOI has 199645 vertices; querying its convex hull (STAC body limit)
  12 items returned
## Size of the cube in x direction does not align with dx, extent will be enlarged by 37.579279 at both sides.
  2017 months 8-9, direct count: share >= 1 clear day 0.999
          window year months scenario
2017 same_season 2017    8-9 all_ff04
2018 same_season 2018      8 all_ff04
2020 same_season 2020      8 all_ff04
2023 same_season 2023      8 all_ff04
wrote reference/necr/windows.csv 

first and last month clear everywhere, per year:
  year early late
1 2017     6    9
2 2018     5   10
3 2019     5    9
4 2020     5    9
5 2021     5    8
6 2022     5   10
7 2023     5   10
```

Same windows as on `ch_ff04` (2026-09-30), now stamped `all_ff04`. Per-month counts: `20261023_window_count-clear_necr.csv`.
