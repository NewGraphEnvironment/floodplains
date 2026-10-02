# Channel migration in IO LULC floodplain change

**Verified:** 2026-10-02 · **Issues:** #106 (this work); relates #54 (patch–watercourse bridge),
#93 (accuracy sample, stratum 16 "any ↔ Water"), #95 / #103 (context and lookback tags),
drift `dft_transition_artifact()` · **Produced by:** `scripts/floodplain_lcc/channel_probe-migration.R`
(logs `scripts/floodplain_lcc/logs/*_channel-migration_*`) · **Status:** CLOSED. It does not
separate (NECR and BULK, 2026-10-02).

When a river migrates it erodes one bank (land → Water) and builds a bar on the other
(Water → Bare Ground / Rangeland, which later vegetates). Inside our floodplains that change
falls into whatever transition stratum its classes give it. It cannot be told apart from
classification flicker, and nothing surfaces the active reaches. The question here: **among
IO's Water-involving change patches, does a cluster of long, thin, channel-adjacent,
opposite-bank-paired patches separate from the rest?** If it does, a context tag
(`in_channel_change` + `channel_role`) earns its own issue. If it does not, IO cannot nominate
migrating reaches at 10 m over 2017–2023, and this file records why.

## The same pattern read two ways

drift's `dft_transition_artifact()` already looks for this geometry, and reads it as
**misregistration**. On a channel shifted by one pixel between epochs, one bank maps
Trees → Water and the other Water → Trees: thin bands that hug the old interface, with
reciprocal partners and roughly zero net change. Migration produces the same kind of band. So
the probe has to say which signals tell the two apart rather than assume them:

- **Width.** A registration artifact is about one pixel wide (`width_px` < 1.5 in drift's
  terms). A migration strip at 10 m is only visible once the bank has moved more than a cell.
- **Class asymmetry.** Misregistration reverses exactly (A→Water / Water→A). After erosion, a
  bar is deposited as Bare Ground or Rangeland, not as the trees that were eroded. drift's
  reciprocity only tests exact reverses, so it cannot see this pair.
- **Persistence.** With `lulc_annual: true` all seven years are on disk. Erosion leaves its
  class once and stays out. A water-level flip comes back.
- **Direction.** A registration shift moves every reach the same compass way. Migration follows
  the bends.

## Pre-registered rule

**Version 2, committed 2026-10-02, before any candidate was computed or any criterion applied.**
Version 1 (943c0ec) was revised in review of the PR that first committed it. A plan review
showed four places where v1 could not separate migration from the things it is meant to
reject (`planning/archive/2026-10-issue-106-channel-migration-probe/review-plan.md`). It also showed one where v1 could
never pass under real migration: a meander puts erosion and deposition on the **same** side
within 300 m, which fills v1's same-side null.

**What had been seen when v2 was written**, so a reader can judge the revision:

- A prototype run after v1 was committed. It vectorised NECR's unsieved Water-involving change:
  8,228 patches, 509.73 ha. It counted patches per transition, which showed Water → Trees
  2,592 and Water → Bare Ground 6. It also returned `dft_transition_artifact()`'s width
  distribution, with a median of 0.5 px.
- The reviewer's read-only population counts: BULK 696.1 ha unsieved and 390.4 ha sieved, and
  NECR's total unsieved change, 5,779 ha.

None of the v1 thresholds moved. Every change below answers a named review finding. Class
asymmetry (exact reverse or not) stays **reported, never decisive**, because the transition
counts above were seen before v2.

### Population

- **Two sets, one pipeline.**
  - **unsieved:** 2017 → 2023, re-derived from the on-disk endpoint rasters
    `data/<area>/rasters/<scenario>/classified_{2017,2023}.tif`
    (`drift::dft_rast_transition(patch_area_min = NULL)`), primary scenario only.
  - **sieved:** the published `transition.tif` (1 ha).

  The rule is applied to each set, and the verdict states both results.
- Only cells where exactly one endpoint is Water (code 1) are kept. Each kept cell gets a
  **role**:
  - **erosion:** X → Water, with X ∈ {Trees, Flooded Vegetation, Crops, Bare Ground, Rangeland}
  - **deposition:** Water → Y, with Y ∈ {Trees, Flooded Vegetation, Bare Ground, Rangeland}
  - **other:** every remaining Water-involving transition
- **A patch is an 8-connected run of cells with one role**, built with `terra::patches()` per
  role. It is not a run of one transition value, because a bank eroding through mixed cover
  would otherwise split into short single-class pieces (review 6). Each patch records its
  dominant transition (modal cell code).
- `dft_transition_artifact()` still runs on the transition-level patches, both sets, for
  the misregistration report: sliver share and exact-reciprocal share.

### Per-patch measurements

| measurement | definition |
|---|---|
| `width_px` | 2A/P in pixels, on the raw cell-edge perimeter. This is drift's sliver metric |
| `elong` | **equivalent-rectangle** long/short ratio from area A and perimeter P′, where P′ is taken after a 1-cell (10 m) Douglas–Peucker simplify to remove raster staircase: L, W = P′/4 ± √(P′²/16 − A), and 1 when the root is imaginary. It is invariant to bending, so a crescent on an outside bend scores as the strip it is (review 7). The MRR ratio is reported beside it |
| `compact` | 4πA/P², reported only |
| `io_adjacent` | erosion: 2017 Water within 3 cells. Deposition: 2023 Water within 3 cells |
| `fwa_dist_m` | distance to the nearest `fwa_rivers_poly` polygon in the WSG, or to the FWA stream line where no river polygon lies within 500 m |
| `lake_margin` | within 50 m of a `whse_basemapping.fwa_lakes_poly` polygon. Drawdown strips on lake shores are long, thin and adjacent, and they are not channel change (review 8) |
| `channel_adjacent` | `io_adjacent` **and** `fwa_dist_m` ≤ 50 m **and** not `lake_margin` |
| `blk`, `side`, `station_m` | from the nearest segment of the FWA stream line (`streams_<sp><order>`) to the patch's `st_point_on_surface()`: its `blue_line_key`, the sign of the cross product against the digitised direction, and the along-stream position `downstream_route_measure` + distance along the feature. FWA lines are digitised upstream, and the probe asserts that against the measures |
| `align_deg` | angle between the MRR long axis and the nearest segment's bearing, folded to 0–90° |
| `sustained` | share of patch cells that **left their 2017 class once and never returned**, with onset (first year away) ≤ **2021**. Snow/Ice (9), Clouds (10) and NA years count as missing, not as switches. Succession such as Water → Bare → Rangeland → Trees counts as sustained. A cell exposed only in the drought year 2023 does not (reviews 3, 4) |

### Candidate

A patch is a **candidate** when **all** of these hold:

- `role` is erosion or deposition
- `width_px` ≥ 1.5, so not a drift sliver
- `elong` ≥ 3
- `channel_adjacent`
- `align_deg` ≤ 30

### Pairs

Two candidates of **opposite role** on the same `blk` can pair when both of these hold:

- they lie within 300 m edge to edge
- their **station intervals overlap**, where a patch's interval is `station_m` ± half its
  MRR long side. Opposite banks of one bend sit at the same station; the next bend does not
  (review 2)

Such a pair is:

- **opposite** if the FWA `side`s differ **and** the straight line between the two patches'
  surface points crosses an IO **stable Water** cell (Water in both 2017 and 2023). That is
  IO's own channel between them, and FWA's offset at half-channel width cannot fake it
  (review 9).
- **same-side** (the null) if the FWA `side`s are equal.

A patch with both kinds of partner counts in both shares.

### Separation

Areas are summed per patch. In NECR, the cluster **separates** when all four of these hold:

- **A. Material.** Candidate area is ≥ 20% of all Water-involving change area.
- **B. Sustained.** Area-weighted `sustained` among candidates is at least **15 percentage
  points** above the same measure among **width-matched non-candidates**: Water-involving
  patches with `width_px` ≥ 1.5 that fail any other condition. The filter alone cannot
  produce the lead (review 5).
- **C. Paired, above the null.** ≥ 25% of candidate area is opposite-paired, **and** the
  opposite share is at least **10 percentage points** above the same-side share (review 14).
- **D. Not a registration shift.** Over all opposite pairs (at least 10), take the compass
  direction from the deposition patch's surface point to the erosion patch's. The mean
  resultant length R of those unit vectors must be < **0.5**. A rigid shift between epochs
  points every pair the same way (R → 1). Migration follows the bends, so the directions
  scatter (review 1). Fewer than 10 opposite pairs means D fails.

**BULK** reproduces the direction:

- B's lead is > 0
- the opposite share is greater than the same-side share
- R < 0.5

It does not have to reproduce the magnitudes, because it is a different river.

### Outcomes, decided in advance

| NECR unsieved | NECR sieved | BULK direction | verdict |
|---|---|---|---|
| separates | separates | holds | **Separates.** File the tag issue from the measured distributions |
| separates | fails | holds | **Separates below the sieve.** File the tag issue; its first decision is the sieve, because the published layer cannot carry what the 1 ha sieve removed |
| separates | either | fails | **NECR only.** No tag issue; record it as a NECR finding that BULK did not reproduce |
| fails | separates | either | **Does not separate.** The sieve selects big patches, and the pre-registered population is the unsieved one |
| fails | fails | either | **Does not separate.** Close #106 on the negative result |

Whichever way it falls, three numbers are reported:

- the sliver share: Water-involving area with `width_px` < 1.5
- the exact-reciprocal share from `dft_transition_artifact()`
- the share of opposite pairs that are exact reverses (erosion from-class = deposition
  to-class)

These measure how much of IO's water change is the misregistration drift describes.

### Anchors

Both are exact. Either failing stops the probe: it has read the wrong raster.

1. Re-sieving the endpoint rasters at 10,000 m² (`dft_rast_transition(patch_area_min =
   10000)`) reproduces the published `transition.tif` cell for cell.
2. Where `reference/<area>/strata.csv` exists, the unsieved total change area (every cell with
   from ≠ to) equals the summed area of its `change` and `sieved` strata. For NECR that is
   **5,779.45 ha**, to within 0.01 ha. The strata were built by `fp_acc_strata()`, independently
   of this probe.

## Results

### Applying the rule

These notes were written before any BULK number was read. They settle readings the rule text
left open; no threshold changed.

- **BULK's R test also needs at least 10 opposite pairs.** D's minimum is applied wherever R is
  read, because an R over fewer than 10 vectors is not decidable.
- **Lake margins are found by footprint, not by WSG.** The rule limits the river polygons to the
  WSG but gives the lake margin no limit, so the lakes are queried by the floodplain grid's
  extent plus 50 m. A lake assigned to the neighbouring group still counts.

### Verdict: does not separate

Rule v2 was applied as written, and the outcome table gives **does not separate**. All four
criteria fail in NECR on both sets, and so does BULK's direction test. IO LULC at 10 m over
2017–2023 cannot nominate migrating reaches in these floodplains. Nothing here is a tag
candidate, so no tag issue was filed.

Logs: `scripts/floodplain_lcc/logs/20261002_channel-migration_{necr,bulk}.{md,csv}`, run from
commit 9eeb5e5 (drift 0.20.0, terra 1.9.50). Both exact anchors held on NECR: re-sieving reproduced
`transition.tif` with 0 differing cells, and unsieved change was 5,779.45 ha against the strata's
5,779.45. On BULK anchor 1 held and anchor 2 does not apply (no strata.csv).

| area, set | Water-involving ha | candidates (ha) | A: share | B: sustained cand / width-matched | C: opposite / same | D: R (pairs) |
|---|---|---|---|---|---|---|
| NECR unsieved | 509.73 | 23 (27.83) | 0.055 | 0.304 / 0.472 | 0 / 0 | — (0) |
| NECR sieved | 230.49 | 15 (23.71) | 0.103 | 0.260 / 0.493 | 0 / 0 | — (0) |
| BULK unsieved | 696.08 | 96 (99.83) | 0.143 | 0.549 / 0.617 | 0.051 / 0.089 | 0.55 (4) |
| BULK sieved | 390.41 | 53 (77.18) | 0.198 | 0.594 / 0.633 | 0 / 0.093 | — (0) |

### What the numbers say

- **Most of IO's water change is the misregistration shape.** Patches under 1.5 px wide hold
  **69%** of NECR's unsieved Water-involving area and **63%** of BULK's. The 1 ha sieve brings
  that down to 41% and 43%. Exact reverse pairs (drift's reciprocity) are a minor part:
  2.6% / 9.8% unsieved.
- **The long, thin, channel-adjacent strips are *less* persistent than other wide water
  change, not more.** B's lead is negative everywhere, from −0.04 to −0.23. A migration strip
  should leave its class once and stay out. These strips come back more often than the
  comparison set, which is the water-level or bar-flicker reading.
- **Erosion and deposition do not face each other.** NECR's 23 candidates (21 on one mainstem
  `blue_line_key`) have no opposite-role partner at the same station; the nearest one is
  3.4 km away. BULK has 4 opposite pairs and 4 same-side ones. Three of the four opposite pairs
  are exact reverses, and their directions are not dispersed (R = 0.55).
- **The cluster is small.** Even before pairing, candidates are 5–20% of Water-involving area.
- **Half of NECR's erosion and deposition area is lake margin.** 48% lies within 50 m of an FWA
  lake (BULK 27%). That is a lake-level signal, and v1 would have counted it as channel.
- **Land → Water outweighs Water → land about 2:1 in both areas** (erosion 315 vs deposition 169 ha
  in NECR unsieved, 467 vs 195 in BULK). That runs against the dry 2023 endpoint. It is not
  explained here and is recorded for #93's stratum 16, which labels exactly this change.

### What this does and does not rule out

It rules out IO 10 m annual land cover, over a six-year window, as the thing that finds migrating
reaches for us. It says nothing about whether these rivers migrate. A 30 m river moving 2 m a year
moves about one cell in this window, which is the sliver class, and that class is
indistinguishable here from misregistration. Decadal migration from the #103 dated air photos and
orthophotos has to choose its reaches some other way: by channel planform, field knowledge, or a
reach list. `data/<area>/channel/probe_*.gpkg` (gitignored) keeps every patch's measurements and
the pairs if anyone wants to look, but by this rule they are not nominations.

## Limits

- **Only wide channels register as Water** at 10 m, roughly 20–30 m and wider. Small streams
  show nothing.
- **2017–2023 at 10 m is short.** Many rivers move less than a cell a year, so IO catches only
  the most active reaches.
- **Water level fakes it.** An annual product can flip a bar between Water and Bare Ground
  from one year to the next. Persistence and the same-side null are the filters. #93's
  stratum 16 will measure how much of IO's water change is real once it is labelled.
