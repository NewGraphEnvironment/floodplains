# Progress — Modernize the README, publish via Pages, set description + homepage (#77)

## Session 2026-09-04

- Plan-mode exploration; a Plan subagent reviewed the draft against the issue and the codebase and
  returned 3 blockers, 4 ordering findings and 9 acceptance gaps. Its review is in
  `planning/active/review-77.md`; every finding was verified in this checkout before being folded
  in, and two changed the design outright (drop the elevation cross-section; build the figures
  from `data/bulk/` rather than the unrostered `neexdzii`).
- Phases approved by the user, with two content steers: tighten the prose to plain language, and
  reframe the disturbance section around the attribution framework being layer-agnostic — fire and
  harvest are what `config/disturbance.yml` lists today, not the limit of what it takes.
- Created branch `77-modernize-the-readme-publish-it-via-gith` off main
- Scaffolded the PWF baseline
- Next: Phase 1
