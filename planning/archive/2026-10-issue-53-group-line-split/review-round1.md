# Review round 1 — branch 53-floodplains-cross-watershed-group-bounda (#53, #138)

Scope: the diff `57e1a9a...HEAD` as given in review-prompt.md, with every changed file read from
disk, plus the unchanged callers of the functions the diff changed. These were checked and are fine:
fp_composition_premise() extraction (nothing after the split reads lc_rec/fp_rec);
fp_bridge_build's rowsum(reorder = FALSE) against !duplicated() order; .fp_poly_only on a GC holding
POLYGON + MULTIPOLYGON + LINESTRING (area 3 of 3, tested); FP_COMP_MAX_OVERLAYS headroom with in_wsg
added (k = 5); the env prefix on the `run` function in region_checks-run.sh (it reaches the child,
tested); the 03 AOI and drift's WKB-keyed cache; accuracy-module readers of the split scenario layer
(they use it only as an st_intersects / bbox AOI); review_build-qgis.R's (name_basin, patch_id) sort
(ties are stable on both sides); the neexdzii run_area.R/README claim (1.13 ha of tree loss, all of it
in name_basin-NA pieces with in_wsg FALSE, measured on data/neexdzii).

## Findings

- **[severity: bug]** scripts/floodplain_lcc/floodplain_probe-whole-fwa.R:162-164 — the #110 probe's
  step-2 replay sources `fp_region.R`, `fp_dem.R` and `02_floodplain_model.R`, then calls
  `fp_floodplain(cfg2, ...)`. `fp_floodplain()` now calls `fp_wsg_polygon(cfg, conn)`
  (02_floodplain_model.R:91) and `fp_wsg_split()` (lines 277, 386), which live in `fp_wsg.R`, and the
  probe never sources that file. The next `floodplain_probe-run.sh <area>` aborts at the replay
  with "could not find function fp_wsg_polygon". This is the case where a fix reaches only one of
  the callers sharing the code: run_area.R, attribute_tag.R and composition_build.R gained the
  source line, and this one did not. Fix: `source(file.path(lcc, "fp_wsg.R"))` beside line 162.

- **[severity: fragile]** scripts/floodplain_lcc/gpkg_backfill-split.R:111 and :199 — the header
  (lines 28-30) promises "a run killed half way is finished by running it again". One window breaks
  that. `fp_write_transition()` writes the transition layer and then the bridge in two separate
  `st_write`s. A run killed between them leaves the new, split transition layer beside the OLD
  `patch_watercourse_*` bridge, which has no `in_wsg` and is keyed on the clipped patches. On the
  re-run `do_trans` is FALSE, because the transition layer already has `in_wsg`, so the bridge is
  never rebuilt. The composition is rebuilt, because its own state is checked. A stale bridge
  describing a relation the layer no longer has is #55's orphan class, and bridge-check silently
  falls back to the pre-#53 key for it (`use_wsg` FALSE). Fix: decide the bridge from its own state,
  as the composition already is. Rebuild it when `attribute_by` is set and the bridge is absent or
  lacks `in_wsg`, even when the transition layer is already split.

- **[severity: fragile]** scripts/floodplain_lcc/gpkg_backfill-split.R:206-210 (with
  fp_provenance.R `fp_prov_set_outputs`) — several of `fp_prov_set_outputs()`'s refusals run only
  after every vector write: the split layers, the transition layer, the bridge, and the composition
  table plus its provenance sibling. Those refusals are: an `outputs_hash` that does not re-derive
  from its round-tripped outputs, no `landcover[scen]` outputs, an unparseable
  `run$datetime_utc`, and an unknown field. The pre-write gate at line 179
  (`fp_composition_premise`) covers none of them. If one fires, the gpkg holds the split layers
  while `outputs.transition_patches` still holds the clipped count. provenance-check 7c then FAILs
  the count, and every re-run refuses the same way, so the only way out is a restore from BACKUP.
  The plan review's O1 fix (premise before the first write) was applied to the composition but not
  to this record. Fix: run the same read-only checks (entry present, hash re-derives, stamp parses)
  before the backup and writes block, as the composition premise does.

- **[severity: fragile]** scripts/floodplain_lcc/fire_tag.R:91 (unchanged file) —
  `fp_disturbance_report(tagged, ...)` now sums every piece, including the `in_wsg` FALSE ground in
  a neighbouring group. That ground is 41.7% of PCEA's floodplain. The diff writes the rule into
  CLAUDE.md ("Readers of patch totals must filter to in_wsg for an item's own figure") and applies
  it to region_acceptance-report.R, but this other caller of the same report was left out, so its
  tree-loss and attribution shares now describe a different population from the acceptance logs'.
  The output goes to the console only, which is why this is not a bug. Fix: filter `tagged` to
  `in_wsg %in% TRUE` for the report when the column exists, as region_acceptance-report.R:184 does.

~/Projects/repo/floodplains/planning/active/review-round1.md
