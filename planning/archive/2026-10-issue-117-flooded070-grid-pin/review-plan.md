# Plan review — #117 (Plan agent, 2026-10-13)

Received while Phase 3's first run was in flight. Full findings as returned, summarised by ID; dispositions below.

| ID | Finding | Disposition |
|---|---|---|
| B1 | Plan text's carve-out (INFO for any record missing the terra keys) fails toward pass; landed code is date-gated FAIL | Plan bullet rewritten to the landed design |
| B2/O1 | A lone step-2 re-run leaves the composition stale; step 1 re-GRABs `fresh` and could mix a data change in | Run 1 was already launched as 1,2,3: its network entry is compared byte-for-byte with the pre-run snapshot as the control. The determinism run is `2,3`, compared by hand for the raster sections |
| O2 | Gate on per-entry run stamps after the marker, not file mtime | Adopted |
| G1 | `run_region.R` cache would skip DUNC on the pre-pin grid under #125 | Recorded on #125 (DUNC needs FORCE=1 or a version-aware cache); CLAUDE.md DUNC figures marked pre-0.7.0 grid |
| G2 | `attribute_tag.R` fails with a misleading compareGeom error on every pre-0.7.0 delineation | Verified (`fl_valley_attribute` compareGeom); refusal added naming #117 |
| G3 | Post-cutover NA terra pair passes | Arm + must-fail added |
| G4 | §7 INFO prints "predates #117" beside the post-cutover FAIL | INFO gated on step time |
| G5 | terra-pair-from-terra check has no in-suite must-fail | Predicate factored, must-fail in file |
| G6 | Stale contract/comment sites: neexdzii area.yml, README sentence, fp_provenance repair comment, packages.R floor comment, probe header | Fixed; NEWS left to /gh-pr-merge |
| G7 | #122's cache key must include the flooded version | Already in #122's body; no change |
| A1 | `fl_dem_aoi()` 0.7.0 still transforms the read window through sf's unpinned PROJ | Verified in the deparsed function; `fp_toolchain` comment softened; filed on flooded |
| A2 | Step 3 warps through gdalcubes, not terra | Comment points at #80 (record gdalcubes) |
| A3 | Before/after is not a pure grid delta (flooded 0.5.0 -> 0.7.0, landcover re-run 10-02) | Log carries a field-by-field `inputs` diff per entry |
| A4 | DEM field readers safe | Noted, no action |
| S1 | #117 body edit should cite measured magnitudes, DUNC's 10-12 step 2, probe re-anchoring | Adopted in the issue edit |
| S2 | Optional 7c grid-alignment arm | Not adopted: scope; noted for #125 |
| S3 | 0.6.4 whole-network gate now dominated | Kept: documents a different reason |
