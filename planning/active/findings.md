# Findings — Probe: cost and difference of a whole-FWA floodplain on MORR (#110)

## Issue context

**If we do it:** #104's open choices (floor, blk vs segment, go/no-go) get decided on measured cost and on what the floodplain looks like. #104 can then be planned as a build rather than as a set of unknowns.
**If we never do:** #104 is either built blind, possibly spending hours per group on first-order valleys a 30 m DEM cannot resolve, or not built at all, and the floodplain stays cut to one species' order ≥ 3 network. On BULK, MORR and NECR that cut drops **20–29% of modelled coho rearing** (orders 1–2), plus the first-order channels feeding ≥ 5th-order rivers (**650–1,370 km** per group).

## Question

What does it cost to delineate a watershed group's **whole** FWA floodplain, and how does the result differ from today's species-cut floodplain? Today's step 2 takes 2–92 min per group (median ~14, three scenarios, read from provenance timestamps). The whole-network cost has never been measured.

**What we know going in** (measured 2026-10-03, `fresh.streams_vw_bcfp`):
- First-order lines are 56–63% of stream length.
- MORR has 6,753 blue lines in all, against 340 in today's coho network.
- #40 measured attribution at 0.39 s per extra watercourse on MORR (16.5M cells). Extrapolated, that is about 40 min per scenario for MORR's whole network by blk. **That number has not been measured.**

## Probe: MORR, one scenario (`co_ff04` parameters)

Five network arms, each delineated with the same VCA parameters:

1. All FWA (order ≥ 1)
2. Order ≥ 2
3. Order ≥ 3
4. Order ≥ 3, plus first-order channels with `stream_order_parent >= 5` (link's bcfishpass bypass rule)
5. Today's coho network (accessible, order ≥ 3), the baseline, which already exists in `data/morr/`

Record per arm:
- **Cost:** wall time and peak RSS, with **delineation and attribution timed separately** (attribution by `blue_line_key`). Also the count of segment groups, if segment-level attribution is tried.
- **Area:** total floodplain, and the floodplain inside the coho network's valleys compared with the baseline's. Re-seeding from more streams moves the boundary even where the arms overlap, because the flood surface is fitted from every seed (#40). This comparison measures that move.
- **Quality:** visual review of first-order valleys at MRDEM-30, i.e. whether they are floodplain or edge artefact. Also the area added by arm 4 beyond the mainstem's own floodplain.
- **Habitat:** modelled rearing km (co, ch) below each floor, from `fresh.streams_vw_bcfp`.

## Constraints

- A probe script reads the network **without** the access filter and calls `flooded` directly, with the scenario row's parameters.
- It does not touch steps 1–3, any published layer, or `provenance.json`.
- Outputs go to gitignored `data/morr/probe_whole_fwa/` plus a committed log.

## Output

A `research/` topic file stating cost per arm, the area difference, and a recommendation on floor and grain. Then #104's body is revised to plan against those numbers.

Relates: #104, #40, #54

## Exploration (2026-10-09, plan mode)

- **Step 2 is cheap; attribution is not.** MORR provenance: `co_ff02` → `co_ff04` written 68 s
  apart (delineation ≈ 1 min), but `co_ff04` → `co_ff06` took 14 min, i.e. the blk attribution of
  340 groups. #40's 0.39 s/group puts arm 1 (6,706 blks) near ~1 h, and a **segment** grain over
  the whole network (37,801 order-1 segments alone in `fresh.streams`) near 6 h. So segment
  attribution is measured on one arm, not all.
- **Arm networks come from the same source as step 1.** 01 reads `fresh.streams` ⋈
  `fresh.streams_access` + fwapg `upstream_area_ha` / `map_upstream`. `fresh.streams` has
  `stream_order_parent`, so all five arms are 01's SQL with only the `WHERE` changed (MORR,
  `fresh.streams` km by order: 1: 5,562 · 2: 1,820 · 3+: 1,654). Arm 3 ⊇ arm 5 exactly.
- **Grids differ per arm.** `fl_dem_aoi()` reprojects MRDEM (EPSG:3979) to the streams CRS over
  each network's bbox, so arms on their own DEMs are on different grids. Comparisons need one DEM.
- **Two exact anchors are available from the existing record.** `network[co3].outputs
  .streams_content_sha256` (01's digest key/values) and `floodplain[co_ff04].outputs
  .floodplain_content_sha256` + `inputs.dem_content_sha256`. The probe's arm-5 rebuild must hit
  all three, which proves its SQL and VCA call are step 1/2's without editing either.
- `fresh.streams_vw_bcfp` carries `rearing_*`/`spawning_*`/`access_*` for the habitat table.
- Pattern to copy: `channel_probe-migration.R` + `fp_channel.R` + `channel_probe-check.R`
  (helpers sourced, anchors that stop the run, gitignored `data/<area>/…`, committed logs).

## Errors Encountered

| Error | Resolution |
|-------|------------|
