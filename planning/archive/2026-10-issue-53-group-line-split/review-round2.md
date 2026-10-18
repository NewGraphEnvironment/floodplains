# Review round 2 — branch 53-floodplains-cross-watershed-group-bounda (#53, #138)

Scope: the diff `57e1a9a...HEAD` from review-prompt-round2.md. I read every changed file from disk,
plus the unchanged callers of the changed functions, and checked round 1's four fixes (94867fc) and
00f714d.

What I ran, all read-only on the repo and `data/`:
- offline `wsg_split-check.R`, `composition-check.R`, `disturbance-check.R` and `provenance-check.R`
  (5g2 included): all pass;
- live `wsg_split-check.R neexdzii` and `pcea`: both pass;
- `fp_fig_region_totals()` rebuilt into the scratchpad: identical to `fig/region_totals.csv`;
- a scratch copy of the repo with `data/dunc`, for the reproduction under finding 1.

**Checked and fine:**
- **Round 1 fix 1.** The probe now sources `fp_wsg.R` (beside `fp_region.R`). Every in-process
  caller of `fp_floodplain`, `fp_lulc`, `fp_composition_build`, `fp_wsg_polygon` or
  `fp_bridge_build` sources what it needs.
- **Round 1 fix 2.** `need_bridge` is now decided from the bridge's own state, and the bridge is
  rebuilt against the split attribution layer.
- **Round 1 fix 3.** `fp_prov_outputs_premise()` runs before the backup and the writes. It runs
  whenever `fp_prov_set_outputs()` will be reached. Its hash re-derivation uses the same
  round-tripped form as the write.
- **Round 1 fix 4.** `fire_tag.R`'s cause report is now over the in_wsg pieces.
- **00f714d.** `region_acceptance-report.R` filters both the patches and the bridge to in_wsg. The
  `(name_basin, patch_id)` key it keeps is unique within in_wsg TRUE.
- **The AOI.** drift's cache key hashes only the AOI's WKB (`stac_cache_key`), so the AOI from
  `fl_valley_poly()` of the floodplain raster keeps the cache key.
- **Duplicate keys.** `flooded::fl_valley_join()` (0.8.2) dedupes `(cell, rank)`, so two rows per
  key are safe. `fp_hj_grid_cells` dedupes as well.
- **The empty case.** `fp_wsg_split` and `fp_split_patches` on zero-row input, or with an empty
  remainder in the subset path, return correctly (tested).
- **Overlay ids.** `waterbody_poly_id` is unique across lakes and manmade waterbodies, and across
  lakes and wetlands (0 shared ids, queried).
- **DUNC figures.** The CLAUDE.md figures match `data/dunc`: 1,446 pieces = 1,299 + 147, and
  -0.03 ha.
- **neexdzii.** `data/neexdzii` has 2,018 in_wsg pieces and 773.4 ha of tree loss over pieces with a
  sub-basin.
- **Other readers.** `run.repairs` readers (`fp_region_cache_unordered`, the region report) and the
  publish layer's raster freshness guard are unaffected by a repair that leaves `datetime_utc` alone.

## Findings

- **[severity: fragile]** scripts/floodplain_lcc/gpkg_backfill-split.R:170-175 (with :214):
  **the composition is decided by a proxy for its state. This is round 1's bridge finding one axis
  over.**
  - **The defect.** `need_comp` is TRUE only when the table lacks `in_wsg` or a context column.
    `fp_composition_build()` writes the table (`st_write`) and then its record
    (`fp_prov_set_sibling`), in two separate steps. A run killed between them leaves a table that
    already has every wanted column beside the pre-split `composition` sibling. The re-run reports
    "current", rebuilds nothing, and the record stays stale. That breaks the header's promise that
    "a run killed half way is finished by running it again" (lines 28-30).
  - **Reproduced** on a scratch copy of the repo holding `data/dunc`. I set
    `landcover.all_ff04.composition.outputs.table_content_sha256` to a stale value, the state that
    crash leaves. `DRY=1 gpkg_backfill-split.R dunc` printed
    `composition_all_ff04_2017_2023 current`. `composition-check.R dunc` then FAILed
    "recorded table digest re-derives from the written table".
  - **Why fragile, not silent.** provenance-check 7c and composition-check (4) do catch it, and
    `composition_build.R` repairs it. But the backfill's own re-run cannot.
  - **Fix.** Decide `need_comp` the way composition-check (4) and `region_acceptance-report.R:209`
    already check the table: rebuild when the recorded `composition.outputs.table_content_sha256`
    (or `rows`) differs from `fp_composition_digest()` of the table on disk, or when the sibling is
    absent. Keep the column test as well.

- **[severity: fragile]** scripts/floodplain_lcc/attribute_tag.R:134-153 (with :158-160):
  **the refusal comes after the write.**
  - **Write before refuse.** The script splits and writes `<scen>_by_<key>` into floodplain.gpkg
    first (line 138), and only then refuses a transition layer without `in_wsg` (line 152). This is
    reachable today on every retired species scenario, which stays clipped by design. For example,
    `attribute_tag.R bulk co_ff04`: `transition_co_ff04_2017_2023` has no `in_wsg`, while
    `co_ff04_by_blue_line_key` and the `co_ff04` row in `flood_scenarios.csv` both exist (checked).
    The run rewrites the retired attribution layer, which is meant to stay untouched until #131. It
    then strands it beside a bridge built from the unsplit attribution.
  - **The remedy it names does not apply.** The stop message says to run
    `gpkg_backfill-split.R bulk`, which touches only the area's own species (`all`). So it never
    splits that transition layer.
  - **A second gap in the same block.** When `fp_bridge_build()` returns NULL, the script prints a
    message and leaves the previous `patch_watercourse_*` layer in place. The code before #53 always
    wrote the (possibly 0-row) bridge, which replaced it. Step 3 handles this case through
    `fp_write_bridge()`'s stale-layer removal. This caller of the shared builder does not, which is
    the #55 orphan class.
  - **Fix.** Move the transition-layer check (lines 144-153) above the split and write (lines
    134-139). Call `fp_write_bridge()`, which writes the bridge or removes a stale one, in place of
    the hand-rolled write.

Not findings, noted for completeness:
- fire_tag.R:95-101: the context lines just below round 1's fix still sum every piece (PCEA: 860
  outside pieces, 1,700 ha), so one report mixes two populations. They are labelled any-touch and
  go to the console only.
- fp_disturbance.R:248: on a several-table entry, the "did not return" refusal pastes the table
  vector with no separator. The message is cosmetic.

~/Projects/repo/floodplains/planning/active/review-round2.md
