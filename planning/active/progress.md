# Progress — Serve whole floodplains keyed by blue_line_key (#104)

## Session 2026-10-11

- Plan-mode exploration; gate decisions: `species: all` key, steps 1-3 + habitat table, DUNC standalone
- Created branch `104-serve-whole-floodplains-keyed-by-blue-li` off main
- Scaffolded PWF baseline from issue #104 with approved phases
- Next: Phase 0 (flooded v0.6.5)
- Phase 0: flooded v0.6.5 installed (pak, github tag); 02 refuses whole mode below flooded 0.6.4
- Phase 1: `FP_SPECIES_WHOLE`/`fp_whole_network()` in fp_region.R; 01's read lifted into `fp_network_sql()`
  (species SQL sha256 pinned to the pre-lift read, `b8a25cd6…`); whole mode drops the streams_access join;
  freshness reference drops the access predicate; region runs refuse `all` both directions
- Phase 2: `habitat_link` table (long form, keyed by FWA position, join per group) + `habitat` provenance
  sibling on network[all<order>]; provenance-check 3d (offline, must-fail arms), producer-scan, 7c reconcile
- Probe: whole SQL on DUNC = 13,023 segments / 3,493 km; bcfp reference 3,493 km (0.0% dev)
- Offline: whole_network-check, region_config-check, floodplain_probe-check, provenance-check all PASS
- Plan review 1 returned (planning/active/review-1.md, 23 findings, dispositions there); fixes landed
- DUNC step 1 (pre-fix code): 6.8 s, 0.47 GB peak RSS, 13,023 segments, 211 waterbodies, habitat_link 53,654 rows
  (bt, wct); link_log null + note (no DUNC row in fresh.log), link_config_name_source unresolved
- Step 2 launched 01:20 UTC; DEM fetch < 4 min this time
- Phase 5: join functions extracted to fp_habitat_join.R; demo copy re-run into scratch reproduces the
  committed MORR log exactly (only timestamp and run time differ; fig2 PNG bytes differ, not replaced)
- Next: after step 2, re-run step 1 (review fixes change the habitat record), then step 3
