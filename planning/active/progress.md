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
