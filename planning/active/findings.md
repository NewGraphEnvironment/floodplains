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
(to be filled during implementation)
