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
  preference: `fraser` (chinook), `peace` (bull trout), `skeena` (coho / `skeena_ch` chinook). The
  publish layer derives its WSG→region map from these files, so a group added here is visible
  downstream with no change there. A region file carries **one** species preference and
  `run_region.R` writes each group's `area.yml` from it — so a group of a different species needs
  its own region file (same `region:` label), not an entry in an existing one.
- **Every published layer carries the item key** — `wsg`, `species`, `scenario` — mirroring the STAC
  item id (`morr_ch_ff06`). The same key is a STAC *property* (to select items) and a gpkg *column*
  (to separate rows once merged), so many areas fetch-and-append into one gpkg and stay separable by
  attribute. Layer names stay producer-keyed (`classified_ch_ff06_2017`) because that is what lets
  two species coexist in one gpkg; flattening to generic layers happens downstream at merge time, so
  adding an area or species never touches a QGIS project. Pre-existing outputs are migrated with
  `scripts/floodplain_lcc/gpkg_backfill-wsg.R <area>` (idempotent).
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

- **19 watershed groups modelled** across four regions — Fraser (chinook: LCHL, LSAL, WILL, TABR,
  UFRA, NECR, MORK, FRAN, BOWR, MCGR), Peace (bull trout: PCEA, PARS, PINE), Skeena (coho: BULK,
  MORR; chinook: KISP), Columbia (bull trout: KOTL, LARL, SLOC) — plus the `neexdzii` parity
  fixture. Groups and items differ: MORR carries two species, so 19 groups publish as 20 items.
- **Multiple species per area** (MORR carries coho + chinook side by side).
- **Every published layer carries the item key** (`wsg`, `species`, `scenario`), so many areas merge
  into one gpkg and stay separable by attribute.
- **Disturbance attribution** wired: fire + harvest overlays tag every change patch. Where recent
  logging is the driver, roughly a third of floodplain tree loss is attributable to **cutblocks**
  (BULK: fire 5% / harvest 36% / residual 62%; KOTL tracks it closely at 3% / 33% / 64%) —
  previously buried in a "conversion/noise" bucket. Where it is not, the method says so: SLOC comes
  back 99% unattributed, and only 4.6 ha of 2017–2023 cutblock falls inside its floodplain, since
  Slocan valley-bottom harvest peaked in the 1980s.
- **Published**: **20 items live** in the `stac_floodplains_bc` STAC collection (`images.a11s.one`),
  keyed by `wsg`/`species`/`scenario`; the release is repo-owned and one-command. Adding the
  Columbia region moved the collection's spatial extent south from 52.71 N to **48.99 N**, so the
  catalogue now answers queries over the Kootenays.

Not yet built: zone-stratified LULC and sub-basin prioritization steps; pest/forest-health as a
third disturbance source (#35); patch-level field QA of the classification (#27); per-area run
provenance (#33); a treed-area denominator so loss is comparable across groups whose floodplains
differ in composition (#38 — the Columbia groups are 61–74% open water).

## Publishing

Modelling and publishing are separate repos, and the dependency points **one way**: the publish
layer ([`stac_floodplains_bc`](https://github.com/NewGraphEnvironment/stac_floodplains_bc)) reads
this repo's `data/` (`$FLOODPLAINS_DATA`); this repo knows nothing about it beyond the reminder a run
prints. After generating products:

```
cd ../stac_floodplains_bc
bash scripts/run_pipeline.sh        # rebuild data/stac from the new outputs
bash scripts/catalogue_release.sh   # validate -> sync -> register -> verify
```

Order matters — the release publishes whatever `run_pipeline.sh` last built, so releasing without
rebuilding ships a stale catalogue. Both are idempotent (the sync skips unchanged objects, the
register upserts), so re-running is safe. Removing or re-deriving a watershed's products is
registry-driven via that repo's `scripts/item_unregister.sh`. The whole lifecycle is repo-owned —
no server-side incantation.

`run_area.R` / `run_region.R` print this sequence when a run produced publishable outputs (steps 2
or 3); `FP_NO_PUBLISH_HINT=1` silences it.

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
