# Review round 1 — #110 whole-FWA probe (branch diff dc77486...HEAD)

Reviewed: fp_whole_fwa.R, floodplain_probe-whole-fwa.R, floodplain_probe-report.R,
floodplain_probe-run.sh, floodplain_probe-check.R, research/whole_fwa_floodplain.md, CLAUDE.md /
research/README.md rows. Cross-read 01_network_extract.R (SQL, digest cols), 02_floodplain_model.R,
fp_provenance.R (both digests, fp_toolchain), fp_raster.R, and flooded 0.6.0's fl_valley_confine,
fl_valley_attribute, fl_group_cells, fl_dem_aoi. Read-only on data/morr (logs, json, provenance).

Checked and found sound: arm predicates vs 01's SQL (NA handling matches three-valued logic; inner
join to streams_access drops nothing on MORR, 58,613 = 58,613); digest coercions (fp_table_content_sha256
renders every numeric through %.6f, so the probe's as.numeric() before digesting is harmless, and
anchor 1 matched); FLT8S DEM round-trip; common-grid refusal in fp_wf_overlap; complete = FALSE
partition guard in `reach` (fl_valley_attribute sets fl_fallback_cells = length(uncovered) on every
path, so n_reach + fb == n_valley is a real identity and complete = TRUE breaks it); waterbody burn
matches flooded's (rasterize, field 1, no touches, after the size/hole filters); FP_WF_RULE equals
the research file's thresholds (60 min, 32 GiB, 5%, 50%, >2%); run.sh gating (PROBE_DONE count +
-nt stamp; `|| done_n=0` form is right; PROBE_DONE is the last statement of every mode block);
habitat SQL columns exist in fresh.streams_vw_bcfp; no mid-run edit of the main script while arm 5
ran (aa051e8/32e95fe touched only report.R/docs; b3e009c landed after arm 5 exited).

## Findings

- **[bug]** scripts/floodplain_lcc/floodplain_probe-report.R:160 — the affordability guard fails
  toward pass. `cand$peak_rss_gb <- max(rss(k), rss("dem"), na.rm = TRUE)`: when the arm's log has
  no `maximum resident set size` line (arm run directly with Rscript rather than through
  floodplain_probe-run.sh — the likely way a many-hour arm 1 gets run — or its log missing),
  `rss(k)` is NA and is silently replaced by the DEM stage's RSS (3.3 GiB on MORR, the cheapest
  stage), so criterion 1 is judged on the wrong process. With both NA, `max(..., na.rm = TRUE)` is
  `-Inf` (proven: returns -Inf with only a warning) and `-Inf <= 32` is TRUE, so `affordable` reads
  TRUE with no measurement at all. `fp_wf_peak_rss_gb()` deliberately returns NA "so a run whose
  wrapper never printed reads as unmeasured rather than as zero", and this line undoes that. Fix:
  NA when `rss(k)` is NA (so `affordable` is NA, not TRUE), e.g.
  `if (is.na(rss(k))) NA_real_ else max(rss(k), rss("dem"), na.rm = TRUE)`.

- **[bug — wrong interpretation of the supersession number]** research/whole_fwa_floodplain.md:30-32
  and floodplain_probe-whole-fwa.R:25-27 claim the coho-reachable floodplain "isolates the boundary
  move ... from the area added by new seeds". It does not. In flooded 0.6.0 `fl_group_cells()`
  computes `member <- valleys_c * fl_mask_distance(seeds, max_width/2) * fl_mask(fl_cost_distance(slope_c, seeds), cost_threshold)`:
  the distance and cost masks are built from the coho seeds and the (common) DEM slope only, so they
  are the SAME zone Z for every arm, and reach_k = valley_k ∩ Z. Hence report section 3's
  gained + lost = (valley_k Δ valley_5) ∩ Z — ANY valley difference within 1,000 m / cost 2,500 of a
  coho stream counts, including tributary valley floors created by the new order-1/2 seeds at their
  mouths and new headwater waterbodies burned into the valley that fall inside Z. `moved_share`
  (report.R:113) and therefore `supersedes` (report.R:167, threshold 2%) are inflated by new-seed
  area, in the direction of "must plan a republish". The rule text itself ("the coho-reachable
  floodplain ... differs") is what the code measures, so the verdict is computable as written; but
  the prose that justifies why this number is a boundary move is false, and #104's planning will
  read it as one. Either drop the "isolates" claim, or split the gained cells (e.g. gained cells that
  are new-arm waterbody cells, and gained cells connected to arm-k-only valley patches outside Z)
  before using moved_share as a boundary-move measure.

- **[fragile]** floodplain_probe-report.R:20-23 / floodplain_probe-whole-fwa.R:317-351 — the report
  binds no derived artifact to the arm floodplain it was derived from. `need` checks presence only;
  `reach.json` and `arm<k>_coho_reach.gpkg` carry no digest of the `arm<k>_floodplain.tif` they were
  reached on; and the report never re-digests `arm<k>_floodplain.tif` against the
  `floodplain_content_sha256` each `arm<k>_timing.json` records. Re-running one arm after `reach`
  (e.g. `floodplain_probe-run.sh morr 2 report`) silently computes section 3 / `supersedes` from a
  stale coho reach. Live instance of the stale file: `data/morr/probe_whole_fwa/arm5_coho_reach.gpkg`
  (22:38) is the superseded complete = TRUE output of the old arm mode; it is only replaced if `reach`
  reaches k = 5. Cheap fix: record `fp_raster_content_sha256(fps[k])` per arm in reach.json and have
  the report compare it, and the timing-json digest, against the tif it reads.

- **[fragile]** floodplain_probe-whole-fwa.R:226/263/322/361 — every mode re-reads the network from
  the database, but only the anchor proves it equals step 1's. Nothing checks the arms read the same
  network as each other across a multi-hour run: `dem.json` records `arm_segments` and each
  `arm<k>_timing.json` records `n_segments`, and the report never compares them. A `fresh` rebuild
  mid-probe would put arms on different networks with no error. One line in the report
  (`tm[[k]]$n_segments == dmj$arm_segments[k]`), or a network digest per mode, closes it.

- **[fragile — wrong number in the report table]** data/morr/probe_whole_fwa/logs/5.log is from the
  superseded arm mode (commit 33fc306), whose process also ran the coho-reach attribution (825 s), so
  `peak_rss_gb` for arm 5 in `arm_tab` (report.R:56, `rss(t$arm)`) describes delineation + blk
  attribution + a second attribution pass, unlike arms 1-4. Not a rule input (arm 5 is not a
  candidate), but it is printed in the cost table beside the others. Re-run arm 5, or footnote it.

- **[bug — documentation fact]** research/whole_fwa_floodplain.md:72-73 — "origin sits ~1.1 m east
  and ~0.6 m north" has the x sign wrong. anchor.json: published xmin 847158.2375 vs today
  847157.0998 (xmax 976062.4047 vs 976061.2694) — today's grid is 1.14 m WEST; ymax 1075619.377 vs
  1075619.991 — 0.61 m north is right.

- **[bug — documentation fact]** research/whole_fwa_floodplain.md:67-68 — "so `fresh` has not been
  rebuilt since 2026-09-01". The record anchor 1 matched is `network.co3`, written 2026-09-03T03:55Z
  (provenance.json run.datetime_utc), and the province-wide link rebuild finished 2026-09-02. The
  evidence supports "unchanged since step 1 read it on 2026-09-03", not "since 2026-09-01".

- **[fragile — label overstates scope]** fp_whole_fwa.R:19 / research file table, arm 1 "all FWA
  (order >= 1)". Arm 1 is all of `fresh.streams`, which on MORR is 9,033 km against 9,385 km in
  `whse_basemapping.fwa_stream_networks_sp`: 2,654 FWA features / ~352 km (3.7%) are absent, by
  edge_type 1100 (146 km), 1400 (120), 1350 (45), 1450 (35), 1475 (4, order >= 3), 1150, 1300 —
  measured by anti-join on linear_feature_id. If #104 means the FWA network, arm 1 understates both
  cost and added area; at least say "all of link's fresh.streams" in the label and research file.

Not findings (accepted per brief): SQL copy guarded by anchor 1; anchor vs replay rather than the
published record; arm5_timing.json's stale extra fields; visual criterion pending.

## Disposition (main session)

| finding | disposition |
|---|---|
| RSS fallback fails toward pass | fixed: NA unless both arm and dem RSS are measured; `affordable` requires non-NA |
| coho reach does not isolate the boundary move | confirmed in `fl_group_cells` (`member <- valleys * dist_mask * cost_mask`, zone from coho seeds + DEM). Prose corrected (dated) in research and the report; measure kept as the supersession measure; waterbody part of the gain split out. Thresholds unchanged |
| outputs not tied to their floodplain | fixed in the report: per-arm tif re-digested against its timing json, reach.json valley_cells must equal the arm's, segment counts must equal the `dem` mode's. No runner edit (live run) |
| network re-read per mode unchecked | fixed: segment counts vs `dem.json` (above) |
| logs/5.log RSS from the superseded run | arm 5 re-run after the main run for a clean RSS (its floodplain is deterministic, so the reach tie still holds) |
| east → west | fixed in research, planning, #117 and flooded#67 bodies |
| "not rebuilt since 2026-09-01" | fixed: unchanged since step 1 ran 2026-09-03 |
| arm 1 is `fresh.streams`, 3.7% short of FWA | research method table states it; `FP_WF_ARMS` label changed after the run (fp_whole_fwa.R is sourced by the live run); report reads labels at report time |
