# Progress — #53 (with #138)

## Session 2026-10-18

- Plan-mode exploration — phases approved by user; user: "go all phases to pr"
- Created branch `53-floodplains-cross-watershed-group-bounda` off main
- Scaffolded PWF baseline from issue #53 with approved phases
- Next: start Phase 1
- Phase 1: `fp_wsg.R` (fp_wsg_polygon, fp_wsg_split, fp_split_patches, fp_floodplain_whole) +
  `wsg_split-check.R`. The inside rows equal drift's zoned `dft_transition_vectors()` output in
  attribute values and WKB (drift is the reference, not the code). Three restored defects (dropping
  the remainder, skipping the polygon extraction, skipping the area filter) each turn 2 assertions red.
- Phase 2 (writers): step 2 and attribute_tag.R split the scenario and `_by_` layers. DUNC all_ff04 split
  in 0.3 s: 18,316.9 ha in, 204.5 ha out, pieces conserve the area to 3.5e-5 m2. `fp_wsg_polygon()`
  recognises a whole-WSG subbasins.gpkg by its exact schema (name_basin, watershed_group_code), so
  neexdzii's 14 interior sub-basins go to the database.
- Readers of the scenario layer, surveyed: every one but 03's AOI sums areas, rasterises, or takes a
  bbox, so two rows change nothing there. habitat_join-query's fl_valley_join() dedupes claims by
  (cell, rank), so repeated keys are fine.
- Phase 3: `fp_lulc_vectors.R` (fp_classified_layer, fp_transition_patches, fp_bridge_build,
  fp_write_transition). Step 3 and attribute_tag.R share one bridge builder, keyed on
  (name_basin, patch_id, in_wsg) and summing overlap per pair before it filters slivers.
  03's AOI is `fp_floodplain_whole()`.
  - **Measured on DUNC, from transition.tif on disk:** re-vectorising reproduces all 1,299 published
    patches. patch_id, name_basin, transition and area_ha are all `identical()`, max area difference
    0. That adds 147 outside pieces, 33.6 ha (715.0 ha inside), in 8.4 s.
  - **No change needed** in two places. fire_tag.R builds from the layer it read, so in_wsg survives
    a re-tag. disturbance-check.R's core-columns assertion already excludes only tag columns, so with
    in_wsg in FP_PATCH_CORE it passes on split layers and fails on unsplit ones, which is correct.
  - Entry names `wsg` and `floodplain` are reserved (their in_ columns belong to other writers).
