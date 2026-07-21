# Progress — Config-driven disturbance attribution (#19)

## Session 2026-07-20

- Plan-mode exploration + Plan-agent design review — phases approved by user
- Plan-agent caught the harvest-layer bbox-prefilter blocker, the in-memory-vs-re-read parity risk,
  the missing DB conn in fp_lulc, and the hardcoded change interval — all folded into the plan
- Confirmed harvest layer (bcdata b1b647a6-…, HARVEST_START_YEAR_CALENDAR) via bcdata
- Created branch `19-config-driven-layer-agnostic-disturbance` off main
- Scaffolded PWF baseline from issue #19 with approved phases
- Next: start Phase 1 (fp_disturbance.R + config/disturbance.yml + change_interval, fire parity)
