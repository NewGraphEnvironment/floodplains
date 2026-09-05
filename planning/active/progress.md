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
