# Plan review (#110) — Plan agent, returned 2026-10-09 ~05:05 UTC

Read-only Plan agent; findings returned as reply text and recorded here. Disposition in the last column.

| id | finding | disposition |
|---|---|---|
| B1 | "extent effect" vs on-disk baseline is on a different grid; overlap refuses misaligned grids | already designed as totals-only; anchor compares on own grid |
| G1 | common DEM: FLT8S, round-trip digest, NA count, CRS assert, re-read in every arm | adopted: `dem` mode writes FLT8S and asserts digest round-trip + CRS |
| G2 | keep `channel_width` on the streams object (auto channel buffer) | already: every SQL column passes to the VCA |
| G3 | waterbodies are ORed into the valley unfiltered; order-1/2 carry 6,147 waterbody keys vs 368 | adopted: per-arm waterbody raster, added area split waterbody / not |
| G4 | arm 4 is bcfishpass's predicate (7,035 seg / 1,184 km); link's frs_order_child rule takes 3,998 / 709 km; parent NULL on 652 order-1 | adopted: relabelled "bcfp bypass rule"; NULL semantics already pinned offline |
| G5 | per-blk comparison conflates added seeds with boundary move | adopted: per arm, a single-group `complete = FALSE` attribution from the coho network = coho-reachable floodplain; compared across arms |
| G6 | seg key format, dropped segments, what seg rows mean | key already `%.0f:%.3f`; dropped groups = n_groups − rows; meaning stated in research |
| G7 | record versions, terra GDAL, refuse mixed versions | adopted: versions in every json; report refuses a mix |
| G8 | habitat codes: 1 modelled, 2 modelled+known, 3 known; use `IN (1,2)`; 25.2% coho rearing below order 3 anchor | adopted |
| O1 | pre-register anchor outcomes | done: anchor now gates the probe's VCA against an fp_floodplain() replay; published record reported |
| O2 | `dem` mode then arms cheap→expensive (5,3,4,2,1, seg) | adopted |
| O3 | habitat table needs only DB | stays in report (no run dependency either way) |
| O4 | nesting live assertion | adopted in `dem` mode |
| A1 | toolchain moved (terra 1.9.50 / GDAL 3.13); fp_toolchain records sf's GDAL only | confirmed by the anchor run (grid ~1 m off, −0.42% area); filed separately |
| A2–A3 | delineation cost scales with seeds; 0.39 s/group has no committed log | measured here |
| A4 | fp_read_config not sourceable | already read directly |
| S1 | 02's `field =` deprecation | out of scope; noted |
| AC1 | pre-register a floor/grain decision rule | adopted: research/whole_fwa_floodplain.md, committed before arms run |
| AC2–AC3 | completeness checks; digest from written file | adopted / already |
