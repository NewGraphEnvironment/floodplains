# Task: Floodplains cross watershed group boundaries, so neighbouring items double-count (MORR: 4.61 km2 inside BULK) (#53, with #138)

## Problem

A watershed group's floodplain extends past the group boundary into its neighbour, so neighbouring
published items double-count the same ground.

Measured on MORR: `co_ff04` is 411.1 km2, of which **4.61 km2 lies inside BULK**. Both are live STAC
items, so the overlap is in published data.


Scope as decided 2026-10-18 (issue body, "Decided"): split at the group line and tag `in_wsg`; #138 adds `in_open_water`; one backfill; one PR closing #53, #138 and #60.

## Context

Floodplains cross watershed-group boundaries, so neighbouring published items double-count ground:
MORR 595 ha and DUNC 205 ha lie outside their own group. PCEA is the extreme case, with 41.7% outside,
because all three of Williston's FWA polygons enter it. Both issues were decided on 2026-10-18: tag,
don't cut. The delineation stays whole. Every floodplain layer is split along the group polygon, and
each piece carries `in_wsg`. Step 3 stops clipping change patches. The composition table gains `in_wsg`
and `in_open_water`. One backfill writes both columns to every published area with no VCA run and no
STAC fetch. One PR closes #53, #138 and #60, whose README totals become a union.

Decided in this session:
- **The open-water id column is `open_water_poly_id`.** It is aliased through the existing carry map,
  so the published `waterbody_poly_id` on wetland patches is untouched.
- **Patches are unclipped in every area.** In neexdzii, the only subset area, a piece outside every
  sub-basin has `name_basin = NA`. Its parity is restated as tree loss over patches that have a
  sub-basin: 773.4 ha, unchanged by construction. The outside share is reported beside it.

What exploration found, which shaped the phases:
- **The clip lives in drift.** `dft_transition_vectors(zones=)` assigns `patch_id` and only then runs
  `st_intersection(out, zones)` (drift 0.20.0). Calling it with no zones and reproducing the same
  intersection gives byte-identical inside pieces. The remainder (`st_difference`) is new. So the
  inside totals equal today's by construction, and the backfill can assert that.
- **`patch_id` is global** (#87), but the bridge keys on `name_basin¦patch_id`. A patch split by the
  line becomes two rows, so the key needs `in_wsg`.
- **Context entries take one `table`.** `.dst_query` emits `FROM <table>`. Open water spans
  `fwa_lakes_poly` + `fwa_manmade_waterbodies_poly`, which have identical schemas (checked).
- **`provenance-check.R` 7c asserts `outputs.transition_patches == nrow(layer)`.** Unclipping moves
  that count, so the backfill must edit `outputs` in place. It cannot go through `fp_prov_set()`:
  that function's JSON round trip moves `inputs_hash` (#126). The edit follows `fp_prov_restamp()`'s
  pattern.
- `attribute_tag.R` writes the `_by_` layer and the bridge too, so it needs the same split. Otherwise
  "the fix landed in one caller".
- The floodplain scenario layer is one MULTIPOLYGON today and becomes two rows. Step 3 must
  `st_union` it before the drift fetch, so the AOI stays one feature. The drift cache key hashes the
  AOI's WKB, so each area's next step 3 run misses the cache once.

## Phase 1: Split helpers + offline check
- [x] `scripts/floodplain_lcc/fp_wsg.R` with three helpers:
  - `fp_wsg_polygon(cfg, conn = NULL)`: a whole-WSG area reads `subbasins.gpkg` (one row, checked
    against `watershed_group`). A subset area reads `fp_wsg_subbasin()` from the DB.
  - `fp_wsg_split(x, wsg_poly)`: each row becomes `in_wsg` TRUE/FALSE pieces. Every column is kept,
    zero-area pieces are dropped, and polygons are extracted from GEOMETRYCOLLECTION.
  - `fp_zone_split(patches, zones, zone_col)`: drift's own intersection, plus the remainder with an
    NA zone.
- [x] `wsg_split-check.R` (offline, hand-built fixtures). Asserted, each with a must-fail arm:
  - pieces conserve each row's area;
  - inside pieces are identical to `st_intersection`;
  - a straddling patch keeps one `patch_id` across two rows;
  - a line-touch GEOMETRYCOLLECTION is reduced to polygons;
  - dropping the remainder fails conservation.

## Phase 2: Step 2 and attribute_tag.R split the floodplain layers
- [x] `02_floodplain_model.R`: split the `<scenario>` and `<scenario>_by_<key>` layers with
  `in_wsg`. The raster is unchanged, so the floodplain `outputs_hash` does not move.
- [x] `attribute_tag.R`: the same split on the `_by_` layer it writes.
- [x] Every reader of a scenario layer that expects one feature unions it first: 03's AOI, Pass 2,
  `fp_composition_build`, and the checks that read `floodplain.gpkg`.

## Phase 3: Step 3 stops clipping; one post-fetch path
- [x] Factor 03's post-fetch half into one function, `fp_lulc_vectors()`. It covers the classified
  layers, the transition patches, the tagging, the item key and the bridge. Step 3 and the backfill
  both call it.
- [x] Patches: `dft_transition_vectors()` with no zones, then `fp_zone_split` (name_basin), then
  `fp_wsg_split` (`in_wsg`).
- [x] Classified layers are split too.
- [x] Add `in_wsg` to `FP_PATCH_CORE`, so no carry can clobber it. Adjust `disturbance-check.R`'s
  "core = the non-`in_` columns" live assertion.
- [x] The bridge key gains `in_wsg`, in both 03 and `attribute_tag.R`.
- [x] `fire_tag.R` keeps `in_wsg` through a re-tag.

## Phase 4: `in_open_water` context overlay (#138)
- [x] `fp_disturbance_validate()`: a `context:` entry's `table` may be a list of tables sharing
  `geom_col` and the carry columns. A list given to `sources:` or `lookback:` is refused.
- [x] `.dst_query()` emits `UNION ALL` over the tables.
- [x] `fp_composition_build` records every table and each table's COMMENT.
- [x] `config/disturbance.yml`: add `open_water` over `fwa_lakes_poly` + `fwa_manmade_waterbodies_poly`,
  `carry: {waterbody_poly_id: open_water_poly_id}`, no size cut-off.
- [x] `disturbance-check.R` offline arms:
  - the multi-table SQL;
  - an empty table list is refused;
  - a list under `sources:` is refused;
  - the alias does not collide with wetland's carry.

## Phase 5: Composition `in_wsg` + the bound
- [ ] `fp_composition_build`: add an `in_wsg` overlay from `fp_wsg_polygon()` (cell centre). The
  sibling `inputs` records the polygon source and a digest of its key.
- [ ] `fp_composition_summary`: headline fields over `in_floodplain & in_wsg`: the floodplain area,
  and of which open water.
- [ ] `composition-check.R`:
  - an offline `in_wsg` fixture arm;
  - the live bound becomes two-sided |rel| < 1%, comparing `in_wsg` change cells with `in_wsg`
    patches;
  - a whole-footprint comparison beside it;
  - the outside share as INFO.

## Phase 6: Provenance outputs edit
- [ ] `fp_prov_set_outputs(cfg, "landcover", key, outputs, repair)`: edits `outputs` and
  `outputs_hash` in place and appends to `run.repairs`, with `previous_datetime_utc` equal to the
  unchanged stamp. The file is verified on disk, and the original bytes are restored if anything
  else moved.
- [ ] `provenance-check.R` offline arms, mirroring the restamp ones.

## Phase 7: Backfill script
- [ ] `scripts/floodplain_lcc/gpkg_backfill-split.R <area>` (`DRY=1` previews only, `FORCE=1`
  overrides), for the area's current-species layers. It:
  - splits the `floodplain.gpkg` layers;
  - re-vectorizes `transition.tif` through `fp_lulc_vectors()`;
  - re-tags every overlay;
  - writes the bridge;
  - rebuilds the composition through `fp_composition_build`;
  - edits the provenance outputs.
- [ ] Refuses before any write unless the inside pieces match the existing layer by
  `(name_basin, patch_id)`: same count, same area to 1e-6 relative, same cause columns
  (`fp_same_values`).
- [ ] Idempotent: a second run is a no-op.
- [ ] Backs up `floodplain.gpkg`, `floodplain_landcover.gpkg` and `provenance.json` to the scratchpad
  first.
- [ ] Run on dunc. Run the checks. Then run the other 22 region groups and neexdzii, logged to
  `scripts/floodplain_lcc/logs/`.

## Phase 8: Live verification
- [ ] Per area: `wsg_split-check.R`, `composition-check.R`, `provenance-check.R`, `disturbance-check.R`,
  `bridge-check.R`.
- [ ] Inside patch totals equal the pre-backfill layer totals, read from the backup.
- [ ] neexdzii: tree loss over pieces with a sub-basin is 773.4 ha, and the outside share is stated.
- [ ] The measurement log goes to `scripts/floodplain_lcc/logs/20261018_wsg_split_backfill.md`, with
  outside shares per group (PCEA among them).

## Phase 9: README totals + docs
- [ ] A gated builder in `readme_functions.R` writes the committed `fig/region_totals.csv`. Per region:
  - groups;
  - the sum of whole items;
  - the `in_wsg` sum, which is a union;
  - open water in `in_wsg`.
- [ ] `README.Rmd` gets a table stating that the totals are a union. Render it, then run
  `readme_determinism-check.sh` and `readme_content-check.py`.
- [ ] `CLAUDE.md`:
  - a #53/#138 bullet;
  - the composition bound;
  - the neexdzii parity, restated;
  - the patch counts and tree-loss figures that moved (DUNC, Skeena).

## Phase 10: Publish-layer handoff
- [ ] File a stac_floodplains_bc issue: the schema adds `in_wsg`, `in_open_water` and
  `open_water_poly_id`, the floodplain layer is now two rows, and the items need a republish. This
  repo does not call the publish layer, so the handoff stays one-way.

## Validation
- [ ] Tests pass (all offline checks + live checks above)
- [ ] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

## Verification (end to end)
- [ ] Offline: `Rscript` each of `wsg_split-check.R`, `disturbance-check.R`, `composition-check.R`,
  `provenance-check.R` and `bridge-check.R` with no area. Each ends `ALL PASS`, and each new guard is
  shown to go red with its defect restored.
- [ ] Live on dunc after its backfill:
  - the `in_wsg` patch total equals the backup's patch total;
  - `composition-check.R dunc` passes the new bound (it failed at +4.70%);
  - `provenance-check.R` passes 7c with the new `transition_patches`;
  - the backfill re-runs as a no-op.
- [ ] One forward step 3 on a small area (dunc) reproduces the backfill's layers (same rows, same
  in/out totals), so the two paths cannot disagree.
