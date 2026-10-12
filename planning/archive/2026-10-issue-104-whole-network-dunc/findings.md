# Findings — Serve whole floodplains keyed by blue_line_key (#104)

## Issue context

**If we do it:** the served collection holds one floodplain per watershed group, covering the whole stream network, and every watercourse polygon carries a network key that any habitat model joins to. Consumers query what they need afterwards ("chinook spawning", "accessible and 3rd order+") instead of us cutting a new delineation per species and threshold.
**If we never do:** each item is a floodplain of one species' accessible network at one `min_order` (`streams_<sp><min_order>`). A different species or threshold means a new run and a new item. Habitat type is not on the polygons at all.

## Problem

Today the floodplain is delineated from a **pre-filtered** network. Step 1 keeps the segments with `access_<species>` at `order >= min_order`, and step 2 delineates around those only. The question being asked ("which floodplain, for what fish, doing what") is baked into the geometry. The served collection (`stac_floodplains_bc`) inherits that, one species-and-threshold cut per item (`co_ff04`, `ch_ff06`, …), and nothing on a polygon says what habitat it is.

The network already carries the attributes to answer those questions after the fact. Per segment, `fresh.streams_vw_bcfp` has `access_*`, `spawning_*` and `rearing_*` for bt / ch / cm / co / pk / sk / st / wct, plus `stream_order` and `blue_line_key`.

## Proposal

1. **Delineate the whole floodplain once per watershed group.** The delineation covers the whole stream network down to a fixed order floor (order 2 or 3, per #110), not one species' accessible subset. Scenarios (flood factors) stay as they are.
2. **Explode it per watercourse** with the existing per-watercourse attribution: `attribute_by: blue_line_key`, `flooded::fl_valley_attribute()` (#40). Rows overlap by design.
3. **Carry the key, not the habitat (decided 2026-10-02).** Each polygon carries only its network key: `blue_line_key`, or a segment key if the explosion is by segment. Habitat is **joined** at query time from whichever model is wanted (`fresh.streams_vw_bcfp`'s `access_*` / `spawning_*` / `rearing_*`, a link variant, a future model), along with `stream_order`. Nothing habitat-specific is baked into the geometry, so a new or revised habitat model needs no re-run and no re-publish. A query like `rearing_ch`, or `access_ch AND stream_order >= 3`, is a join plus a filter.
4. **Serve the whole floodplain plus the keyed per-watercourse layer** in the collection, and let consumers join and filter. The species-specific cut becomes a query, not an item.

## Measured by #110 (MORR, `co_ff04`, 2026-10-09)

#110 probed five floors on one common DEM. The full verdict is in `research/whole_fwa_floodplain.md`
and the numbers are in `scripts/floodplain_lcc/logs/20261009_floodplain_probe-whole-fwa_morr.md`.
What it settles here:

- **Floor: order ≥ 2 (recommended 2026-10-10; BULK confirmed it 2026-10-11, see below).** Reasons, with
  numbers in `research/whole_fwa_floodplain.md` ("Habitat by stream order" and "Recommendation"):
  - **Where the habitat is.** Province-wide, in both habitat models (bcfishpass
    `fresh.streams_vw_bcfp`, 188 groups; link `fresh.streams_habitat_<sp>`, 98 groups), order 1
    holds about 1% of modelled spawning and rearing and order 2 holds 5–21%. Order ≥ 2 covers
    96.6–99.4%; order ≥ 3 would leave the order-2 share with no floodplain to join to. Evidence:
    `scripts/floodplain_lcc/logs/20261010_habitat_by-order_province.md`.
  - **What the VCA can resolve.** Nagel et al. (2014) built the VCA with a minimum-drainage-area
    floor, and note it cannot resolve valleys narrower than 60–90 m on a 30 m DEM. That fits the
    order-1 panels reading as not valley floor ("seems weird that first order streams have a bunch
    of floodplain").
  - Order ≥ 2 passes the cost and area criteria (35.8 min per scenario on MORR, +29% over order
    ≥ 3, 80% outside lakes and wetlands), and its panels read as valley floor. Criterion 3 is read
    per floor (Reading A).
- **Not order ≥ 1.** It costs 91 min per scenario, nearly all attribution (6,753 blue lines).
- **The bcfp bypass** (first-order with parent ≥ 5) passes cost and area on its own. Its visual
  read is pending and leans no, since its largest additions are the same broad flats as order 1's.
  Order ≥ 2 plus the bypass has not been measured as one network.
- **Grain follows the floor.** Segment attribution measured 0.248 s per segment.
  - At order ≥ 2 that is ~86 min per scenario, over the bound, so the grain is `blue_line_key`, with
    the range join below giving within-blk resolution.
  - At order ≥ 3 it is ~31 min, within the bound, so the rule picks segment grain, keyed on
    `(blue_line_key, downstream_route_measure)`.
- **Delineation is cheap; attribution is the cost.** The VCA stays under 3 min even for all 58,613
  MORR segments. Attribution fits about 13 min plus 0.66 s per blue line. The 13 min is flooded's
  `complete = TRUE` fallback, a full-grid `terra::distance`: 825 s with it, about 5 s without it.
  Dropping or restructuring that fallback is the biggest cost lever, and it is a flooded change.
- **Memory is not a constraint:** peak RSS ≤ 9.3 GiB in every stage on MORR, ≤ 20 GiB on BULK.
- **Superseded or extended depends on the floor.**
  - At order ≥ 2 the coho network's floodplain moves 16.6% (gained + lost, against its own
    delineation), past the 2% threshold. Existing items are **superseded** and a republish has to be
    planned.
  - At order ≥ 3 without the access filter it moves 1.6%. Items are **extended**: the new floodplain
    adds the inaccessible order ≥ 3 streams.
  - Floodplains are not monotone in their seeds. Headwater seeds lower the interpolated flood
    surface, so the all-streams floodplain loses 452 ha (1.3%) of today's coho floodplain. A species
    query of a whole-network item is a different answer from today's item, not a superset of it.
  - That loss comes from flooded's pooled flood surface (flooded#68). Two fixes were measured
    (2026-10-09): one over-floods by +67% to +143%, drainage ownership under-floods by about a
    quarter. With no independent reference to say which is closer to the truth, flooded#68 is
    parked and the 1.3% stands as a known caveat on the supersession figures.
- **Habitat outside today's floodplains:** 25.2% of MORR's modelled coho rearing and 15.1% of coho
  spawning sit below order 3. For chinook the figures are 17.7% and 4.8%.
- **The toolchain moved under every published floodplain (#117, flooded#67).** terra 1.9.50 (GDAL
  3.13) reprojects MRDEM onto a grid ~1 m off the one used for the published items, so any re-run
  moves them by a fraction of a percent with no data change. Pin the grid (flooded#67) before this
  issue's republish, so the republish carries one change, not two.
- **Second group: BULK (arms 5, 3, 2; measured 2026-10-11).** Evidence:
  `scripts/floodplain_lcc/logs/20261010_floodplain_probe-subset_bulk.md`; the anchor passed.
  - **Area:** order ≥ 2 adds +54.4% over order ≥ 3 (MORR +29.1%), 87.8% of it outside waterbodies
    (MORR 80.3%). The floor holds, and was not an artefact of lake country.
  - **Supersession:** the coho floodplain moves 25.7% at order ≥ 2 (MORR 16.6%), 2.1% at order ≥ 3.
    1,128 ha (3.0%) is lost to the pooled flood surface (MORR 1.3%).
  - **Cost: fails the 60 min bound.** Arm 2 takes 213 min per scenario (MORR 35.8): 170 blue-line
    attribution, 37 DEM fetch (network wait), 6 delineation. Attribution grew 5.1x for a 2.1x grid and 1.5x the
    blue lines, so the per-blue-line cost model does not transfer. **Attribution speed in flooded
    (`fl_valley_attribute()`, including the `complete = TRUE` fallback) gates committing a region**
    (flooded#71 fallback, flooded#72 per-group cost),
    not the floor.
- **The habitat join, demonstrated (MORR, chinook, 2026-10-11).** Evidence:
  `scripts/floodplain_lcc/logs/20261011_habitat_join-demo_morr.md` and its three figures, from
  `habitat_join-demo.R`; summary in `research/whole_fwa_floodplain.md`. link's chinook habitat from
  two builds (`fresh`, `morr`), joined to arm 2's blue-line floodplain with no re-delineation, in 146 s.
  - **Integrity:** every floodplain cell attributed, none outside; 99% of spawning km and 93–99% of
    rearing km (by build) on a blue line with floodplain (the rest is on order-1 blue lines).
  - **Join by position, not by blue line.** By blue line, 82% of the floodplain reads as chinook
    spawning floodplain. By position (each cell takes the nearest segment on its own blue line, by
    straight-line distance, standing in for the range join on route measure), with shared cells
    owned by the nearest segment of the blue lines that claim them: spawning 11,474 ha, rearing
    19,525 ha (`morr` build).
    On order >= 3, the only arm with segment attribution, the position join agrees with segment
    grain on 78–86% of cells (85–90% under the any-claimer rule).
  - **A new build is a new join:** `morr` adds 4,759 ha of rearing floodplain over `fresh` under the
    nearest rule (2,920 ha under any), 0 lost.

## Publish and query design (proposed 2026-10-08)

A STAC API selects **items**, not features within an item. So "the chinook spawning floodplain" is always two steps: STAC finds the item(s), then a query runs against the asset. stac_floodplains_bc serves a real API (pgstac on the geoserv droplet), so step one can be a proper search.

**Proposed: 1 + 2. Then 4 only if outside users need query-by-URL.**

1. **STAC for discovery, then query the asset over HTTP.**
   - Search by watershed group, region and scenario (flood factor) to get the item.
   - Publish the per-watercourse layer as **GeoParquet** (or FlatGeobuf) beside the gpkg. DuckDB or arrow then reads only the row groups matching `blue_line_key IN (...)`, with no download. A gpkg over `/vsicurl/` works, but SQLite reads it page by page, which for a large layer is close to a full download.
   - Publish the **habitat model as its own Parquet asset**, keyed by `(blue_line_key, measure range)` and stamped with its FWA version. "Chinook spawning floodplain" is then one DuckDB query: the range join described above, plus a filter.
2. **Summary properties on each item, for coarse search.**
   - Examples: km of spawning or rearing habitat inside the floodplain, per species, and the FWA version.
   - pgstac supports CQL2 `filter=`, so "which groups have chinook spawning floodplain" becomes an API search.
   - The cost: a new habitat model means republishing item **properties**. That is metadata only, never geometry.
3. **Not recommended: pre-built items per species and habitat** (e.g. `<wsg>_ch_spawning_ff04`). That is the per-species cut this issue removes, and every habitat model change would force a rebuild and republish. At most it suits a few flagship products.
4. **Optional: an OGC API - Features server beside pgstac** (e.g. tipg), serving a PostGIS view of floodplain x habitat. A URL such as `.../collections/floodplain_habitat/items?filter=species='ch' AND habitat='spawning'` then returns GeoJSON directly. It is the only option that gives a URL query to non-technical users or to QGIS's OGC Features connection, at the cost of more infrastructure.

Asset formats, item properties and the API are all publish-layer changes in stac_floodplains_bc; the coupling stays one-way. This repo's part is producing the per-watercourse layer and the habitat table in those forms.

## Questions to settle in planning

- ~~**What does "whole network" mean?**~~ **Order ≥ 2** (recommended 2026-10-10, confirmed on
  BULK 2026-10-11; see above). Not order ≥ 1.
- **Attribution cost.** 170 min per scenario for order ≥ 2 on BULK. Needs a flooded change before a
  region run: flooded#71 (the `complete = TRUE` fallback) and flooded#72 (per-group cost).
- ~~**Shared ground in the habitat join.**~~ **Decided 2026-10-11:** 78.6% of MORR's order >= 2
  floodplain cells are claimed by two or more blue lines. **Areas use the nearest segment among the
  blue lines that claim the cell** (one owner per cell, so per-reach areas add up to the
  floodplain); **the any-claimer rule is kept as the "connected to habitat" view** (habitat if any
  claiming blue line says so; it keeps attribution's overlap). Only claiming blue lines compete: the
  nearest segment anywhere is on a non-claiming blue line for 26.3% of cells, and 99.9% of those
  nearer segments are order 1. Both are query-time rules, so neither changes the geometry. Numbers in
  `research/whole_fwa_floodplain.md`.
- ~~Are tags booleans or lengths?~~ **Settled by the decision above: no tags.** Habitat varies along a blue line (spawning for 2 km of a 40 km blk), but the join answers that at query time, as km per habitat from the segment table, or as a filter on segments.
- ~~**blk or segment key.**~~ **blk**, following the order ≥ 2 floor (segment grain ~86 min per
  scenario, over the bound; segment grain only pays at order ≥ 3, ~31 min). If a segment key is ever used, key on `(blue_line_key,
  downstream_route_measure)`, never `id_segment`, which link renumbers per watershed group on a
  rebuild.
- **Keeping the floodplain and the habitat model in sync: only the FWA version has to match.**
  - **What breaks a join, and what does not.** A habitat re-run changes attributes, not keys, so
    it never breaks a join. What can break it depends on where segment boundaries come from.
  - **blk key.** No segment boundaries are involved. It stays valid as long as both sides use the
    same FWA version.
  - **Segment key, with breaks taken from FWA alone** (e.g. fixed measure intervals along each blk).
    Same as blk: only the FWA version must match.
  - **Segment key, with breaks taken from the habitat model** (link splits at barriers and habitat
    changes). A model re-run moves the breaks, so an equality join on `(blue_line_key,
    downstream_route_measure)` silently drops or mismatches rows. That is the real sync hazard.
  - **Join by range, not equality:** same `blue_line_key` AND the model segment's measure range
    overlaps the polygon's. The floodplain and the model can then be segmented independently and
    still join, and the join returns km of each habitat per polygon directly.
  - **Which habitat tables.** bcfishpass: `fresh.streams_vw_bcfp` (wide, `spawning_<sp>` /
    `rearing_<sp>` coded 1, 2 = modelled; keyed `segmented_stream_id`). link: `fresh.streams` +
    `fresh.streams_habitat_<sp>` (booleans; keyed `id_segment`, rebuilt per run). Both carry
    `blue_line_key` and route measures, which is what the range join uses. `fresh_default`, the
    per-group schemas and `score*` are alternate runs and tuning experiments, not join targets.
  - **Make the remaining requirement checkable.** Publish the FWA version beside the key, so a
    consumer can compare it with their model's rather than assume they match. Provenance already
    carries link's `fwapg_sha` (`network[...].link_log`).
- ~~**Does the floodplain change when delineated from the whole network?**~~ **Yes, measured
  (#110).** The coho network's floodplain moves 16.6% at order ≥ 2 (superseded; BULK 25.7%) and 1.6% at order
  ≥ 3 (extended; BULK 2.1%). The change is not monotone: 1.3% of today's coho floodplain is lost under the
  all-streams delineation.
- **Land cover change and the bridge:** step 3 and `patch_watercourse_*` (#54) would run on the whole floodplain. The disturbance tags (#19, #95, #103) ride along unchanged.
- **Item model and the region roster:** the species resolution in `run_region.R` and the species-keyed item id (`wsg`, `species`, `scenario`, #30) would change. That is a publish-layer change in `stac_floodplains_bc`, and the coupling stays one-way.

Relates: #40, #54, #89, #30















## Errors Encountered

| Error | Resolution |
|-------|------------|
