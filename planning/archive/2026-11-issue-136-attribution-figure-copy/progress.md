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
- `/code-check branch`: rounds 1 and 2 Clean. Round 3 found the company site holds its own
  byte-identical copy of the old PNG (verified by git blob sha); the swap is already
  newgraphenvironment.github.io#66, now an owed item in task_plan.md
- Round 4: site #66 also wants "not yet attributed" gone, and the (unread until now) comment on
  #136 asks for it with "no mapped cause". Widened #136 (body edited), relabelled, rebuilt, re-rendered
  (Phase 4). A website session (PR #68 on the site) asked for the same and waits on the push
- Round 5: three prose mentions of the old label (CLAUDE.md split across two lines, plus comments
  in disturbance-check.R and fp_disturbance.R), fixed in 4b1313a. Inside round 4's fix, so the
  loop ended by enumeration: a multi-line grep for the old label leaves only planning records;
  `UNATTRIBUTED` is used by readme_functions.R and README.Rmd only (accuracy_estimate.R's is a
  comment word); every other reference to the figure quotes neither label nor subtitle

| Round | Findings | Fixed | Accepted | Inside previous fix? |
|-------|----------|-------|----------|----------------------|
| 1 | 0 | 0 | 0 | — |
| 2 | 0 | 0 | 0 | n |
| 3 | 1 | 1 | 0 | n |
| 4 | 1 | 1 | 0 | n |
| 5 | 2 | 2 | 0 | y (round 4's relabel) |
