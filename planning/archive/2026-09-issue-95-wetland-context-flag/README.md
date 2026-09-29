## Outcome

`config/disturbance.yml` gained a `context:` list of undated overlays, tagged onto change patches
by the same code as the `sources:` causes and structurally unable to explain change. The first is
`in_wetland` + `waterbody_poly_id` from FWA wetlands.
- `fp_disturbance_validate()` enforces the split at config load.
- `fp_disturbance_report()` refuses context entries and untagged patches.
- The README figure reads `sources:` only.
- `fire_tag.R` now re-tags the published layer in place instead of writing #55's `_disturbance`
  orphan, and refuses the write if any cause column would move.

Reviews found five pre-existing defects on the path wetlands now take, all fixed with must-fail
arms:
- carried attributes joined on a `patch_id` that repeats across sub-basins
- all-NA carries written Boolean (live in five areas)
- a missing carry silently dropped
- AOI boxes losing edge strips on reprojection
- `$` partial-matching

The lesson worth keeping: **a check that reads both sides through the same reader cannot see what
that reader does.** The first live re-tag turned every POLYGON into a MULTIPOLYGON (`st_read`'s
`promote_to_multi` default), and the WKB comparison passed because it read both sides promoted. The
data was restored from byte copies taken before the run, and the check now reads the schema from the
GeoPackage's own tables.

## Measurement

- **NECR FWA wetlands vs the `ch_ff04` floodplain:**
  - 4,495 polygons, 16,291.8 ha, of which 6,290.3 ha (**38.6%**) lies inside the floodplain
  - wetland is **15.9%** of the 39,651.5 ha floodplain
  - This falsified a draft comment claiming most wetland already sat inside it.
- **`in_wetland` after re-tag:**
  - NECR: 1,820 patches, 2,482.8 ha (53% of its 4,712.6 ha of change; a patch is flagged when it
    touches a wetland)
  - BULK: 1,231 patches, 1,252.4 ha
- **Cause columns identical before and after on both areas.**
  - NECR tree loss 1,943.2 ha: fire 565.6 / harvest 588.9 / residual 886.3 ha
  - BULK tree loss 1,565.1 ha: fire 66.1 / harvest 509.8 / residual 1,025.4 ha
  - BULK's README figure is unchanged apart from its subtitle.
- **`st_make_valid()` rewrites valid geometry:** 0 of 5,692 NECR patches were invalid, and all
  5,692 were rewritten.
- **Promotion damage, before restore:** NECR 3,947 of 5,692 geometries, BULK 5,024 of 7,161.
- **Review cost:** 8 agents in total (plan review, 3 + 2 code-check rounds, 1 docs round). Two
  loops ended by enumeration, after a round found a defect inside the previous round's fix.

## Evidence

No run logs. Live results were checked by `scripts/floodplain_lcc/disturbance-check.R <area>
<snapshot.rds>`, with snapshots taken by its own `snapshot` mode. The per-round findings are the
`review-*.md` files in this directory.

Closed by: PR for #95 (branch `95-wetland-context-flag-on-transition-patch`)
