# Findings — #8 tiled STAC fetch

## Package audit (2026-07-11)
- `flooded` 0.3.2 = origin/main; **unchanged** since the last WSG run. Local checkout clean.
- `drift` installed 0.4.0 while origin was **0.6.0** (local checkout was 65 behind). Updated to
  0.6.0 from the fast-forwarded checkout.
- Changes since last run (0.4.0 -> 0.6.0):
  - **0.5.0** `dft_stac_cube(clip=)` — continuous Sentinel-2 *trajectory* path; `fp_lulc` does not
    use it. No effect on categorical LULC runs.
  - **0.6.0** `dft_stac_fetch(tile_size=)` — the categorical path `fp_lulc` uses. Default `NULL` =
    old behavior. This is the actionable change.
- `dft_rast_transition` / `dft_transition_vectors` signatures unchanged (0.4.0 `changes_only`
  path intact) — verified via `args()`.

## `tile_size` mechanics (drift NEWS 0.6.0)
- Splits the bbox into a `res`-aligned grid, streams only tiles intersecting the AOI polygon,
  mosaics with `terra::merge()`. `filter_geom`-independent (the in-cube clip segfaults on the
  pinned gdalcubes build; still blocked by gdalcubes#110).
- Tiled fetches cache a terra GeoTIFF (`.tif`) and key distinctly from untiled NetCDF (`.nc`) —
  so enabling it re-fetches once but leaves existing untiled caches intact. `tile_size = NULL`
  is byte-for-byte previous behavior.
- Smaller tiles waste less bbox but cost more per-tile round trips; no auto-tuning.
- CRS units = metres under the default UTM CRS.

## Integration decision
- Opt-in via `area.yml` `tile_size:` (NULL default) rather than a global flip: protects the
  neexdzii **943.13 ha** parity gate and the already-published Fraser groups, which would
  otherwise re-fetch on the tiled path and could differ at mosaic seams.
- Both `fp_lulc` fetch sites take it: whole-floodplain (L68) and per-sub-basin (L149). For a
  whole-WSG group the per-sub-basin AOI ≈ the whole floodplain (one group-polygon sub-basin),
  so both are large and both benefit.

## Plan-agent review (2026-07-11, pre-baseline)
Caught before the baseline commit — fixes folded in:
- **Blocker: no runtime drift floor.** `tile_size` is passed unconditionally, so drift < 0.6.0
  errors "unused argument" for every area; `update_packages` defaults FALSE and packages.R had
  no pin. Fix: `fp_lulc` asserts `packageVersion("drift") >= 0.6.0`; packages.R comment bumped.
- **Blocker: "clear cache between runs" clobbers the shared cache** (`cache_dir = NULL` =>
  one `user_cache_dir("drift")`). Tiled `.tif` / untiled `.nc` key distinctly and never collide,
  so use `force = TRUE`, never a cache wipe. Plan + memo corrected.
- **Gap: no revert-proof way to run the fixture tiled.** `tile_size` came only from `area.yml`;
  editing `config/neexdzii/area.yml` risks committing it into the parity fixture. Fix: `FP_TILE_SIZE`
  env override in `fp_read_config`.
- **Gap: neexdzii is a compact reach** — weak seam test. Accuracy must additionally run on a
  whole-WSG corridor (PCEA). Parity stays neexdzii (that's where 943.13 ha lives).
- **Acceptance: parity tolerance mis-scaled** — the 1 ha sieve means a seam pixel can swing ~1 ha,
  ~25× the 0.004% VCA figure. Judge parity at ~1 ha, downstream of the pre-sieve accuracy metric.
  Added numeric floors (accuracy ≥ 99.9% no seam band; speedup ≥ 2×).
- **Scope:** adopt on benchmarked group(s) first; extend to same-geometry corridors only with the
  generalization stated + per-group coverage check.
- Verified OK: opt-in NULL path sound; CRS fine (drift auto-UTM, `tile_size` metres align `res=10`).

## New-area coverage checks (context, landed under #3)
- MCGR ch=4087 / bt=4884 · BOWR ch=3335 / bt=3807 — chinook chosen (Fraser drainage).
- PCEA ch=0 / bt=6988 · PARS ch=0 / bt=8436 — bull trout only (Arctic slope).
- **PINE = 0 segments for both** — not a species gap; PINE is not loaded in the local fwapg
  build. Blocked until a link/bcfishpass build loads it.
