# Task: Patch<->watercourse bridge (#54) + prune stale transition layers (#55)

The floodplain is exploded two ways and nothing relates them: `<scenario>_by_blue_line_key`
(340 rows, **overlapping** by design, #40) and `transition_<scenario>_2017_2023` (2716 rows,
**disjoint**, unique `patch_id`). Neither answers "how much tree loss belongs to the Morice?"
without a join the consumer invents — and the naive version overcounts by up to **94%**, because
attribution rows sum to 795.8 km2 over a 411.1 km2 floodplain.

Alongside it, `floodplain_landcover.gpkg` publishes stale transition layers beside the current one
with no way to tell which is live. Both gate a clean STAC rebuild; both are structural fixes to the
same file.

## Phase 1 — Prune the stale layers (#55)
- [x] `scripts/floodplain_lcc/gpkg_prune-legacy.R <area>` — `gpkg_backfill-wsg.R` shape: idempotent,
      removes only an explicit list of known-legacy names, prints removed + left
- [x] Never touch a layer not on the list
- [x] Run on morr and bulk; the other 18 report nothing to do
- [x] Re-run: removes nothing the second time

## Phase 2 — The bridge (#54)
- [x] Rewrite around `st_intersection()` on sf objects (one row per intersecting pair, spatial index)
- [x] `overlap_frac = overlap_ha / area_ha`, capped at 1
- [x] Drop zero-area pairs (shared boundary = join artefact, not a relationship)
- [x] No `attribute_by` => no bridge, step 3 unchanged
- [x] Written in step 3 where `fp_file` and `trans_polys` are already in scope

## Phase 3 — Test on BULK
- [x] BULK step 2 + 3 complete; bridge written (19241 pairs, 9038 patches, 267 watercourses)
- [x] Second area confirms union coverage generalises: 0.9646 vs MORR 0.9662

## Phase 4 — Assert the invariants
- [x] `scripts/floodplain_lcc/bridge-check.R` — guard idiom, no database
- [x] Coverage — **corrected**: the sum is ~2.3x because rows overlap; the real check is the
      union, `max(overlap_frac)` per patch (0.966 on MORR)
- [x] Apportioned tree loss sums to the ungrouped total
- [x] Inclusive >= apportioned >= exclusive
- [x] No geometry duplication: transition row count unchanged

## Phase 5 — Docs + close
- [x] `CLAUDE.md`: two orthogonal explosions + the bridge, three semantics named
- [x] `README.md`: the bridge as a published output
- [x] `/planning-archive`, `/gh-pr-push`

## Validation
- [x] `bridge-check.R` green on MORR and BULK (7/7 each)
- [x] Apportioned reconciles on both (MORR 431.82/431.87; BULK 2073.21/2073.25 ha)
- [x] `gpkg_prune-legacy.R`: one transition layer per scenario per span; second run a no-op
- [x] No `attribute_by` => no bridge written (opt-in by config presence)
- [x] `/code-check` clean per commit
