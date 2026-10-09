# Review round 2 — #110 whole-FWA probe (branch diff dc77486...HEAD, focus on ea4233e's fixes)

Probed in a scratch copy (data/morr/probe_whole_fwa copied out; nothing in the repo or data/
written). Checked and sound:

- **Digest re-check reads the right types.** `fp_raster_content_sha256(<path>)` on a copy of
  `arm5_floodplain.tif` returns the exact string in `arm5_timing.json$floodplain_content_sha256`
  (identical() TRUE), the same path form the arm mode digested.
- **dem.json `arm_segments`** reads back as `int [1:5] 58613 20812 7606 14641 4877`;
  `dmj$arm_segments[5]` vs `tm$n_segments` (int 4877) compares TRUE after as.numeric().
- **reach.json** built exactly as the `reach` mode writes it (`res[[k]] <- list(...)`,
  `c(list(mode, arms = res), vers())`, auto_unbox) reads back with simplifyVector = TRUE as a
  5-row data.frame (`arm`, `reach_cells`, `fallback_cells`, `valley_cells` all int); the
  `rch$arms[rch$arms$arm == k, ]` subset gives one row and the `!=` compare works. `vsig(rch)`
  equals `vsig(dmj)` / `vsig(tm)`. A missing field fails closed (`FALSE || logical(0)` is NA ->
  `if` error). Integer-valued timings (`round(52.0, 1)` -> json `52` -> int) are promoted by
  `vapply(..., 0)`, not rejected.
- **One grid for the reach waterbody split.** `compareGeom(dem_common, arm5_floodplain)` and
  `(dem_common, arm5_waterbody)` both TRUE (4082 x 4431); `reach_r` is rasterized onto `dem`, so
  `ra`, `rb` and `wb[[k]]` values align cell for cell; no NA in either raster (0/1 only).
- RSS gate: an absent log or a log with no RSS line now gives NA -> `affordable` FALSE.
- Rule code vs research/whole_fwa_floodplain.md: criteria 1, 2, supersession (>2%, gained + lost
  over arm 5) and grain all match. Habitat SQL: no NULL `stream_order` on MORR (4 bands, 9,033 km).

## Findings

- **[bug — fails toward pass]** scripts/floodplain_lcc/floodplain_probe-report.R:26-29, 182-189 —
  the round-1 RSS fix closes "no RSS line" but not "an RSS line from a different run". `rss(k)`
  reads whatever `logs/<k>.log` holds, and nothing ties that log to the run that wrote
  `arm<k>_timing.json`. `/usr/bin/time -l` prints the RSS block for a FAILED command too
  (probed: an Rscript that `stop()`s after 1 s leaves a log with no `PROBE_DONE` and a
  "maximum resident set size" line reading 0.13 GiB). So: arm 1 launched via
  floodplain_probe-run.sh dies early (DB hiccup, a stop, killed), the operator re-runs the
  multi-hour arm 1 directly with Rscript (round 1's own "likely way" an arm gets run), the timing
  json is fresh, and `rss(1)` returns the failed attempt's small number -> `affordable` TRUE on a
  run whose memory was never measured. Same for a superseded successful run's log (5.log today is
  exactly that, for arm 5). Cheap fix in the report only: count a log's RSS only if it contains
  `^PROBE_DONE <mode>$` and `file.mtime(log) >= file.mtime(<mode's json>)` (the json is written
  just before PROBE_DONE and `time` appends after), else NA.

- **[fragile — round-1 fix landed one axis short]** floodplain_probe-report.R:50-59 /
  floodplain_probe-whole-fwa.R:317-326, 356-375 — round 1's "every mode re-reads the network,
  nothing ties them" was fixed for the five arm modes only. The `reach` mode re-reads the network
  and re-derives the coho seeds (`s5`) that define the whole supersession measure, and reach.json
  records no segment count or digest of them, so the report cannot tell whether `supersedes` was
  computed from the same coho network as arm 5's delineation. The `seg` mode likewise re-reads
  arm 3 and the report never compares `seg$n_groups` (= nrow of its read) with
  `tm[[3]]$n_segments` / `dmj$arm_segments[3]`; seg_timing.json also carries nothing tying it to
  arm 3's floodplain. For `seg` the report-side one-liner is available now
  (`seg$n_groups == dmj$arm_segments[3]`); for `reach` it needs the mode to record
  `n_segments = nrow(s5)` (or a network digest), which means editing the main script after the
  live run exits, not during it.

## Disposition (main session)

Both findings are inside round 1's fixes, so the mechanism was enumerated rather than waiting for a
round 3 instance. Mechanism: **a report figure read from a file whose tie to the run is assumed from
its name or presence.** Every input `fp_wf_report()` reads, and its tie now:

| input | tie |
|---|---|
| `logs/<mode>.log` (RSS) | `PROBE_DONE <mode>` in that log AND log mtime ≥ the mode's json; else NA (fixed, finding 1) |
| `arm<k>_timing.json` ↔ `arm<k>_floodplain.tif` | tif re-digested against `floodplain_content_sha256` (round 1) |
| `arm<k>_waterbody.tif`, `arm<k>_by_blk.gpkg` | mtimes ordered floodplain ≤ waterbody ≤ by_blk ≤ timing (one process); by_blk rows = `attr_rows` |
| `dem.json` ↔ `dem_common.tif` | tif re-digested; every arm's recorded DEM digest equals it |
| `dem.json` segment counts | each arm's `n_segments` (round 1) and `seg$n_groups` for arm 3 (fixed, finding 2) |
| `reach.json` ↔ arm floodplains | `valley_cells` per arm (round 1) |
| `arm<k>_coho_reach.gpkg` ↔ `reach.json` | rasterized cell count = `reach_cells` |
| `anchor.json` ↔ `anchor_floodplain.tif` | digest |
| the network every mode re-read (incl. `reach`, which records no count) | newest `fresh.log` MORR `run_uid` = step 1's recorded `run_uid` (fixed, finding 2) |
| `fresh.streams_vw_bcfp` (habitat), the network for panels | live reads at report time; not compared with the run |
| `arm3_by_seg.gpkg` | not read by the report |
