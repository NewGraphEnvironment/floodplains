# Code-check round 4: branch 125-region-acceptance-fraser-peace-columbia (48fae86...HEAD, fixes through 8951d9e)

Reviewer: subagent, 2026-10-17. Read-only on the repo apart from this file. Probes ran in the session
scratchpad: `r4root/` (scripts and config copied, every data file symlinked, so no GDAL sidecar can land
in `data/`), `r4mut/` (SLOC with its three gpkgs copied, then mutated), and `r4dst/` (parser fixtures).
After the probes, `find data -name '*.aux.xml' -newer review-round3.md` is empty and `git status` is clean.

## What was re-derived under the current HEAD

- **Every table in all four logs regenerates from the code at 8951d9e.** I ran `region_acceptance-report.R`
  for columbia, peace, skeena and fraser in `r4root/`, between 20:29 and 20:38 UTC. Every `| ` table line
  (Fraser 28, Peace 10, Columbia 10, Skeena 10) is byte-identical to the committed log. The only diffs are
  the hand-written Checks tables that follow. The new tie stopped no group.
- **The `dst_section` reset fix holds under `/usr/bin/awk`.** Round 3's reproducer (an `all_ff04` span,
  then a species span, then a crash inside a second `all_ff04` span) now gives INCOMPLETE. Two other
  fixtures give FAIL(1) and ABSENT. On the 23 real disturbance logs the current parser gives PASS in all 23.
  `provenance-check.R`'s last line is `PASS` in all 23.
- **Record order today, all 23 groups.** network < `all_ff02` < `all_ff04` < `all_ff06` < landcover. Every
  `all_ff02` and `all_ff06` record is flooded 0.7.0, and each group's network record is later than the
  previous group's landcover record, so all three steps lie inside each group's window. Every
  `streams_all2` layer digests as `network.all2.outputs.streams_content_sha256` (23/23 TRUE), and every
  `lulc_summary_all_ff04.rds` is present. **So no finding below is reached by today's data.**
- **The CLAUDE.md and log figures I checked are right:**
  - classified coverage is 0.99914–1.00015;
  - inside − patches ranges from −0.066 (KOTL) to +0.120 (LSAL), so "within 0.12" and Columbia's
    "within 0.07" both hold;
  - DUNC: 185.2 km², 1,948 blue lines, 1,299 rows, 116.9 ha, the composition check at +4.70%, and
    `link_log` with `config_name: default` and `link_sha` present;
  - Skeena's correction "BULK 8,058 of 9,210" (sqlite);
  - the commits 760b8d9 and 2dda619 exist and say what the logs cite them for.

## Enumeration

Verdicts: **tied** (the line that ties it), **documented** (the place that says it is untied), **untied**
(still trusted because of where it was found: a finding).

### Round 3's 37 rows, re-walked

| # | input / claim | current verdict |
|---|---|---|
| 1 | region yml `watershed_groups:` via awk `[ ]` split | tied today: all four files are one-line flow lists, and a block list fails closed (`region_checks-run.sh:30-31`). |
| 2 | `scen` default `all_ff04` | tied: equals every group's `primary_scenario` by `fp_region_owned`. |
| 3 | `$out` fresh per run | tied (`:33-35`). |
| 4 | `run()` verdict = exit status | tied (`:41`). |
| 5 | FAIL count `grep -c '^  FAIL '` | tied (`:45`). |
| 6 | args to each check | tied (`:79-82`). |
| 7 | section header prefix | tied (`:57`). It matches only `transition_<scen>_YYYY_YYYY`, plus a legacy `_disturbance` sibling, which disturbance-check fails anyway. |
| 8 | `closed` sticky across a re-opened section | **tied now**: `closed = 0` in the header rule (`:58`); reproduced INCOMPLETE. |
| 9 | FAIL count inside the section | tied (`:61`; all output is `message()`). |
| 10 | ABSENT / INCOMPLETE / FAIL(n) / PASS | tied (`:62-67`). |
| 11 | `dem_cache-check.R`, offline | tied, and labelled so (`:75`). |
| 12 | FAIL listing, captured then tested | tied (`:89-90`). |
| 13 | region yml parsed as YAML (report) | tied (`:228-229`). |
| 14 | `area.yml` species / min_order / primary | tied (`:110-112`), and checked against the records by `fp_region_cache_moved` (`:117`). |
| 15 | `streams_<sp><ord>` → network km, km2 per km, the outlier screen | **untied** (F1). The order tie does not reach it: 01 writes the layer at `01_network_extract.R:332` and the record at `:448`, with DB reads and a sidecar write between them. |
| 16 | `network[...].run.freshness` | tied to the network record. Under F1 it can describe a different network from the km beside it. |
| 17 | `habitat_link` | tied by order: written at `01:555`, after the network record at `:448`. A crash after `:448` makes the network record newer than landcover, so `fp_region_cache_unordered` stops the report. |
| 18a | primary `<sp>_ff04` vector km² (also the coverage denominator) | tied indirectly. 02 writes the tif (`:263`), then the layer (`:269`), then the record (`:278`), and the tif must digest as recorded (`report:183`). A partial rewrite of the layer therefore also rewrote the tif. |
| 18b | `<sp>_ff02`, `<sp>_ff06` km² | **untied** (F1): not ordered, not version-checked, not digested. |
| 18c | `<prim>_by_blue_line_key` → blue lines | **untied** for a standalone rewrite (F1). Within step 2 it is tied by order: it is written after the primary record (`02:374` > `:278`). |
| 19 | `transition_<prim>_<span>`: patch count and area | tied indirectly. 03 writes `transition.tif` (`:158`) before the layer (`:240`) and the record (`:454`), and the tif is digested (`report:173`). |
| 19b | its cause columns → fire / harvest / unattributed | **untied** for `fire_tag.R FORCE=1` (F1). |
| 20 | causes and lookback from `disturbance.yml` | tied (one definition, `fp_disturbance_report`). |
| 21 | label "patches >= 1 ha" | **fixed**: "transition patches (< 1 ha)" plus the under-1-ha count (`report:201, 260-261`). The definition written beside it is wrong (F2). |
| 22 | bridge union / unbridged | tied within step 3 (`03:340` < `:454`). **Untied** for `attribute_tag.R` (F1). |
| 23 | composition table | **tied now** (`report:168-170`, `fp_composition_digest` against `landcover[prim].composition.outputs.table_content_sha256`). An absent table gives NA cells: fails toward blank. |
| 24 | `transition.tif`, `floodplain_<prim>.tif` | **tied now** (`report:173, 183`). |
| 24b | `subbasins.gpkg` | untied. Written by 02 at `:85` with `delete_dsn`, before any record. Whole-WSG it is the FWA group polygon, which no rerun changes unless FWA is reloaded. Noted, not a finding. |
| 25 | step-3 time, with `repairs[[1]]` | tied (`report:190-191`; parse failure gives NA, so the time is blanked). |
| 26 | `RUN_STAMP` | **tied now** (`report:57-68`): no `=`, a bad stamp or an unknown region stops. Residual: a duplicate key (`fraser=A,fraser=B`) silently takes the first. That is the caller's own typo and harmless; noted only. |
| 27 | newest coverage CSV | tied per group via #25 and #29. |
| 28 | CSV `wsg` and `log`, mtime chain | tied (NA propagates to a blank). |
| 29 | wall-time window | **partial** (F3): only the step-3 record must lie in the window. `fp_region_cache_unordered` adds "network and floodplain older than step 3", but not "inside the window". |
| 30 | "No wall time for …" | tied. |
| 31 | outlier screen | tied to its inputs. `km2_per_km` inherits F1. |
| 32 | output CSV | tied. |
| 33 | the logs' tables | **tied**: regenerated byte-identical under HEAD, all four regions. |
| 34 | "derives every figure" | **fixed**: CLAUDE.md now says "every table", and the session-probe figures are recorded in findings.md. |
| 35 | "1,700.3 ha … on the reservoir" | **fixed**: "1,627.0 ha of that is on the network's waterbody polygons, by cell centre" (session probe, findings.md:228). |
| 36 | true union 0.94–0.96, 83.6%, 92.1%, 58.4% | documented as session probes (findings.md; accepted). |
| 37 | composition range, FAIL classes, 23× PASS, DUNC figures, median and IQR | verified again (above). |

### Rows the 37 missed, and the lines 8951d9e added

| # | input / claim | verdict |
|---|---|---|
| 38 | `fp_region_cache_reason(prov, cfg)` as the group tie (`report:117`) | tied for what it reads: the primary floodplain's flooded pin, the network record's schema and min_order, and the order of the landcover record after the network and primary floodplain records. It is **half** of the region cache's verdict, though. `run_region.R:207` also requires `lulc_summary_<sp>_ff04.rds`, the marker it deletes when it chooses to re-run (`:224`). The report never reads the marker, so a group that `run_region` has marked incomplete passes the report (F1). |
| 39 | `same()` for `transition.tif` / `floodplain_<prim>.tif` | tied. The digest function is the one the writers used. A NULL record or absent file stops. |
| 40 | composition digest compare | tied. Same function and same read path as `composition-check.R:220`. |
| 41 | `patches_under_1ha = sum(area_ha < 1)` | tied: computed from the layer's own `area_ha`, which 03 recomputes from geometry (`03:217`). |
| 42 | report header comment `:10-12` and every log's explanatory paragraph: "one transition class within an 8-connected change region" | **claim false** (F2). |
| 43 | Skeena correction: "Each row is one transition class within an 8-connected change region" | **claim false**, as #42. Its counts (8,058 of 9,210) and "reproduces this table" hold. |
| 44 | "Step 3's log calls them 'change patches >= 1 ha', which describes the region, not the row" | tied: `drift::dft_rast_transition` sieves 8-connected changed cells (`R/dft_rast_transition.R:113-119`). On SLOC, the 142 change regions are all ≥ 1 ha. |
| 45 | report header `:25-27` / findings.md: "Every group is first tied to its records … before anything is derived" | **overstated**: it covers rows 15, 18b, 18c, 19b and 22 only by write order or not at all (F1). |
| 46 | CLAUDE.md block: 23× provenance PASS, 23× `all_ff04` PASS, 0.12 ha, 0.9991–1.0001, +1.1–7.8% | verified. |
| 47 | CLAUDE.md `dunc` bullet | verified against `data/dunc/provenance.json` and `dunc_composition.log`. |
| 48 | Columbia "within 0.07 ha"; Fraser "within 0.12 ha (LSAL +0.12)" | verified (CSV: KOTL −0.066, LSAL +0.120). |
| 49 | Peace: "No region lists either group" (PARA, FINA) | verified (`grep` over `config/regions/*.yml`). |

## Findings

- **F1 [fragile]** `scripts/floodplain_lcc/region_acceptance-report.R:117-127, 131-132, 134-135, 144, 153`
  (rows 15, 18b, 18c, 19b, 22, 38, 45). The round-3 fix ties the primary rasters and the composition table
  to `provenance.json`. Five printed columns still come from vector layers that a writer can rewrite
  without moving any record the tie reads, so they are still trusted because they sit in the group's gpkg:
  - **network km, km² per km and the outlier screen's `km2_per_km`**: 01 writes `streams_<sp><ord>` at
    `01_network_extract.R:332` and its record only at `:448`. Between the two it reads link's log over the
    database and writes the stamp sidecar. This is the window where the `text[]` provenance abort sat (in
    CLAUDE.md). A step 1 that dies there leaves the new layer beside the old record. The order check
    passes, and every raster still digests.
  - **ff02 (and ff06 under `fp_floodplain(cfg, "<id>")`)**: 02 runs ff02, then ff04, then ff06 (DUNC
    records 18:38:22 / 18:38:53 / 18:42:31). A step 2 killed during ff04's VCA leaves ff02's new layer,
    tif and record beside the old ff04 and landcover. The tie reads only the primary record, so it
    passes.
  - **blue lines, bridge union and unbridged**: `attribute_tag.R:131,163` rewrites
    `<prim>_by_blue_line_key` and `patch_watercourse_*` and writes no record.
  - **fire / harvest / unattributed**: `fire_tag.R:88` with `FORCE=1` rewrites the cause columns and
    writes no record.

  **Mutation** (`r4mut/`, SLOC with its gpkgs copied): I halved `all_ff02`, `streams_all2` and
  `all_ff04_by_blue_line_key`, set `in_fire = TRUE` on every patch, and set `overlap_frac = 0.5`. The
  report exited 0 and printed network km 2,635.9 → 1,178.9, ff02 152.1 → 0.0, blue lines 1,330 → 665,
  fire 2.0 → 100.0%, union 0.894 → 0.500, and km² per km 0.0586 → 0.1310, with no stop.

  The first two cases are the killed-step case CLAUDE.md names ("Files sitting together on disk are not
  one run"). `run_region.R` already handles them: it deletes `lulc_summary_<sp>_ff04.rds` before a re-run
  (`run_region.R:224`) and treats a missing marker as not done (`:207`). The report took
  `fp_region_cache_reason()` but not the marker, which is the other half of that verdict.

  The fix needs no new recorder:
  1. Require `lulc_summary_<prim>.rds` beside the records.
  2. Compare `streams_<sp><ord>` against `network[<sp><ord>].outputs.streams_content_sha256`. It
     round-trips: all 23 groups match today, on the key and value columns `01:240,253`.
  3. Apply the order, pin and tif-digest test to every `<sp>_ffNN` record the table prints, not only the
     primary.
  4. Say in the header, not "tied", that blue lines, the bridge and the cause shares are the layers'
     current state (`attribute_tag.R`, `fire_tag.R`).

  Not reached today (all 23 ordered, streams digests equal, markers present).

- **F2 [claim not supported]** `region_acceptance-report.R:10-11`, the explanatory paragraph in
  `logs/20261017_whole_network_{fraser,peace,columbia}.md`, and the correction appended to
  `logs/20261014_whole_network_skeena.md`. These say a row is "one transition class within an 8-connected
  change region". That is not what drift produces. `dft_transition_vectors()` runs
  `terra::patches(x, directions = 8, values = TRUE)` (`drift/R/dft_transition_vectors.R:115`), so a row is
  one 8-connected run of cells **with the same transition code**. One class appears as several rows
  wherever its pieces in one region touch only through other classes. Measured on SLOC (`r4root`, point
  on surface of each row against `patches()` of the changed cells in `transition.tif`):
  - **1,179 rows**;
  - **142 change regions** (smallest exactly 1 ha, which confirms the sieve is on the region);
  - **537 distinct (region, class) pairs**.

  So the sentence predicts at most 537 rows, and there are 2.2 times that. This is the round-3 label defect
  one level down: the new definition, like the old label, describes the step's intent and not the rows. A
  correct wording: "one 8-connected patch of a single transition (from → to). The 1 ha sieve is applied to
  the change region it sits in, so most patches are smaller."

- **F3 [fragile — low]** `region_acceptance-report.R:233-240` (row 29). The wall-time tie still admits a
  window that holds only step 3. `fp_region_cache_unordered` adds "network and floodplain older than step
  3", but not "after the window opens". So `run_region.R <r> 3` (steps is `args[2]`, `run_region.R:41`)
  would print step-3-only minutes in the `wall min` column. Each log's prose says the run was "(steps
  1,2,3)", but that prose is copied from the run log, not checked. Requiring the network and primary
  floodplain records to lie in `[from, to]` as well closes it. Not reached: every group's network record
  is later than the previous group's landcover record (listed above).

F1 and F3 are one axis over from round 3's fix. The fix tied the artifacts that carry a digest and
left out the ones the same writers produce beside them. The enumeration above lists every column the two
tables print against its writer. After these three findings, no row is untied and undocumented.

/Users/airvine/Projects/repo/floodplains/planning/active/review-round4.md
