# Task: Agricultural Land Reserve: floodplain share, change share, and change inside the ALR per area (#108)

## Problem

ALR is not in the database. No table in fwapg matches `alr`/`oats`, and no issue covers it. The questions it has to answer:

1. **How much of the floodplain is ALR?** The area of `floodplain_<scenario>` ∩ ALR, including stable land.
2. **How much of the floodplain changed?** This exists already: the transition patches.
3. **How much changed inside the ALR?** Change area ∩ ALR, total and by transition class.

Wetland has the same gap in (1). `in_wetland` sits on **changed** patches only (`changes_only = TRUE`, #95), so "how much of the floodplain is wetland" has no number today either.


## Context

The ALR is not in fwapg, so no area can say how much of its floodplain is Agricultural Land Reserve,
or how much of its change happened inside it. Wetland has the same gap for stable land, because
`in_wetland` sits on changed patches only (#95). The per-WSG report (#92) needs all three numbers
without recomputing them. This plan loads the ALR as a frozen snapshot, tags patches with it the way
`wetland` is tagged, and adds a cell-level **composition table** that every area-share number is
a sum over.

**Measured during planning:** `OATS_ALR_POLYS` has 3,226 polygons. Every one has `STATUS = 'ALR'` and
`FEATURE_CODE` NULL, so no filter is needed. DataBC refreshes it quarterly (end of Jan/Apr/Jul/Oct).
No `alr`/`oats` table exists in fwapg. The publish layer (`stac_floodplains_bc/scripts/01_stage.R`)
extracts layers **by name**, so a new gpkg table is ignored until that repo opts in. The coupling
stays one-way.

**Decisions taken at the gate**
- **Table shape:** a long crossed table (user's choice). There is one row per
  `(from_class, to_class, status, in_alr, in_wetland)` with `cells` + `ha`, and every number in
  the issue is a sum over it.
- **Where:** a shared function that step 3 calls, plus a backfill CLI that runs on the rasters
  already on disk (no STAC re-fetch). This is the user's choice and the `fire_tag.R` pattern.
- **Snapshot:** load once and freeze (the issue's recommendation). The load date, row count and
  catalogue record go into a `COMMENT ON TABLE`, which is machine-readable and gets copied into
  provenance. Refreshing is a deliberate `REFRESH=1`.

**Definitions (what the table means)**
- The population is the **classified footprint**: cells that are non-NA in either endpoint
  `classified_<yyyy>.tif`. This is the same rule as the accuracy module (CLAUDE.md #93).
- `status` is one of:
  - `stable`: from == to.
  - `change`: from != to and `transition.tif` is non-NA, which is exactly what the transition
    layer vectorises.
  - `sieved`: from != to, but the 1 ha sieve removed it.
  - `nodata`: an endpoint is NA.
- Overlay membership is decided **per cell centre** (`touches = FALSE`), which is the accuracy
  module's rule. Wetland means an FWA polygon. Flooded Vegetation stays visible through the class
  columns, so either wetland definition is a sum over the table.

## Phase 1: Load the ALR snapshot
- [x] `scripts/fwapg/alr_load.sh`:
  - `bc2pg WHSE_LEGAL_ADMIN_BOUNDARIES.OATS_ALR_POLYS` into `whse_legal_admin_boundaries.oats_alr_polys`.
  - Then `COMMENT ON TABLE` with the load date (UTC), row count and record id `92e17599-…`.
  - It refuses if the table exists unless `REFRESH=1`, and `DRY=1` reports the remote count only.
  - PG* vars come from `~/.Renviron` and the password is redacted in logs, both as in `fire_load-prior.sh`.
- [x] Assert loaded rows == the WFS `numberMatched` and that `STATUS` is all `ALR` (fail otherwise,
  naming the values).
- [x] Run it, and commit the log under `scripts/fwapg/logs/`.

## Phase 2: Tag change patches with `in_alr`
- [x] Add `config/disturbance.yml` `context:` entry `alr`: `table: whse_legal_admin_boundaries.oats_alr_polys`,
  `geom_col: geom`, `carry: [alr_poly_id]`. Carry the key only, with a comment that `feature_area_sqm`
  is deliberately not carried.
- [x] `disturbance-check.R` offline:
  - a must-fail arm where an `alr` context entry carrying `{feature_area_sqm: area_ha}` is refused;
  - an accepted arm for the real entry;
  - the tag fixture extended so `in_alr` + `alr_poly_id` appear and never reach the report's
    causes.
- [x] `disturbance-check.R` live: `in_alr` present on a re-tagged layer (INFO when absent, since
  rollout is forward-only).

## Phase 3: Composition table
- [x] Move the cell-centre rasterize rule into `scripts/fp_raster.R` as `fp_rast_cells(polys, template)`.
  `fp_acc_rasterize()` (`scripts/landcover_accuracy/fp_accuracy.R`) delegates to it, so there is
  one definition of membership.
- [x] Add `scripts/floodplain_lcc/fp_composition.R`. It has three parts.
  - **`fp_composition(from, to, trans, overlays)`** (pure, rasters in, data.frame out):
    - it encodes class pair, status and overlay bits into one integer raster and reads it with a
      single `terra::freq()` (C++ fast path);
    - it decodes that back to columns;
    - it refuses a `trans` that disagrees with `from*1000+to`.
  - **`fp_composition_build(cfg, scenario, conn)`**:
    - reads the area's tifs from `rasters/<scenario>/` with their category tables stripped;
    - fetches each `context:` entry, using `.dst_fetch` and then the floodplain filter;
    - rasterizes with `fp_rast_cells`, computes the table and adds the item keys
      (`wsg`, `species`, `scenario`);
    - writes `composition_<scenario>_<from>_<to>` to `floodplain_landcover.gpkg` (per-layer,
      `delete_layer`);
    - writes a provenance section `composition[<scenario>]`:
      - `inputs`: the overlay tables and their `COMMENT`, plus the `classified`/`transition`
        content digests;
      - `outputs`: a `fp_table_content_sha256` over the table.
  - No context configured ⇒ the table is still written (class × status only), so no #55 orphan is
    possible.
- [x] Step 3 (`03_lulc_classify.R`) calls `fp_composition_build()` after the transition write.
  It opens a DB conn only when context is configured, and runs in the zero-transition case too
  (stable composition is still true).
- [x] Add `scripts/floodplain_lcc/composition_build.R <area> [scenario]`, a standalone backfill.
  It pins the gpkg date (`fp_gpkg_pin_date()`, #45) and does not source `packages.R`.
- [x] Add `scripts/floodplain_lcc/composition-check.R`.
  - **Offline**, on tiny hand-built rasters, each rule with a must-fail arm:
    - the four statuses partition the footprint;
    - sieved ≠ change;
    - a NA endpoint lands in `nodata`;
    - the cell-centre membership rule holds;
    - the codes round-trip;
    - an out-of-sync `trans` is refused;
    - the overlay columns are independent (ALR ∩ wetland).
  - **Live** for an area:
    - `sum(ha | change)` equals the transition layer's `sum(area_ha)`, with the tolerance set from
      measurement and stated;
    - ALR cell-ha agrees with the vector `area(floodplain ∩ ALR)`, an independent derivation, to a
      stated tolerance;
    - change-in-ALR ≤ change;
    - the provenance `outputs` digest re-derives from the table.
- [x] `provenance-check.R`: a `composition` entry is required when the gpkg holds a
  `composition_*` table (an artifact-derived expectation) and well-formed when present.

## Phase 4: Roll out to NECR and BULK
- [x] Run `fire_tag.R necr` and `fire_tag.R bulk`, which add `in_alr`. If either refuses
  because a cause would move, stop and report; do not `FORCE`.
- [x] Run `composition_build.R necr` and `composition_build.R bulk`, then `composition-check.R`,
  `disturbance-check.R` and `provenance-check.R` for both.
- [x] Commit a log `scripts/floodplain_lcc/logs/<date>_composition_necr-bulk.md` with the
  three headline numbers per area, which are derived from the table and stated nowhere in prose (#77).

## Phase 5: Docs and handoffs
- [x] `CLAUDE.md`: add an ALR context entry, the composition table (its definitions and the
  "report by intersection, never by flag" rule) and the snapshot policy, and update the forward-only
  note.
- [x] Add `research/README.md` / topic-file notes only if a measurement changes what is known (the
  tolerances, for example).
- [ ] File a `stac_floodplains_bc` issue: publish `composition_*` and add `in_alr`/`alr_poly_id` to
  the transition schema (stac#6).
- [ ] Revise the #108 body to the shipped design. Point #92 at the table.

## Critical files
- `config/disturbance.yml`
- `scripts/floodplain_lcc/03_lulc_classify.R`
- `scripts/floodplain_lcc/fp_disturbance.R` (reused: `.dst_fetch`, the validator)
- `scripts/fp_raster.R`
- `scripts/landcover_accuracy/fp_accuracy.R` (`fp_acc_rasterize`)
- `scripts/floodplain_lcc/fp_provenance.R` (reused: `fp_prov_set`, `fp_table_content_sha256`,
  `fp_raster_content_sha256`)
- `scripts/floodplain_lcc/disturbance-check.R`
- `scripts/floodplain_lcc/provenance-check.R`
- new: `fp_composition.R`, `composition_build.R`, `composition-check.R`, `scripts/fwapg/alr_load.sh`

## Verification
- Offline: `Rscript scripts/floodplain_lcc/composition-check.R` and `disturbance-check.R`. Each must-fail
  arm is shown to go red by restoring the defect in a temp copy.
- Live, on NECR and BULK:
  - `composition-check.R <area>` reconciles change ha with the transition layer and ALR ha with
    the vector intersection;
  - `provenance-check.R <area>` passes;
  - `fire_tag.R` reports no cause movement.
- Gate the runs on the in-band error count and the output mtime, never on the wrapper's exit code.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
