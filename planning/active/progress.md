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

### Phases 1-5 landed (offline)

- `4740702` Phase 1 — digest primitives, the `outputs` sibling, guard scaffolding.
- `29b0c00` Phases 2-5 — the three producers, the declared key sets, the config-name property, the
  schema-version property, the A/B outputs comparison.
- `d51de16` Round-1 review fixes (below).

### Round-1 review — two real bugs, both silent

Verified by reproduction before acting, per convention. Both confirmed:

1. **`fp_table_content_sha256` sorted by the KEY**, so rows sharing a composite key kept database
   row order and the digest was a function of it. 01's SELECT has no `ORDER BY`. Fixed by sorting
   the composed line; measured to move no digest already recorded, because for a unique key the two
   orderings give the same permutation.
2. **`fp_prov_set`'s outputs-only refusal read `value$inputs`**, and `$` partial-matches, so an
   entry carrying `inputs_hash` and no `inputs` resolved to the hash and passed the guard written
   for exactly it.

Also fixed: a non-numeric column is now refused rather than rendered by a second branch
(RPostgres' `bigint="character"` mode could otherwise pick the rendering); §5d's mutation counts
re-measured (3 / 1 / 0 / 5, the old 2-and-3 having gone stale the moment #65's own assertions
landed).

**Not reproduced, and recorded as such:** the reviewer flagged `sprintf("%.6f")` as LC_NUMERIC-
dependent. Measured — R forces LC_NUMERIC to C and warns on a change, and sprintf was unmoved
under `de_DE.UTF-8`. No fix; the claim is wrong for R.

### Phase 6 in flight

Baseline captured BEFORE any run (`/tmp/fp65/baseline.txt`), so parity is checkable rather than
asserted. Pass A of neexdzii completed clean (0 in-band errors, provenance rewritten after the
marker) and every artefact reproduced its baseline digest exactly — 673.5 km, 142.82 km², all four
raster digests unchanged. The change is output-neutral.

**The split test already reproduced, and it cost nothing to run.** neexdzii and bulk are both
`fresh` GRABs on WSG BULK, one subset and one whole group. neexdzii's PRE-subset digest is
`37edc39d…`, byte-identical to bulk's whole-WSG network digest; its POST-subset digest is
`fa4d47ea…`, its own. That is exactly what the pre/post placement claims, measured rather than
argued.

`link_config_name` now reads **`bcfishpass`** (source `link_log`), where it read `default` before.

Three runs are now in flight against the FINAL code — neexdzii twice for the A/B, then bulk. `scripts/`
must not be edited until they finish, or pass 1 and pass 2 would be running different code.
