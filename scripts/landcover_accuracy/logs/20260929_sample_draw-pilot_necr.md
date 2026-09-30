# Pilot sample draw — NECR (#93 phase 5)

**Run:** 2026-09-29 · `Rscript scripts/landcover_accuracy/sample_draw-pilot.R necr` · drift 0.19.0 · terra 1.9.50 · seed 930093, n = 30 per stratum

Redrawn after code-check round 1 moved stable Flooded Vegetation outside FWA polygons (4,396 cells) from "stable other" into "stable wetland", as the pinned definition says. The redraw was compared with a second run: `sample.gpkg`, `strata.csv` and `design.json` are byte-identical. The change strata sum to 472,998 cells, equal to the published change cells; the sieved stratum holds 104,947.

```
strata partition the footprint: 4183814 cells (41838.1 ha)
450 points over 15 strata -> /Users/airvine/Projects/repo/floodplains/reference/necr
 stratum         stratum_label   kind n_cells     area       weight  n
       1          change: fire change   58250   582.50 1.392270e-02 30
       2       change: harvest change   62154   621.54 1.485582e-02 30
      10        wetland change change   95045   950.45 2.271731e-02 30
      11    Trees -> Rangeland change   27431   274.31 6.556458e-03 30
      12    Rangeland -> Trees change   53273   532.73 1.273312e-02 30
      13   Crops <-> Rangeland change  131914  1319.14 3.152960e-02 30
      14       Crops <-> Trees change   17877   178.77 4.272895e-03 30
      15       Snow/Ice -> any change     386     3.86 9.226032e-05 30
      16         any <-> Water change   13273   132.73 3.172464e-03 30
      17       other tree loss change    3180    31.80 7.600720e-04 30
      18          other change change   10215   102.15 2.441552e-03 30
      20 sieved change (<1 ha) sieved  104947  1049.47 2.508405e-02 30
      30        stable wetland stable  519852  5198.52 1.242531e-01 30
      31          stable Trees stable 1320611 13206.11 3.156476e-01 30
      32          stable other stable 1765406 17654.06 4.219609e-01 30
```
