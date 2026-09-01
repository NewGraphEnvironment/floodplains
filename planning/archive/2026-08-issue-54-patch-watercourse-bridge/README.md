## Outcome

The floodplain is exploded two incompatible ways — per watercourse (**overlapping** by design, #40)
and per change patch (**disjoint**) — and nothing related them, so "how much tree loss belongs to the
Morice?" had no answer that was not a join the consumer invented. The naive version of that join
overcounts by up to 94%. This ships the relation as a non-spatial
`patch_watercourse_<scenario>_<span>` table beside the patches, one row per (patch, watercourse) pair,
so patches stay canonical and undupilcated and the many-to-many is explicit.

**The design error was in the issue spec, and its own acceptance criterion caught it.** #54
documented `overlap_frac` (overlap_ha / area_ha) as the apportionment weight. It cannot be: the
watercourse rows overlap each other, so a patch under three of them gets three rows each covering
most of it, and `overlap_frac` sums to ~2.3 per patch. Weighting by it gave **790.6 ha of tree loss
against an ungrouped 431.9 — 83% over**. Two fractions are needed and only one is additive:
`overlap_frac` answers "what share of this patch does this watercourse cover", `apportion_weight`
normalises within the patch to sum to exactly 1. Both ship. The stated coverage invariant
("sum(overlap_ha) ≈ area_ha") was wrong for the identical reason; the meaningful check is the
**union**, `max(overlap_frac)` per patch.

**Two areas, and the second one earned its keep.** MORR and BULK are 3.3x apart in patch count
(2716 vs 9045) yet union coverage lands at **0.9662 and 0.9646** — so the `>= 0.90` guard threshold,
set off a single observation, was not a lucky pick, and the ~3.5% shortfall is a stable consequence
of the landcover and valley raster grids not aligning. Reconciliation held at both scales
(-0.010% and -0.002%). Meanwhile `overlap_frac` per-patch sums differ between them (2.31 vs 2.01),
which is the point: how much watercourses overlap is a property of the drainage, not a constant.

A CRS mismatch (Albers attribution vs UTM patches) would have errored on first run; the subtler risk
was fixing it in the wrong direction, since `area_ha` was measured in the patch CRS and transforming
the other way would have left the coverage check drifting against its own denominator.

**#55** swept 6 legacy transition layers across morr and bulk — orphans stranded when disturbance
attribution stopped writing `_disturbance`/`_fire` siblings. They were not stubs: BULK's carried
9,045 rows each, matching the current layer exactly, which is why they went unnoticed. This is the
flip side of #23's per-layer writes rather than a bug in them, so it wants an explicit sweep;
`gpkg_prune-legacy.R` removes only an explicit name pattern and verifies its own work.

Also corrected a stale `CLAUDE.md` line describing the `tile_size` benchmark as ongoing three weeks
after #8 closed with a clear negative — which led to recommending a knob that measurement had already
ruled out (tiling is 6.3x *slower*).

Closed by: PR #57
