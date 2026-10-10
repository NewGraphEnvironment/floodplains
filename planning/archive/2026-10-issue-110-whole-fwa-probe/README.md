# #110 — Probe: cost and difference of a whole-FWA floodplain on MORR

## Outcome

- **What was built.** A read-only probe (`scripts/floodplain_lcc/floodplain_probe-*.R`,
  `fp_whole_fwa.R`). It delineated MORR `co_ff04` from five networks on one common DEM:
  - all `fresh.streams`;
  - order ≥ 2;
  - order ≥ 3;
  - order ≥ 3 plus bcfp's bypass;
  - the coho network.
- **Timing and memory.** DEM fetch, delineation and attribution were timed separately, each in its
  own process, for a peak RSS each.
- **The anchor proved the probe's copies of step 1 and step 2.** The network digest matched step
  1's record, and the floodplain digest matched a same-day `fp_floodplain()` replay.
- **It also found the published record is not reproducible on today's toolchain.** terra 1.9.50
  links GDAL 3.13, and its reprojection puts the DEM grid ~1 m off. Filed as #117 and flooded#67.
- **The verdict** is in [`research/whole_fwa_floodplain.md`](../../../research/whole_fwa_floodplain.md),
  and #104's body now plans against it.
- **What was learned:**
  - Delineation is cheap at every floor; per-watercourse attribution is the cost.
  - Floodplains are not monotone in their seeds.
  - The pre-registered visual criterion was drafted ambiguously, and the two readings give opposite
    answers on whether today's items are superseded. The user decides.

## Measurement

All on one machine (m1), flooded 0.6.0, terra 1.9.50, one scenario (`co_ff04`).

| arm | km | blue lines | floodplain km² | VCA min | blue-line attribution min | peak GiB |
|---|---|---|---|---|---|---|
| all `fresh.streams` | 9,033 | 6,753 | 651.9 | 2.8 | 87.0 | 9.0 |
| order ≥ 2 | 3,471 | 1,711 | 478.8 | 1.9 | 33.0 | 7.9 |
| order ≥ 3 | 1,651 | 401 | 374.8 | 1.4 | 17.6 | 8.9 |
| bypass | 2,835 | 1,195 | 454.5 | 1.7 | 28.9 | 9.1 |
| coho | 1,296 | 340 | 356.5 | 1.2 | 13.8 | 9.3 |

- **Attribution cost:**
  - It fits 790 s + 0.66 s per blue line.
  - About 13 min of that is flooded's `complete = TRUE` fallback. The coho network attributed as
    one group with `complete = FALSE` took 5.0 s.
  - Segment grain measured 0.248 s per segment on order ≥ 3, i.e. 31.5 min for 7,606 segments.
- **Coho network's floodplain moved** (supersession) under each delineation:

  | floor | moved |
  |---|---|
  | order ≥ 3 | 1.6% |
  | bypass | 9.9% |
  | order ≥ 2 | 16.6% |
  | all streams | 30.8% |

  The all-streams floodplain *loses* 452 ha (1.3%) of today's coho floodplain.
- **Habitat below order 3:** 25.2% of coho rearing, which reproduces #104's 20–29%.
- **What changed because of the numbers:**
  - Order ≥ 1 is ruled out on cost.
  - The floor is order ≥ 2 or order ≥ 3, depending on the visual read.
  - Grain follows the floor: blue line at ≥ 2, segment at ≥ 3.
  - #104 learned that a republish is needed at order ≥ 2 but not at order ≥ 3.
- **Wrong turns, kept:**
  - **The first anchor stopped on the DEM digest.** It was diagnosed as a toolchain change, not
    data (the MRDEM S3 object is unchanged since 2026-06-24), and the anchor was redesigned around
    a replay.
  - **The first coho-reach pass ran with `complete = TRUE` by omission,** so the coho floodplain
    equalled the whole floodplain. The run was stopped during arm 3, and the reach pass got its own
    mode with a partition guard.
  - **Every code-check round from 2 to 4 found a defect inside the previous round's fix,** all of
    one mechanism. The report's ties trusted names, presence, or two mutable stores agreeing now.
    The loop was closed by enumerating every input (`review-round4.md`).
  - **Round 3 caught the recommendation going beyond the registered rule.** It is now conditional
    on both readings of criterion 3.

## Evidence

`scripts/floodplain_lcc/logs/20261009_floodplain_probe-whole-fwa_morr.*` (committed).
Gitignored, on m1: `data/morr/probe_whole_fwa/`, which holds the per-mode logs, the jsons, the
review gpkg and panels, and `step2_replay/`.

Closed by: PR for branch `110-probe-cost-and-difference-of-a-whole-fwa`
