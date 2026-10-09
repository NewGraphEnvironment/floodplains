# Whole-FWA floodplain: cost, floor and grain

**Verified:** 2026-10-09 · **Issues:** #110 (this probe); gates #104; filed #117, flooded#67; relates #40, #54, #65 ·
**Produced by:** `scripts/floodplain_lcc/floodplain_probe-run.sh` (logs
`scripts/floodplain_lcc/logs/*_floodplain_probe-whole-fwa_*`) · **Status:** MORR measured
2026-10-09. Recommendation below; the visual criterion awaits the user's read.

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

## Results (MORR, `co_ff04`, measured 2026-10-09)

Evidence: `scripts/floodplain_lcc/logs/20261009_floodplain_probe-whole-fwa_morr.{md,csv}`. Toolchain:
flooded 0.6.0, terra 1.9.50 (GDAL 3.13.0), one machine (m1), 12 terra threads. Common DEM is
18.1 M cells of MRDEM-30 at ~30.43 m, fetched in 0.9 min.

### Cost

| arm | network | km | blue lines | floodplain km² | delineation min | blk attribution min | peak RSS GiB |
|---|---|---|---|---|---|---|---|
| 1 | all `fresh.streams` | 9,033 | 6,753 | 651.9 | 2.8 | 87.0 | 9.0 |
| 2 | order ≥ 2 | 3,471 | 1,711 | 478.8 | 1.9 | 33.0 | 7.9 |
| 3 | order ≥ 3 | 1,651 | 401 | 374.8 | 1.4 | 17.6 | 8.9 |
| 4 | order ≥ 3 + bypass | 2,835 | 1,195 | 454.5 | 1.7 | 28.9 | 9.1 |
| 5 | coho network | 1,296 | 340 | 356.5 | 1.2 | 13.8 | 9.3 |

- **Delineation is cheap at every floor.** It stays under 3 min even for 58,613 segments.
  Attribution is 87–96% of each arm's cost (DEM fetch included).
- **Attribution fits 790 s + 0.66 s per blue line** across the five arms. The slope is confounded
  with valley extent, because bigger arms also have bigger valleys.
- **The intercept is flooded's fallback.** It assigns every valley cell no group reached
  (`complete = TRUE`) by one full-grid `terra::distance`. Measured on arm 5's coho network as a
  single group: 825 s with the fallback, about 5 s without it. So roughly 13 min per scenario is
  avoidable if #104 accepts unassigned cells, or computes the fallback some cheaper way.
- **Segment grain on arm 3:** 7,606 segments took 31.5 min, i.e. 0.248 s per segment.
- **Memory is not a constraint.** Peak RSS was at most 9.3 GiB in every stage.

### Area

Pairs below are floodplain areas in ha on the common grid:

| pair | gained | lost | gained outside waterbodies |
|---|---|---|---|
| order ≥ 2 over order ≥ 3 | 10,908 (+29.1% of arm 3) | 502 | 80% |
| order ≥ 1 over order ≥ 2 | 18,133 (+37.9% of arm 2) | 825 | 86% |
| bypass over order ≥ 3 | 8,279 (+22.1% of arm 3) | 308 | 88% |
| order ≥ 3 over the coho network | 1,825 (+5.1%) | 1 | 74% |

- **Floodplains are not monotone in their seeds.** Adding streams also removes floodplain:
  - The flood surface is interpolated from every seed. Headwater seeds have small upstream areas,
    so they lower the surface near them.
  - Arm 1 loses 452 ha (1.3%) of the coho network's floodplain, and arm 2 loses 444 ha.
  - A whole-network floodplain is therefore **not a superset** of today's species cut. Querying
    it for coho returns a different answer, not a larger one.
- **Waterbodies are 42–58% of every arm's floodplain.** MORR is lake country. They are a minority
  of each floor's *added* area (12–27%), so the added area is mostly not lakes.
- **Extent and regridding:** arm 5 on the common grid is +0.10% against its own grid.

### The coho network's floodplain under each delineation (supersession)

| arm | coho-zone floodplain ha | vs coho network's own (34,343.8) | moved share |
|---|---|---|---|
| 1 | 44,004.9 | +10,111 / −450 | 30.8% |
| 2 | 39,168.4 | +5,267 / −443 | 16.6% |
| 3 | 34,899.4 | +556 / −1 | 1.6% |
| 4 | 37,217.7 | +3,133 / −259 | 9.9% |

Of the gains, 3–11% are waterbody cells.

### Habitat below order 3 (`fresh.streams_vw_bcfp`, modelled = codes 1, 2)

| | below order 3 | of which the bypass's first-order |
|---|---|---|
| coho rearing | 25.2% (308 of 1,225 km) | 22.1 km |
| chinook rearing | 17.7% | 10.2 km |
| coho spawning | 15.1% | 6.7 km |
| chinook spawning | 4.8% | 5.0 km |

The 25.2% reproduces #104's "20–29%" figure, which is the consistency anchor.

### The rule, applied

| floor | 1 affordable (≤ 60 min, ≤ 32 GiB) | 2 adds floodplain (≥ 5%, ≥ 50% outside waterbodies) | 3 visual | supersedes (> 2%) |
|---|---|---|---|---|
| order ≥ 2 | **yes** (35.8 min, 7.9 GiB) | **yes** (29.1%, 80%) | pending | yes (16.6%) |
| order ≥ 1 | **no** (90.7 min) | yes (48.4% of arm 3, 86%) | pending; preliminary no | yes (30.8%) |
| bypass | **yes** (31.5 min, 9.1 GiB) | **yes** (22.1%, 88%) | pending | yes (9.9%) |

Segment grain at 0.248 s per segment, scaled to each floor:

| floor | segment-grain estimate | verdict |
|---|---|---|
| order ≥ 2 | 86 min | fails the 60 min bound |
| bypass | 61 min | fails |
| order ≥ 3 | 31 min | passes |

**Preliminary visual read.** This is mine; the user's verdict is pending. Panels and layers are in
`data/morr/probe_whole_fwa/` (`panel_*.png`, `review.gpkg`).
- **Order-1 additions (the registered criterion).**
  - The two largest (~230 ha) are broad, low-relief flats flanking the Morice mainstem, seeded by
    first-order lines that cross them. A hillshade cannot separate valley floor from terrace there;
    that needs height above channel.
  - The median and small samples are fragments of a few cells around headwater lines.
  - 4,301 of the 6,621 order-1 patches are under 1 ha. They hold 8% of the added area; 73% sits in
    patches of 5 ha or more.
  - Preliminary: the majority of panels do **not** read as valley floor.
- **Order-2 and bypass additions.** These were drawn as evidence outside the registered criterion,
  which names order 1 only.
  - The order-2 samples read as valley-floor corridors and low-relief valley bottoms.
  - The largest bypass addition is the same broad-flat class as order 1's largest.

## Recommendation for #104

- **Floor: order ≥ 2.** It is the only below-3 floor that passes criteria 1 and 2 by itself.
  - It adds 29% floodplain over order ≥ 3, 80% of it outside waterbodies.
  - It costs about 36 min per scenario on MORR, against about 20 for order ≥ 3.
  - Criterion 3 is the user's read of `panel_order2_*` and `review.gpkg`.
- **Not order 1.** It fails on cost alone (91 min per scenario, nearly all attribution) and probably
  on the visual read too.
- **The bypass also passes 1 and 2.** Order ≥ 2 plus the bypass was not measured as one arm; the
  bypass adds first-order area on top of order ≥ 2.
- **Grain: blue line.** Segment grain fails the cost bound at order ≥ 2 (86 min estimated).
  #104's range join (`blue_line_key` + measure overlap) supplies the within-blk resolution
  instead.
- **Existing items are superseded, not extended.** The coho network's floodplain moves 16.6% under
  an order-≥-2 delineation. Even order ≥ 3 without the access filter moves it 1.6%. And because
  floodplains are not monotone in seeds, today's cut is not contained in the new one. #104 must
  plan a republish.
- **Cost lever.** About 13 min of each scenario's attribution is the `complete = TRUE` fallback.
  Dropping it, or computing it once per group, would cut order ≥ 2's attribution by about 40% (33 → ~20 min). That is a
  flooded question to raise in #104, not to settle here.
- **One group.** MORR is a headwater group with large lakes. Waterbody share and the order-1 flats
  may not transfer. A second group (BULK or NECR) at order ≥ 2 alone would test the cost model at
  one arm's price.

## Anchor (measured 2026-10-09)

- Network: arm 5 digests equal to step 1's recorded `streams_content_sha256`, so `fresh` is
  unchanged since step 1 ran on 2026-09-03, and the probe's SQL copy is exact.
- Floodplain: the probe's arm 5 digests equal to `fp_floodplain()` replayed on the same DEM.
- **Published baseline is not reproducible on today's toolchain.** MRDEM-30's source is unchanged
  (S3 `Last-Modified` 2026-06-24), but terra 1.9.50, linking GDAL 3.13.0, reprojects it onto a grid
  whose origin sits ~1.1 m west and ~0.6 m north of the one terra 1.9.34 produced on 2026-09-03,
  with resolution differing in the 7th decimal (30.430634931 vs 30.430634377 m). MORR `co_ff04`
  comes out 35,618.0 ha against the published 35,769.1 ha (−0.42%). `fp_toolchain()` records sf's
  GDAL (3.8.5), not terra's, so the record could not show the change.
