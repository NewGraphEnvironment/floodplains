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

- [ ] **Prereq — AOIs exist.** neexdzii outputs are present; generate PCEA (and PARS) steps 1–2
      first (`run_area.R <wsg> 1,2`) so `floodplain.gpkg`/`subbasins.gpkg` exist. This is
      long-running and is NOT part of the fetch timing.
- [ ] **Parity (go/no-go anchor)** — run `neexdzii` step 3 untiled, then tiled via
      `FP_TILE_SIZE=<m> Rscript scripts/run_area.R neexdzii 3`. Pass = tiled `co_ff04` tree-loss
      equals untiled within **one patch-sieve unit (~1 ha)** — the tolerance is patch-quantized,
      NOT the 0.004% VCA figure: post-sieve (`patch_min_m2 = 10000`) a single seam pixel near a
      1 ha patch boundary can add/drop a whole patch. Untiled must still reproduce 943.13 ha.
- [ ] **Accuracy (the real seam test)** — on a **whole-WSG corridor** (PCEA — the adoption
      target, many interior `terra::merge()` seams; neexdzii is a compact reach and under-tests
      seams), compare classified rasters (pre-sieve) tiled-mosaic vs untiled+clip **inside the
      polygon**. Pass = **≥ 99.9% pixel agreement and no systematic seam band** (disagreement
      not aligned to tile edges). This is the metric that actually rules out the mosaic risk.
- [ ] **Speedup** — direct-time `dft_stac_fetch` untiled vs `tile_size` 5000 / 10000 m on
      PCEA's floodplain, `force = TRUE` each, no cache wipe; record wall-clock ratio.
- [ ] Write measurements to `scripts/floodplain_lcc/logs/20260711_lulc_tile-benchmark_<wsg>.md`.

## Phase 3: Decide + document
- [ ] Populate the `research/` memo Results + Decision from the logs.
- [ ] Adopt only if **all three** hold: parity within ~1 ha, accuracy ≥ 99.9% with no seam band,
      speedup ≥ 2×. Set `tile_size:` in the **benchmarked** large group(s) first (PCEA/PARS).
- [ ] Extend to same-geometry whole-WSG corridors (MCGR, BOWR) **only** with the generalization
      stated (seams are corridor-geometry-dependent), and per-group `verify classified coverage
      ≈ floodplain area` before trusting numbers. Fixture + published groups stay on default.
- [ ] If accuracy shows seams or parity fails: keep opt-in off, record why in the memo.

## Validation
- [ ] neexdzii untiled reproduces 943.13 ha AND tiled passes the ~1 ha parity gate before any
      group adopts `tile_size`.
- [ ] Accuracy floor (≥ 99.9%, no seam band) met on the whole-WSG corridor, not only the reach.
- [ ] Shared drift cache never deleted during benchmarking (published caches intact).
- [ ] `/code-check` clean on each commit; PWF checkboxes match landed work.
- [ ] `/planning-archive` on completion.

## Out of scope
- The new-area configs (MCGR, BOWR / Peace PCEA, PARS) landed alongside under #3 — they
  provide the large whole-WSG floodplains this benchmark measures on, but adding areas is
  not this issue's concern.
- PINE — blocked on a link/bcfishpass build (0 segments in fwapg); tracked in `peace.yml`.
