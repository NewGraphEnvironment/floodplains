# Progress — Cache the step-2 DEM per area (#122)

## Session 2026-10-13

- Plan-mode exploration — phases approved by user (driver-owned URL chosen over flooded#58 / flooded `cache=`)
- Created branch `122-cache-the-step-2-dem-per-area-nrcan-s-s3` off main
- Scaffolded PWF baseline from issue #122 with approved phases
- Next: start Phase 1
- Phase 1: `fp_dem.R` (key, HEAD with Last-Modified + ETag, cache) and `dem_cache-check.R` (offline PASS, 0 failures). Mutations proven: dropping the hit digest check, dropping ETag or sf PROJ from the key each turn a check red; an FLT4S write aborts on the round-trip guard. ETag added to the key beside Last-Modified (the HEAD returns both). FLT8S, as the probe found: the bilinear warp is double in memory.
