# Task: Write the item key (wsg, species, scenario) into published gpkg layers (#30)

Published gpkg layers carry no identifier tying a row back to its source, so downstream consumers
(rtj QGIS projects, the STAC publish layer) cannot merge multiple areas into one gpkg and separate
them by attribute — forcing per-WSG layer renames or `ogr2ogr -sql` injection at merge time.

**Design principle:** the same key must exist as a STAC *property* (to select items) and as a gpkg
*column* (to separate rows after merge). Today they're asymmetric — the item id is `morr_ch_ff06`
but the rows carry none of it. So write the **full item key** (`wsg`, `species`, `scenario`), not
`wsg` alone — otherwise MORR-coho and MORR-chinook are indistinguishable after merge.

**Layer names stay producer-keyed** (`classified_ch_ff06_2017`) — that's what lets two species
coexist in one gpkg via clean per-layer replace (#23). Flattening to generic layers happens
downstream at merge time; the columns are what make it possible.

**Scope:** both published gpkgs — `floodplain_landcover.gpkg` (classified + transition) and
`floodplain.gpkg` (the ff02/04/06 delineations, whose layer names are identical across all 16 areas).
`subbasins.gpkg` is not published → out of scope.

## Phase 1 — Write the item key at generation time (02 + 03)
- [x] `03_lulc_classify.R`: set `wsg`/`species`/`scenario` on `polys` before the classified
      `st_write` (per-year loop) and on `trans_polys` before the transition `st_write` (after the
      disturbance tagging).
- [x] `02_floodplain_model.R`: same three columns on `valleys_poly` before the scenario-layer
      `st_write`, using `sc$scenario_id`.
- [x] Verify: `run_area.R morr 2,3` off cached rasters; every layer in both gpkgs carries
      `wsg="MORR"` + correct `species`/`scenario`.
- [x] Assert headline numbers unchanged (MORR co_ff04: 411.1 km², 433.8 ha).

## Phase 2 — Backfill the 16 existing areas
- [x] `scripts/floodplain_lcc/gpkg_backfill-wsg.R <area>` — both gpkgs, add missing key columns,
      idempotent, values from `config/<area>/area.yml` + layer name.
- [x] Prove in-place layer replace is safe on a **copy** first; else temp-gpkg-and-swap.
- [x] Run over all 16 areas.
- [x] Verify: every layer, both gpkgs, all 16 areas — correct non-NA keys, **feature counts
      unchanged**.

## Phase 3 — KISP (Kispiox) chinook: new area, born with the keys
- [x] `config/kisp/area.yml` (whole WSG, `species: ch`, `schema: kisp`, `primary_scenario: ch_ff04`)
      + `flood_scenarios.csv` with the `ch_*` rows.
- [x] Add `KISP` to a region file for the stac wsg→region mapping. **Check first:** `skeena.yml`
      preference is `[co]` and could resolve KISP to coho — if so, give KISP its own region file
      (`region: skeena`, `species: [ch]`).
- [x] Run `run_area.R kisp 1,2,3` (new AOI ⇒ real ~30 min STAC fetch; `caffeinate -s`).
- [x] Verify KISP carries the keys **natively** (no backfill) + classified coverage ≈ floodplain area.

## Phase 4 — stac smoke test + docs
- [x] Run the stac smoke test (`WSG=kisp`) — validates staging/metrics/registration with the
      new columns AND a never-before-seen WSG. Any stac-side change it surfaces is filed there.
- [x] README + CLAUDE.md: the item-key column contract + the backfill utility.
- [x] Hand off republish (16 → 17 items) to `stac_floodplains_bc#5`.

## Validation
- [x] Newly generated layers carry all three keys; MORR headline numbers unchanged
- [x] All 16 backfilled areas verified (keys correct, feature counts unchanged)
- [x] KISP keyed natively end-to-end; coverage check passes
- [x] stac smoke test green against KISP (or failure understood + filed)
- [x] `/code-check` clean per phase; PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
