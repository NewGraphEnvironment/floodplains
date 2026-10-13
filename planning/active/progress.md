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
