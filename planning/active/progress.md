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
- Phase 4: `open_water` context overlay over fwa_lakes_poly + fwa_manmade_waterbodies_poly, carried as
  `open_water_poly_id`. A context entry may list tables, and the query becomes a UNION ALL. A one-table
  query is unchanged. Live fetch over PCEA's floodplain: 2,038 polygons, ids unique.
  disturbance-check.R: 9 new arms. Three restored defects turn 2, 1 and 2 assertions red.
  Names `wsg`/`floodplain` are reserved. disturbance-check's live loop treats an empty in_open_water
  as legitimate, as it does in_alr, with the composition as the arbiter.
- Phase 5: the composition carries `in_wsg` (cell centre in the group polygon). The sibling's
  `inputs.wsg_polygon` records the polygon's source and its WKB sha256. The summary gains
  `outside_wsg_ha` and `<overlay>_in_wsg_ha` / `change_in_<overlay>_in_wsg_ha`. composition-check.R's
  bound is now two-sided |rel| < 1% on in_wsg cells against in_wsg patches, with a whole-footprint
  comparison beside it and the outside share as INFO. A layer that predates #53 keeps the old
  one-sided check. 4 new offline arms.
- Phase 6: `fp_prov_set_outputs(cfg, key, update, repair)`. Only outputs, outputs_hash and
  run.repairs move. The recorded outputs_hash must first re-derive from the round-tripped outputs
  (true on DUNC's live record), an unknown field is refused, a no-op writes nothing, and a disk
  comparison restores the original bytes on any other change. provenance-check.R §5g2 has 9 arms,
  including a mutant that edits `inputs` and is caught with the file restored. The `wsg` signature
  Signature (cfg, key, update, repair): landcover is the only section it repairs.
- Plan review arrived at ~20:20 UTC (`review-plan.md`, with a disposition per finding). It was folded
  in before any area was written. DUNC had been written once under the pre-review design; it was
  restored from its byte backup (md5 matched) and is re-run in the sweep.
- **Dry sweep, 24 areas, 20:24-20:47 UTC: every area rc=0.** Every published patch re-vectorises
  exactly: WKB-identical in all 23 whole-WSG groups, and by key and area on neexdzii. No cause,
  context or lookback column moves. Outside pieces range from 8 (UNTH) to 860 (PCEA).
  PCEA has 1,700.3 ha of change outside its group, which equals #138's independent measurement.
  neexdzii's sub-basins reach 3.94 ha past BULK; 10 pieces (3.4 ha) lie outside every sub-basin, and
  the inside total is 1,278.7335 ha = published.
  Logs: `scripts/floodplain_lcc/logs/20261018_wsg_split_backfill/*_dry.log`.
- The write sweep started ~20:47 UTC under caffeinate, with BACKUP=data/backup/20261018_wsg_split.
- **Write sweep, 20:47-21:59 UTC: 24/24 rc=0**, each with one `Done:` and one `wsg_split` provenance
  edit. A second DUNC run left all three files byte-identical.
- **Region checks, 22:05-22:35 UTC.** composition-check passes in all 23 groups (it failed in all of
  them before #53). wsg_split-check, provenance-check and disturbance's all_ff04 section pass
  everywhere, and neexdzii passes all five. The FAILs that remain were all known before:
  - NECR composition arm 5 (#140);
  - the bridge union proxy on PCEA, LARL and SLOC (#139);
  - the whole-file disturbance-check, on the retired species layers.
- **Region totals** (fig/region_totals.csv): summed over in_wsg, then summed whole.
  - columbia 1,453.4 vs 1,469.4 km2
  - fraser 5,674.1 vs 5,786.7 km2
  - peace 1,523.5 vs 1,891.7 km2
  - skeena 1,441.3 vs 1,463.7 km2

  The README renders them; its determinism and content checks pass.
- **Forward step 3 on DUNC** was a drift cache hit, and it reproduced the backfill identically:
  digests, both hashes, the composition digest and every landcover layer's WKB.
- Filed stac_floodplains_bc#98 (schema, headline metrics over in_wsg, republish).
- Log: `scripts/floodplain_lcc/logs/20261018_wsg_split_backfill.md`.
