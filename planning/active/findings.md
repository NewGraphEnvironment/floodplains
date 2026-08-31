# Findings — patch<->watercourse bridge (#54) + prune stale layers (#55)

## #55 is 2 areas, not 20

| area | current transition layers | legacy |
|---|---|---|
| morr | 2 | **4** |
| bulk | 1 | **2** |
| the other 18 | 1 | **0** |

6 layers total — exactly the two areas where fire/disturbance tagging was run through the standalone
CLI wrappers, which matches the #19 history. The issue implied a fleet-wide sweep; it is not one.

## The stashed draft had a bug, caught before running it

It passed `by_feature = TRUE` to `st_intersection`, which takes no such argument — swallowed by
`...`, so the call would have computed a **cross product** of the paired vectors instead of pairwise
intersections. Verified no `st_intersection` method accepts it. With ~5k candidate pairs that is 25M
geometry operations: it would hang or return garbage, and nothing would have errored.

## The correct idiom is simpler than the draft

`st_intersection()` on two **sf data frames** returns one row per intersecting pair with attributes
from both sides, using the spatial index:

```
  patch_id blk overlap      <- patch 2 appears twice, once per overlapping watercourse
         1 111       2
         2 111       4
         2 222       4
         3 222       4
```

That is the bridge in one call. The hand-rolled `st_intersects` + index juggling is dropped entirely.

## Why the relation cannot be a column

Attribution rows overlap deliberately (#40): 795.8 km2 of rows over a 411.1 km2 floodplain, **94%
inflation**. A patch on shared ground belongs to several watercourses at once, so a single
`blue_line_key` column would force a choice that destroys the overlap #40 exists to preserve — and
invites `st_join(largest = TRUE)`, which our own `code-check.md` documents as ignoring the join
predicate.

`overlap_frac` is what makes the three consumer semantics available instead of one silently imposed:
inclusive (every patch touching a river), apportioned (weight by frac, sums to the basin total),
exclusive (frac == 1).

## BULK is a genuine second test case

`config/bulk/area.yml` already carries `attribute_by: blue_line_key` from the #48 merge, but
`data/bulk/floodplain.gpkg` holds only `co_ff02/04/06` — no attribution layer yet. So a BULK run
exercises attribution -> bridge end to end on an area whose numbers were never used to design any of
this. Its network predates the link rebuild, so the run validates the **code**, not publishable
numbers.

## Phase 1: pruned

| area | removed | kept | current transition layer(s) |
|---|---|---|---|
| morr | 4 (`ch_ff06`/`co_ff04` x `_fire`/`_disturbance`) | 14 | `transition_ch_ff06_2017_2023`, `transition_co_ff04_2017_2023` |
| bulk | 2 (`co_ff04` x `_fire`/`_disturbance`) | 4 | `transition_co_ff04_2017_2023` |

Second run on both: "nothing to prune". All 18 other areas: "nothing to prune". Backups of both
gpkgs taken before the destructive run, since these are published assets.

The stale layers were substantial, not stubs — BULK's carried 9,045 rows each against a current
layer that is also 9,045. Identical row counts are exactly why they were easy to miss: nothing about
them looked wrong, they were simply produced by a superseded code path.
