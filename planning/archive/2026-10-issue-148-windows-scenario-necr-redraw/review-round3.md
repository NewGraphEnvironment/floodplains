# Code-check round 3 (#148)

## Checklist read

- `index_code-check.md`, `index_code-check-r.md`, `index_code-check-spatial.md`,
  `index_code-check-shell.md`, `index_code-check-python.md`: in full.
- `code-check-python.md` (7,237 bytes): in full.
- `code-check.md` (330,698): prose of all 14 H3s under `## Mechanisms`, `|` rows and
  `<!-- evidence -->` blocks skipped. That covers "A guard's scope, escape hatches, and remedies" and
  "One fact derived twice". I did not read the 23 H3s under "Rules that stand alone", Security or
  Spreadsheets/PDFs.
- `code-check-r.md` (177,187): "Read-back shape must match write-back shape", "CSV whitespace",
  "`strsplit()` drops a trailing empty field", "`nzchar(NA)` is TRUE", "`match()` treats NA as a
  matchable VALUE", "`as.integer("NaN")` is `0`", "`read.delim()` quotes by default", "`ifelse()` with
  an all-NA test". That is 8 headings; the other ~100 I did not read.
- `code-check-spatial.md` (155,517) and `code-check-shell.md` (124,118): index only. The diff touches
  no terra, sf, GDAL or shell code. Reading sample.gpkg for this review went through read-only sqlite.

## Mechanism

The four earlier findings share one assumption: **a number is correct if it matches the nearest
text that states it**. That text is a printed log line or the prose already in the file. It should
instead be re-derived from the artifact the section names. The assumption has two halves.

1. **Derivation.** A value is copied from a rendered, already-rounded form. Rounding 0.1475 a
   second time gave 0.147. A bracketed `ch_ff04` value was copied from the old sentence without
   re-reading the old CSV.
2. **Scope.** "What this branch changed" was taken to mean "the sentences I edited", not "every
   claim whose source file this branch regenerated". So measured blocks next to an edit kept the old
   draw's numbers in present tense: the window shares in round 2, and the Wayback table now. Words
   tuned to an old magnitude also stayed after the magnitude moved: "most under 1 ha" in round 2,
   "nearly all" now.

The candidate set this implies, all of which I checked:

- (A) every number, quantifier and tense claim in the prose diff, re-derived at full precision from
  raw cells or ha;
- (B) every measured claim in any section whose named source the branch regenerated (`sample.gpkg`,
  `strata.csv`, `design.json`, `windows.csv`, `imagery.csv`, `wayback.csv`, `review_key.csv`),
  **whether or not the line was edited**;
- (C) every qualitative word whose truth depends on a magnitude that moved.

## Enumeration (table)

Line numbers are for `research/landcover_accuracy.md` (R) and `CLAUDE.md` (C) at 9140c5d.
"Recomputed" comes from the raw source: cells = ha × 100 on the 10 m grid. "Tie" means the source
value is an exact .x5, where half-up and half-even rounding disagree; either is acceptable.

| claim | line | source | recomputed | verdict |
|---|---|---|---|---|
| Status: sample redrawn on all_ff04, review project ready | R8-9 | 20261023 sample/imagery logs | redraw done; project A built before chips | OK (the "chips built" part is owed and accepted) |
| Verified 2026-10-23 on all_ff04; logs `2026*_reference_*` | R122-124 | logs dir | both dates exist | OK |
| 223 polygons, 2.2 ha of Trees each on average | R129 | omission CSV | 481.46/223 = 2.159 | OK |
| harvest row: 223, 481.5, **0.148**, 0.234 | R133 | omission CSV, cells 48,146 / 41,043 / 36,870 | 0.14753, 0.23420 | OK |
| fire row: 5, 1,481.6, **0.333**, 0.351 | R134 | omission CSV: denom 1,481.56 ha = 148,156 cells, IO loss 98,895 cells | **1 − 98,895/148,156 = 0.332494 → 0.332**; published 0.350516 → 0.351 | **WRONG**: 0.333 is the stored 0.3325 rounded again |
| IO labels 85.2%, misses 14.8%, under the 30% bar | R136-137 | same | 85.247% / 14.753% | OK |
| annual rows 0.12–0.18, over 84–113 ha each | R137 | annual rows | 0.1238–0.1795; 83.72–113.02 ha | OK |
| ch_ff04: 0.255 over 92.1 ha, 79 polygons, published 0.411 | R138-139 | 20260929 CSV | 0.25486, 92.05 (tie), 79, 0.41075 | OK |
| "decided before any all_ff04 accuracy number existed; recorded beforehand" | R140-142 | 315477b vs the omission run (round 1: 14:03 vs 14:08 PDT) | order holds | OK; the "decided before" half has no data source |
| both values under the bar | R142 | 0.255, 0.148 < 0.30 | — | OK |
| sieve misses 23.4%, adds 9 points (16 on ch_ff04) | R143-144 | CSVs | 0.2342 − 0.1475 = 8.7; 0.4108 − 0.2549 = 15.6 | OK |
| 481 ha of qualifying clearcut | R148 | 481.46 | — | OK |
| "Nearly all of the fire row is the 2018 fires" | R148 | fire rows | **1,335.82 / 1,481.56 = 90.2%**; on ch_ff04 it was 99.95% | **weakened**: the 2021 fire is 10% (145.5 ha) |
| 2,646 polygons, 12,809.0 ha, 80,783 ha footprint | R154-155 | 20261023 free log; wetland CSV zone totals | 12,809.0; 80,782.9 | OK (the 2,646 is from the log only) |
| ch_ff04: 1,122 polygons, 6,436.6 of 41,838 ha | R155 | 20260929 log/CSV | 1,122; 6,436.6; 41,838.1 | OK |
| wetland table, 35 values | R157-163 | wetland CSV ha | all 35 agree at 6 dp (e.g. Trees 2017 0.606507 → 0.607) | OK |
| FV 0.3–0.6% every year (0.3–0.9% ch) | R164-165 | CSV | 0.0026–0.0064; ch 0.0034–0.0087 | OK |
| wetland Trees moves 7 points: 0.538 in 2023, 0.611 in 2020 | R170-171 | CSV | 0.538148 / 0.610629, Δ 7.25 | OK |
| floodplain Trees moves 3.5 points, 0.510–0.545 | R172 | CSV | 0.510451 (2019) – 0.545338 (2017), Δ 3.49 | OK |
| 2× stronger in wetlands | R172 | 7.25 / 3.49 | 2.08 | OK |
| ch_ff04: 0.508–0.583 in wetlands, **0.411–0.445 overall** | R173-174 | 20260929 CSV, floodplain Trees | 0.5076–0.5834; **overall minimum 0.4099 (2021) → 0.410** | **WRONG**: 0.411 is 2019's 0.4108, copied from the old sentence |
| drawn 2026-10-23 on all_ff04 after draws on 2026-09-29 / 10-02 | R178 | logs | all three exist | OK |
| same seed and allocation, FORCE=1 | R185-186 | design.json, strata.csv | 930093; n = 30 × 16 | OK |
| nobody had labelled; model labels discarded unread | R186-188 | log only | no labels*.csv in reference/necr | cannot be checked beyond absence |
| "Every reference input was regenerated" | R188-189 | mtimes, git | all 7 draw-dependent files regenerated; labels_form.qml (Oct 8) is draw-independent | OK as meant |
| 16 strata partition 80,783 ha (41,838 ch) | R191 | strata.csv | 8,078,287 cells | OK |
| change strata 1,019,347 cells, sieved 204,033 | R192-193 | strata.csv | 1,019,347 / 204,033 | OK (equality with transition.tif not re-derived) |
| redraws byte-identical | R193 | 20261023 sample log (cmp) | — | OK (log only) |
| strata table, 16 × ha and weight | R202-217 | strata.csv | all 32 agree; stable other 25,902.35 → 25,902.3 is a tie | OK |
| 1 of 30 fire points outside fire, 17 of 30 harvest outside cutblock | R219-221 | sample.gpkg `in_*_poly` | stratum 1: 1; stratum 2: 17 | OK |
| ch_ff04: 3 and 17 | R221 | d4a3101 sample.gpkg | 3, 17 | OK |
| "whole ch_ff04 grid **(2026-10-02)**: 48.9% (287.8 of 588.9 ha), fire 94.2%" | R221-223 | #93 archive README/progress; `git log -S` puts it in 8d619d8 | **measured 2026-09-29 (#93)**; nothing re-measured it on 10-02 | **WRONG DATE**, added by this branch |
| stable strata 85% (86% ch) | R229-230 | strata weights | 0.8486; 0.8619 | OK |
| amendment: first hash in 4072a24 | R388-393 | `git show 4072a24` | adds labels_model.sha256 | OK |
| "before labeller B made any label" | R388-389 | no labels_b.csv | — | OK as far as disk shows |
| August 2017 reaches 0.869 (0.852) | R467 | window CSVs | 0.868538; 0.852244 | OK |
| imagery table: 136 (28.3%), 480, 4.41 m, 2019: 12, film 1963–2006, 480 in 1996 and 2000 | R486-489 | imagery.csv; 20261023 log | 136; 480; 4.41; 12; 1963–2006; {1996, 2000} | OK |
| first draw 204 of 480 (42.5%) | R491 | d4a3101 imagery.csv | 204 | OK |
| 161 point-tile hits, 15 on collar (229 / 25 first draw) | R493-494 | not in any committed log: the 20261023 log's index block starts at 1973, so the header and the hits message are cut | consistent: sum of n_images = 146 = 161 − 15 | partly checkable |
| "Dated imagery does not change windows.csv. **Only a redraw** re-measures it" | R511 | code: windows depend on the floodplain (scenario), not the draw | a same-scenario redraw needs no re-measure | imprecise (see finding) |
| 960 chips, 766 MB, 0 failed, 14.5 min cold | R547-548 | 20261023 imagery-wayback log | 960 + 2 VRTs = 962 files, 766 MB, 14.5 min | OK |
| cold build 15–21 min | R548 | 14.5 and 21.2 min | 14.5 rounds to 15 | OK |
| 160 of 480 same capture (115 first draw) | R552 | wayback.csv (new and d4a3101) | 160; 115 | OK |
| BULK comparison: 80% / 65%, both 49.8%, neither 4.6%; first draw 73% / 76% | R61-63 of section (file ~590) | wayback.csv | 385/480 = 80.2%; 312/480 = 65.0%; 239 = 49.8%; 22 = 4.6%; old 349 = 72.7%, 365 = 76.0% | OK |
| "about double", "3.2 times", "a ninth" | same | BULK 38.0 / 35.1 / 15.7 / 42.6 | 2.11×, 1.85×; 3.17×; 0.108 | OK |
| **unedited, in the same section:** "NECR, 480 points (90,538 point-release captures, 52 distinct capture dates)" | ~552 | 20261023 log; wayback.csv | **89,814; 55** | **STALE** (first draw) |
| **unedited:** table 2017 6/237/106/131, 2023 148/115/102/115 | ~555-558 | wayback.csv | **2017 34/287/64/95; 2023 136/100/76/168** | **STALE** |
| **unedited:** "243 points (51%) within ±1 year of 2017 … 2023 has 263 (55%)" | ~560-561 | wayback.csv | **321 (66.9%); 236 (49.2%)** | **STALE**, and the direction reverses for 2023 |
| **unedited:** "639 of the 960 picks at 0.5 m; 211 at zoom 17, 749 at zoom 18" | ~562-563 | wayback.csv | **596; 209 / 751** | **STALE** |
| **unedited:** "176 of the 480 points have a neighbour within 300 m" | ~568 | sample.gpkg geometry | **119** (176 on d4a3101) | **STALE** |
| **unedited:** "At NECR point 1 (`17_00009`) the 2017-11-16 release serves a 2013-05-06 capture…" and the "2017-06-11, 0.31 m" example | ~541-543, ~594 | review_key.csv: `17_00009` moved (cell 22,170,746 → 35,503,676); log shows review_id 1's 2017 pick is 2016-06-30, 0.31 m | describes the moved point | **STALE** (point_id is not an identity) |
| Composite windows: four empty month-years | R644-645 | window CSV status | 2017-4, 2017-5, 2017-7, 2021-9 | OK |
| July 2019 0.149 (0.180), June 2019 0.840 (0.811) | R646 | CSVs | 0.1493 / 0.1804; 0.8397 / 0.8114 | OK |
| only May and August pass in every year except 2017 | R647 | CSV at threshold 0.95 | May, Aug | OK |
| tie: 0.999 vs 0.963 (0.9985 vs 0.988) | R648 | CSVs | 0.99874 / 0.96306; 0.99850 / 0.98803 | OK |
| Sep 2017 0.998; direct Aug–Sep count 0.999 (1.000) | R650 | CSV 0.998357; the direct count is in no CSV | log line only | partly checkable |
| windows the same on both; `windows.csv` scenario all_ff04 | R641, R652 | windows.csv now and at d4a3101 | identical months | OK |
| early: May in six (June 2017); ch: May in five, April 2021 | R654-655 | CSVs | yes; yes | OK |
| late: Oct ×3 (2018, 22, 23), Sep in 2017/19/20, Aug in 2021; ch Oct ×4 | R655-656 | CSVs | yes; ch Oct in 2018/19/22/23 | OK |
| C: key "A forced redraw starts a new one" | C265-266 | sample_draw-pilot.R:119-127 skips the key check under FORCE; fp_acc_review_key's design check refuses a stale key | done by hand, refused loudly otherwise | OK |
| C: NECR redrawn on all_ff04 | C308-309 | design.json | transition_all_ff04_2017_2023 | OK |
| C: windows files name their scenario, read through the two readers | C311-312 | grep: chip_build, review_build, review_render, derive | every reader goes through them | OK |
| C: sieve removes 17% (all_ff04) | C315 | 204,033 / 1,223,380 | 16.7% | OK |
| C: (#140; fixed there …) | C896 | #140 archive README: check (5) PASS; 20261023 free log: ALL PASS | — | OK |

## Findings

- **[bug]** `research/landcover_accuracy.md:134`. The fire row's IO omission is printed as **0.333**.
  From the CSV's own cells it is 1 − 98,895/148,156 = **0.33249, i.e. 0.332**. The stored 0.3325 was
  rounded a second time, which is the same defect round 2 fixed one row up for criterion 4. Fire
  does not feed a criterion, but it is a published value.
- **[bug]** The `research/landcover_accuracy.md` section "Esri Wayback captures nearest each
  endpoint" (about lines 540–595) still gives the **first draw's** numbers in present tense under
  "NECR, 480 points". That section names `reference/necr/wayback.csv` as its product, and this
  branch regenerated that file. Against the committed file:
  - point-release captures and distinct dates: 90,538 / 52 against 89,814 / 55;
  - the 2017 row: 6/237/106/131 against **34/287/64/95**;
  - the 2023 row: 148/115/102/115 against **136/100/76/168**;
  - within ±1 year: "243 (51%)" against **321 (67%)** for 2017, and "263 (55%)" against **236
    (49%)** for 2023. The ranking flips: 2017 is now the better-covered endpoint;
  - picks at 0.5 m: 639 against 596; zoom 17 / 18: 211 / 749 against 209 / 751;
  - neighbour within 300 m: "176 of the 480" against **119** (computed from sample.gpkg);
  - the point-1 (`17_00009`) release/capture example and the "2017-06-11, 0.31 m" label example
    describe a point that moved. The redraw put `17_00009` on another cell.

  The branch edited three lines of this section with all_ff04 values ("766 MB", "160 of 480 (115 on
  the first draw)", the BULK ratios). It left the header at `Verified: 2026-10-08`. So a reader
  sees, in one section, a table that contradicts the line below it: 160 same-capture points sit
  beside a table in which 2023 is better covered than 2017. This is the class of round 2's
  window-share finding, one section over.
- **[bug]** `research/landcover_accuracy.md:173-174`. The new bracket reads "(`ch_ff04`: … 0.411–0.445
  overall)". The `ch_ff04` floodplain Trees minimum is 2021's **0.4099 → 0.410**. 0.411 is 2019's
  0.4108, copied from the pre-branch sentence. The spread it states, 3.5 points, is right.
- **[fragile]** `research/landcover_accuracy.md:221-222`. The branch added the date "(2026-10-02)" to
  the 48.9% / 287.8 of 588.9 ha / 94.2% measurement. `git log -S` and the #93 archive (README:47,
  progress:22) both place it at **2026-09-29** (#93, 8d619d8). No #103 file re-measures it. The value
  stands; the provenance date is wrong.
- **[fragile]** `research/landcover_accuracy.md:148`. "Nearly all of the fire row is the 2018 fires"
  was 99.95% on `ch_ff04` and is **90.2%** on `all_ff04` (1,335.8 of 1,481.6 ha). The 2021 fire is
  145.5 ha, at a different omission (0.28). State the share instead.
- **[fragile]** `research/landcover_accuracy.md:511`. "Only a redraw re-measures it" names the wrong
  trigger. The windows are counted over the floodplain, and the readers refuse on **scenario**, not
  on the draw. A redraw on the same scenario needs no re-measure, and a scenario change needs one
  however it arrives. The accurate sentence is something like "a scenario change re-measures it".

Code diff, `diff_code.patch`, re-read: **clean**.
- Both readers refuse a missing, NA, mixed or other scenario, and an empty file. `NA %in% s` is FALSE.
- `month.abb` is locale-independent, and `month_lab` gets character months from the reader.
- `window_count-clear.R` stamps `cfg$primary_scenario`, which is the same value whose floodplain
  layer it counts over (line 50).
- Every reader of `windows.csv` and `windows_clear_obs.csv` goes through the two helpers.
- The fixtures reach each refusal arm.
