# Findings — Item key (wsg, species, scenario) in published gpkg layers (#30)

## Issue context

Published gpkg layers carry no reliable identifier, so downstream consumers can't merge areas and
separate them by attribute. Verified against current outputs:

- `classified_*` — schema is `class_name` **only**; no identifying attribute.
- `transition_*` — has `name_basin`, but values are inconsistent across areas (`"Morice"` in morr,
  `"pars"` in pars): a basin label, not a WSG code.
- `floodplain.gpkg` — **also a published asset**; layers `co_ff04`/`ch_ff04` are **identically named
  across all 16 areas** with only a `valley` column. Worst case: layer-name collision on merge with
  no attribute to separate. Brought into scope (user decision) — the issue text named only
  `floodplain_landcover.gpkg`.

## Design decision — full item key, not just wsg

The consumption chain is: **discover** (STAC property) → **fetch** (item-keyed assets) → **merge**
(one gpkg, many areas) → **project** (QGIS, attribute filter). The key must exist on *both* sides —
as a STAC property to select items, and as a gpkg column to separate rows after merge. Today they're
asymmetric: item id `morr_ch_ff06` vs rows carrying nothing.

`wsg` alone is insufficient: MORR publishes two items (coho `co_ff04`, chinook `ch_ff06`) with the
same `wsg`, overlapping geometry, different extents — indistinguishable after merge. So write
`wsg` + `species` + `scenario`. Precedent: `lulc_summary.rds` already carries `scenario_id` +
`flood_factor` as columns.

**Layer names stay producer-keyed.** Generic names inside a per-area gpkg would collide across
species and force read-modify-write on re-runs, undoing #23's clean per-layer replace. Flattening to
generic layers (`classified_2017` = all areas + species appended) belongs at merge time downstream.

## Verified facts

- `cfg$watershed_group` (uppercase FWA/link key) + `cfg$species` already on `cfg`; `scenario_id` /
  `sc$scenario_id` in scope at every write site — no new plumbing.
- **Additive downstream:** `stac_floodplains_bc/scripts/01_stage.R:83-84` reads metrics by column
  name; no schema/`ncol` assertions in its smoke test.
- Only two gpkgs are published (`05_stac_register.py:80,86`). `subbasins.gpkg` is not → out of scope.
- `transition_*_disturbance` (fire_tag.R wrapper) re-reads the transition layer → inherits the keys.
- stac's `wsg_region` roster is **derived from floodplains `config/regions/*.yml`**
  (`01_stage.R:41-56`) — a new WSG in a region file is visible downstream with **no stac code change**.
- **KISP (Kispiox River)** confirmed in FWA; chinook well modelled — 4,458 `access_ch` segments at
  order ≥ 3 (`fresh.streams_vw_bcfp`), vs 4,458 coho / 5,335 steelhead of 7,443 total.
- `neexdzii` has `watershed_group: BULK`, same as the `bulk` area (it's a BULK subset) — both carry
  `wsg = "BULK"`. Harmless: neexdzii is the parity fixture, not published to STAC.

## Backfill vs re-run

16 existing areas need the keys. Backfilling in place (seconds/area) beats re-running the pipeline
(hours, and needlessly re-derives numbers that must not change). Risk to prove first: reading a layer
from a gpkg and writing the same layer name back to the same file — verify on a copy before touching
real data.

## Run results
(to be filled during implementation)
