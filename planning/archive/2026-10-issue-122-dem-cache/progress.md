# Progress — Cache the step-2 DEM per area (#122)

## Session 2026-10-13

- Plan-mode exploration — phases approved by user (driver-owned URL chosen over flooded#58 / flooded `cache=`)
- Created branch `122-cache-the-step-2-dem-per-area-nrcan-s-s3` off main
- Scaffolded PWF baseline from issue #122 with approved phases
- Next: start Phase 1
- Phase 1: `fp_dem.R` (key, HEAD with Last-Modified + ETag, cache) and `dem_cache-check.R` (offline PASS, 0 failures). Mutations proven: dropping the hit digest check, dropping ETag or sf PROJ from the key each turn a check red; an FLT4S write aborts on the round-trip guard. ETag added to the key beside Last-Modified (the HEAD returns both). FLT8S, as the probe found: the bilinear warp is double in memory.
- Phase 2: step 2 calls `fp_dem_cached()`; `inputs$dem_source`, `run$dem_cache`; `provenance-check.R` adds `dem_cache_reconcile()` (5h offline with a must-fail arm; 7c live) and a #122 cutover for the new keys. Offline provenance-check, whole_network-check, floodplain_probe-check and region_config-check all PASS; `provenance-check.R neexdzii` PASS on its pre-cutover record.
- Phase 3: `attribute_tag.R` reads through `fp_dem_cached()` (sources fp_raster/fp_provenance/fp_dem; it does not source packages.R). All 150 scenario rows across `config/*/flood_scenarios.csv` carry max_width 2000 = step 2 buffer, so it hits. Parse-checked only: no live run, because every area with `attribute_by` is a published one.
- Phase 5: CLAUDE.md bullet + Prerequisites note; #122 body records the decision and the three departures from its proposal (geometry digest, ETag, toolchain in the key; per-species file).
- Plan review folded in (findings.md has the disposition): B1 attribute_tag buffer/digest, whole toolchain in key, shared record list, stronger reconcile, re-HEAD, temp cleanup, resolver-gated cutover.
- Phase 4 (23:12Z–23:25Z): neexdzii cold, re-key and warm runs of 2,3 plus attribute_tag, all 0 errors. DEM digest 192ea21e… unchanged from the #117 re-baseline; every floodplain/landcover/composition output hash unchanged; only dem_resolver/dem_source moved. provenance-check neexdzii reconciles all three DEM digests; composition-check ALL PASS. Hit 0.3–0.6 s vs fetch ~15 s today. Log: `scripts/floodplain_lcc/logs/20261013_dem_cache_neexdzii.md`.
- `/code-check branch`: round 1 Clean (one wording nit fixed); round 2 Clean (one header wording fixed); round 3 found three claim/behaviour mismatches, one inside round 2's fix, so the loop ended on an enumeration: all 120 added comment lines plus the CLAUDE.md bullet and check header walked against the code, three more false claims corrected (53d1971). Round 3 also added a HEAD-count assertion pinning "a hit makes one HEAD request". Four review agents in total (plan review + 3 rounds).
