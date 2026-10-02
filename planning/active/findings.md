# Findings — Agricultural Land Reserve: floodplain share, change share, and change inside the ALR per area (#108)

## Issue context

**If we do it:** every area can say how much of its floodplain is Agricultural Land Reserve, how much of it changed, and how much of that change was inside the ALR. Each is broken down by transition (tree loss, Crops ↔ Rangeland, wetland change) beside the existing fire/harvest attribution. Wetland gets the same summary, so the floodplain's composition is a reported variable rather than something read off a map.
**If we never do:** the ALR stays a map layer someone overlays by hand. The per-WSG report (#92) cannot state the agricultural share of the floodplain or of its change, which is the main frame for land-use pressure on these valley bottoms.

## Problem

ALR is not in the database. No table in fwapg matches `alr`/`oats`, and no issue covers it. The questions it has to answer:

1. **How much of the floodplain is ALR?** The area of `floodplain_<scenario>` ∩ ALR, including stable land.
2. **How much of the floodplain changed?** This exists already: the transition patches.
3. **How much changed inside the ALR?** Change area ∩ ALR, total and by transition class.

Wetland has the same gap in (1). `in_wetland` sits on **changed** patches only (`changes_only = TRUE`, #95), so "how much of the floodplain is wetland" has no number today either.

## Source

**ALC Agricultural Land Reserve Polygons**, BC Data Catalogue record `92e17599-ac8a-47c8-877c-107768cb373c`, warehouse object `WHSE_LEGAL_ADMIN_BOUNDARIES.OATS_ALR_POLYS`, Open Government Licence – BC. Columns: `ALR_POLY_ID`, `STATUS`, `FEATURE_CODE`, geometry. The record was last modified 2026-10-02: the boundary changes with ALC inclusion and exclusion decisions, so a load is a **dated snapshot**, and the load date has to be recorded (#96 is the provenance gap for overlay tables generally).

## Proposed shape (to settle at the plan gate)

1. **Load** `OATS_ALR_POLYS` into fwapg with `bc2pg`, the way fire and cutblocks were loaded, and record the load date. Check `STATUS`/`FEATURE_CODE` values first: if the layer holds anything other than current ALR, filter at load or in the config.
2. **Tag changed patches.** Add a `context:` entry in `config/disturbance.yml`: undated, it says where a patch is, never a cause, exactly the `wetland` pattern (#95). That gives `in_alr` + `alr_poly_id` on transition layers, through step 3 and `fire_tag.R`. Carry the key only: the ALR table has `FEATURE_AREA_SQM`, and the validator refuses carries that collide with patch columns.
3. **Report areas by intersection, never by flag.** `in_<x>` is an any-touch flag, so summing flagged patch areas overstates the share. #100 measured half of NECR's harvest-attributed tree loss lying outside any cutblock, and #88 is the same point. A **composition summary** per area and primary scenario:
   - floodplain ha; ALR ha; FWA wetland ha; ALR ∩ wetland ha
   - change ha; change in ALR ha; change in wetland ha
   - per transition class: ha inside and outside ALR

   Computed at cell level on the classified grid (the accuracy module already decides wetland per cell this way), so stable land is included.

## Decisions for the plan gate

- **Where the summary lives.** It could be a new step-3 output (a non-spatial gpkg table such as `floodplain_composition_<scenario>`, which then reaches STAC and needs a stac_floodplains_bc change), or a standalone script feeding #92 only. Recommendation: step 3, because a figure that exists only in a report script cannot be checked against its source.
- **ALR snapshot policy:** load once and freeze, or refresh per run. Recommendation: freeze, recording the load date and row count, and refresh deliberately.
- **Rollout:** areas gain `in_alr` on their next step 3, or from `fire_tag.R` where their cause columns would not move (mcgr and pine are refused, per CLAUDE.md). The composition summary is new, so it needs a run per area either way.

## Acceptance

- `in_alr` present on NECR and BULK transition layers, with `disturbance-check.R` extended (a must-fail arm for a context entry carrying a colliding column).
- Composition table for NECR and BULK. Its parts reconcile: ALR-inside + outside = floodplain, and change-in-ALR ≤ change. Its change total matches the transition layer's area.
- #92 can read all three numbers without recomputing them.

## Later, not this issue

- **Composition through time.** ALR and wetland are present-day boundaries. Tracking how wet areas, wetlands, deciduous and mixed forest, and the channel move across the floodplain needs the #103 dated imagery and #106's labelled channel review. The composition table here is the baseline those would be measured against.
- **Historical ALR boundaries** (ALC decision history) are a separate source, if wanted.

Relates: #92, #95, #88, #100, #96, #103, #106


## Planning measurements (2026-10-02)

- `bcdata info WHSE_LEGAL_ADMIN_BOUNDARIES.OATS_ALR_POLYS`: count 3,226; columns ALR_POLY_ID, STATUS, FEATURE_CODE, GEOMETRY, OBJECTID, SE_ANNO_CAD_DATA, FEATURE_AREA_SQM, FEATURE_LENGTH_M. Updated quarterly (end Jan/Apr/Jul/Oct).
- WFS GetFeature (STATUS, FEATURE_CODE), all 3,226 rows: STATUS = 'ALR' on every row, FEATURE_CODE NULL on every row -> no load filter needed.
- fwapg: no table matching alr/oats (only link scratch tables `zz_lnk_mc_scratch_salr`).
- ~~stac_floodplains_bc `scripts/01_stage.R` extracts named layers only, so a new gpkg table is ignored until that repo opts in.~~ **Wrong** (plan review A1): `01_stage.R:296-298` copies `floodplain_landcover.gpkg` WHOLE, so `composition_*` publishes on the next rebuild. What IS by name is the provenance reader, which refuses an unknown TOP-level key (`fp_provenance.R:172-178`) -- hence the `composition` sibling inside `landcover[<scenario>]`.

## Measurements during build (2026-10-02)

- transition.tif carries STABLE cells too (NECR 3,605,869 of 4,078,867 non-NA); sieved change is NA in
  it, stable cells are never NA. So `change` = trans non-NA AND from != to.
- The classified footprint is the terra::mask(touches = TRUE) ring: +5.5% NECR, +6.3% BULK over the
  vector floodplain. ALR on the NECR footprint 17,809 ha vs vector 16,894.7; on centre-in-floodplain
  cells 16,885.5 (0.05%). -> `in_floodplain` is always a column, and the share denominator.
- Change cells exceed the transition patches by +0.37% NECR / +0.34% BULK (sub-basin clipping).
- NECR footprint FWA wetland 6,436.64 ha == accuracy/wetland_composition.csv exactly.
- Cost: NECR ~45 s / 12-13 GB RSS; BULK ~130 s / 13 GB (169 Mcell grid).
- Recorded hashes cannot be re-derived from parsed provenance.json (JSON round trip changes types);
  provenance-check never does either.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| composition-check FAIL: ALR cells 17,809 vs vector 16,895 (5.4%) | the footprint ring; added `in_floodplain` and compare on it |
| composition-check FAIL: inputs_hash re-derive from JSON | wrong premise (round trip changes types); assert format instead |
| `stats::aggregate()` would drop the nodata reference rows (NA in `by`) | count by string key |
| progress bars in the BULK build log | stripped `(\|-+){4}\|=*` from the committed log |
