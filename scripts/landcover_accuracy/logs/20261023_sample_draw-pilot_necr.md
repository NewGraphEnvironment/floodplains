# Sample redraw on all_ff04: NECR (#148)

**Run:** 2026-10-23 · `FORCE=1 Rscript scripts/landcover_accuracy/sample_draw-pilot.R necr all_ff04` · drift 0.24.3 · seed 930093, n = 30 per stratum

The species items were retired from the catalogue on 2026-10-15, so NECR's published floodplain is `all_ff04`; the sample, drawn on `ch_ff04`, moved there. Nothing had been labelled in either review project. Before the draw the first draw's `review_key.csv` and `labels_model.sha256` were removed (they map to points that moved) and its review projects, chips, Wayback cache and model-labeller directory were moved aside unread to `data/necr/accuracy/_aside_20261023_ch_ff04/`.

**Deterministic.** Run twice (7.0 min each); `sample.gpkg`, `strata.csv` and `design.json` were `cmp`-identical. `design.json` names `transition_all_ff04_2017_2023`, and `fp_acc_area("necr")` resolves all_ff04 / all / 2 from the design with no NOTE.

```
strata partition the footprint: 8078287 cells (80782.9 ha)
480 points over 16 strata -> reference/necr
 stratum         stratum_label   kind n_cells     area       weight  n
       1          change: fire change  153172  1531.72 0.0189609505 30
       2       change: harvest change  170943  1709.43 0.0211607981 30
      10        wetland change change  147317  1473.17 0.0182361681 30
      11    Trees -> Rangeland change   37014   370.14 0.0045819120 30
      12    Rangeland -> Trees change  124877  1248.77 0.0154583515 30
      13   Crops <-> Rangeland change  238493  2384.93 0.0295227194 30
      14       Crops <-> Trees change   33519   335.19 0.0041492708 30
      15       Snow/Ice -> any change    1490    14.90 0.0001844450 30
      16         any <-> Water change   20798   207.98 0.0025745557 30
      17       other tree loss change    4891    48.91 0.0006054501 30
      18          other change change   19449   194.49 0.0024075649 30
      19  change in prior fire change   67384   673.84 0.0083413724 30
      20 sieved change (<1 ha) sieved  204033  2040.33 0.0252569635 30
      30        stable wetland stable 1028333 10283.33 0.1272959230 30
      31          stable Trees stable 3236339 32363.39 0.4006219388 30
      32          stable other stable 2590235 25902.35 0.3206416162 30
```
