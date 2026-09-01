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

## Phase 2: two bugs, both caught before the long run

**CRS mismatch.** The attribution layer is EPSG:3005 (BC Albers, inherited from the stream network);
the transition layer is EPSG:32609 (UTM 9N, from the landcover raster). `st_intersection` errors
outright, so this could not have shipped silently — but the *direction* of the fix could have.
`area_ha` was measured in the patch CRS, so watercourses must be transformed **to** the patches; the
reverse would leave the coverage check comparing areas from two projections and drifting against its
own denominator.

**The spec in #54 was wrong, and its own acceptance criterion caught it.** `overlap_frac` was
documented as the apportionment weight. It cannot be: watercourse rows overlap each other, so a patch
under three of them gets three rows each covering most of it, and `overlap_frac` sums to **2.31 per
patch** on MORR. Weighting by it gave **790.6 ha of tree loss against an ungrouped 431.9 -- 83% over**.

Two fractions are needed and only one is additive:

| column | meaning | per-patch sum |
|---|---|---|
| `overlap_frac` | what share of this patch does this watercourse cover? | **2.31 mean** |
| `apportion_weight` | what share of this patch is credited to it? | **1.000** (0.9998-1.0003) |

With the normalized weight it reconciles: apportioned **431.82** vs ungrouped **431.87 ha**, a
0.045 ha gap from two patches lying outside every attribution polygon. The three semantics separate
meaningfully on the Morice: **inclusive 75.0 >= apportioned 45.7 >= exclusive 14.7 ha**.

**The stated coverage invariant was wrong for the same reason.** "sum(overlap_ha) ~= area_ha" reports
~2.3x because the rows overlap. The meaningful check is the **union** -- `max(overlap_frac)` per
patch -- which is **0.966 mean** on MORR. The ~3% shortfall is patch boundaries and attribution
boundaries coming off different raster grids (UTM landcover vs Albers valley), not a lost join.

`bridge-check.R` asserts all of it, including a check that `overlap_frac` is **not** usable as a
weight -- if it ever sums to 1 the two columns have been conflated and the distinction the table
exists to make is gone.

## Phase 3: BULK confirms the thresholds generalise

| | MORR | BULK |
|---|---|---|
| patches | 2716 | **9045** |
| bridge pairs | 6612 | **19241** |
| watercourses carrying patches | 185 | **267** |
| union coverage | 0.9662 | **0.9646** |
| `overlap_frac` per-patch sum | 2.308 | **2.012** |
| apportioned vs ungrouped tree loss | 431.82 / 431.87 ha | **2073.21 / 2073.25 ha** |

Union coverage lands at **0.965 on both**, across areas 3.3x apart in patch count. The `>= 0.90`
guard threshold was set off a single observation and BULK shows it was not a lucky pick — the ~3.5%
shortfall is a stable property of the landcover and valley raster grids not aligning, not noise.
Reconciliation holds at scale: **-0.002%** on 2073 ha.

`overlap_frac` sums differ meaningfully between areas (2.31 vs 2.01), which is the point: how much
watercourses overlap is a property of the drainage, not a constant. Any design that assumed a fixed
relationship between the two fractions would have been wrong on one of these areas.

## How the run finally completed

Two harness-managed background runs were killed mid-flight, both under `caffeinate -s` with zero
in-band errors. `caffeinate` was never the problem: the harness owned the task and reaped it.
Relaunching **detached** (`nohup bash -c '...' & disown`) survived, and the run finished in ~8 min
rather than ~30 because the killed attempt had already cached the 2017 rasters.

The lesson is one this session had already learned once and I did not apply: a long run belongs
detached, not in a harness-managed background slot. I had started to hand the job to the user
instead, which was the wrong call -- it was within my power the whole time.
