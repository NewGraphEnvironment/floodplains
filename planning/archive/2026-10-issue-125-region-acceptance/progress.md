# Progress — Whole-network floodplains for every region (#125)

## Session 2026-10-17

- Plan-mode exploration — phases approved by user (close #125 on merge; QGIS look as its own issue)
- Created branch `125-region-acceptance-fraser-peace-columbia` off main (the issue's default slug
  names the branch PR #132 already merged)
- Scaffolded PWF baseline from issue #125 with approved phases
- Next: start Phase 1
- Phase 1: `region_checks-run.sh` reproduced the Skeena checks table; mutation table in findings.
  Fraser, Peace, Columbia: provenance PASS in all 20, `dem_cache-check.R` PASS, the `all_ff04`
  disturbance section PASS in all 20. There are three unexpected FAILs, each diagnosed in findings
  and each to get an issue: NECR composition (5), where the accuracy module is bound to
  `area.yml`; and the bridge union proxy on PCEA, LARL and SLOC, which is the check's weighting,
  not lost ground.
- Phase 2: `region_acceptance-report.R` reproduced Skeena, apart from 0.7 ha in BULK's outside share
  (cell centre against an unrecorded hand method). The outlier screen flagged PCEA (41.7% outside:
  the Williston Reservoir spill).
- Commits: 9f76112 (scripts), this one (findings, stdout fix)

## Session 2026-10-18 (UTC)

- GitHub reachable again 01:28 UTC after ~7 h of TLS timeouts.
- Phase 3: flooded 0.8.2 was already installed (11:00 UTC on 10-17), so the Phase 1 checks ran on it; verdicts unaffected (findings). `habitat_join-query.R` on all 20 groups, 01:30-02:24 UTC, all `ok`: every floodplain cell attributed; habitat rows all matched except KOTL/LARL/SLOC (21/35/10 per species), from link 0.66.0 rebuilding `fresh_default` on 2026-10-17. Recorded in #123.
- `region_config-check.R`, `whole_network-check.R`: exit 0.
