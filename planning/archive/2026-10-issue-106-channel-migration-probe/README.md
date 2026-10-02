## Outcome

The question was whether IO LULC's Water-involving change inside the floodplain holds a separable
channel-migration cluster: long, thin, channel-adjacent erosion and deposition strips on opposite
banks. It was measured on NECR and BULK under a rule fixed before any criterion was applied. **Rule
v2 does not separate on those two groups**, so no `in_channel_change` tag was built. That is not
yet a verdict on IO: nothing is labelled, and the groups were not chosen for active channels. #106
stays open for labelled review. The probe, its helpers and an offline
check stay in `scripts/floodplain_lcc/`. The durable verdict is
[`research/channel_migration.md`](../../../research/channel_migration.md).

Three findings changed the work while it ran:

- drift's `dft_transition_artifact()` already measures this geometry and reads it as
  misregistration.
- Rule v1's same-side null would have been filled by real meanders.
- 2023, the endpoint, is a drought year.

The plan review caught all three (`review-plan.md`), and rule v2 answers them. v2 was committed
before any criterion ran, with a statement of what data had been seen by then.

## Measurement

| area, set | Water-involving ha | candidate share (A ≥ 0.20) | sustained lead (B ≥ +0.15) | opposite / same paired share (C) | R (D < 0.5) |
|---|---|---|---|---|---|
| NECR unsieved | 509.73 | 0.055 | −0.168 | 0 / 0 | no pairs |
| NECR sieved | 230.49 | 0.103 | −0.233 | 0 / 0 | no pairs |
| BULK unsieved | 696.08 | 0.143 | −0.068 | 0.051 / 0.089 | 0.55 (4 pairs) |
| BULK sieved | 390.41 | 0.198 | −0.040 | 0 / 0.093 | no pairs |

- **Most of the water change is sliver-width.** Patches under 1.5 px hold 69% of NECR's and 63%
  of BULK's unsieved Water-involving area, the shape drift calls misregistration.
- **The lake-margin exclusion matters.** It removes 48% of NECR's erosion and deposition area.
- **Both anchors held to the cell.** Re-sieving reproduced `transition.tif` with 0 differing
  cells (NECR and BULK). NECR's unsieved change was 5,779.45 ha, equal to the #93 strata.
- **What changed because of it:**
  - No tag is built.
  - Nothing new is published.
  - The next step is labelled review, not a decision about IO.
- **Wrong turns kept:**
  - Two fixture rotation bugs.
  - A first NECR run discarded because it predated the round-1 code-check fixes (the first-year
    Snow/Ice handling and the lake query).
  - Two mutations survived at first, because the fixtures could not reach them.

## Evidence

`scripts/floodplain_lcc/logs/20261002_channel-migration_*`

Landed by: PR #107 (relates to #106, which stays open)
