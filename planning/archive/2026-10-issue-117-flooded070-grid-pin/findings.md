# Findings — Published floodplains do not reproduce on today's toolchain, and provenance names the wrong GDAL (#117)

## Issue context

**If we do it:** provenance names the GDAL that actually warped the DEM, and we know which published floodplains a re-run would move and by how much before anyone re-runs one.
**If we never do:** a re-run of any area on today's toolchain changes its published floodplain with no data change. The record cannot say why, because it names sf's GDAL (3.8.5), while terra links a different one (3.13.0) and terra is what reprojects the DEM.

## Problem

Measured 2026-10-09 by #110's anchor on m1:
- `fp_floodplain()` replayed for MORR `co_ff04` reproduces the probe exactly.
- The published record (2026-09-03) is not reproduced. The DEM digest differs and the floodplain comes out **35,618.0 ha against 35,769.1 ha (−0.42%)**.
- MRDEM-30's source is unchanged (S3 `Last-Modified` 2026-06-24).
- terra went 1.9.34 → 1.9.50, and 1.9.50 links **GDAL 3.13.0**. Its warp puts the DEM's grid origin ~1.1 m west and ~0.6 m north of the old grid (flooded#67).
- **The cause is the PROJ datum operation, not the GDAL version** (corrected 2026-10-13; this bullet first said GDAL, from a comparison that changed GDAL and PROJ together). MRDEM is NAD83(CSRS) and BC Albers is NAD83. PROJ 9.5.1 (linked by sf, and by the published run) converts between them with no datum shift. PROJ 9.8.1 (linked by terra 1.9.50) routes through WGS 84, about 1.3 m away: +1.13 m east, −0.61 m north near MORR, which is the grid move above. GDAL derives its suggested grid from the transformed edges, so the grid moved with the operation. flooded#67 now fixes the grid (30 m, aligned to multiples of 30) and pins the shift-free operation between NAD83 realizations.

`dem_content_sha256` (#65) caught this as designed. Two things around it are wrong:

1. **`fp_toolchain()` records `sf::sf_extSoftVersion()`'s GDAL, not terra's.** On this machine they differ (3.8.5 vs 3.13.0), and the DEM warp runs through terra. So every `run.toolchain.gdal` describes a library that did not reproject the DEM. Add terra's own versions beside it, `terra::gdal(lib = "all")` (GDAL **and PROJ**), in `run`, not `inputs`, for the same reason terra's version sits there. PROJ is the one that moved the published floodplains.
2. **No area has run step 2 since 2026-09-03.** The next re-run of any area therefore moves its published floodplain by a toolchain change. Decide before that happens: pin the grid and datum step in flooded (flooded#67, done on its branch) and re-run deliberately, or accept the move and state it in the release notes. Do not let it arrive mixed in with a real change.

The "OPEN" comment at `02_floodplain_model.R:151-155` predicted exactly this case: "If a two-machine run shows this digest moving with the data unchanged, the right response is to move it to `outputs`". The move here comes from one machine across an upgrade rather than from two machines, but it is the same question. Moving the digest would hide the change, not fix it. The fix is a deterministic grid (flooded#67), after which the digest is a sound input again.

Relates: #65, #110, flooded#67.

**After flooded#67 merges** (added 2026-10-13): every step-2 record changes once.
- `dem_res_m` goes from 30.430634 to 30.
- `dem_ncell` drops sharply (MORR about 16.5 M → 9.2 M), because the grid is the AOI bbox in 3005 rather than the rotated crop.
- `dem_content_sha256` changes.
- MORR `co_ff04` moves 35,618.0 → 35,679.2 ha (+0.17%), with about 1,400 ha changing hands at the margins.

The #110 anchor and the whole-FWA `dem_common.tif` digest need re-anchoring, and published areas need a deliberate re-run. With the pin, a re-run reproduces across GDAL 3.8.5 ↔ 3.13.0 and PROJ 9.5.1 ↔ 9.8.1, as long as the DEM is re-derived through `fl_dem_aoi()` (terra), not through the `gdalwarp` utility with its defaults.


## Exploration (2026-10-13)

- flooded 0.7.0 (flooded PR #77, merged 2026-10-13T18:47Z) pins `fl_dem_aoi()`'s grid and datum step. Installed here: 0.6.6.
- This machine, one R session: `sf::sf_extSoftVersion()` GDAL 3.8.5 / PROJ 9.5.1 / GEOS 3.13.0; `terra::gdal(lib = "all")` GDAL 3.13.0 / PROJ 9.8.1 / GEOS 3.14.1.
- `fp_toolchain()` is called by 02, 03 and `fp_composition.R`; the publish layer (`stac_floodplains_bc`) never reads `run.toolchain`, so adding keys there cannot break publishing.
- `viol_split` requires every `KEYS_TOOLCHAIN` member on parsed records, so growing the set without a forward-only carve-out would fail every existing `provenance.json`.
- `fl_dem_aoi()` callers: 02, `attribute_tag.R`, the whole-FWA probe (anchor + dem modes). None passes `res` or `pipeline`.
- Decision context: #125 (2026-10-13) moves every region to whole network and retires the species items, so published species areas are not re-run here.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `diff -q` printed `git diff --no-index` usage | `diff` is a shell function wrapping git diff here; use `cmp` or `/usr/bin/diff` |
