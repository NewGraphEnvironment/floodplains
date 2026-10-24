# Code-check round 4 (#148)

## Checklist read

- `index_code-check.md`, `index_code-check-r.md`, `index_code-check-spatial.md`,
  `index_code-check-shell.md`, `index_code-check-python.md`: in full.
- `code-check.md`: the prose of all 14 H3s under `## Mechanisms` (`|` rows skipped), which includes
  "A guard's scope, escape hatches, and remedies" and "One fact derived twice". I did not read
  "Rules that stand alone", Security, or Spreadsheets/PDFs.
- The full `code-check-r.md`, `-spatial.md`, `-shell.md` and `-python.md`: index only. This round
  reviews prose against data. I read the data read-only, with Python (`sqlite3` `mode=ro`, `csv`),
  and ran no R.
- I opened nothing under `data/necr/accuracy/model/` or `_aside_*/`.

## Job 1: round 3's fixes (ab4d314), re-derived from primary sources

| fix | source | re-derived | verdict |
|---|---|---|---|
| fire IO omission 0.332 | omission CSV, `fire/all`: 988.95 / 1,481.56 ha | 1 − 0.667506 = 0.332494 | OK |
| fire published 0.351 (unchanged) | 962.25 / 1,481.56 | 0.350516 | OK |
| "2018 fires are 90% of the fire row" | 1,335.82 / 1,481.56 | 90.16% | OK |
| "(99.95% on `ch_ff04`)" | 20260929 CSV: 634.87 / 635.16 | 99.954% | OK |
| "the 2021 fire adds 145 ha" | 145.46 | 145 | OK |
| ch_ff04 overall Trees 0.410–0.445 | 20260929 wetland CSV, floodplain zone, from ha | min 0.40988 (2021), max 0.44468 (2017) | OK |
| 48.9% measured 2026-09-29 | #93 archive progress.md:22, README:47; `git log -S287.8` → 8d619d8 on 2026-09-29 | — | OK |
| windows: "only a change of scenario re-measures it" | `fp_acc_windows_read` / `fp_acc_window_obs_read` refuse on scenario | — | OK |
| Wayback Verified line | — | — | OK |
| `17_00009` example labelled first draw, 2026-10-08 | review_key at d4a3101: cell 22,170,746 (now 35,503,676) | — | OK |
| 89,814 point-release captures, 55 dates | `wayback_index_all_ff04.log` | same | OK |
| 2017 row 34/287/64/95; 2023 row 136/100/76/168 | `wayback.csv`, \|years_from_endpoint\| | same | OK |
| 321 (67%), 236 (49%) | same | 66.875%, 49.17% | OK |
| first draw 243 (51%), 263 (55%) | d4a3101 `wayback.csv` | 243 = 50.6%, 263 = 54.8% | OK |
| "the better-covered endpoint changed" | 321 > 236; 243 < 263 | — | OK |
| 0.31–0.5 m; 596 picks at 0.5 m; zoom 17/18 = 209/751 | `wayback.csv` | same | OK |
| 119 neighbours within 300 m (176 first draw) | point geometry in `sample.gpkg`, now and at d4a3101 | 119; 176 | OK |
| "for example "2017-06-11, 0.31 m"" | `wayback.csv` | 43 picks have exactly this | OK as an example |

All of round 3's fixes hold.

## Enumeration (sections)

Sources this branch regenerated (`git diff --name-only d4a3101...HEAD`, plus data files):
- reference files: `sample.gpkg`, `strata.csv`, `design.json`, `review_key.csv`, `imagery.csv`,
  `wayback.csv`, `windows.csv`, `labels_model.sha256`;
- logs: the 20261023 omission, wetland, window and free logs;
- data files: `wetland_composition.csv`, `omission_disturbance.csv`, `windows_clear_obs.csv` (this
  file is byte-identical to the committed 20261023 window CSV);
- code: `chip_build-composite.R`, `review_build-qgis.R`, `review_render-sheets.R`,
  `window_count-clear.R`, `fp_accuracy.R`.

Line numbers below are for `research/landcover_accuracy.md` at ab4d314.

| section | stated producer / source | regenerated? | measured NECR claims → verdict |
|---|---|---|---|
| H1 + Status (1-24) | `scripts/landcover_accuracy/` | yes | "redrawn on all_ff04", "review project ready", "windows: August; 2017 Aug–Sep", "criterion 4 does not hold" are **re-derived**; "chips built and in the review project" is **OWED (accepted)** |
| ## Pre-registered criteria (26) | none (pre-registered) | — | none |
| ### How each criterion is computed (44) | none | — | none |
| ### Free-reference omission, defined (72) | none | — | "18% of the table" is about the provincial cutblock table, not the floodplain, and its source was not regenerated: **pre-registered** |
| ### Strata (97) | none (pinned 2026-09-29; amended 10-02) | indirectly | sieve 18% (l.100), 78% of Trees→Rangeland (l.105), prior fire 27% / 172 ha / 177 ha (l.116-117): **pre-registered rationale left by decision** (task_plan l.92, review-plan item 6). The 78% is not in the decision list's wording, but it sits in the same pinned subsection and is the same kind of claim. |
| ## Free reference: results (120) | omission and wetland scripts and logs | yes | header **re-derived** |
| ### Omission of known disturbance (126) | omission CSV | yes | 223 polygons, 2.2 ha; both rows; 85.2% / 14.8%; 0.12–0.18 over 84–113 ha; 0.255 / 92.1 / 79 / 0.411 (labelled ch); 23.4% and 9 points (16 for ch); 481 ha; 90% / 99.95% / 145 ha: all **re-derived** |
| ### How IO labels a mapped wetland (154) | wetland CSV and free log | yes | 2,646 polygons (free log:25); 12,809.0 ha and 80,783 ha (CSV); all 35 table cells from ha; FV 0.3–0.6% (0.26–0.64%); 7 points (0.538 / 0.611); 3.5 points (0.510–0.545); 2×; the ch values in brackets: all **re-derived** |
| ## Reference sample (179) | `sample_draw-pilot.R`; sample, strata and design files | yes | dates, seed 930093, 30 per stratum, 80,783 ha (41,838 ch), 1,019,347 change cells (summed from `strata.csv` n_cells), 204,033 sieved; the 16-row table; fire 1 of 30 outside and harvest 17 of 30 outside (from `sample.gpkg`'s `in_*_poly`); 85% stable (0.8486); all **re-derived**. 48.9% / 287.8 / 588.9 / 94.2% are **labelled ch_ff04**. The "earlier draws" paragraph is **labelled ch_ff04 / first draw**. |
| ## Labelling key and its 3 H3s (234-305) | pre-registered | — | none |
| ## Review setup (306) | `review_build-qgis.R`, `chip_build-composite.R` (changed), `review_key.csv` (regenerated) | yes | "append-only" (l.317-318): **finding 4**. "48 for NECR" is structural (16 × 3). The 1,800 and 1,920 chip counts are **OWED (accepted)**. "5 of 15 test points … had no usable scene" is a historical, past-tense #93 timing run. 0.869 (0.852) and "Aug–Sep clears everywhere" are **re-derived**. |
| ### Model labeller (349) | pre-registered + amendment | yes (`review_key.csv`) | "480 and 48 rows" is **historical** ("at the time"). 48 / 39 / 86% is **pre-registered rationale left by decision**. 75 points, 36 stable: **re-derived** (`review_key.csv`: 75 TRUE, 12 in each of 30/31/32). The amendment is **labelled**. "26 of 40 sheets" was dated and measured on batch 1 of the first draw; it is a property of the Read tool, not of the draw. The "NECR run" log line is **OWED (accepted)**. |
| ## Dated reference imagery (475) | `imagery_index-dated.R` (`imagery.csv`), `imagery_build-dated.R` | yes | The table (136 / 28.3%, 480, 4.41 m, 12, 1963–2006, 480 in 1996 and 2000) is **re-derived**. 161 hits and 15 on the collar are **re-derived** from `data/necr/accuracy/imagery_index_all_ff04.log` ("161 point-tile hits, 146 on image data"). 204 / 42.5% and 229 / 25 are **labelled first draw**. "87 of 250" is the **historical** wrong turn. **"georeferences 250 of 250 frames" (l.511): finding 2.** |
| ## Esri Wayback (532) | `wayback_index-capture.R` (`wayback.csv`), `wayback_build-chips.R` | yes | Every number fixed in round 3 is **re-derived** (Job 1). **"neighbours are usually different captures" (l.573): finding 1.** **"Log: 20261008_wayback_necr.md" (l.582) beside the all_ff04 build figures: finding 3.** "three cells … open lake" is **historical** (the first build). 160 (115) is **re-derived**. BULK 80% / 65% / 49.8% / 4.6% (73% / 76%) is **re-derived**. |
| ## Accuracy labels never mix (601) | design | yes | `use = "accuracy"` on all 480 rows, scenario `all_ff04`: **re-derived** |
| ## Composite windows (609) | `window_count-clear.R`, window logs and CSV | yes | Four empty month-years (2017-4, -5, -7; 2021-9); 0.149 and 0.840; May and August; 0.999 against 0.963; 0.869; 0.998; direct count 0.999 (derive2 log); windows 8-9 and 8; early and late months. All **re-derived** from the CSV at full precision. `repoprted` count is 0 in all 5 window logs. The failed 2022-8 and -9 were re-run, and the final CSV has 45 ok and 4 empty rows. |
| ## Drought years (666) | gauge script, HYDAT | no | not in scope |

### Double rounding (every 3- and 4-dp value in the file)

`grep -oE '\b[01]\.[0-9]{3,4}\b'` finds 87 values. I checked each against a full-precision source:
- omission: from ha, which is cells / 100 and so exact;
- wetland shares: from ha, recomputed as ha / zone total;
- strata weights: from the full-precision `weight` column;
- windows: from the full-precision `share_ge1`.

None is a twice-rounded value. Two values have no artifact in the repo, by design: 0.0031–0.0040 and
0.038–0.139, the batch-1 sheet differences, which live in the model directory I may not read.

### CLAUDE.md (`git diff d4a3101...HEAD -- CLAUDE.md`)

- The `review_key.csv` "forced redraw starts a new one" line is true as an outcome. The mechanism is
  manual, though. `sample_draw-pilot.R:119-127` skips the key check under `FORCE=1` and does not touch
  the key. The 20261023 sample log records that the key was removed before the draw. A forced redraw
  that keeps the old key is refused later by `fp_acc_review_key`'s design check. Not a finding.
- "NECR was then redrawn on `all_ff04`": `design.json` has `transition_layer =
  transition_all_ff04_2017_2023`, and every row of `sample.gpkg` has `scenario = all_ff04`. True.
- "So do `windows_clear_obs.csv` and `windows.csv`, read through the two readers": true.
  - `window_count-clear.R:163` (derive) reads through `fp_acc_window_obs_read`.
  - `chip_build-composite.R:39`, `review_build-qgis.R:80` and `review_render-sheets.R:56` read through
    `fp_acc_windows_read`.
  - `window_count-clear.R:234` is the writer, and it stamps the scenario at l.229.
- "17% of NECR's IO change (`all_ff04`)": 204,033 / (1,019,347 + 204,033) = 16.7%. True.
- "#140; fixed there, and the design moved to `all_ff04` under #148": true. design.json records it,
  and round 3 found check (5) passing.

## Findings

- **[wrong published claim]** `research/landcover_accuracy.md:571-573`: "so the +/-150 m chips
  overlap, and neighbours are usually different captures". `wayback.csv` and `sample.gpkg` say the
  opposite, on both draws.
  - On the `all_ff04` draw there are 86 point pairs within 300 m. Their picked `capture_date`
    differs in **0 of 86** pairs at 2017 and **2 of 86** at 2023. Their `release_id` differs in 2
    and 1.
  - On the first draw (d4a3101) there are 140 pairs, and capture differs in 3 and 4.
  - So neighbours almost always share one capture and one release, and their overlapping pixels are
    identical.

  The sentence dates from #115 (99e2970, 2026-10-08), and it was never measured over the population.
  The 10-08 log's only evidence is a look at 6 rendered points (`20261008_wayback_necr.md:83`). This
  branch re-stamped the section "Verified: 2026-10-23, on the `all_ff04` draw", which certifies the
  sentence. Voronoi clipping is still needed for the few pairs that differ, so no code changes.
  Only the stated justification is wrong. Fix: state the measured count, for example "2 of the 86
  neighbour pairs within 300 m differ in capture or release; the clip guards those".
- **[stale, present tense]** `research/landcover_accuracy.md:511`: "Passing the year's full frame set
  georeferences 250 of 250 frames." 250 is the first draw's frame count (#103 archive README:48,54).
  The `all_ff04` build georeferenced **305 of 305**
  (`scripts/landcover_accuracy/logs/20261023_imagery-wayback_necr.md:99-100`;
  `data/necr/accuracy/imagery_build_all_ff04.log`). The section's Verified line says 2026-10-23 on
  `all_ff04`, so this reads as current. Fix: "georeferenced 250 of 250 on the first draw, and 305 of
  305 on `all_ff04`". The "87 of 250" in the wrong-turn bullet stays, because it is historical.
- **[provenance]** `research/landcover_accuracy.md:580-582`: the `all_ff04` build figures (766 MB, 0
  failed, 14.5 min cold) are followed by "Log: `scripts/landcover_accuracy/logs/20261008_wayback_necr.md`".
  That log records **711 MB**, **21.2 min** and **4 failed** (l.9, 60, 76). The 766 MB / 14.5 min line
  is `20261023_imagery-wayback_necr.md:113`. A reader checking the number finds a different one.
  Fix: cite both logs, the 10-23 one for the `all_ff04` figures.
- **[contradiction with CLAUDE.md]** `research/landcover_accuracy.md:317-318`: "`review_key.csv` … is
  append-only". #148 rewrote it whole: 480 deletions and 480 insertions, the same `review_id` →
  `point_id` mapping, every cell moved. The 20261023 sample log says the old key was removed before
  the draw. CLAUDE.md now carries the exception ("A forced redraw starts a new one … (#148)"), and
  the research file that the review project's own setup is described in does not. Fix: add the same
  clause.

No other present-tense measured NECR claim in a regenerated-source section falls outside the four
accepted states (re-derived / labelled / pre-registered by decision / OWED). The owed items, as
accepted: the Status "chips built", the Review setup chip counts, and the "NECR run" log line.

/Users/airvine/Projects/repo/floodplains/planning/active/review-round4.md
