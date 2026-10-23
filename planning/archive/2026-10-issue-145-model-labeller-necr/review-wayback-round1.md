# Code-check round 1: wayback_coverage-area.R and the BULK coverage log (#145)

## Checklist read

- code-check-python.md: in full (N/A, no Python in the diff).
- code-check.md: all 14 H3 prose sections under `## Mechanisms`, without the `|` table rows. None of the 18 under "Rules that stand alone", Security, or Spreadsheets and PDFs, because their index lines name nothing this diff uses.
- code-check-r.md: read 8 sections: `package_version()` errors on a pre-release, `match()` treats NA as a value, `ifelse()` with an all-NA test, `c()` dispatches on its first argument, `sample.int(prob =)`, `as.integer("NaN")`, `stats::aggregate()`, and `sort()`/`order()` collate by locale. The remaining ~110 were not read; their index lines name nothing this diff uses.
- code-check-spatial.md: read 3 sections: `st_make_valid()` rewrites valid geometry, `st_union()` after `st_transform()` with mixed XY/XYZ, and a GDAL failure partway through `st_read()`. The remaining ~95 were not read.
- code-check-shell.md: none read, because the diff contains no shell.

## What was verified (no defect)

- **Every number in the log was recomputed from `data/bulk/accuracy/wayback_coverage.csv`:**
  - the band table (32/242/106/620 and 53/264/34/649), with 38.0% and 35.1% within +/-2;
  - both endpoints within +/-2: 15.7%;
  - the same capture at both endpoints: 27.6%, whether matched by date, by date and resolution, or by release;
  - 449 picks in 2014 at 2017; 264 picks at -1, all of them 2022; 375 at -3; 258 between -7 and -13;
  - resolution 0.31-0.6 m, medians 0.50 and 0.46;
  - zoom 17: 755 picks at 2017; zoom 18: 936 at 2023; zoom 19: none;
  - the newest capture, 2025-06-10;
  - no point without a capture;
  - the 95% half-width of about 0.03, the runtime of 57.6 min, and NECR's 349/480 (73%) and 365/480 (76%).

  All of them match.
- **The sample reproduces.** I re-drew the 1,000 points with the script's own code and seed. I then read every release's zoom 17-19 metadata from drift's cache and joined it outside `dft_wayback_captures`, keeping the top DrawOrder and the deepest zoom per release. Re-picking by days from 1 July gave the CSV's capture date at 2,000 of 2,000 (point, endpoint) rows.
- **The days-versus-whole-years band equivalence holds on this data.** A pick ranked by whole years first (NECR's `fp_acc_wayback_pick` ordering) gives the same signed year offset as drift's pick at 2,000 of 2,000 rows. The argument has a 1-2 day hole around 1 January (for example, Y-1 Dec 31 is 182 days from 1 July Y, while Y Dec 31 is 183). No capture in any release over these points is dated outside April-October, so the hole is empty here.
- **"No capture newer than 2016 in any release" holds, and it does not depend on drift keeping only the deepest zoom per release.** None of the 258 points has a capture dated after 2016 at any of zoom 17, 18 or 19 in any of the 197 releases. Taking captures from every zoom rather than the deepest one leaves 38.0% / 35.1% / 15.7% unchanged.
- **The script itself** has no defects:
  - `feature = seq_len(n)` matches drift's row-index `feature`;
  - points with no capture would survive the `merge(all.x = TRUE)` as NA and land in "no capture";
  - `cut()` puts 0 in "same year";
  - `write.csv(na = "")` is explicit;
  - the CRS is EPSG:3005, so the random points are equal-area;
  - the drift version floor is compared correctly.

## Findings

- **[severity: bug, wrong claim]** research/landcover_accuracy.md (new bullet), "Most of the 2017 side was last flown in 2014": 449 of 1,000 2017 picks (44.9%) are 2014 captures. That is the largest group, not a majority. "Last flown in 2014" is also wrong for most of those 449: 339 of them have a later capture (their 2023 picks are 2020: 242, 2021: 9, 2022: 71, 2023: 17). The log's own wording is correct ("449 of the 2017 picks are 2014 captures ... no release shows those points between 2015 and 2019"). The research bullet compressed it into a quantifier and a tense the CSV does not support.

- **[severity: bug, wrong claim]** research/landcover_accuracy.md (new bullet) "In BULK, Sentinel-2 carries most labels alone", and scripts/landcover_accuracy/logs/20261023_wayback_coverage_bulk.md ("What it decides") "Sentinel-2 composites carry most points alone": the CSV gives the following shares:

  | points with a capture within +/-2 years at | share |
  |---|---:|
  | neither endpoint | 42.6% |
  | exactly one endpoint | 41.7% |
  | both endpoints | 15.7% |

  So Sentinel-2 is the only source within +/-2 years at either endpoint for a minority of points, not most. The supported statements are about one endpoint or about both:
  - "at each endpoint, most points (62% at 2017, 65% at 2023) have no capture within +/-2 years";
  - "84% lack a capture within +/-2 years at one endpoint or both".

  Restate it as one of these, or give the 42.6% figure.

scripts/landcover_accuracy/wayback_coverage-area.R and scripts/packages.R: no findings.
