# Whole-FWA floodplain: cost, floor and grain

**Verified:** 2026-10-09 · **Issues:** #110 (this probe); gates #104; relates #40, #54, #65 ·
**Produced by:** `scripts/floodplain_lcc/floodplain_probe-run.sh` (logs
`scripts/floodplain_lcc/logs/*_floodplain_probe-whole-fwa_*`) · **Status:** OPEN — rule
pre-registered, MORR run pending.

#104 proposes delineating each watershed group's floodplain once, from the whole stream network,
keyed by `blue_line_key`, with habitat joined afterwards instead of cut into the geometry. Today
the floodplain is delineated from one species' accessible order ≥ 3 network. This file holds what
that change costs, which order floor is worth delineating at MRDEM-30, and whether the per-
watercourse grain should be the blue line or the segment.

## Method

One scenario (`co_ff04`), one group (MORR), five networks, all filters of one read of
`fresh.streams` with 01's SQL:

| arm | network |
|---|---|
| 1 | all of `fresh.streams` (order ≥ 1) — not quite all FWA: on MORR it holds 9,033 of `fwa_stream_networks_sp`'s 9,385 km; the 3.7% it omits is mostly edge types 1100, 1350, 1400 and 1450 |
| 2 | order ≥ 2 |
| 3 | order ≥ 3 |
| 4 | order ≥ 3 + first-order with `stream_order_parent >= 5` (bcfishpass's bypass predicate, not link's `frs_order_child` rule) |
| 5 | coho accessible, order ≥ 3 (step 1's network, the baseline) |

All five are delineated on one DEM (arm 1's bbox), so they compare cell for cell. Each is
attributed by `blue_line_key`, and arm 3 also by segment `(blue_line_key,
downstream_route_measure)`. Delineation, attribution and the DEM fetch are timed separately; each
stage runs in its own process for a peak RSS. Per arm, a single-group `complete = FALSE`
attribution from the **coho network only** gives the coho network's floodplain under that arm's
delineation: what a #104 consumer would get by querying the whole floodplain for coho, set against
today's item. That is the supersession question.

*Corrected 2026-10-09, after the rule was registered and before any result was read:* this text first
claimed the measure isolates the boundary move (#40: the flood surface is fitted from every seed)
from area added by new seeds. It does not. flooded's `fl_group_cells()` keeps the valley cells inside
a zone set by the coho seeds and the DEM alone, so the zone is the same for every arm. The measure
therefore also carries tributary-mouth valleys and waterbodies that new seeds bring into that zone,
and the report splits the waterbody part out. The rule's thresholds are unchanged.

Before any arm, an anchor proves the probe's copies of step 1 and step 2: its arm 5 network must
digest equal to step 1's record, and its floodplain must digest equal to `fp_floodplain()` itself,
replayed the same day on the same DEM.

## Decision rule (pre-registered 2026-10-09, before any arm ran)

Written before the arm results exist, and not to be edited to fit them.

**Floor.** A floor below order 3 (arm 2, arm 1) or the bypass add-on (arm 4) is recommended
for #104 only if all three hold, each measured against the next floor up:

1. **Affordable:** DEM + delineation + blk attribution for MORR at one scenario ≤ 60 min, and
   peak RSS ≤ 32 GiB.
2. **Adds floodplain, not lakes:** the added area is ≥ 5% of arm 3's floodplain, and ≥ 50% of
   the added area lies outside the arm's waterbodies.
3. **Looks like floodplain:** in the hillshade review of order-1 additions, the majority of panels
   are read as valley floor rather than hillslope or DEM-edge artefact. This criterion is a human
   read; the probe records a preliminary read and marks it pending until the user confirms.

**Supersession.** If the coho-reachable floodplain under the recommended floor differs from arm
5's by more than 2% of arm 5's area (gained + lost), the existing species-cut items are
superseded, not merely extended, and #104 must plan a republish.

**Grain.** Segment grain is recommended only if its measured attribution cost on arm 3, scaled by
the measured per-group rate to the recommended floor's segment count, stays ≤ 60 min per
scenario. Otherwise the blue line, with habitat joined by range (#104's design).

## Results

Pending the MORR run.

### Anchor (measured 2026-10-09)

- Network: arm 5 digests equal to step 1's recorded `streams_content_sha256`, so `fresh` is
  unchanged since step 1 ran on 2026-09-03, and the probe's SQL copy is exact.
- Floodplain: the probe's arm 5 digests equal to `fp_floodplain()` replayed on the same DEM.
- **Published baseline is not reproducible on today's toolchain.** MRDEM-30's source is unchanged
  (S3 `Last-Modified` 2026-06-24), but terra 1.9.50, linking GDAL 3.13.0, reprojects it onto a grid
  whose origin sits ~1.1 m west and ~0.6 m north of the one terra 1.9.34 produced on 2026-09-03,
  with resolution differing in the 7th decimal (30.430634931 vs 30.430634377 m). MORR `co_ff04`
  comes out 35,618.0 ha against the published 35,769.1 ha (−0.42%). `fp_toolchain()` records sf's
  GDAL (3.8.5), not terra's, so the record could not show the change.
