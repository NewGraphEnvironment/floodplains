# Progress — Provenance records the recipe, not the cake (#65)

## Session 2026-09-02

- Plan-mode exploration: read the whole provenance stack (`fp_provenance.R`, `01`/`02`/`03`
  producers, `provenance-check.R`, `provenance_ab-compare.R`) and probed six premises live before
  proposing anything — see `findings.md`.
- Plan-agent design review returned 5 blockers / 13 gaps / 5 ordering findings. Verified the
  load-bearing ones directly rather than taking them at face value: the wrong `config_name`, the
  `$HOME` path inside hashed `inputs`, and `schema_version` being asserted nowhere all confirmed
  against the live file. Four of its findings changed the design — the network key, the
  pre/post-subset split, the declare-or-fail pair, and folding the `sha_source` fix in.
- User approved the plan, plus two scope decisions: fold landcover's `transition.tif` into the
  `outputs` work (one rollout, not two), and verify live on **neexdzii + bulk**.
- Created branch `65-provenance-records-the-recipe-not-the-ca` off main.
- Next: Phase 1 — digest primitives and guard scaffolding, offline.
