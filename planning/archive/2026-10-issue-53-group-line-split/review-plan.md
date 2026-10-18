# Plan review (Plan agent, spawned 2026-10-18 20:02 UTC, delivered ~20:20 UTC)

Full text was delivered as the agent's reply; this file records each finding and its disposition.
Verdict: design sound; transition.tif re-vectorises byte-identically (WKB) when the sub-basins go
through EPSG:4326 first (lsal 4562/4562, dunc 1299/1299).

| id | finding | disposition |
|----|---------|-------------|
| B1 | bridge-check.R key picks up in_wsg; pk_of lacks it | already fixed in b5649d7 (excluded + keyed) |
| B2 | classified tifs carry no category table | backfill splits the existing layers (as written) |
| B3 | KEYS_COMPOSITION_INPUTS is closed: a new `wsg_polygon` input key is UNDECLARED, and once declared, missing on legacy compositions | moved under `inputs$overlays$wsg` |
| B4 | subset area: zone pieces re-split along BULK (re-noded, slivers) | zone pieces are split only where they cross the group line by >= 1 m2 |
| G1 | legacy species layers stay clipped | left as is, documented; acceptance is the primary scenario |
| G2 | patch-total readers (stac 01_stage, region_acceptance-report) switch to whole-footprint | handoff states `in_wsg` for headline metrics; noted for the region report |
| G3 | fl_fallback_cells attr lost after the split | read before the split |
| G4 | entry named `wsg` | already fixed (FP_DST_RESERVED_NAMES) |
| G5 | COMMENT lookup on two tables | already fixed (per table) |
| G6 | second run not a no-op | composition rebuilt only on missing columns; outputs edit is a no-op when equal |
| G7 | parity figure in README.Rmd, run_area.R | updated in Phase 9 |
| G8 | stale "patch_id per sub-basin" comments (#87) | comments touched by this branch corrected; #87 left open |
| G9 | snapshot ordering without in_wsg | already fixed |
| G10 | a cell claimed twice by one key across the line | fp_hj_grid_cells dedupes (key, cell) |
| G11 | backups in the scratchpad | moved to data/backup/20261018_wsg_split/ (gitignored) |
| G12 | gpkg date pin in the CLI | already present |
| G13 | handoff covers schema only | handoff lists metrics, outside pieces, produced_datetime, stac sums |
| O1 | composition guards fire after writes | backfill re-checks the composition premises before any write |
| O2 | dry-run every area before writing any | done before the write sweep |
| O3 | forward step 3 last | run last |
| A1 | gate on WKB, not area | whole-WSG gate compares WKB; subset compares area per key |
| A2 | AOI from fl_valley_poly(floodplain tif) keeps drift's cache key | adopted |
| A3 | FORCE overrides only the cause gate | already so |
| A4 | no make_valid before split | GEOS errors surface in the dry sweep |
| A5 | empty in_open_water | already INFO |
| A6 | which table an open_water id came from | not carried; ids are FWA-unique across waterbody tables |
| A7 | stac reader inert; add toolchain to repair | toolchain added to the repair record |
| S3 | in_wsg after the item keys on split layers | item keys kept last |
| AC1 | 1% bound too loose | in_wsg bound tightened to a measured absolute; whole footprint near-exact; vector cross-check of in_wsg added |
| AC2 | "union" wording | README states it is the area inside the region's group polygons |
| AC3 | known failures | listed in the log |
| AC5 | patches -> pieces | stated in CLAUDE.md |
