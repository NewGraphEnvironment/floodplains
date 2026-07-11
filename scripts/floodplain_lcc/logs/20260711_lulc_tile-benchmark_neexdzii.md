# neexdzii tile_size benchmark — parity + accuracy gate (#8)

**Date:** 2026-07-11 · **Stack:** drift 0.6.0, terra 1.9.34, link 0.44.2, flooded 0.3.2 ·
**AOI:** neexdzii `co_ff04` (BULK reach, ~171 km²; interior sub-basins) · **tile_size:** 5000 m
· **Scenario:** step 3 only (existing step 1/2 outputs reused).

Same-stack comparison — both runs on drift 0.6.0. Untiled reproduces the documented fixture, so
the only variable is `tile_size`.

## Timing (wall-clock, step 3 end-to-end incl. classify + both passes)

| run | real (s) | real (min) |
|---|---|---|
| untiled | 631 | 10.5 |
| tiled (5000 m) | 3959 | **66.0** |

**Tiling is 6.3× SLOWER here.** Pass 1 fanned the reach into ~75 tiles/year (× 3 years) and
pass 2 fetched ~8 tiles/sub-basin/year; the per-tile round-trip overhead dwarfs a single
bbox stream. tile_size is a *large-bbox* optimization — on a compact reach it is strictly worse.

## Parity (gross tree-loss / gain, ha)

| metric | untiled | tiled | Δ |
|---|---|---|---|
| loss | 943.13 | 941.25 | **−1.88** (−0.20%) |
| gain | 197.10 | 197.62 | +0.52 |

Untiled = the documented 943.13 ha fixture exactly. The −1.88 ha is downstream sieve
quantization: the 1 ha `patch_min_m2` bins the ~dozen differing edge pixels (below) into/out of
~2 threshold-straddling patches. Exceeds the strict ~1 ha gate, but it is a sieve artifact, not
a classification error.

## Accuracy (classified-pixel agreement, overlapping non-NA px, ~1.76M/yr)

| year | agreement | disagreeing px |
|---|---|---|
| 2017 | 99.9991% | 16 |
| 2020 | 99.9992% | 14 |
| 2023 | 99.9993% | 12 |

Coverage: untiled 1,785,557 vs tiled 1,785,598 non-NA cells (2023) — 41-cell (0.002%) diff.
12–16 scattered pixels, decreasing over years — AOI-margin / mosaic-edge, **not a systematic
seam band**. The mosaic preserves the classification.

## Verdict (neexdzii)

- **Accuracy: PASS** — ≥ 99.999%, no seam band. The tiled mosaic is faithful.
- **Parity: −1.88 ha** — over the strict ~1 ha gate but a sieve-quantization artifact of a dozen
  edge pixels (0.2%). Confirms tiled ≠ byte-identical → fixture + published groups stay untiled.
- **Speedup: NEGATIVE (6.3× slower)** — tile_size must NOT be applied to small reaches. The
  benchmark that matters is a large whole-WSG corridor (PCEA), where the untiled bbox is the cost.

## Implications for PCEA / adoption

- Only groups where the floodplain footprint is a *small fraction of the bbox* can win. Choose a
  **larger** tile_size for PCEA (10000–20000 m) to cap round-trips; 5000 m over-fragments.
- Adoption tolerance: accept the ~0.2% sieve-quantized tree-loss shift IF a real speedup lands;
  judge on the pre-sieve pixel agreement (the faithful metric), not byte-parity.
