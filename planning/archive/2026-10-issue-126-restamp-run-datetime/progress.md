# Progress — PR #85's in-place repair left run.datetime_utc behind the rasters (#126)

## Session 2026-10-12

- Plan-mode exploration — phases approved by user
- Decision at the plan gate: re-stamp to the repair time AND record `run.repairs` (user)
- Created branch `126-pr-85-s-in-place-repair-left-run-datetim` off main
- Scaffolded PWF baseline from issue #126 with approved phases
- Next: start Phase 1
- Plan review (Plan agent) landed: 1 blocker (fp_prov_set round trip moves inputs_hash on every
  live entry; already avoided), gaps G1-G4, ordering O1-O3, assumptions A1-A5. Saved to
  review-plan.md and folded into task_plan.md.
- Phase 1 + reconcile function: `fp_prov_lc_rasters`, `fp_prov_late_rasters`, `fp_prov_restamp`
  (edits run in place, verifies the file on disk, restores bytes on mismatch),
  `fp_prov_reconcile_late`. provenance-check.R 5g (offline, 30+ arms) and a 7c live arm.
- Live must-fail captured before any write: necr and kotl FAIL on exactly the late-raster arm
  (7 classified each); bulk and lnth pass.
- Mutation table (scratch copy): digest, backfill, stray-tag, no-digest, mtime floor and
  forward-only mutants each turn 5g red.
- Phase 2: raster_strip-tags.R tracks flagged/repaired paths and runs the reconcile for every
  landcover entry before its exit; `BACKFILL=1` opts in to re-stamping an earlier run's repair.
- Phase 3 (live): necr 19:14:08Z -> 22:44:28Z, kotl 19:46:31Z -> 22:47:07Z. The parsed comparison
  matches the snapshot outside `run`, the second run leaves the md5 unchanged, provenance-check
  passes on both, and stac's guard passes on both (it stops on the pre-backfill necr snapshot).
  Without BACKFILL the run refuses and leaves the md5 unchanged; bulk reports `current`, md5
  unchanged. Log: scripts/floodplain_lcc/logs/20261013_provenance_restamp_necr-kotl.md
- Phase 4: CLAUDE.md #83 bullet updated. The issue table matched the measured stamps exactly, so the issue body was not edited.
- /code-check branch, three rounds (review-round{1,2,3}.md):
  R1 2 findings (repair recorded sf's GDAL, not terra's; one entry's error aborted the loop).
  R2 2 findings: re-stamping could switch off fp_composition's step-2-re-run guard (fixed: refuse
  against the step-3 time); R1's tryCatch missed fp_prov_read one line over (inside a fix, so an
  enumeration was needed; every raising call in the block enumerated).
  R3 no bugs: unparseable floodplain stamp read as "none" (fixed with a must-fail arm); the reader
  enumeration of run.datetime_utc covered 11 readers across both repos. Loop ended by enumeration:
  every NA branch in the new code stops or refuses.
