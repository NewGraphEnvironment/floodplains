# floodplains

Reusable floodplain delineation + land cover change detection across British Columbia
watershed groups. Centralizes a workflow first built in
[`restoration_wedzin_kwa_2024`](https://github.com/NewGraphEnvironment/restoration_wedzin_kwa_2024)
(Neexdzii Kwa) so it can be run over and over for new areas from one codebase.

## What it does

For a given area (a watershed group, optionally subset to a reach), the pipeline:

1. **Network** — extracts a coho-accessible stream network (order ≥ 3) via [`link`](https://github.com/NewGraphEnvironment/link).
2. **Floodplain** — delineates the modelled floodplain with the Valley Confinement Algorithm via [`flooded`](https://github.com/NewGraphEnvironment/flooded), on the national MRDEM-30 DEM.
3. **Land cover change** — classifies Impact Observatory 10 m LULC (Sentinel-2) for multiple years and computes transitions (tree loss, agricultural expansion) within the floodplain via [`drift`](https://github.com/NewGraphEnvironment/drift).

The **method lives in the packages** (`link`, `flooded`, `drift`); this repo is the thin
**driver + config + provenance** layer that runs them per area — the same split as
[`flooded`] (method) vs [`stac_dem_bc`] (catalog).

## Design

- **One codebase, config per area.** Code is single-source in `scripts/`; the per-area bits
  (watershed group, subset reach, flood scenarios, sub-basin break points, prioritization
  weights) live in `config/<area>/`. Mirrors `link`'s `data-raw/study_area_run.sh` multi-WSG
  runner pattern.
- **Areas are additive.** `config/neexdzii/` is the **parity fixture** — the generalized
  pipeline must reproduce the known-good Neexdzii numbers (coho-3 network 678.2 km, floodplain
  171.0 km², floodplain tree loss 943 ha) before any new area is trusted. `config/morr/`
  (Morice) is the first new area.
- **Outputs are per-area** under `data/<area>/` (gitignored). Cloud storage (an S3 STAC
  collection, `stac_floodplains_bc`) is a deferred follow-up — see Roadmap.

## Layout

```
floodplains/
├── scripts/
│   ├── packages.R              # dependency install/load (link, flooded, drift, ...)
│   ├── run_area.R              # top-level runner: run_area <area> [steps]
│   └── floodplain_lcc/         # 01-05 pipeline (copied from rwk; being generalized)
├── config/
│   ├── neexdzii/               # parity fixture (BULK, subset upstream of confluence)
│   │   ├── area.yml
│   │   ├── flood_scenarios.csv
│   │   └── break_points.csv
│   └── morr/                   # Morice watershed group (first new area)
│       └── ...
├── data/<area>/                # outputs (gitignored)
└── planning/                   # planning-with-files (PWF)
```

## Status

**Scaffold.** The `scripts/floodplain_lcc/01-05` are the verbatim Neexdzii originals; they are
not yet AOI-parameterized and `run_area.R` is a skeleton. Generalizing them, proving Neexdzii
parity, and running MORR is tracked in the first issue.

## Prerequisites (when running)

- Local `fwapg` PostgreSQL (standard libpq env vars) — steps 01/02
- `link` ≥ 0.44.0, `flooded`, `drift`, `fresh` (falls + parameter CSVs) — see `scripts/packages.R`
- Internet for the national MRDEM-30 DEM (`flooded::fl_dem_aoi()`) and Microsoft Planetary
  Computer STAC (LULC imagery)

## Roadmap

- [ ] Generalize `01-05` to config-driven; build `run_area.R`; prove Neexdzii parity; run MORR
- [ ] S3 storage + a `stac_floodplains_bc` STAC collection (COGs + gpkg), served via titiler
      (`drift::dft_map_interactive()` already supports this) — reports then pull pinned outputs
- [ ] Per-area reporting consumes outputs instead of re-modelling

[`flooded`]: https://github.com/NewGraphEnvironment/flooded
[`stac_dem_bc`]: https://github.com/NewGraphEnvironment/stac_dem_bc
