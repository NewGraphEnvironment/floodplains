# #64 — the landcover digest hashed the container, not the landcover

**Closed 2026-09-02.** #63 measured two machines producing identical rasters and different digests.
This replaced the file hash with a content digest, and found along the way that the issue's own
premise and its stated root cause were both wrong.

## Measurement

**The defect.** `fp_file_sha256()` hashed the GeoTIFF file. Across m1 and m4 on the identical
commit and the same database: **28,291,615 cells per year, zero differing**, three different
digests — a constant +10,028 bytes, all of it TIFF tag 42112 (`GDAL_METADATA`), 382 bytes under one
terra and 5,396 under the other.

**The fix.** `fp_raster_content_sha256()` digests a geometry header plus per-block hashes of cell
values, streamed in fixed 512-row blocks. Measured: 1.16 s for 28.3M cells; agrees across machines
on all three years where the file hash does not; still moves on one changed cell and on one cell
becoming nodata. `block_rows` is a contract, not a knob — the digest is over per-block hashes, and
deriving it from `terra::blocks()` or free memory would make the digest machine-dependent, the
defect being fixed. Streaming matters at BULK: 11552 × 14651 = 169.3M cells, 1.35 GB read whole
against ~47 MB per block.

**Two premises corrected by measurement.**

1. **#64 said the digest is published as `nge:landcover_key`. It is not.** The publisher maps that
   key to `inputs$item_hash` — a hash over the STAC **item ids**, which #33 established cannot
   detect an upstream in-place reprocess (io-lulc ids are `<tile>-<year>`, no `created`/`updated`).
   CLAUDE.md's "should be the raster digest" has never been true of what ships. Filed as
   `stac_floodplains_bc#40`; not wired, because the coupling is one-way by design.
2. **The root cause was not the terra version.** Attributing the storage-mode split to 1.9.34 vs
   1.9.11 was never isolated. Measured on **one** terra reading the **same** file:
   ```
   GDAL_PAM_ENABLED unset -> double,  NaN 324891
   GDAL_PAM_ENABLED=NO    -> integer, NA  324891
   ```
   The PAM `.aux.xml` sidecar flips it — and the two sides of #63's comparison differed exactly
   that way, since the m4 copies were `scp`'d without their sidecars. GDAL writes that sidecar as a
   side effect of anyone opening the file, so the storage type depends on who has looked at it.

**The normalization, and an honest correction.** `v[is.na(v)] <- NA_real_` is the load-bearing line;
`as.double()` beside it is subsumed, because assigning a double promotes the vector whatever the
index selects. The code says so rather than claiming two independent guards. The gap is invisible to
`all.equal()`, to `!=` with `na.rm`, and to matching NA counts — only `identical()` separates them.

## The wrong turns, kept

- **The guard passed with the fix deleted.** §5c read both fixtures with the same terra in one
  process, so the storage-type axis never varied. Two reviewers found it independently. Closed by
  §5d, which asserts the property on plain vectors with no GDAL at all.
- **Then the same class recurred three times, one axis over each round**: round 2 found the
  serialization pin's guard couldn't fail and `SECTIONS_WITH_RASTERS` was a coincidence; round 3
  found `KEYS_TOOLCHAIN` on the line above still was. It ended by **enumeration** — every literal
  key set checked for what pins it, which surfaced a fourth instance (`KEYS_LINK_LOG`, pre-existing
  since #33) and showed the two remaining literals are correct as literals.
- **Three of my own fixtures could not reach their own property**: a `block_rows` comparison of
  512 vs 256 on a 40-row raster; an all-NA toolchain listing 3 of 5 keys so a different arm fired;
  and a NULL-valued year asserted against the wrong arm's message.
- **`on.exit()` at a script's top level never fires** — I introduced it in §5c despite CLAUDE.md
  documenting the trap, and the same trap was live and pre-existing in §5b, leaving `TZ=UTC` set for
  the rest of the process. Both fixed.
- A commit message lost a code span to backtick command substitution in `git commit -m`. Amended.

## What landed

`fp_raster_content_sha256()` + `fp_norm_block()` + `fp_toolchain()`; the field renamed to
`classified_content_sha256`; terra/sf/GDAL/GEOS/PROJ recorded in **`run`**, never `inputs` — a
version that legitimately differs between machines would reintroduce the churn this removes, one
field over, and the three floodplain `inputs_hash` values were verified byte-identical across a
re-run that added the block. `provenance-check.R` grew §5c, §5d, a `run`-half producer scanner and
four coverage arms: **76 assertions**, each shown able to fail.

## Follow-ups

`stac_floodplains_bc#40` (publish the raster digest instead of `item_hash`), #70 (the floodplain
delineation is pinned only by its parameters — `floodplain_<scenario>.tif` has no content digest).

## Evidence

- `scripts/floodplain_lcc/logs/runs/20260902_*_run-area_neexdzii_*` — the run logs (gitignored).
- `findings.md` here carries the per-phase measurements; `review-round[1-3].md` the review rounds.
- The cross-machine check is re-derivable: `fp_raster_content_sha256()` on any two copies of the
  same classified raster.
