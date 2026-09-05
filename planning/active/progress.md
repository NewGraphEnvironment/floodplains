# Progress — classified_*.tif carry 30 stray gdalcubes/NetCDF tags (#83)

## Session 2026-09-05

- Plan-mode exploration; phases approved by user, plus two gate decisions:
  in-place tag strip (not a re-run) for the 14 existing files, and `stop()`
  (not `warning()`) on a dirty write.
- Cause isolated from committed evidence rather than re-measured: the #79
  split-run log had already made terra the only unlevelled variable, and the
  tags split exactly on it (necr/kotl m4 1.9.11 dirty, bulk/lnth m1 1.9.34 clean).
- Blast radius swept across all 23 areas: 116 tifs, 14 dirty.
- Created branch `83-classified-tif-carry-30-stray-gdalcube` off main
- Scaffolded PWF baseline with approved phases
- Next: Phase 1 — pin the mechanism offline

## Session 2026-09-05 (continued)

- Phase 1 (26f809c -> 97dbd23): mechanism pinned; the repair route named at the gate rejected
- Phase 2 (7c3d80e): scripts/fp_raster.R; all three writeRaster sites routed through fp_rast_write
- Phase 3 (9449858): provenance-check.R section 5f (14 checks) + section 7 digest reconciliation
- Phase 4 (8308474): raster_strip-tags.R; 14 files repaired in necr and kotl; evidence log committed
- Phase 5: CLAUDE.md; drift#63 filed upstream; floodplains#84 filed for the STATISTICS_* finding
- Reviews: one Plan review (~30 findings) and two code-check rounds, folded in
- Next: PR
