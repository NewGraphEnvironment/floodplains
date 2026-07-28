# floodplains

Reusable floodplain delineation + land-cover-change detection across British Columbia watershed
groups. Centralizes a workflow first built in
[`restoration_wedzin_kwa_2024`](https://github.com/NewGraphEnvironment/restoration_wedzin_kwa_2024)
(Neexdzii Kwa) so it runs per-area, for any group, from one codebase.

## What it does

For an area (a watershed group, optionally subset to a reach), the pipeline:

1. **Network** — extracts the species-accessible stream network (order ≥ 3) via
   [`link`](https://github.com/NewGraphEnvironment/link). Species is config-driven (coho, chinook,
   bull trout).
2. **Floodplain** — delineates the modelled floodplain with the Valley Confinement Algorithm via
   [`flooded`](https://github.com/NewGraphEnvironment/flooded), on the national MRDEM-30 DEM.
3. **Land-cover change** — classifies Impact Observatory 10 m LULC (Sentinel-2) for 2017/2020/2023
   and computes floodplain transitions (tree loss, agricultural expansion) via
   [`drift`](https://github.com/NewGraphEnvironment/drift), then **attributes** each change patch to
   its likely cause (fire, harvest) from config-driven overlay layers.

The **method lives in the packages** (`link`, `flooded`, `drift`, `fresh`); this repo is the thin
**driver + config + provenance** layer that runs them per area.

## Design

- **One codebase, config per area.** Code is single-source in `scripts/`; per-area bits (watershed
  group, species, subset reach, flood scenarios, sub-basin break points) live in `config/<area>/`.
  Adding an area = adding `config/<area>/`, no code change.
- **Multiple species coexist per area.** Outputs are keyed by species (`streams_co3`/`streams_ch3`,
  `co_ff04`/`ch_ff06`), so e.g. MORR carries both coho and chinook in one `data/morr/` without
  either overwriting the other. Run a non-default species with `FP_SPECIES=…`.
- **Regions batch a set of groups.** `config/regions/<region>.yml` runs many WSGs with a species
  preference: `fraser` (chinook), `peace` (bull trout), `skeena` (coho).
- **Disturbance attribution is layer-agnostic.** `config/disturbance.yml` lists overlay layers
  (fire, harvest) that tag each change patch; the residual (matches none) is the
  classification-noise floor. Adding a source is config-only.
- **Parity fixture.** `config/neexdzii/` (BULK, subset upstream of the confluence) must reproduce
  the known-good numbers — coho-3 network **678.2 km**, floodplain `co_ff04` **171.0 km²**, tree
  loss **943.13 ha** — before any change is trusted.
- **Outputs** are per-area under `data/<area>/` (gitignored); published outputs live in the
  `stac_floodplains_bc` STAC collection.

## Layout

```
floodplains/
├── scripts/
│   ├── run_area.R              # runner: run_area <area> [steps]  (steps 1,2,3)
│   ├── run_region.R            # batch a region of WSGs (config/regions/<region>.yml)
│   └── floodplain_lcc/
│       ├── 01_network_extract.R   # fp_network(cfg)
│       ├── 02_floodplain_model.R  # fp_floodplain(cfg)
│       ├── 03_lulc_classify.R     # fp_lulc(cfg)  (classify + transition + disturbance tag)
│       └── fp_disturbance.R       # fp_disturbance_tag() — config-driven attribution
├── config/
│   ├── <area>/                 # area.yml + flood_scenarios.csv (+ optional break_points.csv)
│   ├── regions/<region>.yml    # a named set of WSGs + species preference
│   └── disturbance.yml          # shared overlay sources (fire, harvest)
├── data/<area>/                # outputs (gitignored)
└── planning/                   # planning-with-files (PWF)
```

## Status

The pipeline (steps 1–3) is generalized and config-driven; `run_area.R` / `run_region.R` work;
Neexdzii parity holds exactly.

- **16 watershed groups modelled** across three regions — Fraser (chinook: LCHL, LSAL, WILL, TABR,
  UFRA, NECR, MORK, FRAN — 3,366 km² floodplain, 15,022 ha gross tree loss 2017→2023), Peace (bull
  trout: PCEA, PARS, PINE), Skeena (coho: BULK, MORR) — plus the `neexdzii` parity fixture.
- **Multiple species per area** (MORR carries coho + chinook side by side).
- **Disturbance attribution** wired: fire + harvest overlays tag every change patch. Result: roughly
  a third of floodplain tree loss is attributable **cutblocks** (BULK: fire 5% / harvest 36% /
  residual 62%) — previously buried in a "conversion/noise" bucket.
- **Published**: watershed groups staged to the `stac_floodplains_bc` STAC collection
  (`images.a11s.one`).

Not yet built: zone-stratified LULC and sub-basin prioritization steps; pest/forest-health as a
disturbance source; patch-level field QA of the classification.

## Prerequisites (when running)

- Local `fwapg` PostgreSQL (standard libpq env vars) — steps 01/02 and disturbance attribution
- `link` ≥ 0.44.0, `flooded`, `drift` ≥ 0.8.0, `fresh`, `terra` ≥ 1.8-10 — see `scripts/packages.R`
- Internet for the national MRDEM-30 DEM (`flooded::fl_dem_aoi()`) and Microsoft Planetary Computer
  STAC (LULC imagery)
- Disturbance overlay layers loaded into `fwapg` via `bcdata bc2pg` (fire is standard; harvest =
  consolidated cutblocks filtered `HARVEST_START_YEAR_CALENDAR >= 2017`)

## Roadmap

- [ ] Add zone-stratified LULC + sub-basin prioritization steps
- [ ] Add pest/forest-health as a disturbance source (config contract already supports it)
- [ ] Patch-level (exploded) classified output + field accuracy assessment (confusion matrix)
- [ ] Per-area reporting consumes published outputs instead of re-modelling
