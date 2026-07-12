# fp_lulc Pass-2 reuse — validation + speedup (#11)

**Date:** 2026-07-11 · **Stack:** drift 0.6.0, terra 1.9.34 · **AOI:** neexdzii `co_ff04`
(14 sub-basins) · **Change:** Pass 2 crops+masks Pass 1's `classified_all` per sub-basin instead
of re-fetching STAC. Same-stack A/B on step 3.

## Speedup

| run | STAC queries | real (s) |
|---|---|---|
| baseline (re-fetch per sub-basin) | 15 (1 Pass 1 + 14 Pass 2) | 631 |
| reuse (crop+mask Pass 1) | **1** | **51** |

**12.4× faster.** Pass 2's 14 fetches are eliminated; it is now pure in-memory crop/mask.

## Correctness — EXACT

Per-sub-basin `lulc_summary` (245 rows: 14 basins × classes × 3 years) vs the same-stack
baseline:
- total area 52,632.3 ha both; **max per-row area delta 0.000 ha**, 0 rows differ > 0.5 ha.
- Identical, not merely within edge noise: independent per-sub-basin fetches landed on the same
  res-aligned UTM grid as Pass 1, so cropping Pass 1's raster returns the same pixels.
- Pass-1 tree loss unchanged at 943.13 ha (Pass 1 was not touched).

## Verdict

Strictly better — 12.4× faster with byte-identical output. Adopt. Impact scales with sub-basin
count (neexdzii 15→1 fetches); whole-WSG groups (1 sub-basin) still halve their fetch (Pass 2 no
longer re-fetches the whole floodplain). This is the real fetch-cost lever the `tile_size`
investigation (#8) was reaching for.
