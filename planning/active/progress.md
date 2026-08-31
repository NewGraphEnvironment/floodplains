# Progress — patch<->watercourse bridge (#54) + prune stale layers (#55)

## Session 2026-08-31

- #48 merged as PR #56 (`7e52205`) before starting, so this branch is single-concern
- Scoped #55 by measurement: 6 legacy layers across 2 areas, not a fleet-wide sweep
- Found and discarded a `by_feature` bug in the stashed #54 draft; verified the correct
  `st_intersection`-on-sf idiom against a fixture
- Phases approved by user
- Created branch `54-patch-watercourse-bridge` off main
- Next: Phase 1 — the prune script
