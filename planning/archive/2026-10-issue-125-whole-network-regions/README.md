## Outcome

`run_region.R` gains a `network: whole` region mode (#125). Every group in such a region runs as
`species: all`, the whole stream network at order >= 2 (#104): the species pre-pass is skipped and
replaced by a segment count in `network_source`. The region owns `species`, `attribute_by` and
`min_order`, and may convert a species area in place, while a species region still refuses `all`
in both directions.

All four region files moved to whole mode. KISP folded into `skeena.yml`, DUNC joined
`columbia.yml`, and Columbia's `network_guard: warn` was dropped. Skeena was then run live.

The review loop's main lesson was about the resume cache. Files sitting together on disk are not
one run: steps 1, 2 and 3 write their records at different times. Three code-check rounds each
found a hole in the previous fix:
- `reg$network` partial-matching `network_source`;
- a one-run reconciliation signal;
- a marker left beside rewritten records.

It ended by enumerating every writer of the records the cache reads (`findings.md`). The plan
review also found that publishing freezes until stac_floodplains_bc#75: stac stages from this
working tree and refuses `all_*` provenance keys.

## Measurement

- **Whole-network km (order >= 2) equal bcfp to the km in all 23 region groups** in their
  region's schema (measured 2026-10-13). That includes MCGR (2,833 km) and PINE (5,768 km), so
  #76's blocks were species-network only.
- **Skeena run 2026-10-14, flooded 0.7.0:**

  | | BULK | MORR | KISP |
  |---|---|---|---|
  | `all_ff04` | 660.0 km² | 479.3 km² | 324.4 km² |
  | wall time | 59.0 min | 15.7 min | 24.0 min |

  Peak was ~16.5 GiB (summed R RSS, 30 s samples). DEMs fetched in 19–37 s, against #122's
  ~37 min on a slow day.
- **`composition-check.R`'s 1% change-vs-patch bound fails in all three** (+1.47 / +4.40 /
  +1.27%). Change cells inside the group polygon equal the patch totals exactly, so it is the #53
  edge effect: 2.0% of BULK's floodplain lies past its polygon. The guard was not loosened.
- **Mutation table:** 13 restored defects, every one turning a check red (`findings.md`). The
  first version of one arm passed for the wrong reason (M5), which a reviewer also caught.

## Evidence

- `scripts/floodplain_lcc/logs/20261014_whole_network_skeena.md`
- run logs `data/logs/region_skeena_*_20261014_123741*` (gitignored)
- review files `review-plan.md` and `review-round*.md` in this directory

Closed by: PR (Relates #125; the Fraser, Peace and Columbia runs remain)
