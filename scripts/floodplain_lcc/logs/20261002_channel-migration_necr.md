# Channel-migration probe: necr (ch_ff04, 2017 -> 2023)

Produced by `scripts/floodplain_lcc/channel_probe-migration.R necr`, 2026-10-02 08:50 PDT, drift 0.20.0, terra 1.9.50.
Rule: research/channel_migration.md (rule v2, pre-registered).

Anchor 1: re-sieving the endpoints at 1 ha reproduces transition.tif (0 differing cells).
Anchor 2: unsieved total change 5779.45 ha = strata change + sieved 5779.45 ha.

## unsieved

- role patches 7341, Water-involving 509.73 ha (erosion 314.92, deposition 168.98, other 25.83)
- misregistration (transition-level patches, drift): sliver 69.2% of area, exact reciprocal 2.6%
- each condition alone, share of erosion + deposition area: width 33.7%, elong 80.6%, io_adjacent 88.2%, FWA <= 50 m 69.2%, not lake margin 51.9%, aligned 58.3%
- width_px p10/25/50/75/90: 0.50 / 0.50 / 0.50 / 0.75 / 0.88
- elong (equivalent rectangle) p10/25/50/75/90: 1.00 / 1.00 / 1.00 / 3.90 / 10.41
- elong (MRR) p10/25/50/75/90: 1.00 / 1.00 / 1.00 / 3.00 / 4.57
- fwa_dist_m p10/25/50/75/90: 0.00 / 0.00 / 8.38 / 243.36 / 553.74
- sustained p10/25/50/75/90: 0.00 / 0.00 / 0.00 / 0.50 / 1.00
- candidates 23; pairs: 0 opposite (NA% exact reverse), 0 same-side; 0 FWA-opposite pairs had no stable Water between them

| cand ha | share (A) | sustained cand / width-matched (B) | opposite / same (C) | R over opposite pairs (D) | A | B | C | D | separates | direction |
|---|---|---|---|---|---|---|---|---|---|---|
| 27.83 | 0.055 | 0.304 / 0.472 | 0.000 / 0.000 | NA (n = 0) | FALSE | FALSE | FALSE | FALSE | FALSE | FALSE |

## sieved

- role patches 850, Water-involving 230.49 ha (erosion 159.63, deposition 59.73, other 11.13)
- misregistration (transition-level patches, drift): sliver 41.1% of area, exact reciprocal 0.8%
- each condition alone, share of erosion + deposition area: width 63.9%, elong 89.1%, io_adjacent 79.4%, FWA <= 50 m 75.0%, not lake margin 46.2%, aligned 53.1%
- width_px p10/25/50/75/90: 0.50 / 0.50 / 0.67 / 1.00 / 1.75
- elong (equivalent rectangle) p10/25/50/75/90: 1.00 / 1.00 / 2.15 / 8.62 / 22.22
- elong (MRR) p10/25/50/75/90: 1.00 / 1.00 / 1.85 / 3.00 / 5.22
- fwa_dist_m p10/25/50/75/90: 0.00 / 0.00 / 13.78 / 243.15 / 556.63
- sustained p10/25/50/75/90: 0.00 / 0.00 / 0.26 / 1.00 / 1.00
- candidates 15; pairs: 0 opposite (NA% exact reverse), 0 same-side; 0 FWA-opposite pairs had no stable Water between them

| cand ha | share (A) | sustained cand / width-matched (B) | opposite / same (C) | R over opposite pairs (D) | A | B | C | D | separates | direction |
|---|---|---|---|---|---|---|---|---|---|---|
| 23.71 | 0.103 | 0.260 / 0.493 | 0.000 / 0.000 | NA (n = 0) | FALSE | FALSE | FALSE | FALSE | FALSE | FALSE |

