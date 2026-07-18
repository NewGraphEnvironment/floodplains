# Task Plan — Tiled STAC fetch (`tile_size`): integrate + benchmark (#8)

Wire drift 0.6.0's `dft_stac_fetch(tile_size=)` (drift#36) into `fp_lulc` as an opt-in
per-area knob, then benchmark speedup vs parity vs accuracy before adopting it broadly.
Method stays in `drift`; this repo only exposes the knob and gathers the evidence.

## Phase 1: Integrate as opt-in
- [x] Update `flooded` / `drift` to latest; confirm `flooded` 0.3.2 unchanged, `drift` 0.4.0 -> 0.6.0.
- [x] Pass `tile_size = cfg$tile_size` at both `dft_stac_fetch` sites in `03_lulc_classify.R`
      (whole floodplain + per-sub-basin). Absent from `area.yml` => NULL => unchanged path.
- [x] Document the optional `tile_size:` key in `fp_read_config`; bump drift floor to >= 0.6.0
      and refresh the drift#36 gotcha note in CLAUDE.md.
- [x] Establish evidence structure: `research/` (durable memo) + `scripts/floodplain_lcc/logs/`
      (committed benchmark logs); leave `data/logs/` for gitignored bulk output.
- [x] Plan-review hardening: `fp_lulc` asserts `drift >= 0.6.0` (fail loud — the unconditional
      `tile_size` arg breaks EVERY area on older drift, and `update_packages` defaults FALSE);
      `FP_TILE_SIZE` env override in `fp_read_config` (revert-proof fixture tiling); packages.R
      floor comment bumped.

## Phase 2: Benchmark (the SRED experiment)

Cache hygiene (both blockers from plan review): drift's cache is one shared dir
(`cache_dir = NULL` => `user_cache_dir("drift")`). **Never delete it** — that would destroy
every published group's `.nc` cache. Tiled (`.tif`) and untiled (`.nc`) key distinctly and
never collide, so re-download for timing uses `force = TRUE` on a direct `dft_stac_fetch`
call, not a cache wipe. Tile the fixture via the `FP_TILE_SIZE` env var, never by editing
`config/neexdzii/area.yml`.

- [x] **Prereq — AOIs.** Used existing outputs: neexdzii for parity/accuracy; reused the existing
      **FRAN** 883 km² floodplain for the speedup fetch (no PCEA steps 1–2 needed — the speedup is
      a pure `dft_stac_fetch` question, so any existing large corridor serves).
- [x] **Parity** — neexdzii step 3 untiled (943.13 ha, reproduces fixture) vs tiled via
      `FP_TILE_SIZE=5000` (941.25 ha). Δ **−1.88 ha** — over the strict ~1 ha gate, but sieve
      quantization of ~a dozen edge pixels, not a modelling error.
- [x] **Accuracy** — neexdzii classified rasters tiled vs untiled: **≥ 99.999%** pixel agreement
      (12–16 px/1.76M), coverage within 0.002%, **no seam band**. Mosaic is faithful.
- [x] **Speedup** — direct `dft_stac_fetch` timing on FRAN, `force=TRUE`, isolated cache:
      untiled 177 s vs tiled 20000 m **0.79×** / 10000 m **0.31×**. Slower at every size. neexdzii
      full step-3 was 6.3× slower. **FAILS.**
- [x] Wrote measurements to `logs/20260711_lulc_tile-benchmark_{neexdzii,fran}.md`.

## Phase 3: Decide + document
- [x] Populated the `research/` memo Results + Decision from the logs.
- [x] **Decision: DO NOT adopt.** Speedup is refuted (tiling slower at every size, every AOI) —
      floodplain corridors tile badly (thin diagonal: coarse tiles blanket the bbox, fine tiles
      explode round-trips; no sweet spot). No group sets `tile_size:`; all stay on the untiled
      default. Accuracy passed, so nothing is broken — it is simply not faster.
- [x] Keep the opt-in wired (default off, harmless). The real bbox-download fix is in-cube
      (drift#36 `filter_geom`), blocked upstream by gdalcubes#110 — tracked there, not here.

## Validation
- [x] neexdzii untiled reproduces 943.13 ha exactly; tiled Δ −1.88 ha (sieve-quantized, over the
      strict gate) — moot for adoption since speedup failed first.
- [x] Accuracy floor met (≥ 99.999%, no seam band) on neexdzii. The whole-WSG-corridor accuracy
      test became moot: speedup failed decisively on FRAN (geometry-robust), so no group adopts
      regardless of corridor accuracy.
- [x] Shared drift cache never touched — benchmarking used isolated/`FP_TILE_SIZE` paths, `force`
      not wipe. Published caches intact.
- [x] Scripts parse; PWF checkboxes match landed work.
- [ ] `/planning-archive` on completion (after this commit closes #8).

## Out of scope
- The new-area configs (MCGR, BOWR / Peace PCEA, PARS) landed alongside under #3 — they
  provide the large whole-WSG floodplains this benchmark measures on, but adding areas is
  not this issue's concern.
- PINE — blocked on a link/bcfishpass build (0 segments in fwapg); tracked in `peace.yml`.
