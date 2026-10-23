## Checklist read

- `code-check.md`, every H3 under `## Mechanisms` (prose, `|` rows skipped), in full: "A guard that fails toward pass", "A fixture that cannot reach the failure mode", "A proxy is not the property", "Verification that reads its own output", "A guard's scope, escape hatches, and remedies" (including its "Terminating means enumerating..." and "Compression runs both ways" paragraphs), "A fix lands in one of two callers...", "Restore the bug and prove the guard fires", "A shared working tree...", "A wrapper's exit is not the work" (head).
- `code-check-r.md`, the index lines for what this script uses: `ifelse()` with an all-NA test, `merge`/`as.integer` coercions, `$` partial matching, `tryCatch`, `sort()` locale. None applies: `ifelse()` there has a character `no` branch, and `$` is used only on columns that exist.
- `code-check-spatial.md`, the index lines for `st_make_valid()` (it rewrites geometry, but here only for the sample, never written back), `st_sample` on a projected CRS, and the Wayback rules (capture date versus release date, one zoom per call).

## Method

Every number was recomputed in R from `data/bulk/accuracy/wayback_coverage.csv` (2,000 rows, 1,000 features, 0 NA `years`), `reference/necr/wayback.csv` (960 rows, 480 points), `reference/necr/imagery.csv`, and the per-zoom capture table `zz/allc.rds` (zoom 17: 181,376 rows; zoom 18: 40,355; zoom 19: 0). The script is `scratchpad/r3/enum.R`. drift's `dft_wayback_captures`, `wayback_zoom_keep` and `dft_wayback_pick`, and the repo's `fp_acc_wayback_pick`, were read from source. `accuracy-check.R` was run in a copy of the repo without `data/` (`scratchpad/r3/copy`): 217 PASS lines, ALL PASS.

Notation: `p17` and `p23` are the BULK rows per endpoint, `w17 = abs(p17$years) <= 2`, `w23` likewise, and `a` and `b` are the same flags for NECR.

## Enumeration

| # | file:line | claim | derivation | verdict |
|---|---|---|---|---|
| 1 | research +560 | 1,000 area-random points on `all_ff04` | `nrow(p17)` = 1000; `area.yml` primary_scenario all_ff04; CRS BC Albers (equal-area), `st_sample(type="random")` with s2 off | holds |
| 2 | research +561 | within ±2 years of 2017 for 38.0% | `mean(w17)` = 0.380 | holds |
| 3 | research +561 | of 2023 for 35.1% | `mean(w23)` = 0.351 | holds |
| 4 | research +562 | both 15.7% | `mean(w17&w23)` = 0.157 | holds |
| 5 | research +562 | 42.6% has none at either | `mean(!w17&!w23)` = 0.426 | holds |
| 6 | research +562 | nearest to 2017 is a 2014 capture for 44.9% of points | `sum(y17==2014)` = 449 | holds |
| 7 | research +563 | a quarter of the floodplain has nothing newer than 2016 | 2023 picks with a capture year ≤ 2016 = 258; per-zoom `max(year)` ≤ 2016 = 258 of 1000 across zooms 17 and 18 in every release (zoom 19 has none) | holds (in the zooms queried, 17–19, as the log's Pick line states) |
| 8 | research +563 | NECR's points are a stratified sample, so not one estimate | design of `reference/necr` | holds |
| 9 | research +564 | NECR per-endpoint shares about double BULK's (73% and 76%) | 349/480 = 0.727 and 365/480 = 0.760; ratios 1.91 and 2.17 | holds |
| 10 | research +565 | both-endpoint share 3.6 times (56.2%) | 270/480 = 0.5625; 0.5625/0.157 = 3.58 | holds |
| 11 | research +565 | neither share a sixth (7.5%) | 36/480 = 0.075; 0.075/0.426 = 0.176, nearer 1/6 than 1/5 | holds |
| 12 | research +565-566 | only Wayback measured; BULK orthophoto and air photo coverage not indexed | `reference/bulk` does not exist | holds |
| 13 | log 4 | metadata only, no tile fetched | the script calls only `dft_wayback_captures` and `dft_wayback_pick` | holds |
| 14 | log 8-9 | 15:01:51Z to 15:59:25Z, 57.6 min | 57 min 34 s = 57.57 min | holds |
| 15 | log 9-10 | almost all of it the 197 releases' metadata queries, which a re-run reads from cache | the per-release loop is the only network work; perzoom.R found 0 cache misses over 197 releases × layers 4:6 on this bbox | holds |
| 16 | log 11-12 | each share estimates a share of floodplain area | equal-probability points in an equal-area CRS | holds |
| 17 | log 12-13 | 95% interval near 0.37 is about ±0.03 | 1.96·sqrt(.37·.63/1000) = 0.030 | holds |
| 18 | log 14-15 | drift picks by days from 1 July; NECR picks by whole years first | `dft_wayback_pick` orders on `abs(days)`; `fp_acc_wayback_pick` orders on `abs(yrs)`, then days | holds |
| 19 | log 16-17 | a capture k years off is between k−0.5 and k+0.5 years away, so the bands compare | with a 1 July anchor, a capture in year E+k lies (k−0.5, k+0.5] years away, so the nearest by days has the minimal whole-year offset (up to boundary ties) | holds |
| 20 | log 18-19 | every point had a capture at both endpoints | `sum(is.na(d$years))` = 0 | holds |
| 21 | log table | 2017: 32/242/106/620; 2023: 53/264/34/649 | `table(endpoint, band)` | holds |
| 22 | log 28 | both 15.7%, exactly one 41.7%, neither 42.6% | `mean(xor(w17,w23))` = 0.417 | holds |
| 23 | log 28-30 | 27.6% (276) has the same capture at both endpoints; one side at 92, neither at 184 | same release_id = same capture_date+res = 276; of those, xor = 92, neither = 184, both = 0 | holds |
| 24 | log 30-31 | 449 of the 2017 picks are 2014 captures, 3 years early | `sum(y17==2014)` = `sum(p17$years==-3)` = 449 | holds |
| 25 | log 31 | so no release shows those points between 2015 and 2019 | per-zoom table: 0 of 449 have any 2015–2019 capture in any release at zoom 17 or 18 | holds (zooms 17–19) |
| 26 | log 32-33 | 264 picks are 2022, 375 are 2020, 258 are 2010–2016 (−7 to −13) | `table(y23)`; range of `years` for y23 ≤ 2016 is −13 to −7 | holds |
| 27 | log 33-34 | a quarter has no capture newer than 2016 in any release | 258 of 1000 by per-zoom max | holds (zooms 17–19) |
| 28 | log 34-35 | newest capture at any sample point 2025-06-10 | `max(allc$capture_date)` = `max(d$capture_date)` = 2025-06-10 | holds |
| 29 | log 36 | resolution 0.31–0.6 m, median 0.5 at 2017, 0.46 at 2023 | `range(d$res_m)`; medians 0.50 and 0.46 | holds |
| 30 | log 36-37 | zoom 17 serves 755 of the 2017 picks, zoom 18 serves 936 of the 2023 picks, zoom 19 none | `table(endpoint, zoom)`: 755/245 and 64/936; no zoom-19 rows | holds |
| 31 | log 41-42 | NECR 349 of 480 (73%) and 365 (76%) | as row 9 | holds |
| 32 | log 44-45 | per endpoint the gap is about double | as row 9 | holds |
| 33 | log 45 | BULK dates an endpoint for roughly a third of its floodplain | 38.0% and 35.1% | holds ("roughly") |
| 34 | log 46 | three-quarters of NECR's sample | 72.7% and 76.0% | holds |
| 35 | log 46-47 | both: 56.2% of NECR (270 of 480) against 15.7%; neither 7.5% (36) against 42.6% | as rows 4, 5, 10 and 11 | holds |
| 36 | log 51-52 | most of BULK's floodplain (62% at 2017, 65% at 2023) has no capture within ±2 years | `mean(!w17)` = 0.620, `mean(!w23)` = 0.649 | holds |
| 37 | log 52 | 42.6% none at either, 41.7% at exactly one | as row 22 | holds |
| 38 | log 53-54 | other dated sources not indexed for BULK | as row 12 | holds |
| 39 | log 55 | in NECR the 2021 orthophoto covers 204 of 480 points | `imagery.csv`: orthophoto rows all 2021, 204 unique points | holds |
| 40 | log 55-56 | so where Wayback is far, Sentinel-2 dates that side unless an orthophoto or air photo does | the sheets carry a Sentinel-2 composite for every year; the orthophotos and air photos are the only other dated sources named in rule 5 | holds |
| 41 | log 56 | rule 5 caps a label on an undated or far source | research line 276ff: "Older or newer imagery supports `low` at most"; undated basemaps `low` | holds |
| 42 | log 61-62 | both within ±2 (15.7%): Wayback can confirm a change; elsewhere it dates at most one side | the complement is exactly-one or neither | holds |
| 43 | script 9-10 | a point gets the one capture drawn on top there | `wayback_zoom_keep` keeps one zoom per feature per release | holds |
| 44 | script 11-12 | banded by whole years as rule 5 is (±2 supports high or medium) | rule 5, research 276ff | holds |
| 45 | script 26 / packages.R / PR 21 | drift ≥ 0.24.0 floor, which the script asserts | `packageVersion("drift") < "0.24.0"` stop | holds |
| 46 | README +53-56 | 38.0%, 35.1%, about half NECR's per-endpoint shares, both 15.7% (NECR 56.2%), neither 42.6% (NECR 7.5%), 2014 for 44.9%, a quarter ≤ 2016 | BULK/NECR = 0.52 and 0.46; the rest as above | holds |
| 47 | progress +40 | drift 0.20.0 → 0.24.3, fly → 0.24.1, flooded → 0.8.4, link → 0.68.0, ngr → 0.0.4, spacehakr 0.4.1 new | installed versions match on the "to" side; the "from" side cannot be derived now | holds (to side) |
| 48 | progress +40 | `accuracy-check.R` passes (217) | re-run in a copy: 217 PASS, ALL PASS | holds |
| 49 | progress +41 | 197 releases × 3 zooms, cached by bbox | the loop runs over `releases` × `23L - zoom` (3 layers); the cache key includes the bbox | holds |
| 50 | progress +41 | 57.6 min (15:01:51Z → 15:59:25Z) | as row 14 | holds |
| 51 | task_plan Phase 5 | 38.0% / 35.1% / both 15.7% | as above | holds |
| 52 | PR 8 | read every Wayback release's capture metadata | all `dft_wayback_releases()` rows (197), at zooms 17–19 | holds |
| 53 | PR 8 | 38.0%, 35.1%, about half NECR's, both 15.7% (NECR 56.2%), most has none within ±2 at each endpoint, 42.6% none at either, 44.9%, a quarter | as above | holds |
| 54 | PR 38 | BULK's thinner Wayback coverage | per-endpoint, both and neither all thinner | holds |
| 55 | PR 40 | **Agent count for this task: 21** (1 plan review, 2 canaries, 12 labelling batches, 6 code-check rounds) | the archive holds `review-wayback-round1.md` and `review-wayback-round2.md`, and this is round 3: at least 3 more review agents beyond the 6 `review-round*.md` | **wrong** |
| 56 | PR 29 | `/code-check branch` ran six rounds and ended on round 6's enumeration | true of the branch review, but the Wayback diff added since then has had its own rounds (wayback 1–3) | incomplete; part of F1 |

## Findings

**F1 (wrong count, PR body line 40).** "Agent count for this task: 21. That is 1 plan review, 2 canaries, 12 labelling batches and 6 code-check rounds." The Phase 5 Wayback diff has had at least three review agents of its own (`review-wayback-round1.md`, `review-wayback-round2.md`, and this round), so the total is at least 24, plus any further rounds. The Test plan's code-check line (line 29) describes only the six branch rounds and does not mention the Wayback rounds. That is the same staleness, arriving one section over. Fix the count, and add a line on the Wayback rounds to the Test plan. This sits outside the three bullets named for review, but it is a count in the same PR body that this work made stale.

**Code.** No defect found. Sampling is area-proportional: equal-area CRS, `type = "random"`, and an `exact = TRUE` count check. A point with no capture survives as NA through `merge(all.x = TRUE)` and is banded "no capture". The version floor sits before any network call. `ifelse()` there has a character `no` branch, so it keeps its type.

Every claim in the four named files and in the named PR bullets holds. The only row that does not is F1.

/Users/airvine/Projects/repo/floodplains/planning/archive/2026-10-issue-145-model-labeller-necr/review-wayback-round3.md
