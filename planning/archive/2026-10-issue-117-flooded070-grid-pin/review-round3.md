# #117 branch review — round 3

Scope: `branch.diff` (merge-base...HEAD, index.html excluded), the changed files read in the repo,
issue bodies #117 / #125 / #128 / soul#402 / flooded#78 / stac_floodplains_bc#76, flooded#67 + PR #77,
flooded 0.7.0 NEWS and DESCRIPTION (at 698042e), soul `origin/main:conventions/code-check-spatial.md`,
the scratchpad snapshot `before/provenance.json`, `after_run1.json`, `after_run2.json`, run logs,
and every `data/*/provenance.json`.

## The mechanism

Rounds 1 and 2 found one shape eight times: **a fact restated away from its source loses its
referent, or keeps a referent the branch moved.** A vector copied from flooded#67 kept its numbers
but lost its direction (sf minus terra), +0.17% lost its base (the 9.8.1-grid replay), "PROJ 9.5.1"
was attached to a run that never recorded a PROJ, and a parity sentence, a drift floor and a
Prerequisites line still described a state the branch had changed. The fix in each case was to
carry the referent: which run, which library, which base, which date.

The author enumerated two sets that this reaches: (a) package floors, (b) percentages. A third set
exists: (c) **dated and versioned referents**, meaning every "from/since/unchanged from <date>",
"on <version>", "current" and "the old grid" the branch writes, plus issue-state claims ("closed",
"done on its branch"). That set is where the findings below come from.

## Findings

- **[fragile, minor] scripts/run_area.R:28, CLAUDE.md:649 (neexdzii bullet), CLAUDE.md:168 (#108
  bullet), logs/20261013_flooded070_rebaseline_neexdzii.md table header — digest comparisons are
  dated to 2026-09-01, when no digest existed.**
  - run_area.R says "The network is unchanged from the 2026-09-01 baseline (same content digest)",
    and CLAUDE.md says "the network digest is unchanged from 09-01".
  - #108's sentence now reads "reproduced the 2026-09-01 parity (770.0 ha, 2,032 patches, the
    transition `outputs_hash` byte-identical)".
  - `outputs` / `outputs_hash` / `streams_content_sha256` were introduced by #65, merged
    2026-09-02T21:03Z (PR #74). The snapshot this branch compared against is the 09-02 record:
    network `2026-09-02T19:43:33Z` (streams digest `1f88bf8b…`), floodplain `2026-09-02T19:44Z`,
    landcover `2026-10-02T21:38:55Z`. The 10-02 step 3 that #108 cites compared its `outputs_hash`
    to "the pre-run record" (`logs/20261002_composition_build-rollout_necr-bulk.md:70`), not to
    anything from 09-01.
  - The 09-01 numbers (673.5 / 142.8 / 770.0) are the same values. The digests are not "from 09-01"
    and cannot be. Say "unchanged from the 2026-09-02 record (same content digest)", and in the
    log label the before column "2026-09-02 record (09-01 contract)". The landcover row comes from
    the 10-02 record.
  - The branch introduced this when it added the dates; the undated pre-branch #108 sentence did
    not claim it.

- **[fragile, minor] README.Rmd:322-324 (and README.md, index.html) — the README's one statement
  about which groups are at "the current model version" names only MCGR and PINE. After this
  branch, no published group is.**
  "This is **what is configured**, which is not the same as what has been modelled, published, or
  re-run at the current model version — MCGR and PINE are published but cannot be re-run as things
  stand (#76)."
  - Step 2 now refuses flooded < 0.7.0.
  - Every published floodplain record is pre-pin: 63 species entries with `dem_res_m` between
    30.06 and 30.60, flooded 0.5.0, terra 1.9.34. DUNC (unpublished) is also pre-pin.
  - The only area at the current version is neexdzii, which is unpublished.
  - Before #117 the sentence was accurate, because 21 of the 22 published groups had been re-run at
    the then-current flooded ≥ 0.5.0. Its referent ("current model version") moved under it, the
    same class as round 1's #108 sentence.
  - A reader now concludes that every group except those two is current. Add one clause saying
    every published floodplain predates flooded 0.7.0's grid (#117, re-run under #125). No count is
    needed, so #77's rule is not broken.

- **[fragile, minor] soul#402 body, "What is wrong" and "Proposed change" — the issue describes
  the convention as it stood before soul 7b2a125. Two of its four proposed changes are already on
  soul main.**
  soul commit 7b2a125 (2026-10-13T18:58Z) landed in `conventions/code-check-spatial.md` before
  soul#402 was filed (22:11Z). That commit already added:
  - the datum-step paragraph ("A template fixes the grid, not the values: the datum step is PROJ's
    choice too … ~1.3 m between PROJ 9.5.1 and 9.8.1, which is also what moved GDAL's suggested
    grid. Pin it with `terra::project(pipeline =)` …");
  - an evidence entry, "Corrected 2026-10-13 in flooded#67: the move above was the PROJ datum step,
    not the GDAL version".

  soul#402 still says "The rule **and its evidence** say the grid moved because GDAL 3.8.5 and
  3.13.0 choose differently", and still proposes "Add the second half: … pin the datum step" and
  "Evidence block: append the correction". Whoever picks it up would add both a second time.

  What is actually still wrong on soul main is narrower:
  - the heading;
  - the first sentence ("its pick changed between GDAL 3.8.5 and 3.13.0");
  - the diagnostic sentence ("To tell a GDAL change from a terra one, warp the same file through sf
    and through terra in one session").

  Narrow the body to those three, and say the rest landed in 7b2a125.

- **[fragile, minor] #117 body, Problem item 2 — "(flooded#67, done on its branch)" is stale.**
  - flooded#67 is closed. PR #77 merged 2026-10-13T18:47Z, and the v0.7.0 tag exists.
  - This branch edited the same bullet (it added the DUNC parenthetical) and left the state claim.
  - The "Resolved" section supersedes it, but the body is meant to read correctly from top to
    bottom (feature-workflow, "Issue bodies get edited").
  - Change it to "(flooded#67, merged as flooded 0.7.0)".

## Note (not a finding)

- CLAUDE.md:243 says "Every step-2 record from before 0.7.0 is on **the** old grid". There are two
  pre-pin grids:
  - the species records (terra 1.9.34, the no-shift grid);
  - DUNC (terra 1.9.50 per its record, written 2026-10-12, so the WGS 84-routed grid).

  Each moves differently on re-run, which matters only for #125's before/after accounting. "on a
  pre-pin grid" would be exact.

## Enumerations re-derived

- **(a) Floors.** Enforced in code:
  - flooded ≥ 0.7.0 (02:56, attribute_tag:67) and ≥ 0.6.4 for whole-network (02:46);
  - drift ≥ 0.10.0 (03:38), ≥ 0.19.0 (sample_draw-pilot.R:34), ≥ 0.20.0 (channel_probe-migration.R:36).

  Prose:
  - README.Rmd:337, README.md:208 and CLAUDE.md:740 all state flooded ≥ 0.7.0, drift ≥ 0.10.0 and
    terra ≥ 1.9-25.
  - terra 1.9-25 is confirmed in flooded's DESCRIPTION at 698042e (`terra (>= 1.9-25)`).
  - packages.R:13's `terra >= 1.8-10` and CLAUDE.md:755's `terra ≥ 1.8-10` describe drift#27's
    reason and are implied by the higher floor. They are not contradictions.

  Consistent.
- **(b) Percentages.** All re-derived and correct:
  - −0.42%: 35,618.0 / 35,769.1.
  - +0.17%: 35,679.2 / 35,618.0.
  - −0.25%: 35,679.2 / 35,769.1.
  - −0.55%: 142.040 / 142.823.
  - +0.44%: 773.43 / 770.02.
  - −0.6%: 40,888.2 / 41,142.9 (−0.62%).
  - ~1.3 m = √(1.138² + 0.612²) = 1.29 m; 1.14 m W / 0.61 m N.

  Each one names its base.
- **(c) Dated and versioned referents.** The four findings above, and the note, come from this set.
  These items in it check out:
  - DUNC "flooded 0.6.5": the record's sha 6f50840 = the v0.6.5 tag; `dem_res_m` 30.167632.
  - #117 "No species area has run step 2 since 2026-09-03": the latest species step 2 is unth
    2026-09-03T20:05Z.
  - Log "flooded 0.7.0, github@698042e": a post-tag CLAUDE.md sync commit, `Version: 0.7.0`.
  - run 1 / run 2 launch times against entry stamps.
  - #125's `dem_res_m` 30.167632 and its cache predicate (run_region.R:180).
  - link#328 closed.

## Checked and clean

- Live state re-derived from `data/neexdzii`:
  - `co_ff04` vector area 142.0398 km² (the #63 parity method is the vector `st_area`, and it
    agrees with the 157,822 × 900 m² cell count);
  - tree loss 773.43 ha over 788 of 2,018 patches;
  - network 673.4775 km over 1,915 segments.
- Run 1 against run 2 (`after_run1.json` / `after_run2.json`): `inputs_hash` and `outputs_hash`
  are equal for floodplain co_ff02 / 04 / 06 and landcover co_ff04, the composition's two hashes are
  equal, and every raster stamp moved. Neither run log matches `Execution halted` or `^Error`.
- Snapshot against run 1, field by field:
  - network `inputs`: only the fresh and link stamps moved;
  - floodplain `inputs`: only dem_*, plus the flooded stamp;
  - landcover `inputs`: only the three classified digests.

  This matches the log's "What moved".
- `fl_dem_aoi()` 0.7.0, deparsed: the template is built from `aoi_buf` in `target_crs`. For a 3005
  AOI it is not transformed at all. The read window is `sf::st_transform(aoi_buf, r_crs)`
  (unpinned), and the warp passes `pipeline`. The fp_toolchain comment and flooded#78's quoted code
  match the function.
- The fp_toolchain comment says gdalcubes "links the same system libraries as terra" here:
  `gdalcubes_gdalversion()` reports GDAL 3.13.0, the same as `terra::gdal()`.
- The landcover_accuracy `fl_dem_aoi()` callers pass a 3005 bbox. 0.7.0's new geographic-CRS `res`
  requirement does not reach them.
- Date gate:
  - the terra arms sit inside the `SECTIONS_WITH_RASTERS` branch, after the all-NA arm, so an
    all-NA toolchain cannot slip past as a terra-only problem;
  - an empty or missing step time is treated as old, and the separate `datetime_utc` arm reports
    it;
  - all 63 species entries and DUNC resolve to pre-cutover, and neexdzii's four entries carry
    3.13.0 / 9.8.1.

  No hole found.
- No consumer validates `run.toolchain` keys strictly. A grep of stac_floodplains_bc finds only its
  own sf-based pin in `stage_years-check.R`.
- The probe records `flooded` in every json, and `report` refuses arms run across an upgrade, so a
  stale `dem_common.tif` cannot be mixed with a 0.7.0 replay unnoticed.
- No script asserts the old 142.8 / 770.0 contract. The remaining mentions are dated history
  (CLAUDE.md:427, 654; archives).

/Users/airvine/Projects/repo/floodplains/planning/active/review-round3.md
