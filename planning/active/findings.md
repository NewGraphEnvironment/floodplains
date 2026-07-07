# Findings — Generalize pipeline to AOI-driven, prove Neexdzii parity, run MORR (#1)

## Exploration (2026-07-06)

### Current state of the scripts
- `scripts/floodplain_lcc/01–05` are verbatim Neexdzii (rwk) originals. Per-area identity is
  hardcoded and **duplicated**: `blk = 360873822` / `drm_confluence = 166030.4` in `01`
  (L37–38) and again in `05` (L120–121); `aoi_wsg = "BULK"`, `schema = "neexdzii"`,
  `min_order = 3` in `01` (L44–45, L39).
- All outputs currently root at `here::here("data", "lulc")` — not area-scoped.
- `02` reads `break_points.csv` and `flood_scenarios.csv` from `data/lulc/`, but the canonical
  copies now live in `config/<area>/`.
- **`index.Rmd` is missing from this repo**, yet `01` (L146), `02` (L81), `03` (L50/137/146)
  all call `rmarkdown::yaml_front_matter(here::here("index.Rmd"))$params` for
  `update_gis`/`path_gis` — those calls error today. QGIS-copy is being removed from the
  pipeline (issue step 4 does the copy manually).
- `run_area.R` is a skeleton: parses `<area> [steps]`, reads `area.yml`, prints, then `stop()`s.

### VCA params already externalized (good)
- `02` reads `flood_factor`, `slope_threshold`, `max_width`, `cost_threshold`, `size_threshold`,
  `hole_threshold` per-row from `flood_scenarios.csv` (L123–135) — not hardcoded.
- `flood_scenarios.csv` and `break_points.csv` are byte-identical between `neexdzii` and `morr`
  (morr's are copied templates — its `break_points.csv` needs real MORR points in Phase 3).

### The subset branch (key generalization in 01)
- Neexdzii: `subset` present → `01` delineates AOI via `fresh::frs_watershed_at_measure(conn,
  blk, drm_confluence)` (L86) then spatially filters streams to that AOI (L113–114).
- MORR: `area.yml` has `subset: null` → whole WSG, so `fp_network` must skip the delineation +
  filter and export the whole WSG network.

### Package versions / method
- `link` 0.44.2 locally (DESCRIPTION) — satisfies ≥0.44.0 (access-segmentation fix, link#223/#228).
- `01` deliberately uses `lnk_config("default")` (subsurfaceflow OFF, "NewGraph methodology"),
  not `"bcfishpass"` — this is a method choice, kept as a constant, not area config.
- `03` method constants to keep: `years = c(2017, 2020, 2023)`, `patch_min_m2 = 10000` (1.0 ha
  sieve), `ag_classes = c("Crops","Rangeland","Bare Ground")`, `zone_col = "name_basin"`.

### Parity provenance (known-good targets)
From rwk `planning/archive/2026-07-issue-152-link044-network-verify/`:
- coho order-3+ network **678.2 km** (1936 segments, 106 BLKs). Pre-link accessible network was
  733.9 km; the switch to `link default` config dropped it to 678.2 km.
- floodplain `co_ff04` **171.0 km²**.
- tree loss **943.13 ha**.
- link 0.44.x reproduced a byte-identical network + identical downstream numbers, only ~0.004%
  VCA run-to-run raster noise.

### Runner reference
- `link/data-raw/study_area_run.sh` — model the multi-area loop on its pattern: expand areas →
  `for w in bucket; do Rscript driver.R "$w" "$CONFIG" || echo "[WARN] ... (continuing)"; done`,
  per-item soft-fail, timestamped per-step logs, pre-flight gate.

## Issue context

Full issue #1 body:

> ## Context
> The `scripts/floodplain_lcc/01-05` are the verbatim Neexdzii (rwk) originals — coupled to that
> project's paths/params (e.g. `01` hardcodes `blk = 360873822`, `drm_confluence = 166030.4`,
> `schema = "neexdzii"`; scripts read `here::here("data","lulc")` and `index.Rmd` params). This
> issue lifts the per-area bits into `config/<area>/`, wires a runner, proves the generalization
> is faithful against Neexdzii, then runs the first new area — **MORR (Morice watershed group)** —
> to produce a coho-3 floodplain + land cover change detection. Method stays in the packages
> (`link`/`flooded`/`drift`); we only generalize the driver.
>
> ## Scope (staged — parity before new area)
> ### 1. Generalize the pipeline to config-driven
> - Lift per-area params out of `01-05` into `config/<area>/area.yml` + `flood_scenarios.csv` +
>   `break_points.csv` (watershed group, subset reach, min_order, species, schema, scenarios,
>   break points).
> - Outputs write to `data/<area>/` (not a shared `data/lulc/`).
> - Build `scripts/run_area.R` into a working runner: `Rscript scripts/run_area.R <area> [steps]`
>   (default steps 1,2,3 = network, floodplain, lulc). Model the multi-area loop on `link`'s
>   `data-raw/study_area_run.sh` pattern.
> ### 2. Prove Neexdzii parity (regression fixture)
> - Run `run_area.R neexdzii` end-to-end against local `fwapg` + `link` >= 0.44.0.
> - Verify it reproduces: coho-3 network 678.2 km, floodplain co_ff04 171.0 km², floodplain tree
>   loss 943 ha (allow VCA rasterization run-to-run noise ~0.004%). If it does not match, the
>   generalization is wrong — fix before proceeding.
> ### 3. Run MORR (first new area)
> - Resolve the open question in `config/morr/area.yml`: does MORR run as the **whole** watershed
>   group, or subset to a reach? Default: whole WSG.
> - Review/replace the MORR `flood_scenarios.csv` and `break_points.csv` (currently copied from
>   Neexdzii as templates).
> - Run `run_area.R morr` steps 1-3: coho-3 accessible network -> VCA floodplain (MRDEM-30) -> IO
>   10 m LULC classify + transition (tree loss / ag expansion).
> - Record MORR headline numbers (floodplain extent, tree loss, per-sub-basin).
> ### 4. Land MORR outputs in GIS (local, interim)
> - Copy MORR gpkgs into the **rwk QGIS project under a `morr/` subdirectory** — **local only, do
>   NOT Mergin-sync** into the shared rwk field project yet.
>
> ## Deferred (separate issue)
> - Cloud storage: push outputs to S3 as a `stac_floodplains_bc` STAC collection (COGs + gpkg),
>   served via titiler; reports then pull pinned outputs instead of re-modelling.
>
> ## Prerequisites
> Local `fwapg` (libpq env vars); `link` >= 0.44.0, `flooded`, `drift`, `fresh`; internet for
> national MRDEM-30 (`flooded::fl_dem_aoi()`) + Microsoft Planetary Computer STAC.

## MORR headline results (2026-07-06, whole WSG, coho order-3+)

- Network: **1295.6 km** (4877 segments, orders 3-8, 412 waterbodies).
- Floodplain extent (VCA, MRDEM-30): co_ff02 **379.0 km²** · **co_ff04 411.1 km²** (functional) ·
  co_ff06 **432.4 km²**.
- Single sub-basin ("Morice") = whole WSG; `lulc_summary.rds` has 22 rows (class × year).

### MORR LULC — CORRECTED after cache-collision fix (2026-07-06, full coverage)

After `dft_cache_clear(source="io-lulc")` + re-run of `run_area.R morr 3`, the classification now
covers the full floodplain (42,097 ha classified/yr vs the poisoned 924 ha; new classified raster
extent matches the MORR fp bbox). Corrected co_ff04 land-cover change 2017→2023:
- **Tree loss 433.8 ha** (2727 change patches, 1.06% of floodplain) — was the bogus 22.0 ha.
- Tree gain 684.5 ha → **net tree +250.7 ha** (slight greening). Ag expansion 411.2 ha.
- Independent cross-check: classified Trees 19,790 ha (2017) → 20,065 ha (2023), 47% of floodplain.
- Transitions read as real Morice floodplain dynamics (Rangeland↔Trees succession 531/352 ha,
  Bare Ground→Trees regrowth 85 ha, Trees→Water channel migration 61 ha) — NOT the Bulkley
  agricultural signature that the poisoned cache produced.
- No separate large-AOI problem: the full 10 m fetch over 84×87 km succeeded (8745×8462 cells).

### ⚠️ (RESOLVED) MORR LULC was INVALID — drift cache-key collision (caught 2026-07-06)

The reported tree loss (22.0 ha) and the entire transition matrix are an **artifact of incomplete
land-cover classification**, NOT a real "MORR floodplain barely changed" finding:

- `dft_stac_fetch` (step 3) classified only **~1,199 ha ≈ 3% of the 41,113 ha co_ff04 floodplain**.
  The classified cells form a single **5.9 × 10.2 km patch** in the lower Morice near the Bulkley
  confluence; the floodplain spans **84.6 × 87.4 km**. ~97% of the floodplain is unclassified (NA).
- So the 22 ha tree loss (and the agriculture-dominated transitions: Crops→Rangeland, Rangeland→
  Built, etc.) reflect only that one small settled pocket — unrepresentative of the whole floodplain.
- **Cross-check:** the per-sub-basin summary totals only 924.63 ha/yr classified (Trees 564 ha =
  61%), not the ~25,000 ha of Trees a fully-classified 41,113 ha floodplain would show.
- **Root cause: `drift::dft_stac_fetch` CACHE-KEY COLLISION** (NOT mosaicking — earlier guess was
  wrong). The cache file is `file.path(cache_source_dir, paste0(yr, ".nc"))` (dft_stac_fetch.R:103) —
  keyed only by **source + year, no AOI**. Neexdzii ran first (Phase 2) and populated
  `~/Library/Caches/drift/io-lulc/{2017,2020,2023}.nc` with the **Neexdzii** extent. MORR ran second
  (Phase 3); with `force=FALSE` (default) `dft_stac_fetch` found those files and returned the
  **Neexdzii** rasters, masked to the MORR floodplain. Only the ~1,199 ha where the two overlap near
  the shared Bulkley/Morice confluence survived → the "3% coverage". Transitions were agricultural
  because it was literally Bulkley/Houston-valley data.
- **Proof:** cache `io-lulc/*.nc` extent = E 645443-696463 / N 6000758-6056578 ≈ Neexdzii fp bbox
  (645444-696461 / 6000762-6056573), NOT MORR fp bbox (566715-651331 / 5948369-6035818).
- **Secondary bug:** `force=TRUE` is also broken — it calls `gdalcubes::write_ncdf()` on the
  existing cache path, which errors "File already exists" (no overwrite). Can't override a stale
  cache without manually deleting the file.
- **Impact is scoped:** floodplain EXTENT (co_ff04 411.1 km², co_ff02 379.0, co_ff06 432.4; network
  1295.6 km) is from steps 1-2 (VCA), independent of the LULC cache — stands. Neexdzii parity
  unaffected (ran first, clean cache, matched 943.13 ha). Only MORR step-3 LULC is invalid.
- **Fix (drift):** put the AOI in the cache key (bbox/geometry hash) + make `force=TRUE` overwrite.
  Filed: **NewGraphEnvironment/drift#25** (draft in `planning/active/drift_issue_stac_cache.md`). **Immediate unblock (no drift fix needed):** clear
  the stale cache and re-run `run_area.R morr 3` — a per-AOI cache clear is a valid workaround.
- Phase 4 landcover copy stays on hold until MORR step 3 is re-run with correct coverage.

## Resolved decisions

- **MORR whole-WSG vs subset** — resolved: **whole WSG** (`subset: null`, issue default).
- **MORR break points** — resolved: **single outlet basin** (user choice). Real outlet point
  derived + verified (see progress.md); interior sub-basin delineation deferred to a later pass.
