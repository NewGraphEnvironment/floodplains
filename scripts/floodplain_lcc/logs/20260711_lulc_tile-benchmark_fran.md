# FRAN tile_size fetch-speedup benchmark (#8)

**Date:** 2026-07-11 · **Stack:** drift 0.6.0, terra 1.9.34 · **AOI:** FRAN `ch_ff04`
(883 km², bbox 11,708 km² → footprint 7.5% of bbox — a thin diagonal corridor) · **Method:**
direct `dft_stac_fetch` timing, year 2023, cold (`force=TRUE`), isolated `cache_dir` (never
touches the shared cache). Reuses the existing FRAN step-1/2 output — no re-model needed.

## Result

| fetch | tiles | real (s) | vs untiled | valid cells |
|---|---|---|---|---|
| untiled | — | 177.1 | 1.00× | 9,116,848 |
| tiled 20000 m | 27 | 225.4 | **0.79×** | 9,117,073 |
| tiled 10000 m | 84 | 564.5 | **0.31×** | 9,117,073 |

Output is equivalent (0.002% valid-cell diff). Tiling is **slower at every tile size**.

## Why (robust, geometric)

A floodplain is a thin diagonal corridor — the worst case for square-tile coverage:
- **Coarse tiles** (20 km, 27 of them) still blanket ~92% of the bbox (27 × 400 km² ≈ 10,800 of
  11,708 km²) → almost no download saving, but 27× the per-tile gdalcubes cube-build + read + a
  `terra::merge`. Net slower.
- **Fine tiles** (10 km, 84 of them) cover less area but the round-trip overhead explodes → 3.2×
  slower.
- There is no sweet spot: the corridor's footprint (7.5%) can only be captured tightly by tiles
  small relative to the corridor *width*, which forces many tiles → overhead dominates.

Corroborated by neexdzii (171 km² reach, `tile_size=5000`): full step-3 was 6.3× slower
(66 min vs 10.5 min). Both a small reach and the largest whole-WSG floodplain lose.

## Secondary finding

The untiled single-year fetch is only ~177 s — the "~30 min, download-bound" cost noted in
CLAUDE.md is dominated by classify/transition over 3 years + both passes, NOT the fetch. So even
a hypothetical fetch speedup would not move step-3 wall-clock much. The download-bound framing
overstated the fetch's share.

## Verdict

**Do not adopt `tile_size` for floodplain LULC.** Accuracy is fine (see neexdzii log,
≥99.999%) — tiling is not broken, it is just slower for this geometry class. The bbox-download
waste must be attacked in-cube (drift#36's `filter_geom` polygon clip, blocked upstream by
gdalcubes#110), not by client-side square tiling. Keep the opt-in wired (harmless, default off);
set it on no group.
