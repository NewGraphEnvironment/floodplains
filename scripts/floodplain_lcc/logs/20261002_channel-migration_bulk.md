# Channel-migration probe: bulk (co_ff04, 2017 -> 2023)

Produced by `scripts/floodplain_lcc/channel_probe-migration.R bulk`, 2026-10-02 09:06 PDT, drift 0.20.0, terra 1.9.50.
Rule: research/channel_migration.md (rule v2, pre-registered).

Anchor 1: re-sieving the endpoints at 1 ha reproduces transition.tif (0 differing cells).
Anchor 2: no strata.csv; unsieved total change 4624.97 ha.

## unsieved

- role patches 6750, Water-involving 696.08 ha (erosion 466.84, deposition 195.16, other 34.08)
- misregistration (transition-level patches, drift): sliver 62.6% of area, exact reciprocal 9.8%
- each condition alone, share of erosion + deposition area: width 43.2%, elong 86.9%, io_adjacent 94.2%, FWA <= 50 m 86.4%, not lake margin 73.3%, aligned 62.3%
- width_px p10/25/50/75/90: 0.50 / 0.50 / 0.56 / 0.80 / 1.08
- elong (equivalent rectangle) p10/25/50/75/90: 1.00 / 1.00 / 1.00 / 4.64 / 12.07
- elong (MRR) p10/25/50/75/90: 1.00 / 1.00 / 1.33 / 3.00 / 4.74
- fwa_dist_m p10/25/50/75/90: 0.00 / 0.00 / 6.10 / 115.17 / 447.38
- sustained p10/25/50/75/90: 0.00 / 0.00 / 0.00 / 0.60 / 1.00
- candidates 96; pairs: 4 opposite (75% exact reverse), 4 same-side; 1 FWA-opposite pairs had no stable Water between them

| cand ha | share (A) | sustained cand / width-matched (B) | opposite / same (C) | R over opposite pairs (D) | A | B | C | D | separates | direction |
|---|---|---|---|---|---|---|---|---|---|---|
| 99.83 | 0.143 | 0.549 / 0.617 | 0.051 / 0.089 | 0.550 (n = 4) | FALSE | FALSE | FALSE | FALSE | FALSE | FALSE |

## sieved

- role patches 1157, Water-involving 390.41 ha (erosion 281.36, deposition 84.32, other 24.73)
- misregistration (transition-level patches, drift): sliver 43.1% of area, exact reciprocal 5.9%
- each condition alone, share of erosion + deposition area: width 66.5%, elong 94.2%, io_adjacent 93.8%, FWA <= 50 m 94.7%, not lake margin 72.8%, aligned 58.0%
- width_px p10/25/50/75/90: 0.50 / 0.50 / 0.75 / 1.18 / 1.73
- elong (equivalent rectangle) p10/25/50/75/90: 1.00 / 1.00 / 3.55 / 10.52 / 25.28
- elong (MRR) p10/25/50/75/90: 1.00 / 1.00 / 2.00 / 3.77 / 5.81
- fwa_dist_m p10/25/50/75/90: 0.00 / 0.00 / 0.00 / 19.29 / 175.05
- sustained p10/25/50/75/90: 0.00 / 0.00 / 0.25 / 0.98 / 1.00
- candidates 53; pairs: 0 opposite (NA% exact reverse), 3 same-side; 1 FWA-opposite pairs had no stable Water between them

| cand ha | share (A) | sustained cand / width-matched (B) | opposite / same (C) | R over opposite pairs (D) | A | B | C | D | separates | direction |
|---|---|---|---|---|---|---|---|---|---|---|
| 77.18 | 0.198 | 0.594 / 0.633 | 0.000 / 0.093 | NA (n = 0) | FALSE | FALSE | FALSE | FALSE | FALSE | FALSE |

