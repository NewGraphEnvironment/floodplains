# Chip re-build after the #103 redraw: NECR

**Run:** 2026-10-02 07:44–12:26 UTC · `caffeinate -s Rscript scripts/landcover_accuracy/chip_build-composite.R necr` · windows from `reference/necr/windows.csv` (unchanged)

The 2026-09-30 chip cache was carried into the rebuilt review project, so only the points the redraw moved or added were fetched. `grep -c repoprted` on the full log: 0, so no failed gdalcubes chunk reads (drift#87). The project then took the four S2 layers, each with its own map theme.

```
100 / 480 points, 42.5 min
200 / 480 points, 142.3 min
300 / 480 points, 208.6 min
400 / 480 points, 282.1 min
1920 chips (0 missing) for 480 points x 4 windows in 282.3 min -> /Users/airvine/Projects/repo/floodplains/data/necr/accuracy/review/necr_lulc_review/chips
```
