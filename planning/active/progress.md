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
- DUNC step 2: 534 s wall (DEM + 3 scenarios + blk attribution), 13.3 GB peak RSS; ff02/04/06 valley cells
  196,456 / 203,285 / 205,508 at 30.17 m; all_ff04 attributed to 1,942 of 2,236 blue lines (294 reach no
  valley cell), 1,159 fallback cells; 0 errors (warnings: flooded `field` deprecation x2, the 294 omitted groups)
- Step 1 re-run (r2, review-fix code): habitat sibling carries species array, fwa_content_sha256, fwapg_sha null/unresolved
- Live provenance-check neexdzii + bulk: PASS (214 ok each) -- species mode untouched
- habitat_join-query.R dunc: integrity 203,285/203,285, key match 100% (bt, wct), bt spawning floodplain
  5,101 ha nearest / 5,908 any vs 16,907 by blue line; log 20261012_habitat_join-query_dunc.md
- Step 3 launched 01:30 UTC
- DUNC step 3: 580 s, 19.3 GB; 1,282 patches, bridge 188 blue lines (coverage 0.928), composition 18,485.7 ha,
  tree loss 119.5 ha (harvest 32.6%, fire 0)
- Checks: bridge-check dunc all_ff04 PASS; provenance-check dunc PASS (habitat reconciled); composition-check
  dunc FAILS change-vs-patch bound (+4.67% vs <1%): 205.4 ha (1.1%) of floodplain lies outside the group
  polygon and 41.2 ha raw change sits there (#53); guard not loosened, recorded as a finding
- Phase 6: DUNC log, research section, CLAUDE.md (Layout bullet, area line, dunc entry)
- Issues: #104 body (pilot section, two questions settled), #120 body (lands under #104), #53 (DUNC cross-boundary), filed #123
- Code-check round 1: 1 fragile (`%||%` undefined in habitat_join-query.R for R < 4.4) -- fixed
