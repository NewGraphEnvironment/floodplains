## Outcome

Floodplains ran past their watershed group: onto the receiving river's valley floor at the outlet,
and across shared lakes (PCEA took all three of Williston's FWA polygons). As decided on 2026-10-18,
the delineation was kept whole and **labelled** rather than cut.
- **The split.** Every vector layer is split along the group polygon with `in_wsg`.
- **Step 3.** It stops clipping change patches, through `fp_split_patches()`, which reproduces drift's
  own intersection and keeps the remainder.
- **Open water.** `in_open_water` flags every FWA lake and manmade waterbody (#138).
- **The composition.** It carries both columns by cell centre.
- **The backfill.** `gpkg_backfill-split.R` applied all of this to the 24 areas on disk with no VCA
  run and no STAC fetch.
- **The README.** Its region totals are now a union over `in_wsg` (#60).

What was learned:
- **The old clip was a bug.** composition-check failed on every whole-network group because its two
  populations differed (clipped patches against unclipped cells), not because the bound was wrong.
- **Change was cheap once tested exactly.** Re-vectorising `transition.tif` reproduces the published
  patches byte for byte when the sub-basins go through EPSG:4326 as step 3 reads them. That made
  every inside total testable as an identity rather than a tolerance.
- **The cost was in crash recovery.** Code review ran four rounds, and rounds 2–4 each found a
  defect inside an earlier fix, all in one class: a re-run reading progress from the artefact being
  changed, or from a work list the run can change. It ended by enumerating every write and its
  predicate (`review-enumeration.md`), not by a quiet round.

## Measurement

All 24 areas were measured on 2026-10-18. The outside area is `!in_wsg` on the primary scenario.
- **Reproduction.** In all 23 whole-WSG groups the inside patches are the published clipped patches
  byte for byte (WKB). Inside change and tree loss are unchanged (max difference 0.000000 ha).
- **Outside share.** A median of 1.6% of the floodplain lies outside the group (range 0.81–3.26%),
  but PCEA has 41.7%. PCEA's change outside its group is 1,700.3 ha, which equals #138's independent
  measurement.
- **neexdzii parity holds.** Tree loss over patches that have a sub-basin is 773.4 ha, and the
  floodplain is 142.0 km². Its sub-basins reach 3.94 ha past BULK.
- **composition-check passes in all 23 groups.** It had failed in all 23 (+1.1% to +7.8%, PCEA
  +225%). In-group cells now agree with in-group patches within 0.5 ha (DUNC −0.03 ha), and the
  whole footprint agrees exactly.
- **Region totals, in-group / overlapping sum, km².** These changed what the README states.
  - Columbia 1,453.4 / 1,469.4
  - Fraser 5,674.1 / 5,786.7
  - Peace 1,523.5 / 1,891.7
  - Skeena 1,441.3 / 1,463.7
- **The forward path reproduces the backfill.** A forward step 3 on DUNC was a drift cache hit,
  because the AOI comes from `fl_valley_poly()` of the raster. It reproduced the backfill
  identically: digests, both hashes, and every layer's WKB.

## Evidence

`scripts/floodplain_lcc/logs/20261018_wsg_split_backfill*`

Closed by: PR (this branch, `53-floodplains-cross-watershed-group-bounda`)
