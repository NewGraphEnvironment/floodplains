# Whole-FWA floodplain: cost, floor and grain

**Verified:** 2026-10-11 · **Issues:** #110 (this probe); gates #104; filed #117, flooded#67; relates #40, #54, #65,
flooded#68 · **Produced by:** `scripts/floodplain_lcc/floodplain_probe-run.sh` (logs
`scripts/floodplain_lcc/logs/*_floodplain_probe-whole-fwa_*`); habitat by order
`scripts/floodplain_lcc/logs/20261010_habitat_by-order_province.md`; second group
`scripts/floodplain_lcc/floodplain_probe-subset.R` (logs `*_floodplain_probe-subset_{morr,bulk}.md`); habitat join
`scripts/floodplain_lcc/habitat_join-demo.R` (log and figures `20261011_habitat_join-demo_morr*`) ·
**Status:** MORR measured 2026-10-09, BULK (arms 5, 3, 2) 2026-10-11. **Recommendation revised
2026-10-10: floor order ≥ 2** (see "Recommendation for #104"); BULK confirms the floor and fails the
cost bound, on attribution.

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
  (`complete = TRUE`) by one full-grid `terra::distance`. On arm 5's coho network:
  - With the fallback, as 340 blue-line groups, attribution took 829.9 s (`arm5_timing.json`).
  - Without it, as one group with `complete = FALSE`, it took 5.0 s (`reach.json`).
  - A superseded run that attributed the same network as one group *with* the fallback took
    825 s. That figure is recorded in the planning log only; its log file was overwritten.
  - So roughly 13 min per scenario is avoidable if #104 accepts unassigned cells, or computes the
    fallback some cheaper way.
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
  of each floor's *added* area (12–20% across the three floors), so the added area is mostly not
  lakes.
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

### Habitat by stream order, province, both models (2026-10-10)

The MORR figures above are one group, and one model. Measured across every group in the local
fwapg, for both habitat models, as the share of modelled habitat length by FWA stream order
(`scripts/floodplain_lcc/logs/20261010_habitat_by-order_province.md`):

| model (table) | groups | order 1 | order 2 | order ≥ 3 |
|---|---|---|---|---|
| bcfishpass (`fresh.streams_vw_bcfp`, codes 1, 2) | 188 | 0.6–3.4% | 5.2–21.1% | 76.7–94.2% |
| link (`fresh.streams` + `fresh.streams_habitat_<sp>`) | 98 | 0.7–3.2% | 5.3–21.3% | 77.9–93.9% |

Ranges are across species (bt, ch, cm, co, pk, sk, st, wct) and uses (spawning, rearing), with one
exception that is out of scope: sockeye rearing sits 46–50% on order 1, and all 7,250 km of it in
bcfishpass is on waterbodies (lake flow lines). Lakes enter the floodplain as waterbodies, not as
stream floodplain.

- **Order 1 holds about 1% of modelled habitat in both models.** Partly by construction:
  bcfishpass gives order-1 streams no channel width, so its habitat models barely classify them.
- **Order 2 holds 5–21%,** most for bull trout rearing (21%), coho rearing (18–20%) and pink and
  chum spawning (15–19%).
- **So a floor at order ≥ 2 covers 96.6–99.4% (bcfishpass) and 96.8–99.3% (link) of modelled
  spawning and rearing; order ≥ 3 covers 76.7–94.2% (bcfishpass) and 77.9–93.9% (link).**
- The two models agree to within about four points in every cell (largest gap: chum spawning on
  order 2, 18.8% vs 14.7%), though they segment the network differently and link's is still being
  tuned. The floor does not depend on which model is used.

### Literature: what the VCA is for on small streams (2026-10-10)

Searched in the `vca_refs` and `habitat_modelling` ragnar stores; quotes are from the source text.

- **The VCA was built with a stream-size floor.** Nagel et al. (2014), the VCA manual: a
  *"Minimum drainage area—This parameter deletes valley bottom polygons that are smaller than the
  user-defined minimum drainage area"*; and *"Unchanneled valleys are not considered."*
- **It cannot resolve small valleys at 30 m.** Nagel et al. (2014): *"the VCA has difficulty
  resolving unconfined valleys that are narrower than about two to three times the DEM cell size
  (60-90 m in width for a 30 m DEM)"*. On MRDEM-30, ground the VCA keeps beside a first-order line
  is low-relief terrain near a stream, not that stream's floodplain; the order-1 review panels
  read the same way.
- **bcfishpass keeps lateral habitat only where it touches modelled habitat.** A BC
  lateral-habitat assessment built on bcfishpass's VCA (`BC_report_formatted_final.pdf` in
  `habitat_modelling`, authors not yet identified): *"The floodplain raster was refined to exclude
  regions with no connectivity to stream segments modelled as spawning or rearing habitat"*. Here
  that rule becomes a query on the joined habitat, not a cut in the geometry (#104 point 3).
- **Small streams are a riparian question more than a floodplain one.** Fogel et al. (2022):
  *"floodplain reconnection is likely to be more effective at reducing temperatures in large
  rivers, whereas riparian restoration is likely more effective… in small streams"*, and *"many
  small streams have no floodplain reconnection potential at all"*.
- Not yet in the stores: BC's Riparian Management Area Guidebook (Zotero item, no PDF), V-BET
  (Gilbert et al. 2016; no PDF), and the wood-recruitment source-distance papers (McDade et al.
  1990; Murphy and Koski 1989). They bear on riparian buffers, which are outside this note.

### The rule, applied

**Criterion 3 is ambiguous as registered, and the ambiguity decides the outcome.** Round 3 of the
code check found it, and the drafting was mine.
- Criteria 1 and 2 are each "measured against the next floor up".
- Criterion 3 names the review of **order-1 additions** only.
- That supports two readings, and they give opposite answers on supersession, so neither is
  chosen here.

| floor | 1 affordable (≤ 60 min, ≤ 32 GiB) | 2 adds floodplain (≥ 5%, ≥ 50% outside waterbodies) | coho floodplain moved |
|---|---|---|---|
| order ≥ 2 | **yes** (35.8 min, 7.9 GiB) | **yes** (29.1%, 80%) | 16.6% |
| order ≥ 1 | **no** (90.7 min) | yes (48.4% of arm 3, 86%) | 30.8% |
| bypass | **yes** (31.5 min, 9.1 GiB) | **yes** (22.1%, 88%) | 9.9% |
| order ≥ 3 (no access filter) | yes (19.9 min) | the baseline floor | 1.6% |

Segment grain at 0.248 s per segment, scaled to each floor:

| floor | segment-grain estimate | verdict |
|---|---|---|
| order ≥ 2 | 86 min | fails the 60 min bound |
| bypass | 61 min | fails |
| order ≥ 3 | 31 min | passes |

**Preliminary visual read.** This is mine; the user's verdict decides criterion 3. Panels and layers
are in `data/morr/probe_whole_fwa/` (`panel_*.png`, `review.gpkg`).
- **Order-1 additions (`panel_1`–`panel_6`, the registered criterion).**
  - The two largest (~230 ha) are broad, low-relief flats flanking the Morice mainstem, seeded by
    first-order lines that cross them. A hillshade cannot separate valley floor from terrace there;
    that needs height above channel.
  - The median and small samples are fragments of a few cells around headwater lines.
  - 4,301 of the 6,621 order-1 patches are under 1 ha. They hold 8% of the added area; 73% sits in
    patches of 5 ha or more.
  - Preliminary: the majority of panels do **not** read as valley floor.
- **Order-2 and bypass additions (`panel_order2_*`, `panel_bypass_*`).** These were drawn after the
  rule as evidence, outside the registered criterion.
  - The order-2 samples read as valley-floor corridors and low-relief valley bottoms.
  - The largest bypass addition is the same broad-flat class as order 1's largest.

## Recommendation for #104 (revised 2026-10-10): floor order ≥ 2

**Floor order ≥ 2, order 1 out, grain `blue_line_key`.**

- **Order 1 out.** It fails criterion 1 on cost (91 min per scenario). Its review panels read as
  not valley floor (the preliminary read, and the user's on 2026-10-10: "it is a lot of floodplain. like seems
  weird that first order streams have a bunch of floodplain above them?"). The literature says the
  VCA cannot resolve those valleys at 30 m. And it holds about 1% of modelled habitat.
- **Order 2 in.** It passes criteria 1 and 2 (35.8 min, 7.9 GiB; +29% floodplain, 80% outside
  waterbodies). Its panels read as valley-floor corridors. And it holds 5–21% of modelled
  spawning and rearing in both models, province-wide. A floor at order ≥ 3 would leave that
  habitat with no floodplain polygon to join to.
- **This resolves criterion 3 as Reading A** (per floor): the order-1 review rules out order 1;
  it does not gate order 2.
- **Grain: blue line.** Segment grain is estimated at 86 min at order ≥ 2, over the 60 min bound.
  #104's range join on `(blue_line_key, measure range)` supplies within-blk resolution.
- **Habitat is joined, never cut.** Either model joins on FWA position. bcfishpass is keyed
  `segmented_stream_id`, link `id_segment`, which link rebuilds every run, so the durable key is
  `blue_line_key` + route measure, which both carry. A model or species change needs no re-run.
- **Supersession.** The coho network's floodplain moves 16.6% under order ≥ 2 (BULK 25.7%), past the 2%
  threshold, so existing items are superseded and #104 plans a republish. Time it with the grid
  pin (flooded#67), so the republish carries one change.
- **The bcfp bypass** (first-order with parent ≥ 5) is not added. Its largest additions are the same
  broad-flat class as order 1's, and order ≥ 2 already holds the habitat.

**Second group: BULK, arms 5, 3 and 2 (measured 2026-10-11).** Evidence:
`scripts/floodplain_lcc/logs/20261010_floodplain_probe-subset_bulk.md`, produced by
`floodplain_probe-subset.R`, which applies the report's section 2 and 3 formulas without arm 1 and
reproduces the MORR report exactly (`…_subset_morr.md`). The anchor passed (network, DEM and
floodplain match the step 2 replay).

| `co_ff04` | MORR | BULK |
|---|---|---|
| DEM grid (cells) | 18.1 M | 38.3 M |
| arm 2: DEM / delineation / blk attribution / total, min (the rule's cost) | 0.9 / 1.9 / 33.0 / 35.8 | 37.2 / 5.9 / 170.0 / 213.1 |
| arm 2 peak RSS | 7.9 GiB | 17.3 GiB |
| order ≥ 2 vs ≥ 3: added floodplain | +29.1% | +54.4% (23,841 ha) |
| share of the addition outside waterbodies | 80.3% | 87.8% |
| coho floodplain moved, order ≥ 2 (gained + lost) | 16.6% | 25.7% (+8,683 / −1,128 ha) |
| coho floodplain moved, order ≥ 3 | 1.6% | 2.1% |

- **Area: the floor holds, more strongly.** Order 2 adds more valley on BULK, and more of it is
  off-lake, so MORR's result was not an artefact of lake country.
- **Supersession: further past the 2% threshold.** The 1,128 ha lost is 3.0% of arm 5's coho
  floodplain (MORR 1.3%): the pooled flood surface (flooded#68).
- **Cost: fails criterion 1's bound, and the cause is attribution.** 170 of arm 2's 213 min is
  `fl_valley_attribute()` by blue line; the DEM fetch is 37 min, nearly all network wait (51 s of CPU; MORR's fetch
  took 0.9 min), and delineation 6 min. Attribution grows faster than both the grid and the group count:
  BULK's grid is 2.1x MORR's, its arm 2 blue lines 1.5x, its attribution 5.1x (arm 5, today's network: 3.4x).
  Criterion 1 was registered for MORR, but this run's job was to test
  the cost model, and the model does not hold. Attribution speed, not the floor, is what gates a
  region; the `complete = TRUE` fallback (~13 min per scenario on MORR) is part of it.

**Still open before committing a region:**
- attribution cost in flooded (`fl_valley_attribute()`), measured on BULK at 170 min per scenario
  for order ≥ 2: the `complete = TRUE` fallback (flooded#71) and the per-group cost (flooded#72);
- the flood-surface artefact (below).

**The habitat join works on the blue-line floodplain (demonstrated 2026-10-11, MORR, chinook).**
Evidence: `scripts/floodplain_lcc/logs/20261011_habitat_join-demo_morr.md` and its three figures,
from `habitat_join-demo.R`. link's chinook spawning and rearing, from two builds (`fresh`, `morr`),
were joined to arm 2's floodplain as attributed by `blue_line_key`, with no re-delineation (146 s
for both rules, both builds and the arm 3 comparison).
- **Integrity.** All 517,087 floodplain cells are attributed, with none missing and none outside
  it. 99% of spawning km sits on a blue line with a floodplain polygon in both builds, and 98.9%
  (`fresh`) and 93.2% (`morr`) of rearing km. The rest (80 km of habitat in `morr`) is all on
  order-1 blue lines, which the floor leaves out. Segment keys match 100% (`fresh`) and 99.99% (`morr`).
- **Join by position, not by blue line.** Joined by blue line, a polygon takes any habitat on its
  blue line, and 39,507 ha (82% of the floodplain) reads as chinook spawning floodplain. Joined by
  position, each cell takes the nearest segment (straight-line distance) on its own blue line.
  This stands in for the range join on route measure above; the two can differ across a meander
  neck. It is cheap.
- **Shared ground: decided 2026-10-11 (user).** 78.6% of arm 2's floodplain cells are claimed by
  two or more blue lines (mean 3.28), so the position join needs a rule for them:
  - **nearest** (the default for areas): the cell takes the nearest of its claiming blue lines'
    nearest segments, so each cell has one owner and per-reach areas add up to the floodplain.
    1,878 cells (0.4%) tie and go to the lowest `blue_line_key`. Only the claiming blue lines compete.
    The nearest segment anywhere is on a non-claiming blue line for 26.3% of cells (25.5% on a blue
    line with no floodplain at all), and 99.9% of those nearer segments are order 1, which the floor
    leaves out.
  - **any** (the "connected to habitat" view): the cell is habitat if any claiming blue line's
    nearest segment says so.

  | `morr` build, arm 2, ha | spawning | rearing | rearing only |
  |---|---|---|---|
  | by blue line | 39,507 | 43,434 | 3,927 |
  | by position, nearest | 11,474 | 19,525 | 8,099 |
  | by position, any | 16,626 | 23,255 | 6,932 |
- **Against segment-grain attribution** (arm 3, which has both): 78–86% of cells agree under
  nearest, 85–90% under any. Segment grain maps the most spawning floodplain (19,333 ha, `morr`),
  because it counts a cell for every segment within the VCA thresholds.
- **A new habitat build is a new join.** `morr` adds rearing floodplain over `fresh` and removes
  none: 4,759 ha under nearest, 2,920 ha under any (fewer, because under any many of those cells
  were already rearing through a neighbouring blue line). Under any, the added rearing reaches a
  median 91 m and at most 1,012 m from the segments that changed (nearest: 64 m, 967 m). The
  geometry did not change.
- **Flood level.** The demo uses ff04, the level the arms were run at; chinook's headline is ff06.
  Accepted for the demonstration (user, 2026-10-11).

**Considered and not taken: order ≥ 3 (Reading B).** It is cheaper (19.9 min), keeps segment
grain, and only extends today's items (1.6% move). But it leaves 5–21% of modelled habitat with
no floodplain.

**The flood-surface artefact (flooded#68) is parked, not fixed.**
- The all-streams floodplain still loses about 1.3% of the coho floodplain on MORR (452 ha),
  because of the pooled flood surface.
- Two candidate fixes were measured: one over-floods by +67% to +143%, drainage ownership
  under-floods by about a quarter.
- Without an independent reference, neither can be shown to be closer to the truth.
- Read the supersession figures with that 1.3% in mind.

## Known limits of this run

- **How the arms' networks are tied.** The probe re-reads the network in every mode.
  - **Arm 5, the coho seeds, is tied by content.** Its digest equals step 1's record at the anchor
    and equals it again at report time.
  - **The window check.** No link log or recompute row for MORR falls inside the probe window.
  - **Arms 1–4's other segments are tied only by count** (`dem.json` against each arm). link's
    exported `lnk_access()` and `lnk_pipeline_persist()` write no log row, so a change to a
    non-coho segment that kept the count would not be seen. A content tie needs a full-group digest
    recorded in every mode, which this run did not record.
- **The code version is stated, not gated.** The anchor ran on the commit where `delineate()` and
  the SQL last changed. Round 3 of the code check diffed both and found them unchanged since.

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
- **Isolated: the GDAL version, not terra** (measured 2026-10-09, same machine). The same MRDEM
  crop warped to EPSG:3005 through sf's GDAL 3.8.5 lands exactly on the published grid (xmin
  847158.237521, res 30.430634377); through terra's GDAL 3.13.0 it lands at 847157.099813 /
  30.430634931. Given only a CRS, GDAL picks the output grid itself, and the pick changed between
  the two releases. Pinning the grid is flooded#67.
