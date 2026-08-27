# Progress — Add a columbia region (KOTL/LARL/SLOC) (#36)

## Session 2026-08-27

- Plan-mode exploration; phases approved by user (bt only; scope runs through publish)
- Verified species resolution, disturbance coverage, and the publish path against the live DB
  before writing any config — see `findings.md`
- Mid-plan discovery: `fresh_default` gained KOTL/LARL/SLOC during exploration, turning the run
  from a BUILD into a GRAB and surfacing the freshness-guard calibration finding
- Created branch `36-add-a-columbia-region-kotl-larl-sloc-bul` off main
- Next: Phase 1 — `network_source`/`network_guard` pass-through, then `columbia.yml`
