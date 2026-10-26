# Dated imagery and Wayback on the all_ff04 draw: NECR (#148)

**Run:** 2026-10-23 · `imagery_index-dated.R necr`, `wayback_index-capture.R necr`, `review_build-qgis.R necr`, `imagery_build-dated.R necr`, `wayback_build-chips.R necr`

The air photo 2012 thumbnails (388 frames, keyed by frame, not point) were copied from the first draw's project; every other file was built cold. URLs and hosts are redacted by the scripts; none appear below.

## imagery_index-dated.R
```
   airphoto 1973    196  40.8   FALSE FALSE
   airphoto 1974    205  42.7   FALSE FALSE
   airphoto 1975     54  11.2   FALSE FALSE
   airphoto 1976     34   7.1   FALSE FALSE
   airphoto 1977    172  35.8   FALSE FALSE
   airphoto 1978      5   1.0   FALSE FALSE
   airphoto 1979     84  17.5   FALSE FALSE
   airphoto 1980    248  51.7   FALSE FALSE
   airphoto 1984    178  37.1   FALSE FALSE
   airphoto 1985    336  70.0   FALSE FALSE
   airphoto 1986     34   7.1   FALSE FALSE
   airphoto 1987    197  41.0   FALSE FALSE
   airphoto 1988    461  96.0   FALSE FALSE
   airphoto 1989     51  10.6   FALSE FALSE
   airphoto 1990    294  61.3   FALSE FALSE
   airphoto 1991    240  50.0   FALSE FALSE
   airphoto 1992     79  16.5   FALSE FALSE
   airphoto 1994     37   7.7   FALSE FALSE
   airphoto 1995    279  58.1   FALSE FALSE
   airphoto 1996    480 100.0   FALSE FALSE
   airphoto 1997    314  65.4   FALSE FALSE
   airphoto 1999     29   6.0   FALSE FALSE
   airphoto 2000    480 100.0   FALSE FALSE
   airphoto 2002    111  23.1   FALSE FALSE
   airphoto 2005    103  21.5   FALSE FALSE
   airphoto 2006    111  23.1   FALSE FALSE
   airphoto 2012    480 100.0    TRUE  TRUE
   airphoto 2019     12   2.5    TRUE FALSE
 orthophoto 2021    136  28.3    TRUE  TRUE
exit=0
```

## wayback_index-capture.R
```
  150/197 releases read (25.0 min)
  175/197 releases read (29.2 min)
89814 (point, release) captures; 55 distinct capture dates

960 rows -> reference/necr/wayback.csv (33.5 min)
capture distance from each endpoint (points):
        band
endpoint same year +/-1 year +/-2 years further no capture
    2017        34       287         64      95          0
    2023       136       100         76     168          0

signed years from endpoint:
        years
endpoint -11 -10  -8  -7  -6  -5  -4  -3  -2  -1   0   1   2   4
    2017   0   0   0   0   0   3  42  11  64 148  34 139   0  39
    2023   3  19  19  69   9  49   0   0  24  83 136  17  52   0

same capture at both endpoints: 160 of 480 points

zoom and resolution of the picked captures:
    src_res
zoom 0.31 0.34 0.46 0.5
  17  107    0   11  91
  18  158   36   52 505
exit=0
```

## review_build-qgis.R (A, before chips)
```
patches.gpkg: written from transition_all_ff04_2017_2023 (24 columns)
✔ Added "Points to label" (Point)
✔ Added "Cell being labelled (10 m)" (Polygon)
ℹ "Points to label" already carries that style - nothing to do
ℹ "Cell being labelled (10 m)" already carries that style - nothing to do
! "Change patches": no style - the layer will draw with a default symbol
✔ Added "Change patches" (Polygon)
no chips yet: run chip_build-composite.R once reference/<area>/windows.csv exists (window_count-clear.R derive)
✔ Set 2 themes in 'data/necr/accuracy/review/necr_lulc_review/necr_lulc_review.qgs'
✔ Removed 5 themes from 'data/necr/accuracy/review/necr_lulc_review/necr_lulc_review.qgs'; 2 remain.
themes, in drop-down order:
  0 Start - Esri satellite (undated, for finding your way)
  9 After labelling - IO change patches and FWA wetlands
project: data/necr/accuracy/review/necr_lulc_review/necr_lulc_review.qgs
```

## imagery_build-dated.R
```
     source year points     share digital theme
   airphoto 2012    480 1.0000000    TRUE  TRUE
 orthophoto 2021    136 0.2833333    TRUE  TRUE
are planar
orthophoto 2021: 227 tiles -> orthophoto_2021.vrt (0.15 m)
This object has 19385 records and requires 2 paginated requests to complete.
Retrieving data
Parsing data
Downloaded 305 of 305 files
Georeferenced 305 of 305 images
airphoto 2012: 305 frames georeferenced, 0 not (0 of them failed to download); 0 of 480 covered points have none
airphoto 2012 -> airphoto_2012.vrt (4.41 m)
1: 13 of 1589 corrected frames are less than 95% covered by the DEM (as little as 91% of one footprint). Their ground elevation is the mean of the covered part, which need not represent the whole — measured over 11,520 truncations that costs a median 0.34% of footprint width at 60-80% coverage and 1.5% below 20%, but up to 24% on broken ground. The DEM stops short of 13 of them; extending it by 469 m would contain every footprint. See `dem_shortfall_m` for the figure per frame. 
exit=0
```

## wayback_build-chips.R
```
  2023: 400 chips (400 fetched, 0 kept), 13.2 min
  2023: 450 chips (450 fetched, 0 kept), 13.9 min
2023: 480 chips (480 fetched, 0 kept), 0 with no capture, 0 failed -> wayback_2023.vrt
manifest -> data/necr/accuracy/wayback/built.csv: built 960

every point reads its own chip; dated/wayback_* = 962 files, 766 MB; 14.5 min
review_id 1, first endpoint:
 review_id endpoint release_id release_date capture_date src_res
         1     2017      26751   2020-04-08   2016-06-30    0.31
exit=0
```
