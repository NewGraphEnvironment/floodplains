# window_count-clear.R necr validate — 2026-09-30

`Rscript scripts/landcover_accuracy/window_count-clear.R necr validate`: drift 0.20.0, 2021-07,
`cloud_cover_max = 20`, `bands = "red"`, `aggregation = "count"` (distinct clear days per pixel).
Run 18:00:01–18:02:15 UTC.

## (a) res 100 vs res 20, 6 km sub-AOI on the floodplain's largest part

| res | cells | median | p10 | max | share ≥ 1 | share ≥ 3 |
|---:|---:|---:|---:|---:|---:|---:|
| 100 | 579 | 5 | 5 | 6 | 1 | 1 |
| 20 | 8,376 | 5 | 5 | 6 | 1 | 1 |

The coarse grid does not move the count.

## (b) against an independent rstac item query (bbox)

17 items (cloud ≤ 20) over **6 distinct dates** on tiles 09UYV, 10UCE and 10UDE. The max
per-pixel count is 6 at both resolutions, so the count stays within the distinct dates. It also
shows that drift counts days, not items: the 17 items would have allowed up to 17.

## (c) whole floodplain, timed

`ch_ff04` at res 100: 61,507 cells, median 5, p10 4, max 6, share ≥ 1 **0.9996**, share ≥ 3
0.994. It took **0.8 min**, so `run` (49 calls) was estimated at ~0.7 h. drift queried the AOI's
convex hull, because the 87,350-vertex AOI exceeds the STAC body limit.
