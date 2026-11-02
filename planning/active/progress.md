# Progress — fig/attribution.png: the subtitle is written for the analyst, not the reader (#136)

## Session 2026-11-02

- Plan-mode exploration — phases approved by user
- Created branch `136-fig-attribution-png-the-subtitle-is-writ` off origin/main
- Scaffolded PWF baseline from issue #136 with approved phases
- Next: start Phase 1
- Plan review (Plan agent) in `review-plan.md`: its blocker was the scp in flight (all three
  gpkgs match m1 by sha256); its gaps folded into task_plan.md
- Phase 1: both subtitles dropped from `fp_fig_attribution()`, comments reworded
- Phase 2: rebuilt `fig/attribution.png` on m4 from m1's gpkgs; read back with no subtitles and
  the bar unchanged at fire 66 ha 4% / harvest 474 ha 30% / not yet attributed 1025 ha 66%.
  Copied gpkgs removed
- Phase 3: README.md unchanged; index.html differs only in the embedded PNG (diff with payloads
  masked is empty). Determinism check OK; content check OK, links included (`CHECK_LINKS=1`)
