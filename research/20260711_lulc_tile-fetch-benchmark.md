# Tiled STAC fetch (`tile_size`) — speedup vs parity vs accuracy

**Date opened:** 2026-07-11 · **Issue:** #8 · **drift:** 0.6.0 (`dft_stac_fetch(tile_size=)`,
drift#36) · **Status:** OPEN — design set, runs pending.

## Hypothesis

`dft_stac_fetch` streams the whole floodplain **bounding box**; for a thin, diagonal whole-WSG
floodplain corridor that is ~10× the pixels inside the polygon. Setting `tile_size` streams only
tiles intersecting the AOI, mosaicked with `terra::merge()` → close to footprint. Expectation:
**large wall-clock reduction on the download-bound fetch, with land-cover output unchanged inside
the polygon.** The uncertainty worth investigating: does the tiled mosaic preserve classification
accuracy (no `terra::merge()` seam artifacts), and does it hold the known-good parity number?

## Method

| Axis | Subject | Test | Pass criterion |
|---|---|---|---|
| **Parity** | neexdzii (known-good anchor) | step 3 untiled vs tiled (via `FP_TILE_SIZE`) | untiled reproduces `co_ff04` **943.13 ha**; tiled within **~1 ha** of untiled |
| **Accuracy** | PCEA (whole-WSG corridor) | classified rasters (pre-sieve) tiled-mosaic vs untiled+clip, inside polygon | **≥ 99.9%** pixel agreement, **no seam band** aligned to tile edges |
| **Speedup** | PCEA floodplain | direct-time `dft_stac_fetch` untiled vs `tile_size` 5000 / 10000 m, `force = TRUE` | **≥ 2×** wall-clock; record ratio |

Why two subjects: neexdzii is a compact reach (few/no interior seams) so its parity is
*necessary but weak* on the mosaic risk — it anchors the number. The seam risk only shows on a
thin diagonal whole-WSG corridor (PCEA), which is also the adoption target. Both are needed.

**Parity tolerance is patch-quantized, not the 0.004% VCA figure.** Tree-loss is computed after
the 1 ha patch sieve (`patch_min_m2 = 10000`), so a single seam pixel near a patch boundary can
add/drop a whole ≥1 ha patch — a swing ~25× the raw VCA noise. Judge parity at ~1 ha, and read
it downstream of the pre-sieve accuracy metric.

**Cache hygiene.** drift's cache is one shared dir (`cache_dir = NULL`). It is NEVER deleted
during benchmarking — that would destroy every published group's `.nc` cache. Tiled (`.tif`) and
untiled (`.nc`) key distinctly and never collide, so timing re-downloads use `force = TRUE`.

Raw timings/coverage → committed evidence logs under `scripts/floodplain_lcc/logs/`
(`yyyymmdd_lulc_tile-benchmark_<wsg>.md`). This memo records the distilled verdict.

## Results

_TBD — populated after the runs._

## Decision

_TBD._ If accuracy + parity hold: adopt `tile_size` per-area for large whole-WSG floodplains
(set `tile_size:` in their `area.yml`), leaving the parity fixture + published groups on the
default path. If seams degrade accuracy: keep opt-in off and record why.
