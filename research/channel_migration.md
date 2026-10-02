# Channel migration in IO LULC floodplain change

**Verified:** 2026-10-02 · **Issues:** #106 (this work); relates #54 (patch–watercourse bridge),
#93 (accuracy sample, stratum 16 "any ↔ Water"), #95 / #103 (context and lookback tags),
drift `dft_transition_artifact()` · **Produced by:** `scripts/floodplain_lcc/channel_probe-migration.R`
(logs `scripts/floodplain_lcc/logs/*_channel-migration_*`) · **Status:** OPEN. The rule is
pre-registered and no result exists yet.

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
- **Persistence.** With `lulc_annual: true` all seven years are on disk. Erosion switches once
  and stays switched, while a water-level flip moves back and forth.

## Pre-registered rule

**Committed 2026-10-02, before the probe was written or run.** It is editable only in review
of the PR that first commits it, and still only before any result exists. Thresholds are set
from what the geometry implies, not from data.

### Population

- Patches are vectorised from the **unsieved** 2017 → 2023 transition, re-derived from the
  on-disk endpoint rasters `data/<area>/rasters/<scenario>/classified_{2017,2023}.tif` with
  `drift::dft_rast_transition(patch_area_min = NULL)`, primary scenario only. Only patches
  where exactly one side is Water (code 1) are kept.
- The published, 1 ha-sieved layer is reported beside it. The rule is applied to both, and
  the verdict states each result.

### Per-patch measurements

| measurement | definition |
|---|---|
| `role` | **erosion**: X → Water with X ∈ {Trees, Flooded Vegetation, Crops, Bare Ground, Rangeland}. **deposition**: Water → Y with Y ∈ {Trees, Flooded Vegetation, Bare Ground, Rangeland}. Every other Water-involving transition is **other** |
| `width_px` | from `dft_transition_artifact()`, 2A/P in pixels |
| `elong` | long / short side of `sf::st_minimum_rotated_rectangle()` |
| `compact` | 4πA/P² |
| `io_adjacent` | erosion: a 2017 Water cell lies within 3 cells of the patch. Deposition: a 2023 Water cell lies within 3 cells of it. The patch's own cells are excluded |
| `fwa_dist_m` | distance to the nearest `whse_basemapping.fwa_rivers_poly` polygon in the WSG, or to the FWA stream line where no river polygon lies within 500 m |
| `channel_adjacent` | `io_adjacent`, **or** `fwa_dist_m` ≤ 50 m. The 50 m allows for 1:20k offset |
| `blk`, `side` | `blue_line_key` of the nearest FWA stream-line segment, and which side of that segment's direction the patch centroid lies on (sign of the cross product) |
| `align_deg` | angle between the MRR long axis and the bearing of the nearest stream segment, folded to 0–90° |
| `single_switch` | share of patch cells whose 2017–2023 annual class sequence changes **exactly once** |

### Candidate

A patch is a **candidate** when **all** of these hold:

- `role` is erosion or deposition
- `width_px` ≥ 1.5, so not a drift sliver
- `elong` ≥ 3
- `channel_adjacent`
- `align_deg` ≤ 30

A candidate is **paired** when a candidate of the **opposite role** lies on the same `blk`, on
the **opposite** `side`, within 300 m edge to edge.

### Separation

Areas are summed per patch. The cluster **separates** in NECR when all three of these hold:

- **A. Material.** Candidate area is ≥ 20% of all Water-involving change area.
- **B. Persistent.** Area-weighted `single_switch` among candidates is at least **15
  percentage points** above the same measure among non-candidate Water-involving patches.
- **C. Paired, above the null.** ≥ 25% of candidate area is paired, **and** the paired share is
  greater than the **same-side** null: the share of candidate area that would pair if the
  partner had to be on the same side (same `blk`, opposite role, within 300 m). A water-level
  flip on a single bar produces same-side pairs. Migration produces opposite-side ones.

**BULK** must reproduce the direction of B and C: the persistence difference is > 0 and the
paired share is greater than the same-side null. It does not have to reproduce the
magnitudes, because it is a different river.

### Outcomes, decided in advance

- **Separates on both the unsieved and the sieved sets.** File the tag issue, designed from
  the measured distributions.
- **Separates unsieved only.** File the tag issue as above. Its first decision is the sieve:
  the published layer cannot carry what the 1 ha sieve removed.
- **Does not separate.** Close #106 on the negative result. IO cannot nominate migrating
  reaches here, and decadal migration from the #103 dated imagery has to find its reaches some
  other way.

Whichever way it falls, the sliver share (Water-involving area with `width_px` < 1.5) is
reported. It measures how much of IO's water change is the misregistration drift describes.

### Sanity anchor

`reference/necr/strata.csv` stratum 16 "any ↔ Water" is **126.06 ha**. That is the
**sieved** Water-involving change left once the first-match precedence in
`fp_acc_strata()` (`scripts/landcover_accuracy/fp_accuracy.R`) has taken everything ranked
above it: fire, harvest, prior fire, wetland change (either side Flooded Vegetation, or the
cell inside an FWA wetland) and Snow/Ice → any. The sieved Water-involving area the probe
reports must therefore be ≥ 126.06 ha. After the probe drops the transitions with a Flooded
Vegetation or Snow/Ice side, which are the two exclusions it can make from classes alone, the
remainder must still be ≥ 126.06 ha. A probe that reports less has read the wrong raster. This
is a lower bound and not a reconstruction. The exact figure needs `fp_acc_strata()`'s cause,
wetland and prior-fire rasters, and rebuilding those is #93's job.

## Results

*Pending: Phase 3 of #106.*

## Limits

- **Only wide channels register as Water** at 10 m, roughly 20–30 m and wider. Small streams
  show nothing.
- **2017–2023 at 10 m is short.** Many rivers move less than a cell a year, so IO catches only
  the most active reaches.
- **Water level fakes it.** An annual product can flip a bar between Water and Bare Ground
  from one year to the next. Persistence and the same-side null are the filters. #93's
  stratum 16 will measure how much of IO's water change is real once it is labelled.
