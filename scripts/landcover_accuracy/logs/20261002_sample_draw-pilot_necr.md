# Sample redraw with the prior-fire stratum: NECR (#103, phase 4)

**Run:** 2026-10-02 · `Rscript scripts/landcover_accuracy/sample_draw-pilot.R necr` · drift 0.20.0 · seed 930093, n = 30 per stratum

#103 adds stratum 19, "change in prior fire": published change cells inside a fire from the
`lookback:` window, which is 2002–2016 for the 2017–2023 interval. It is decided at cell level from
the `fire_prior` lookback entry and ranks right after the cause strata. Nothing had been labelled
when this ran: `labels.gpkg` held 450 rows, none with a status, and `labels.csv` did not exist.

**Strata that lost no cells kept every point.** Compared with the 2026-09-29 draw (git `HEAD`),
strata 1, 2, 14, 17, 20, 30, 31 and 32 have identical `point_id`/`cell`/`map_class`. That holds
across drift 0.19.0 → 0.20.0. Stratum 14 lost 2 cells and still kept its points. The strata that
gave cells to 19 moved under the same ids:

| stratum | moved | ha before → after |
|---|---:|---|
| 10 wetland change | 28 of 30 | 950.45 → 758.02 |
| 11 Trees → Rangeland | 29 of 30 | 274.31 → 180.56 |
| 12 Rangeland → Trees | 30 of 30 | 532.73 → 390.10 |
| 13 Crops ↔ Rangeland | 30 of 30 | 1,319.14 → 1,304.38 |
| 15 Snow/Ice → any | 30 of 30 | 3.86 → 3.39 |
| 16 any ↔ Water | 28 of 30 | 132.73 → 126.06 |
| 18 other change | 15 of 30 | 102.15 → 99.49 |

The amounts given up sum to 453.4 ha, which is stratum 19's area. The points also gain an
`in_fire_prior_poly` column, and `design.json` gains
`lookback: {name: fire_prior, lookback: 15, years: [2002, 2016]}`.

```
strata partition the footprint: 4183814 cells (41838.1 ha)
480 points over 16 strata -> /Users/airvine/Projects/repo/floodplains/reference/necr
 stratum         stratum_label   kind n_cells     area       weight  n
       1          change: fire change   58250   582.50 1.392270e-02 30
       2       change: harvest change   62154   621.54 1.485582e-02 30
      10        wetland change change   75802   758.02 1.811792e-02 30
      11    Trees -> Rangeland change   18056   180.56 4.315679e-03 30
      12    Rangeland -> Trees change   39010   390.10 9.324028e-03 30
      13   Crops <-> Rangeland change  130438  1304.38 3.117682e-02 30
      14       Crops <-> Trees change   17875   178.75 4.272417e-03 30
      15       Snow/Ice -> any change     339     3.39 8.102655e-05 30
      16         any <-> Water change   12606   126.06 3.013040e-03 30
      17       other tree loss change    3180    31.80 7.600720e-04 30
      18          other change change    9949    99.49 2.377974e-03 30
      19  change in prior fire change   45339   453.39 1.083676e-02 30
      20 sieved change (<1 ha) sieved  104947  1049.47 2.508405e-02 30
      30        stable wetland stable  519852  5198.52 1.242531e-01 30
      31          stable Trees stable 1320611 13206.11 3.156476e-01 30
      32          stable other stable 1765406 17654.06 4.219609e-01 30
```

A second run wrote `sample.gpkg`, `strata.csv` and `design.json` **byte-identical** to the first (`cmp`).
