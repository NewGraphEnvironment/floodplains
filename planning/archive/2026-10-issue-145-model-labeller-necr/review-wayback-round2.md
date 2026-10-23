# Code check, round 2: BULK Wayback coverage (#145 Phase 5)

## Checklist read

- `code-check-python.md` in full (no Python in this diff; nothing applies).
- `code-check.md`, prose of every H3 under `## Mechanisms` (table rows skipped). Most relevant: "A proxy is
  not the property" (a sentence describing a result is a claim about the criterion), "A guard's scope"
  (quantifiers end on an enumeration), "Verification that reads its own output".
- `code-check-r.md` sections for the shapes used: `$` partial matching, `ifelse()` with an all-NA test,
  `merge`/`c()`, "Rscript reads a script as it runs".
- `code-check-spatial.md`: `st_make_valid()` rewrites valid geometry (harmless here: the union is only
  sampled), "A Freshwater Atlas ..." not applicable.
- floodplains `CLAUDE.md`, agent-operations "Documents that share an ancestor corroborate nothing":
  every "most", "a quarter", "about double", "about half", "every", "no ... in any release", percentage
  and count walked against `data/bulk/accuracy/wayback_coverage.csv` and `reference/necr/wayback.csv`.

## What was verified (holds)

Recomputed from `data/bulk/accuracy/wayback_coverage.csv` (2,000 rows, 0 NA):

- Band table 32/242/106/620 and 53/264/34/649; within ±2: 38.0% / 35.1%; both 15.7%, exactly one 41.7%,
  neither 42.6%; same capture at both endpoints 27.6% (276).
- 2017 picks in 2014: 449 (44.9%); 2023 picks: 264 in 2022, 375 in 2020, 258 in 2010–2016 (−7 to −13),
  so "a quarter" (25.8%) holds. Median res 0.50 / 0.46 m, range 0.31–0.60; zoom 17 serves 755 of 2017,
  zoom 18 serves 936 of 2023, zoom 19 none; newest capture over all captures 2025-06-10; every point has a
  capture at both endpoints; 62% / 65% without one within ±2; ±0.03 interval at p≈0.37, n=1000 (0.030).
- Run time 15:01:51Z → 15:59:25Z = 57.6 min. drift 0.24.3 has 197 releases (2014-02-20 → 2026-09-24).
- "No release shows those points between 2015 and 2019" and "no capture newer than 2016 in any release":
  `dft_wayback_pick` picks by days over all captures, and `wayback_zoom_keep` keeps one zoom per point per
  release, so a capture at a different zoom could have been hidden. Re-ran `dft_wayback_captures()` once
  per zoom (17, 18, 19) on the reproduced points, from drift's metadata cache only (all 591 keys present,
  0 network queries): of the 449 2014-picks, 0 have any 2015–2019 capture at any zoom; of the 258
  ≤2016 2023-picks, 0 have any capture after 2016 at any zoom. Both claims hold across zooms.
- NECR comparison: 349/480 (72.7%) and 365/480 (76.0%) from `reference/necr/wayback.csv`; per-endpoint
  ratio 1.9× / 2.2×, so "about double" / "about half" hold **for the single-endpoint shares**.

## Findings

- **[severity: bug]** `planning/archive/2026-10-issue-145-model-labeller-necr/README.md:54` and
  `pr_body.md:8` — "and of both for 15.7%: about half NECR's share" / "and of both for 15.7%, about half
  NECR's share". The ratio clause sits directly on the both-endpoints figure, but NECR's both-endpoints
  share is 270/480 = **56.3%** (`reference/necr/wayback.csv`), so 15.7% is about **a quarter** of it
  (0.28×), not half. "About half" is true only of the per-endpoint shares (38.0/72.7 = 0.52,
  35.1/76.0 = 0.46). Either move the clause after the per-endpoint figures or state both ratios.

- **[severity: bug]** `scripts/landcover_accuracy/logs/20261023_wayback_coverage_bulk.md:28-29` —
  "27.6% has the same capture at both endpoints, so Wayback dates only one side of any change there."
  Of those 276 points, **184 (two-thirds) have that capture more than ±2 years from both endpoints**, and
  only 92 have it within ±2 of one. At most points with a shared capture Wayback dates *neither* side under
  rule 5's band. "At most one side" (the wording line 53 already uses) is correct; "only one side" is not.

- **[severity: bug]** `scripts/landcover_accuracy/logs/20261023_wayback_coverage_bulk.md:48-49` and
  `pr_body.md:8` — "has no capture within +/-2 years, so Sentinel-2 alone dates that side". This asserts
  an absence that was not measured: the run measured Wayback only. BC orthophotos and air photos are dated
  sources this module already indexes (`imagery.csv`, #103), and in NECR they reach the endpoint band:
  `reference/necr/imagery.csv` has a **2021 orthophoto at 204 of 480 points** (within ±2 of 2023) and a
  **2019 air photo at 14** (within ±2 of 2017). BULK has no `reference/bulk/imagery.csv` yet, so whether
  Sentinel-2 is alone there is unknown. Scope the sentence to Wayback ("no Wayback capture dates that
  side; orthophoto and air photo coverage is not yet indexed for BULK"). The script header
  (`wayback_coverage-area.R:4-5`, "decides ... which rest on Sentinel-2 alone") makes the same leap, though
  as a design statement it matters less.

- **[severity: fragile]** `research/landcover_accuracy.md:562-564` — the bullet lists 38.0%, 35.1%,
  "both 15.7%" and "42.6% has none at either", then says "the gap is about double". That holds for the two
  single-endpoint shares only. Against NECR, the both-endpoints share is 56.3% vs 15.7% (3.6×) and the
  neither share 7.5% vs 42.6% (5.7×). Because the research file is the durable verdict, name which
  shares the "about double" is about (the log's "Against NECR" paragraph already does), or the
  sentence will be repeated as covering all four.

No defects found in the script mechanics (`wayback_coverage-area.R`) or `packages.R`.
