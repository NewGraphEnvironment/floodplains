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
- [ ] `scripts/floodplain_lcc/gpkg_prune-legacy.R <area>` — `gpkg_backfill-wsg.R` shape: idempotent,
      removes only an explicit list of known-legacy names, prints removed + left
- [ ] Never touch a layer not on the list
- [ ] Run on morr and bulk; the other 18 report nothing to do
- [ ] Re-run: removes nothing the second time

## Phase 2 — The bridge (#54)
- [ ] Rewrite around `st_intersection()` on sf objects (one row per intersecting pair, spatial index)
- [ ] `overlap_frac = overlap_ha / area_ha`, capped at 1
- [ ] Drop zero-area pairs (shared boundary = join artefact, not a relationship)
- [ ] No `attribute_by` => no bridge, step 3 unchanged
- [ ] Written in step 3 where `fp_file` and `trans_polys` are already in scope

## Phase 3 — Test on BULK
- [ ] `Rscript scripts/run_area.R bulk 2,3`; gate on error markers AND output mtime
- [ ] Confirm the label column attaches on a second area (MORR was 33 of 340)

## Phase 4 — Assert the invariants
- [ ] `scripts/floodplain_lcc/bridge-check.R` — guard idiom, no database
- [ ] Coverage: per-patch `sum(overlap_ha)` ~= `area_ha` (catches a silently-wrong join)
- [ ] Apportioned tree loss sums to the ungrouped total
- [ ] Inclusive >= apportioned >= exclusive
- [ ] No geometry duplication: transition row count unchanged

## Phase 5 — Docs + close
- [ ] `CLAUDE.md`: two orthogonal explosions + the bridge, three semantics named
- [ ] `README.md`: the bridge as a published output
- [ ] `/planning-archive`, `/gh-pr-push`

## Validation
- [ ] `bridge-check.R` green on MORR and BULK
- [ ] Apportioned reconciles to ungrouped total on both
- [ ] `gpkg_prune-legacy.R`: one transition layer per scenario per span; second run a no-op
- [ ] No `attribute_by` => `floodplain_landcover.gpkg` byte-identical
- [ ] `/code-check` clean per commit
