# floodplains

Reusable floodplain delineation + land-cover-change detection across British Columbia watershed
groups. Centralizes a workflow first built in
[`restoration_wedzin_kwa_2024`](https://github.com/NewGraphEnvironment/restoration_wedzin_kwa_2024)
(Neexdzii Kwa) so it runs per-area, for any group, from one codebase.

## What it does

For an area (a watershed group, optionally subset to a reach), the pipeline:

1. **Network** — extracts the species-**accessible** stream network (order ≥ 3) via
   [`link`](https://github.com/NewGraphEnvironment/link). Species is config-driven (coho, chinook,
   bull trout). See [What "accessible" means](#what-accessible-means) — it is a connectivity model,
   **not** modelled spawning or rearing habitat.
2. **Floodplain** — delineates the modelled floodplain with the Valley Confinement Algorithm via
   [`flooded`](https://github.com/NewGraphEnvironment/flooded), on the national MRDEM-30 DEM.
3. **Land-cover change** — classifies Impact Observatory 10 m LULC (Sentinel-2) for 2017/2020/2023
   and computes floodplain transitions (tree loss, agricultural expansion) via
   [`drift`](https://github.com/NewGraphEnvironment/drift), then **attributes** each change patch to
   its likely cause (fire, harvest) from config-driven overlay layers.

The **method lives in the packages** (`link`, `flooded`, `drift`, `fresh`); this repo is the thin
**driver + config + provenance** layer that runs them per area.

## Reading the outputs (experimental)

**This is a screening and exploration tool, not a validated change-detection product.** The
floodplain is a DEM-derived model; the land-cover change is a global 10 m product applied to BC
valley bottoms; **neither has been field-validated**. Treat the numbers as hypotheses that say
*where to look*, not as measurements of change on the ground. There is substantial QA still to do.

Known uncertainties, roughly in order of how much they could move a figure:

- **About two-thirds of detected floodplain "tree loss" is unattributed.** Our own disturbance
  attribution returns BULK **fire 5% / harvest 36% / residual 62%** and KOTL **3% / 33% / 64%**.
  That residual is *unexplained*, not merely "noise": it may be real removal we cannot source,
  drought or seasonal drying, water-level change, terrain shadow, or misclassification. Those have
  **not** been separated from one another.
- **"Tree loss" is a land-cover class transition, not confirmed forest removal.** What is measured
  is pixels leaving the tree class. Many patches are genuine removal; many are not.
- **Acquisition timing is unknown and unrecoverable from the source.** `io-lulc-annual-v02` items
  are one composite per MGRS zone per year (`09U-2023`, `10U-2023`) and carry **no acquisition
  date, no `created` and no `updated` property**. A wet year against a dry one — or a June against
  an August composite — could skew results substantially, and we can neither quantify that nor rule
  it out from anything we record.
- **Cross-group figures are not comparable yet.** With no treed-area denominator (#38), a group
  whose floodplain is 61–74% open water (the Columbia groups) cannot be set against a forested one
  on hectares of loss.
- **No patch-level field QA has been done** (#27). Nothing here has been checked against ground.
- **The floodplain is modelled too.** Valley Confinement Algorithm output on a 30 m national DEM,
  delineated against the *accessible* network (below) — not a mapped or surveyed floodplain, and
  **not** a flood-frequency product despite the `ff` scenario names.

What the outputs *are* good for: triage and exploration — finding where change concentrates inside
a group, comparing scenarios over the same ground, and generating candidates for field checking.
Everything is published openly so it can be interrogated. **Please do interrogate it**, and file
what you find.

## What "accessible" means

The network this repo delineates floodplain against is the **accessible** network: stream that is
connected to the ocean (or to the species' range) without an intervening natural barrier, subject
to a **per-species gradient ceiling**. It is a *connectivity* model. It is **not** the modelled
intrinsic spawning or rearing habitat, which bcfishpass also produces (`spawning_<sp>` /
`rearing_<sp>`) and which is far more restrictive because it additionally keys on modelled channel
size and narrower gradient bands.

The ceiling is **not one number** — it is per species, and it lives in link's config bundle at
`extdata/configs/bcfishpass/parameters_fresh.csv`, column `access_gradient_max`:

| species | `access_gradient_max` |
|---|---|
| CH, CM, **CO**, PK, SK | **0.15** |
| ST, WCT | 0.20 |
| **BT**, CT, DV, RB | **0.25** |

So a chinook or coho area is delineated against stream up to **15%** gradient; a bull trout area
(`kotl`, `larl`, `sloc`, `pars`, `pcea`, `pine`) up to **25%**. That difference is why bull trout
consistently shows more accessible km than chinook in the same group, and why coho and chinook
networks are *identical* wherever both are modelled — same 0.15 ceiling, same barrier set.

Barrier sources are the `break_order` list in that bundle's `config.yaml` (observations, gradient
barriers, falls, definite barriers, subsurface flow, habitat endpoints, crossings). The
`bcfishpass` bundle opts **subsurfaceflow ON** for parity with bcfishpass; the `default` bundle
leaves it off, which is why the two disagree by ~0.7% median province-wide.

**The gap between accessible and modelled habitat is large**, so the distinction is not academic.
Measured 2026-09-03 at order ≥ 3:

| WSG | species | accessible km | spawning km | rearing km | spawning as % of accessible |
|---|---|---|---|---|---|
| FRAN | ch | 2139 | 587 | 803 | **27%** |
| BOWR | ch | 1017 | 649 | 736 | 64% |
| LNTH | ch | 694 | 448 | 509 | 65% |
| KOTL | bt | 1921 | 921 | 1636 | 48% |
| PCEA | bt | 2194 | 888 | 1743 | 40% |

Floodplain extent here is therefore delineated against a network **1.5–3.6× longer** than the
modelled spawning network. Read the published areas as *"floodplain along stream this species can
reach"*, never as *"floodplain along spawning habitat"*.

**Which bundle produced a given network is recorded, not assumed.** `fresh.log.config_name` carries
it per watershed group, and step 1 resolves `link_config_name` from that log row into
`provenance.json` (#65). Today every WSG in `fresh` is `bcfishpass`
(`config_hash sha256:19e3a…`) and every WSG in `fresh_default` is `default`
(`sha256:3cfde…`).

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
  downstream with no change there. A region file carries **one** species preference, so a group of a
  different species needs its own region file (same `region:` label), not an entry in an existing one.
- **A region run reconciles area config; it does not regenerate it.** The region owns a fixed set of
  keys (species, `min_order`, `network_source`, `attribute_by`, …); the area owns everything else, so
  a second species' scenario rows, citations, `break_points.csv` and every comment survive.
  `flood_scenarios.csv` is created when absent and appended to when the resolved species has no rows
  — existing rows are never rewritten. **`DRY=1` writes nothing at all**: it prints the
  reconciliation it would perform. (It used to write configs before the dry gate, so the preview was
  as destructive as a real run.)
- **A floodplain can be attributed per watercourse.** Optional `attribute_by:` (a column of the
  stream network, e.g. `gnis_name` or `blue_line_key`) adds a `<scenario>_by_<column>` layer with
  one row per watercourse via `flooded::fl_valley_attribute()`, so a delineation answers "where is
  the floodplain of *this river*?" and not only "of this group's network". The delineation itself
  is never recomputed, so regrouping relabels without moving a boundary, and **rows overlap** where
  ground is genuinely shared at a confluence — on MORR that is 43.6% of the floodplain, so a hard
  partition would mis-assign nearly half of it. Absent ⇒ nothing runs and output is unchanged.
- **Every published layer carries the item key** — `wsg`, `species`, `scenario` — mirroring the STAC
  item id (`morr_ch_ff06`). The same key is a STAC *property* (to select items) and a gpkg *column*
  (to separate rows once merged), so many areas fetch-and-append into one gpkg and stay separable by
  attribute. Layer names stay producer-keyed (`classified_ch_ff06_2017`) because that is what lets
  two species coexist in one gpkg; flattening to generic layers happens downstream at merge time, so
  adding an area or species never touches a QGIS project. Pre-existing outputs are migrated with
  `scripts/floodplain_lcc/gpkg_backfill-wsg.R <area>` (idempotent).
- **Change patches can be attributed to watercourses.** The floodplain is exploded two ways that do
  not line up — per watercourse (overlapping) and per change patch (disjoint) — so a
  `patch_watercourse_<scenario>_<span>` table ships beside the patches with one row per
  (patch, watercourse) pair. It carries two fractions because only one is additive:
  `overlap_frac` (what share of the patch a watercourse covers) and `apportion_weight` (what share
  is credited to it, summing to 1). That lets a consumer ask for tree loss **inclusively** (all
  ground a river touches), **apportioned** (adds up to the basin total), or **exclusively** (ground
  no other watercourse claims) — rather than inheriting one silently and being wrong by 83%.
- **Disturbance attribution is layer-agnostic.** `config/disturbance.yml` lists overlay layers
  (fire, harvest) that tag each change patch; the residual (matches none) is the
  classification-noise floor. Adding a source is config-only.
- **Parity fixture.** `config/neexdzii/` (BULK, subset upstream of the confluence) must reproduce
  the known-good numbers — coho-3 network **673.5 km**, floodplain `co_ff04` **142.8 km²**, tree
  loss **770.0 ha** — before any change is trusted. Re-baselined 2026-09-01 under `flooded` 0.5.0.
  The previous contract (678.2 / 171.0 / 943.13) is **dead, not superseded**: it came from a
  bankfull regression fed hectares where Hall et al. specify km² and mm where they specify cm/yr.
  Record these as a fresh contract, never as a delta from the old ones.
- **Outputs** are per-area under `data/<area>/` (gitignored); published outputs live in the
  `stac-floodplains-bc` STAC collection. Note the id is **hyphenated** — `stac_floodplains_bc`
  with underscores is the *repository* name, and querying it returns a `NotFoundError` that reads
  like "not published" rather than "wrong name".

## Layout

```
floodplains/
├── scripts/
│   ├── run_area.R              # runner: run_area <area> [steps]  (steps 1,2,3)
│   ├── run_region.R            # batch a region of WSGs (config/regions/<region>.yml)
│   ├── fp_gpkg.R               # pins gpkg timestamps so a rebuild is byte-reproducible
│   └── floodplain_lcc/
│       ├── 01_network_extract.R   # fp_network(cfg)
│       ├── 02_floodplain_model.R  # fp_floodplain(cfg)
│       ├── 03_lulc_classify.R     # fp_lulc(cfg)  (classify + transition + disturbance tag)
│       ├── fp_disturbance.R       # fp_disturbance_tag() — config-driven attribution
│       ├── fp_region.R            # whole-WSG sub-basin + region/area config ownership
│       ├── fp_provenance.R        # provenance.json writer (what produced these outputs)
│       ├── gpkg_determinism-check.R   # guard: a full rebuild is byte-identical
│       ├── provenance-check.R         # guard: the inputs/run split, and no leaked credentials
│       └── region_config-check.R      # guard: a region run cannot destroy area config
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
- **Disturbance attribution** wired: fire + harvest overlays tag every change patch. **The largest
  bucket remains the one we cannot explain** — BULK returns fire 5% / harvest 36% / **residual
  62%**, KOTL 3% / 33% / **64%**. Harvest accounts for roughly a third where recent logging drives
  the change, which is a third that previously sat undifferentiated; the remaining two-thirds is
  still undifferentiated and is the main open question — see
  [Reading the outputs](#reading-the-outputs-experimental). Where harvest is *not* the driver the
  method says so rather than guessing: SLOC returns 99% unattributed against only 4.6 ha of
  2017–2023 cutblock inside its floodplain, consistent with Slocan valley-bottom harvest peaking in
  the 1980s.
- **Published**: **20 items live** in the `stac-floodplains-bc` STAC collection (`images.a11s.one`),
  keyed by `wsg`/`species`/`scenario`; the release is repo-owned and one-command. Adding the
  Columbia region moved the collection's spatial extent south from 52.71 N to **48.99 N**, so the
  catalogue now answers queries over the Kootenays.

Not yet built: zone-stratified LULC and sub-basin prioritization steps; pest/forest-health as a
third disturbance source (#35); patch-level field QA of the classification (#27); a treed-area
denominator so loss is comparable across groups whose floodplains differ in composition
(#38 — the Columbia groups are 61–74% open water). Per-area run provenance (#33) is **done**.

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

**Rebuilds are byte-reproducible.** GDAL stamps every GeoPackage with the wall-clock time of the
write, which would make each rebuild a new checksum regardless of content — churn where provenance
is wanted, across the 72% of the published bucket that is GeoPackage. The stamp is pinned to a
fixed epoch (`scripts/fp_gpkg.R`), so a full rebuild from identical inputs is byte-identical and
`file:checksum` downstream means what it says. `scripts/floodplain_lcc/gpkg_determinism-check.R`
asserts it. One stated limit: rewriting a single layer into an *existing* gpkg is not byte-stable
(SQLite records write history in its header), so the guarantee covers a clean rebuild, not every
rerun.

## Run provenance

Every run writes `data/<area>/provenance.json` recording **what produced the outputs**: the link
log row for the network (`config_hash`, `run_uid`, `link_sha`, the bcfp pin), the VCA parameters
and DEM geometry for the floodplain, and the resolved landcover source for the LULC. The publish
layer carries it into STAC item properties.

Each section splits into `inputs` and `run`. `inputs` is a function of the inputs and is
byte-stable across reruns — `inputs_hash` is one scalar over it, so "did anything that matters
change?" is a string comparison. `run` is the run event and is free to vary.

The landcover fingerprint is a **digest of the classified rasters**, not the STAC item ids. An
io-lulc item id is `<tile>-<year>` and the items carry no `created`/`updated`, so an in-place
reprocess upstream leaves every id identical — the ids name what was read, but only the raster
digest can fail when the upstream moves.

```bash
Rscript scripts/floodplain_lcc/provenance-check.R <area>   # no database needed
```

Forward-only: an area carries a block once it has been re-run. `run_region.R` treats a missing
`provenance.json` as cache-invalidating, so a resumable region run backfills as it goes.

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
