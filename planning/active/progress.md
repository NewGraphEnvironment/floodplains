# Progress — Record run provenance per area (#33)

## Session 2026-09-01

- Plan-mode exploration — two Explore agents over the pipeline drivers and over
  `link`/`drift`/`flooded` provenance APIs; live STAC probe against Planetary Computer
- Four design decisions taken by the user: item ids over cache key, one merged
  `provenance.json` per area, JSON only (#52 stays separate), forward-only (no backfill)
- Created branch `33-record-run-provenance-per-area` off main
- Scaffolded PWF baseline from issue #33 with approved phases
- Next: Phase 1 — `fp_provenance.R` writer + `provenance-check.R` guard
