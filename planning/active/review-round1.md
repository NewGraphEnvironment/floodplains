# Code-check round 1 — #108 composition table (staged diff, 2026-10-02)

Reviewer: subagent, read-only. Probes run in a temp copy of the repo (data/ and .git excluded), plus
read-only reads of copied rasters/sidecars (PAM off when reading data/ in place). No writes to data/
or the database.

Probes that came back clean (no finding):
- Offline `composition-check.R` in the copy: ALL PASS.
- `.comp_read_class()` on a copy of BULK `classified_2017.tif` + its `.aux.xml`: 9-row RAT, `activeCat` 1,
  Clouds (10) named; no empty-name rows, so the "raster cats first, drift table to fill" union is sound.
- NECR classified 2017 / transition.tif read with PAM off: no raw 0 ("No Data") code in the classified
  raster (the encoder would silently decode a 0 as an NA endpoint with status stable), and the
  transition raster holds `f*1000+t` incl. stable cells, consistent with the encoder's -1 check.
- FLT4S precision: worst code with 8 overlays is 39999*256+255 ~= 1.02e7 < 2^24; exact.
- stac_floodplains_bc `fp_prov_read()` refuses unknown TOP-level keys only and reads explicit paths
  below; a `composition` sibling inside `landcover[<scenario>]` is inert there (B1 holds).
- `gpkg_backfill-wsg.R` unanchored regex: `transition_co_ff04_...`, `patch_watercourse_co_ff04_...`,
  `composition_co_ff04_...`, `co_ff04_by_blue_line_key` all resolve to `co_ff04`; non-matching layers
  (`streams_co3`) fall through exactly as before.
- provenance-check 7c layer-year reconciliation regex `^classified_<key>_[0-9]{4}$` does not pick up
  `composition_*`.

## Findings

- **[fragile] scripts/floodplain_lcc/03_lulc_classify.R:479 (with :422-423, :436)** — a composition
  failure after the landcover record leaves step 3 half-done in a way the resumable runner cannot
  repair, and a first-time failure leaves no trace either. `fp_composition_build()` runs after
  `lulc_summary.rds` is saved and after `fp_prov_set("landcover")` has replaced the entry, and so wiped
  any earlier `composition` sibling. If it then aborts (DB unreachable for the overlay fetch, OOM in
  `lapp`/`rasterize` on a whole-WSG grid, a `-1` refusal), two things follow.
  (a) `run_region.R` skips the group on its next run because `lulc_summary.rds` exists, so the
  composition never gets built.
  (b) If an earlier run had written `composition_<scen>_<span>`, that layer stays in
  `floodplain_landcover.gpkg`, which the publisher copies whole. It describes the previous run's
  rasters. provenance-check 7c does catch this case ("exists with no composition record").
  If no earlier table existed, 7c reports `ok ... no composition table yet (forward-only)`. That is
  indistinguishable from an area that simply predates #108, so the guard fails toward pass.
  Cheapest fixes:
  - Delete the stale `composition_*` layer before or at the landcover `fp_prov_set`, the same
    `#55` treatment the bridge gets.
  - Or have 7c treat a landcover entry written after #108 (e.g. it carries a field only post-#108
    runs write) with no composition as a failure.
  At minimum, document `composition_build.R` as the recovery in the step-3 abort path.

- **[fragile] scripts/floodplain_lcc/fp_composition.R:202-215** — the composition's hashed `inputs`
  carry `overlays.<name>.features` and `keys_sha256`. Both are computed AFTER `st_transform()` and
  the `st_intersects(p, fp)` filter, i.e. after PROJ + GEOS. CLAUDE.md's #65 rule is explicit:
  > a post-subset digest in `inputs` would make `inputs_hash` a function of the sf build, which is
  > the cross-machine churn #64 removed arriving one field over

  Here the borderline case is a wetland/ALR polygon touching or nearly touching the floodplain
  boundary, which a different GEOS/PROJ can include or exclude. Impact is limited today:
  `provenance_ab-compare.R` does not read the sibling, and the publisher does not publish it. But it
  is the exact pattern the repo has ruled out.
  Fix: take `features`/`keys_sha256` over the bbox-fetched set (pre-intersects), which is what the
  network does. Or move the post-filter count/digest to `outputs`.
  Related, same block: `as.numeric(p[[k]])` silently turns a TEXT carry into all-NA before
  `fp_table_content_sha256()` sees it. That defeats that function's deliberate refusal of
  non-numeric columns. The digest would then never move when such a table changes. Not reachable
  with today's `waterbody_poly_id` / `alr_poly_id`, but `context:` entries may carry any column.

- **[fragile] scripts/floodplain_lcc/fp_composition.R:193-195 (+ :225-234)** — `in_floodplain` is
  rasterised from whatever `floodplain.gpkg` holds at composition time, but the sibling records only
  `floodplain_layer = scenario_id`, never the floodplain's content. On the backfill path
  (`composition_build.R`) a step 2 re-run between step 3 and the backfill produces a problem.
  `in_floodplain` (and every "share of the floodplain") then comes from the new polygon. The
  classified rasters and the transition are still masked to the old one. `viol_composition` cannot
  see this, because it only compares raster digests. Fix: record
  `floodplain[<scen>].outputs_hash` (or a digest of the rasterised `in_floodplain` grid) in the
  composition `inputs`, and compare it in `viol_composition` the way the classified/transition
  digests are compared.

- **[fragile] scripts/floodplain_lcc/composition_build.R:405-413** — the item key `species` falls
  back to `area.yml`'s default species when the scenario has no transition layer. That happens for a
  zero-change run, or a step 3 that died before vectorising. Backfilling a second-species scenario
  (e.g. `morr ch_ff06`) in that state keys its rows `species = co`. `gpkg_backfill-wsg.R` derives
  species from the scenario prefix (`sub("_.*$", "", scenario)`), and that fallback is the safer
  one here too.

No bugs found in the encoder/decoder, the status rules, the sibling writer, or viol_composition's
stale-detection arms. All the must-fail arms in composition-check and provenance-check 3c are
structured correctly.
