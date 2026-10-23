# Progress — #145 model labeller on NECR

## Session 2026-10-23

- Plan-mode exploration; phases approved by user (audit subset = existing 48; threshold κ ≥ 0.7 both endpoints and change agreement ≥ 0.85; #113 decisions folded in)
- Measured before the gate: both NECR working copies hold 0 labels (480 / 48 rows); no `reference/necr/labels*.csv`
- Created branch `145-check-bulk-s-change-against-dated-imager` off main
- Scaffolded PWF baseline from issue #145 with approved phases
- Next: start Phase 1
- Phase 1: pre-registered the model labeller (roles, what the model sees and never sees, threshold, fail path) and folded #113's two decisions (rule 5 ±2 years; growth blinding accepted and reported) into `research/landcover_accuracy.md`, committed before any label. Plan review spawned in the background at 05:59Z.
