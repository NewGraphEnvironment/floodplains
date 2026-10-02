# Findings — Channel migration: tag long, thin, channel-adjacent water-change patches (erosion/deposition pairs) (#106)

## Issue context

**If we do it:** change patches that are a river moving (bank erosion on one side, bar deposition and colonisation on the other) are identified as channel change, separately from land-use change and classification noise. That gives the floodplain change story a geomorphic part it currently lacks. With the dated air photos and orthophoto from #103, actual channel position can then be measured over decades.
**If we never do:** channel movement sits in "any ↔ Water", Trees→Rangeland or "not yet attributed", indistinguishable from flicker. Active, migrating reaches, which matter for restoration, never surface.

## Problem

IO LULC change inside the floodplain contains a recognisable migration signature that nothing tags:

- **Erosion:** Trees / Rangeland / Bare → Water, a strip along the outside of a bend.
- **Deposition and colonisation:** Water → Bare (a new bar), then Bare/Rangeland → Trees as the bar vegetates.
- **Migration is the pair:** an erosion strip and a deposition strip on opposite banks of the same reach. A lone Water patch is more often a water-level difference or a classification flip.

Today those patches land in whatever transition stratum their classes put them in. NECR's "any ↔ Water" accuracy stratum alone is 126 ha (`reference/necr/strata.csv`).

## Proposal: measure first, then tag

**1. Probe (NECR, then BULK).** For every Water-involving transition patch, compute:
- **Elongation:** minimum-rotated-rectangle length/width, and compactness 4πA/P².
- **Distance to the channel:** FWA `rivers_poly` for double-line rivers, otherwise the stream line. Use a buffer of a few cells, because FWA geometry is 1:20k and can sit tens of metres off.
- **Alignment:** the patch's long axis against the stream's local bearing.
- **Adjacency to IO Water** in the endpoint years, i.e. IO's own channel rather than FWA's.
- **Opposite-bank pairing:** erosion and deposition patches on the same `blue_line_key` (the #54 bridge already links patches to watercourses), on opposite sides of the channel.

Decide from the distributions whether a "long, thin, channel-adjacent, paired" cluster separates from the rest.

**2. If it separates, tag it.** Add something like `in_channel_change` (+ `channel_role`: erosion / deposition) on the transition layer, as an additive **context** tag in the `in_wetland` / `in_fire_prior` pattern (#95, #103). It locates change and is never a cause in the tree-loss attribution.

**3. Real migration rates come from dated imagery, not IO.** The #103 review project already holds georeferenced 2012 air photos (all 480 NECR sample points) and a 0.15 m 2021 orthophoto, and film epochs back to the 1970s are indexed per point (`reference/necr/imagery.csv`, fly#53 for film georeferencing). Comparing channel position across those epochs measures movement over decades. The IO tag nominates where to look.

## Limits to state up front

- **Only wide channels register as Water** at 10 m, roughly 20–30 m+. Small streams show nothing; the mainstems will.
- **2017–2023 at 10 m is short.** Many rivers move less than a cell a year, so IO catches only the most active reaches.
- **Water level fakes it.** An annual product can flip Water ↔ Bare on a bar between high- and low-water years. Pairing and elongation are the filters, and the "any ↔ Water" stratum in #93's sample will measure how much of IO's water change is real once labelled.

## Ownership

- **Generic patch shape metrics** (elongation, compactness, orientation) are not floodplain-specific and probably belong in drift, alongside `dft_transition_vectors`.
- **The channel-specific parts** (FWA distance, the `blue_line_key` pairing, the tag) belong here. Check drift's exports first.

Relates: #54, #93, #95, #103, fly#53

## Exploration (2026-10-02)

- drift `dft_transition_artifact()` already computes width (2A/P), boundary-hugging and exact
  A->B / B->A reciprocity, and reads the reciprocal pair as misregistration. It is reused. The
  migration pairing (X->Water with Water->Bare/Rangeland) is not exact-reverse, so the probe
  computes it.
- The published transition is sieved at 1 ha (`03_lulc_classify.R`). The probe re-derives an
  unsieved transition from the endpoint tifs.
- `transition.tif` carries stable A->A codes (`from*1000+to`, 50 levels), so the from-class
  around a patch is readable.
- `fp_acc_strata()` precedence (`scripts/landcover_accuracy/fp_accuracy.R:143-161`): causes >
  prior fire > wetland change (from or to = 4, or inside an FWA wetland) > Rangeland/Trees/Crops
  pairs > Snow/Ice > any<->Water. Stratum 16 (126.06 ha) is sieved Water change minus all of
  those. The probe's anchor is therefore a lower bound, not a reconstruction.
- Pairing assigns `blk` from the nearest FWA stream line, not from the #54 bridge. The bridge
  exists only for published (sieved) patches and attributes through overlapping floodplain
  polygons, while opposite-bank geometry needs the centreline. This deviates from the plan's
  wording; recorded here.

## Errors Encountered

| Error | Resolution |
|-------|------------|
