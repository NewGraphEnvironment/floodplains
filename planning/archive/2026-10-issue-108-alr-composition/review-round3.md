# Code-check round 3 — #108 composition table (staged diff + round-1/2 fixes, 2026-10-02)

Reviewer: subagent, read-only. No writes to data/ or the database. Read: the diff, every changed
file in full, fp_disturbance.R's `.dst_fetch`, run_region.R's resume block, 02's write/record order,
and every `data/*/provenance.json` (landcover/floodplain timestamps, change_interval, digest keys,
composition presence) via a read-only python parse.

## Mechanism

There is one shared assumption: **a value the build reads from a mutable store *now* (disk, area.yml,
provenance.json, the DB) is the value step 3 saw when it wrote the landcover record.**

- On the step-3 path that holds because the two are adjacent in time.
- `composition_build.R` separates them in time, and none of the inputs is pinned to the run by
  construction. Each round has tied one more input to the landcover record, one at a time.
- The ties come in two kinds:
  - a **refusal before `st_write`** (prevents the bad table);
  - a **comparison in `provenance-check.R`** (reports the bad table after it is written and recorded).
- The author's enumeration lists both kinds as though they were the same. They are not:
  - the classified and transition digests are only **tied** (detected after the fact), not **guarded**;
  - the floodplain is guarded by an **ordering** check (timestamps), not a content check.

| value consumed by `fp_composition_build` | source at build time | tied to the run? | refused before the write? |
|---|---|---|---|
| classified endpoint tifs | `rasters/<scen>/classified_<yr>.tif` now | yes: the digest is recorded, and `viol_composition` compares it with `landcover.inputs` | **no**: the digest is computed inside the sibling-writer call, after `st_write` (finding 1) |
| transition.tif (or its absence) | `file.exists(tr_path)` now | yes: `viol_composition` compares it with `landcover.outputs` | **partly**: the -1 cell check refuses a transition/classified mismatch, but not "both rewritten by a later aborted run" and not "unlinked by a zero-change aborted run" (finding 1) |
| floodplain polygon (`in_floodplain`) | `floodplain.gpkg` layer now | yes: `floodplain_outputs_hash` is pinned, which catches a step 2 re-run after the composition | yes, **by ordering only**: refuses if `floodplain.run` is later than `landcover.run`. Every current area passes it (table below). `NA` timestamps would fail toward pass, but every record has one |
| change_interval | area.yml now | yes (`viol_composition` arm) | yes (`lc_span` refusal) |
| context overlays | DB now | self-recorded only (snapshot comment + bbox keys digest) | n/a (accepted) |
| item keys wsg/species | transition layer, else scenario prefix | yes (the published layer) | n/a |
| classes | raster RAT (PAM sidecar) + drift table now | no record, but a code with no name is refused | yes (refusal) |
| resume marker | `lulc_summary.rds` | **not per-scenario**, so it cannot carry "this scenario's composition is missing" (finding 2) | — |

| write | precedes which guard |
|---|---|
| step 3: delete stale `composition_<scen>_<span>` + unlink both summaries | precedes `fp_prov_set(landcover)`. If that throws, the old composition record survives with no table, and 7c reports it ("names X, which is not in the gpkg"). OK. |
| `fp_composition_build`: `st_write` | precedes (a) the raster digests, which are evaluated when `fp_prov_set_sibling` forces `value`; (b) the no-entry re-check; (c) the mtime guard; (d) `fp_prov_write`'s whole-document `assert_unique`/`assert_serializable`; (e) the provenance-check STALE arms. The author named only (c). (a), (b) and (d) are unlikely to fire. (e) is the one that matters (finding 1). |
| step 3: delete only the CURRENT span's layer | name keyed by today's `change_interval`, so the previous span's layer is never matched (finding 3) |

Timestamps measured on every area: every `floodplain[<k>].run` is earlier than its `landcover[<k>].run`, so
the round-2 refusal does not block any current backfill. That includes morr co_ff04 03:57 < 04:15 and
ch_ff06 04:19 < 04:35. Every landcover record carries `change_interval`, `classified_content_sha256`
and `outputs.transition_content_sha256`, so no current area hits a missing-field STALE on backfill.

## Findings

- **[fragile] scripts/floodplain_lcc/fp_composition.R:252-265.** The classified and transition
  digests are compared with the landcover record only after the table is written and recorded.
  - **Where it bites:** step 3 writes the tifs (03:138-159) long before the landcover record.
    Between the two are the per-year `as.polygons`, the disturbance DB tagging and the bridge. The
    bridge is where #63's abort happened. Peak RSS is 20-54 GB.
  - **What that abort leaves:** a re-run that dies in that window leaves new tifs and a new (or
    unlinked) transition.tif. The OLD landcover record, the OLD composition and the OLD
    `lulc_summary.rds` are all still in place, because the unlink comes later.
  - **What the repair does:** running `composition_build.R` as the repair passes every refusal. The
    span matches, the floodplain is not newer, and -1 passes because the new tifs and new
    transition agree. It then overwrites the published composition table with one built from
    rasters no record vouches for, and records it. Only a later `provenance-check` reports
    "STALE: its classified digests…".
  - **Zero-change variant:** step 3 unlinks transition.tif and then aborts. The build takes
    `trans = NULL` and silently re-labels every change cell `sieved`, again detected only after
    the write.
  - **Fix (one block before any computation):** compute
    `fp_raster_content_sha256(paths)` and `fp_raster_content_sha256(tr_path)` (NA if absent). Then
    refuse unless they equal `lc_rec$inputs$classified_content_sha256[yrs]` and
    `lc_rec$outputs$transition_content_sha256`. Reuse the values in the sibling record. This turns
    the last two "tied" rows into "guarded", which is the shape the change_interval fix already has.

- **[fragile] scripts/run_region.R:152,173 with scripts/floodplain_lcc/03_lulc_classify.R:446,497-498
  and provenance-check.R:1864.** The R2 fix makes the absence of `lulc_summary.rds` carry
  "composition incomplete". `lulc_summary.rds` is a last-writer-wins file shared by every
  species/scenario in the dir, and run_region's cache keys on that file alone.
  - **Masking sequence (morr):** morr co (skeena.yml) re-runs and dies in `fp_composition_build`,
    so both markers are unlinked. Next, a documented `FP_SPECIES=ch … run_area.R morr` succeeds and
    rewrites `lulc_summary.rds`. The next `skeena` run then marks MORR `ok(cached)`.
  - **Result:** co_ff04 has a fresh landcover record, no composition record and no table, and 7c
    prints `ok … no composition table yet (forward-only, #108)`. Round 1's fail-toward-pass outcome
    is back on the multi-species path.
  - **Reverse direction:** a ch failure deletes co's marker, which forces a full steps-1-3 co re-run.
    That costs time only.
  - **Fix:** have run_region key `cached` on `lulc_summary_<primary_scenario>.rds`. It already has
    `primary_scenario` from the region file.
  - **Or:** have 7c treat a landcover entry whose `run.datetime_utc` is after the #108 merge and
    which has no composition as `bad`, instead of `ok`.

- **[fragile] scripts/floodplain_lcc/03_lulc_classify.R:437-443 with provenance-check.R:1848-1849.**
  The stale-table delete and 7c's both-directions check both build the layer name from the CURRENT
  span.
  - **The orphan:** after a `change_interval` edit and a step 3 re-run, the previous
    `composition_<scen>_<oldfrom>_<oldto>` stays in `floodplain_landcover.gpkg`. The publisher
    copies that file whole. The landcover entry that described the layer has been replaced, and
    neither 7c arm can see it, because 7c only ever asks about the name derived from the new record.
  - **Same class elsewhere:** the old-span `transition_*` / `patch_watercourse_*` layers have the
    same #55-class orphan problem, which predates this PR. The composition is new surface, and the
    delete was added specifically to prevent its orphan.
  - **Fix:** delete every `^composition_<scen>_[0-9]{4}_[0-9]{4}$` layer, not just the current
    one. 7c can report any `composition_<key>_*` layer whose name is not the recorded
    `outputs.layer`.

No new bugs in the encoder/decoder, the sibling writer, the span refusal, the floodplain-ordering
refusal, the item-key fallback, or viol_composition's arms.
