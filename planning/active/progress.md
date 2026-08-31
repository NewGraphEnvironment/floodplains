# Progress — patch<->watercourse bridge (#54) + prune stale layers (#55)

## Session 2026-08-31

- #48 merged as PR #56 (`7e52205`) before starting, so this branch is single-concern
- Scoped #55 by measurement: 6 legacy layers across 2 areas, not a fleet-wide sweep
- Found and discarded a `by_feature` bug in the stashed #54 draft; verified the correct
  `st_intersection`-on-sf idiom against a fixture
- Phases approved by user
- Created branch `54-patch-watercourse-bridge` off main
- Next: Phase 1 — the prune script

## Session 2026-08-31 (cont.)

- Phase 1 done: 6 legacy layers pruned across morr + bulk, idempotent, 18 areas clean (`2aa21f1`)
- Phase 2 done: bridge written; two bugs caught before the long run — a CRS mismatch, and the
  `overlap_frac`-as-weight spec error that overstated tree loss by 83% (`009e4c7`)
- Phase 4 guard written; **MORR green 7/7** through the real pipeline
- Phase 5 docs done
- BULK: step 2 + attribution landed (428 watercourses); the background run was killed during
  `co_ff06`. Step 3 (~30 min) is all that is outstanding for the BULK bridge
- Next: finish BULK step 3, then archive + PR
