# Code-check round 1, reviewer p4 (#103 staged diff)

`Rscript scripts/landcover_accuracy/accuracy-check.R` → **ALL PASS** (run 2026-10-02, unmodified tree).

## Findings

- **[HIGH] scripts/landcover_accuracy/imagery_build-dated.R:131-133.** The "fly#88" skips are caused by
  this script, not by fly. `fly_georef(fet, sel, ...)` is handed `sel`, which holds only the frames being
  tried this batch. fly_georef recomputes footprints and rotation from `photos_sf` through `fly_bearing()`,
  and that function needs the ADJACENT frame (same roll, frame_number ±1) to be in the same object. A
  frame whose neighbours are not in `sel` gets no bearing. Its footprint is then drawn axis-aligned (a
  landscape footprint), the image is a portrait thumbnail, and fly's stretch guard skips it. fly warns
  about exactly this ("pass neighbouring frames rather than a sample"), and `suppressWarnings()` on line
  133 discards the warning.

  Measured on the committed imagery.csv and a live BCDC pull of the same bbox:
  - The batch-1 set (the nearest 2012 frame per point) is 250 frames. `fly_bearing(sel)` gives NA for
    **87** of them, and NA for **0** of them when given the full 2012 set (`phy`).
  - Cross-tab against the files actually written to `dated/airphoto_2012/georef/`: bearing NA → 87 not
    georeferenced, 0 georeferenced. That is exactly the "87 of 250" in the header and in fly#88.
  - Direct probe in the scratchpad: frame `bcd12001` 219 (fly#88's own "skipped" example) passed alone
    gives "no flight bearing", then "stretch it by 2.343x. Skipped". Passed with frames 218 and 220,
    "Georeferenced 3 of 3".

  Consequences:
  - 93 of 480 points (19%) end with no 2012 frame, and most of those would be covered.
  - The fallback cannot help much, because each later batch is an even sparser sample.
  - fly#88's diagnosis ("portrait thumbnail, landscape footprint" as a fly defect) is wrong, and so are
    the header comment (lines 18-22) and imagery_index-dated.R:19-20, which both cite it.

  Fix: pass the year's frames to fly_georef. That is `phy`, or `sel` plus its ±1 roll neighbours from
  `phy`, which is cheaper because fly_georef re-sizes every row of `photos_sf` with the DEM. fly_georef
  matches by `fetch_result$airp_id`, so the extra rows are not fetched. Then drop or narrow the
  `suppressWarnings`, and correct fly#88's body.

  Secondary point on the same loop: a frame whose thumbnail fetch fails (network) is also put into
  `tried`, is counted as "skipped by fly (fly#88)", and is never retried in that run.

- **[MEDIUM] scripts/landcover_accuracy/imagery_build-dated.R:52-54.** The staleness guard
  `file.mtime(imagery.csv) < file.mtime(sample.gpkg)` cannot be relied on, because git does not preserve
  mtimes. A checkout writes files in index order, and `imagery.csv` sorts before `sample.gpkg`, so on
  every fresh clone (or branch switch touching both) the index is older and the script refuses.
  Simulated in a temp repo: after a clone, imagery.csv was 0.4 ms older and the guard fired. The remedy
  it demands, re-running imagery_index-dated.R, needs the private FP_ORTHO_STAC and rewrites a committed
  file from today's catalogues.

  The guard also fails toward pass. A redraw followed by a `git checkout reference/necr/imagery.csv`
  (or any touch) makes a stale index look fresh. The root cause is that imagery.csv is keyed by
  `point_id` alone, which CLAUDE.md says is not an identity. Carry `cell` (or the
  FP_ACC_DESIGN_KEY columns) in imagery.csv and check it against sample.gpkg by content
  (`fp_acc_design_check`), not by mtime.

- **[LOW] scripts/landcover_accuracy/review_build-qgis.R:120-123 + accuracy-check.R (form check).** The
  form's value map is EMBEDDED in the .qgs when "Reference labels" is first added, and the layer is
  never re-added. A review project built before this change therefore keeps a form that lacks
  `orthophoto`/`airphoto`, even though the committed `labels_form.qml` (the only thing the new check
  reads) has them. The `necr_lulc_review_pre103` project is in that state.

  This is not live for NECR, because the current `necr_lulc_review` project was rebuilt and its .qgs
  carries all three values (checked). Any other existing project would silently offer a reduced
  list. This is noted rather than urgent.

## Checked and clean

- fp_acc_strata precedence: cause > prior > wetland > transition, and sieved/stable cells are not
  claimed by prior.
- The stratum-19 label is not a cause label, so the fp_acc_estimate cause/unattributed split is
  unchanged.
- The accuracy_estimate.R lookback refusal:
  - integer `identical()` holds after `read_json(simplifyVector = TRUE)`;
  - a `null` design gives NULL;
  - `$` partial-matching is safe for these keys.
- design.json `lookback` writes `null` when absent.
- The patches.gpkg column comparison returns TRUE on the real files, so there is no rewrite every run.
- Theme names match the layer names, and the VRTs use relative paths (`relativeToVRT="1"`).
- No endpoint, href, token or collection id is in the diff or in imagery.csv, and the dated VRTs are
  under gitignored `/data/*`.
