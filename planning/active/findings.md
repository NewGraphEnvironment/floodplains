# Findings — Config-driven disturbance attribution (#19)

## Issue context

Generalize `fire_tag.R` (one-off, single hardcoded layer) into a config-driven, layer-agnostic
disturbance-attribution step. Any polygon layer with a temporal field, declared as config, tags each
change patch per-source, windowed to the change interval. Additive; residual = noise floor.

## Plan-agent design review — key points

- **Output = columns on the transition layer** (not a separate layer). Verified non-breaking:
  `05_prioritization_score.R:96-109` reads the transition layer then `st_drop_geometry()` and selects
  columns by name; `04_lulc_zones.R` doesn't read it; no `.Rmd` references disturbance columns.
- **Parity is achievable in-memory:** `03:138` recomputes `area_ha` on `trans_polys`, then `:140`
  writes it — the in-memory object carries the same `area_ha` that standalone `fire_tag.R` re-reads.
  Tag between `:138` and `:140`.
- **BLOCKER — server-side bbox prefilter:** `fire_tag.R:38-42` pulls all province perimeters (fine for
  fire, hundreds of polys) but the province-wide cutblock layer would OOM. The generic SQL must push
  `ST_Intersects(geom, ST_MakeEnvelope(<st_bbox(patches) in source srid>))` into the WHERE. This is
  what lets one routine handle both a small perimeter layer and a huge harvest layer.
- **PARITY RISK — in-memory vs re-read:** `fire_tag.R:32` tags the round-tripped + `st_make_valid()`'d
  gpkg geometry; the wired path tags in-memory `trans_polys` (not made-valid). `in_fire` from
  `st_intersects` could flip a hairline boundary case. Mitigate: `st_make_valid()` both sides in the
  routine; gate the WRAPPER (re-read) path exactly; allow ±0.5 ha on the WIRED path.
- **GAP — fp_lulc has no DB conn:** open one only when `cfg$disturbance` is set (`on.exit` disconnect)
  so offline step-3 runs are unaffected.
- **GAP — change interval hardcoded** at `03:45` (`years`) and `03:82` (`from/to`): hoist to
  `cfg$change_interval` so the transition window and the attribution window share one value.
- **CRS/patch_id:** transform each source to `st_crs(patches)` (UTM), not assume 4326; dominant-overlap
  join keys on `patch_id` (must be unique per exploded patch).
- **Config precedent:** `config/regions/*.yml` = shared province-wide config → `config/disturbance.yml`.

## Data layers
- Fire (loaded): `whse_land_and_natural_resource.prot_historical_fire_polys_sp`, `fire_year`.
- Harvest (NOT loaded — bc2pg it): `whse_forest_vegetation.veg_consolidated_cut_blocks_sp` (bcdata
  record `b1b647a6-f271-42e0-9cd0-89ec24bce9f7`), year col `HARVEST_START_YEAR_CALENDAR`. Huge
  province-wide layer → load filtered `>= 2017`.
- Pest (deferred): `whse_forest_vegetation.pest_infestation_poly`, `capture_year`, insects + disease.

## Run results

**Phase 1 parity (fire-only, wrapper re-read path):** exact — BULK 103.2 ha, MORR-co 27.1, MORR-ch 29.4.

**Phase 2 parity (fire, wired in-pipeline):** BULK 103.22 vs 103.2, MORR-co 27.07 vs 27.1 (both ±0.5).
Transition layers now carry `in_fire`/`fire_year`/`fire_number` in-pipeline.

**Phase 3 multi-source (fire + harvest):** harvest loaded (121,836 cutblocks, 2017–2026):

| area | total loss | fire | harvest | residual |
|---|---|---|---|---|
| BULK co_ff04 | 2073.3 ha | 103.2 (5%) | 739.0 (36%) | 1286.3 (62%) |
| MORR co_ff04 | 433.8 ha | 27.1 (6%) | 125.1 (29%) | 281.6 (65%) |
| MORR ch_ff06 | 482.4 ha | 29.4 (6%) | 149.5 (31%) | 303.5 (63%) |

Harvest explains ~30–36% of floodplain tree loss that was previously in the "95% noise" bucket. Fire
+ harvest together ~35–41%; residual (true conversion + classification noise) ~62–65%. Per-source %
sums exceed 100% by ~3% = patches both burned AND logged (salvage) — additive attribution working.
The residual is still large: much of Trees→Rangeland is io-lulc noise, plus real Trees→Built/Crops/
Water conversion not captured by fire/harvest.
