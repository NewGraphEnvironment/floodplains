# #117 — Published floodplains do not reproduce on today's toolchain, and provenance names the wrong GDAL

## Outcome

The DEM grid had moved about 1.3 m with no data change. The cause was PROJ 9.8.1's NAD83(CSRS)→NAD83 operation, not the GDAL version as the issue first said. flooded 0.7.0 (flooded#67) pins the grid and the datum step, and this repo adopted it:

- Step 2 refuses flooded < 0.7.0 for every area.
- `fp_toolchain()` records terra's own GDAL and PROJ (`gdal_terra`, `proj_terra`) beside sf's. `provenance-check.R` requires them on entries whose step ran after the cutover; older entries are reported as INFO. In-suite must-fail arms cover an sf-sourced pair, an NA pair and an in-place repair.
- `attribute_tag.R` refuses a grid mismatch in either direction by name.
- The neexdzii parity fixture is re-baselined.

Published species areas are not re-run here. #125 moves every region to whole-network floodplains and retires the species items (stac_floodplains_bc#76).

What was learned:
- Cross-GDAL agreement under the pin is 0.12 mm per cell, not byte identity.
- `fl_dem_aoi()`'s read window still goes through sf's unpinned PROJ (flooded#78).
- Every percentage of "the move" needs its base. MORR is −0.25% against its published record and +0.17% against the 9.8.1 replay.
- Digests only exist from the 2026-09-02 record, so nothing can be "digest-identical to 09-01".

Follow-ups filed: flooded#78, soul#402 (the spatial convention still names GDAL), a DUNC cache note on #125.

## Measurement

The neexdzii contract is **673.5 km / 142.0 km² / 773.4 ha** (2,018 patches). The previous one was 673.5 / 142.8 / 770.0 on flooded 0.5.0's moving grid.

- **Network:** content digest identical to the 2026-09-02 record. Its `inputs_hash` moved only through package stamps.
- **Floodplain:** moved only in the `dem_*` fields and the flooded stamp. The DEM went from 6,533,563 cells at 30.46984 m to 3,474,262 cells at 30 m, with its origin on a multiple of 30.
- **Reproduction:** a second steps-2,3 run reproduced every floodplain, landcover and composition digest byte for byte, on one machine and one toolchain.
- The −0.55% floodplain / +0.44% tree-loss move spans flooded 0.5.0 → 0.7.0, so it is not attributed to the pin alone.

The plan review changed the design before it shipped. The plan text's "INFO for any record missing the keys" would have failed toward pass.

Code-check took 3 rounds plus an enumeration. Rounds 2 and 3 each found a defect inside the previous round's fix. The mechanism was facts restated away from their source losing their anchor: direction, base, run or date. The loop ended on enumerating three sets: package floors, percentages, and dated references plus issue-state claims.

## Evidence

- `scripts/floodplain_lcc/logs/20261013_flooded070_rebaseline_neexdzii.md`
- `review-*.md` in this directory

Closed by: PR #129
