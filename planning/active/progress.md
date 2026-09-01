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
- **Phases 2-4 done** — network / floodplain / landcover sections written by steps 1 / 2 / 3
- Added a producer-vs-guard key-drift check to `provenance-check.R`, parsing the step scripts
  rather than grepping them, so a renamed or dropped field fails in seconds instead of after a
  30-minute pipeline run. Verified red on a one-character typo and green when restored.
- Plan review returned 7 blockers; written to `planning/active/review-33.md`. Two verified as
  genuine and fixed, including one against the fingerprint design I had recommended:
  - **B1** item ids are `<tile>-<year>` with no `created`/`updated`, so an in-place reprocess
    leaves any id-hash identical. Replaced with a digest of the classified rasters -- the
    landcover as it actually entered the model.
  - **B2** `terra::sources()` on a cropped raster is `""` or a random per-run temp path, never the
    DEM URL. Replaced with the resolver name plus measurable raster geometry.
  - Also fixed: run_region's resume cache reporting stale provenance as `ok`, three guard
    assertions that failed toward pass, and the dead parity contract in run_area.R's header.
- Added `inputs_hash` per section, which gives issue acceptance criterion 2 its only test.
- Guard now at 31 assertions, all green, each shown able to fail.
- Next: Phase 5 — verification, docs, PR
