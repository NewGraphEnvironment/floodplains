# Esri Wayback capture index and chips: NECR (#115)

**Runs:** 2026-10-08 UTC. One machine; the GDAL tile cache and the metadata cache are in gitignored `data/necr/accuracy/wayback/`.

| step | command | wall time |
|---|---|---|
| index, cold | `Rscript scripts/landcover_accuracy/wayback_index-capture.R necr` | 32.2 min (197 releases x metadata layers 4-6) |
| index, warm | same | 1.3 min, `wayback.csv` byte-identical to the cold run |
| build, cold | `caffeinate -s Rscript scripts/landcover_accuracy/wayback_build-chips.R necr` | 21.2 min (956 chips fetched, 4 failed) |
| build, after fixes | same | 0.3 min (956 kept, 4 fetched, 0 failed) |
| review project A, B | `Rscript scripts/landcover_accuracy/review_build-qgis.R necr`, then `REVIEWER=b` | seconds each |

## Index

```
90538 (point, release) captures; 52 distinct capture dates

960 rows -> reference/necr/wayback.csv (1.3 min)
capture distance from each endpoint (points):
        band
endpoint same year +/-1 year +/-2 years further no capture
    2017         6       237        106     131          0
    2023       148       115        102     115          0

signed years from endpoint:
        years
endpoint -10  -8  -7  -5  -4  -3  -2  -1   0   1   2   4
    2017   0   0   0   0  67  14 106 122   6 115   0  50
    2023  36  41  33   5   0   0  43 102 148  13  59   0

same capture at both endpoints: 115 of 480 points

zoom and resolution of the picked captures:
    src_res
zoom 0.31 0.34 0.46 0.5
  17   76    0   14 121
  18  132   41   58 518
```

Point 1 (`17_00009`, review_id 1): 2017 -> capture **2017-06-11, 0.31 m** (WV03). It is served by release 16245 (2022-04-27), the latest release serving that capture; 15045 (2020-04-29) is the first. The tie between them goes to the later release by design.

## Build

The first (cold) run:

```
2017: 478 chips (478 fetched, 0 kept), 0 with no capture, 2 failed -> wayback_2017.vrt
2023: 478 chips (478 fetched, 0 kept), 0 with no capture, 2 failed -> wayback_2023.vrt

failed chips (4):
 endpoint review_id release_id                                    why
     2017       367      60013      gdal_utils warp: an error occured
     2017       207      63116 the cell is flat (a placeholder tile?)
     2023       206      63116 the cell is flat (a placeholder tile?)
     2023       207      63116 the cell is flat (a placeholder tile?)

gdal_utils warp: an error occured                  the cell is flat 
                                1                                 3 

every point reads its own chip; dated/wayback_* = 958 files, 710 MB; 21.2 min
review_id 1, first endpoint:
 review_id endpoint release_id release_date capture_date src_res
         1     2017      16245   2022-04-27   2017-06-11    0.31
```

- The warp error (review_id 367, 2017) was transient: it succeeded on the next run.
- The three "flat" refusals were **open lake**, not placeholder tiles. They were rendered and looked at. The flat guard was removed, because a Water cell needs its chip.

The run after the code-check fixes:

```
2017: 480 chips (2 fetched, 478 kept), 0 with no capture, 0 failed -> wayback_2017.vrt
2023: 480 chips (2 fetched, 478 kept), 0 with no capture, 0 failed -> wayback_2023.vrt
manifest -> data/necr/accuracy/wayback/built.csv: built 960

every point reads its own chip; dated/wayback_* = 962 files, 711 MB; 0.2 min
review_id 1, first endpoint:
 review_id endpoint release_id release_date capture_date src_res
         1     2017      16245   2022-04-27   2017-06-11    0.31
```

- 115 of 480 points resolve to the **same capture at both endpoints** (the index reports it). Their label says so, e.g. "Esri 2023: 2016-09-30, 0.5 m".
- Rendered 6 points x 2 endpoints from the mosaic VRTs and looked at them. Each point sits in its own capture. Neighbours' chips show as notched Voronoi pieces at the edges, in different captures. One 2023 pick (2024-04-12) is a spring capture with snow.

## Review projects

- A: added `2017 Esri capture (nearest per point) - FIRST YEAR` and `2023 ... - LAST YEAR` with their themes. `cells.gpkg` was rewritten with `cell`, `capture_2017` and `capture_2023` (480 rows).
- B: 48 rows. The `dated/wayback_*` file set is identical to A's (hard links).
- `labels.gpkg` is byte-identical before and after in both projects.
- Blind checks:
  - no `[0-9]+_[0-9]{5}` in any file name under either project (outside the chip cache), or in either wayback VRT;
  - no `wayback.csv`, `built.csv` or `review_key.csv` inside either project;
  - `cells.gpkg` columns are `review_id`, `cell`, `capture_2017`, `capture_2023`.
