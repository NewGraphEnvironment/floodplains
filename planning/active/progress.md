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
