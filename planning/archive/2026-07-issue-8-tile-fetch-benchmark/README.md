## Outcome

Integrated drift 0.6.0's `dft_stac_fetch(tile_size=)` (drift#36) into `fp_lulc` as an opt-in
per-area knob (`area.yml` `tile_size:`, default off), then benchmarked speedup vs parity vs
accuracy to decide whether to adopt it. **Negative result — do not adopt.** Accuracy is fine
(neexdzii tiled vs untiled classified rasters agree ≥ 99.999%, no seam band) and parity holds
within sieve quantization (~1 ha), but tiling is **slower at every tile size on every AOI**:
neexdzii full step-3 6.3× slower, FRAN 883 km² direct fetch 0.79× (20 km) / 0.31× (10 km). The
reason is geometric and robust — a floodplain is a thin diagonal corridor, the worst case for
square tiling (coarse tiles blanket the bbox with no download saving but N× per-tile overhead;
fine tiles hug the corridor but explode round-trips). The opt-in stays wired but off; the
bbox-download waste must be fixed in-cube (drift#36 `filter_geom`, blocked by gdalcubes#110), not
by client-side tiling. A plan-agent review before baseline caught two blockers (no runtime drift
floor; a cache-wipe that would clobber the shared cache). Evidence:
`scripts/floodplain_lcc/logs/20260711_lulc_tile-benchmark_{neexdzii,fran}.md`; verdict:
`research/20260711_lulc_tile-fetch-benchmark.md`.

Closed by: PR #10 (merge 9cb10f7) — closes #8.
