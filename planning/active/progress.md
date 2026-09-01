# Progress — Record run provenance per area (#33)

## Session 2026-09-01

- Plan-mode exploration — two Explore agents over the pipeline drivers and over
  `link`/`drift`/`flooded` provenance APIs; live STAC probe against Planetary Computer
- Four design decisions taken by the user: item ids over cache key, one merged
  `provenance.json` per area, JSON only (#52 stays separate), forward-only (no backfill)
- Created branch `33-record-run-provenance-per-area` off main
- Scaffolded PWF baseline from issue #33 with approved phases
- **Phase 1 done** — `fp_provenance.R` + `provenance-check.R`, guard green with every assertion
  shown able to fail
- Three defects found by the guard while writing it, all fixed in the writer rather than the test:
  a checkout SHA recorded for a different installed version, a version string accepted as a
  RemoteSha, and duplicate keys from `c()`. A fourth — `$` partial-matching `link_log` to
  `link_log_note` — is pinned by its own premise assertion.
- Next: Phase 2 — step 1 network section
