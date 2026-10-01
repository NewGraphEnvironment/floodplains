## Outcome

The second branch of #93. It ran the two steps that drift#92 had blocked, and #93 stays open for
the human labelling, the estimates and the verdict.

- **Upgrade.** drift went to 0.20.0, which counts distinct clear days.
- **Rule first.** The composite-window rule was pre-registered in its own commit (9847d35) before
  any count ran.
- **Windows.** They were measured and written to `reference/necr/windows.csv`.
- **Chips.** 1,800 review chips were built and added to the rfp QGIS project.

What was learned:
- **The rule needed its one allowed deviation.**
  - No month is clear everywhere in all seven years.
  - Without 2017, August is the same season.
  - 2017 is clear only once widened to August–September.
  - HLS is therefore not needed for the endpoint.
- **/code-check ran 3 rounds and then an enumeration.**
  - Round 1 found a type-inference bug: an all-single-month `windows.csv` reads back as
    integer. It also found two gaps in the rule.
  - Round 2 surfaced drift#87: failed gdalcubes chunk reads never reach R.
  - Round 3 found the gap inside that fix: the log grep did not cover `derive` or the logs
    that filled the cache.
  - The mechanism is "a reader inferring an unrecorded fact from a value's appearance". The
    enumeration covered 13 sites.
- **A latent defect surfaced on first use.** `chip_rgb.qml`, committed in #101, carried an
  invalid `--` in an XML comment. Nothing had ever read it, because no chips existed.

The durable verdicts are in `research/landcover_accuracy.md` ("Composite windows").

## Measurement

- **Validate** (2021-07):
  - res 100 and res 20 agree (median 5 days).
  - The max is 6 days, bounded by 6 distinct dates out of 17 items.
  - The whole floodplain took 0.8 min, with 0.9996 of cells seeing at least 1 clear day.
- **Run:** 49 month-years in 27 min, 0 failed, 0 chunk-error lines.
  - Four month-years have no scene under 20% cloud: 2017 April, May and July, and 2021
    September.
  - July 2019 reaches only 0.180.
- **Span:** August. It ties with May on length and wins on minimum share, 0.9985 against
  0.988.
- **2017:** August scores 0.852. The direct count of August–September scores 1.000.
- **Chips:** 1,800 with 0 missing, 15.8 h at 31.5 s each (the 09-29 estimate was 44 s). The
  worst chip is 1.0% NA.
- **Wrong turn kept:** the first chip-time estimate of ~22 h came from 30 chips, and the full
  build was 28% faster per chip.

## Evidence

`scripts/landcover_accuracy/logs/20260930_*` · review rounds and enumeration in this directory (`review-*.md`)

Closed by: PR (Part of #93), branch `93-lulc-accuracy-windows-chips`
