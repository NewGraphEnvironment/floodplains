# Findings — #53 (with #138)

## Issue context (#53)

## Problem

A watershed group's floodplain extends past the group boundary into its neighbour, so neighbouring
published items double-count the same ground.

Measured on MORR: `co_ff04` is 411.1 km2, of which **4.61 km2 lies inside BULK**. Both are live STAC
items, so the overlap is in published data.

## Cause

`02_floodplain_model.R:106` derives the delineation AOI from the stream network:

```r
dem <- flooded::fl_dem_aoi(streams, buffer = buf, target_crs = sf::st_crs(streams))
```

The accessible network runs to the group's downstream boundary — for MORR, the Morice mainstem to
its confluence with the Bulkley — and the VCA delineates a floodplain around those streams. Near the
outlet that floodplain naturally continues past the boundary onto the receiving river's valley floor.

Nothing clips the result to the watershed group. `subbasins.gpkg` is written but never constrains the
delineation; it is consumed by step 3 for reporting only. Verified by deleting MORR's
`break_points.csv` (#48): the sub-basin changed 4382.2 -> 4379.1 km2 and the floodplain did not move
at all.

## Scope

Every whole-WSG area whose accessible network reaches its outlet, which is most of them. MORR is
simply the one that was measured, because #48 sent us looking. The magnitude will vary with how wide
the receiving valley is at the confluence — a group emptying into a large river will overlap more
than one emptying into a canyon.

Not yet measured across the other 19 areas. That measurement should come before any fix, since it
determines whether this is a 1% correction or something that changes headline numbers.

## Why it is not obviously a bug

Arguably the floodplain of a river genuinely does continue past an administrative boundary, and
clipping it would cut a real landform at a line that has no physical meaning. Two defensible
positions:

1. **Clip to the group polygon.** Items become disjoint and areas across groups are additive, which
   is what a regional total needs. Cost: a floodplain is truncated mid-landform at the outlet.
2. **Leave it and record it.** The delineation stays physically honest; consumers are told the items
   overlap and by how much, the way the per-watercourse rows already overlap by design (#40).

(2) is more consistent with what this repo already does elsewhere — `<scenario>_by_<key>` rows
overlap at confluences deliberately, on the reasoning that a hard partition is a false answer where
ground is genuinely shared. The same argument applies at a group boundary.

But (1) is what makes summing across a region correct, and the Fraser total in `README.md`
(3,366 km2 across 10 groups) is currently a sum of possibly-overlapping polygons rather than a union.
**That figure should be checked either way**, independently of which option is chosen.

## Acceptance

- Overlap measured for every published area, not just MORR
- The regional totals in `README.md` recomputed as a union and compared to the current sums
- A decision recorded on clip-vs-record, with the reasoning
- If recorded rather than clipped: the overlap is discoverable by a consumer, not left implicit

## Related

- #48 — where this surfaced; the sub-basin was ruled out as the cause
- #40 — deliberate overlap between per-watercourse rows, the precedent for option (2)
- #30 — the item key, which is what would let a consumer detect overlapping items after a merge

## Measured on a whole-network area (DUNC, 2026-10-12, #104)

**205.4 ha of DUNC's 18,500.7 ha `all_ff04` (1.1%) lies outside the DUNC group polygon.** That
includes 41.2 ha of raw 2017→2023 land cover change. Step 3 clips the change patches to the
sub-basin, but the cell-level composition does not. So `composition-check.R dunc` fails its
change-vs-patch bound: +4.67%, against < 1% (measured 0.29–0.37% on species areas).

The whole network reaches more boundaries than an accessible one, so this overlap is likely to be
larger on every whole-network group. Whichever fix this issue takes (clip at delineation, or own
cross-boundary ground once) also decides whether that check's tolerance needs re-deriving.
Evidence: `scripts/floodplain_lcc/logs/20261012_whole_network_dunc.md`.


## Decided (2026-10-18): split at the group line and tag `in_wsg`

This replaces the 2026-10-14 decision to leave the overlap and record it. Neither clip (option 1) nor leave (option 2): the delineation is kept whole and **labelled**, the #40 pattern of attributing a fixed delineation rather than re-running it.

- **Every floodplain layer is split along the group polygon** (`subbasins.gpkg`, already on disk for every whole-WSG area), and each piece carries **`in_wsg`**: TRUE inside the item's own group, FALSE outside. Not `wsg`, which is the item key (#30) and means which item a row belongs to. `in_wsg` follows the repo's `in_*` columns.
- A consumer chooses: everything (the whole landform, as published today), `in_wsg` only (items are disjoint, so regional totals are sums), or `!in_wsg` (the overlap, discoverable per item).
- **Step 3 stops clipping change patches to the sub-basin** and tags them with `in_wsg` instead. Today it clips, while the cell-level composition keeps the outside cells, so the two populations disagree and `composition-check.R` fails its 1% bound on every whole-network group. With one rule for every layer, totals filtered to `in_wsg` equal today's patch totals.
- **The cell-level composition table gains `in_wsg`** beside `in_floodplain`. `composition-check.R`'s bound compares the `in_wsg` population, with the outside share reported beside it, so the check can fail again for a reason. Inside-polygon change cells already equal the patch totals within 0.12 ha in all 23 region groups (#125, 2026-10-17).
- **The floodplain raster is unchanged.** Areas are computed from the vector layers and the composition table; a raster consumer masks with the group polygon.
- **Backfill, not re-run.** A backfill script over each area's outputs on disk (the `gpkg_backfill-wsg.R` pattern) adds the column to all 23 published areas with no VCA or STAC fetch. The publish layer then adds `in_wsg` to its schema and republishes (one-way coupling, as always).
- Waterbodies are the same question at its largest, and #138 takes the same decision.

What is still owed, on **one branch with #138**:

- the split and tag in steps 2 and 3;
- #138's `in_open_water` context overlay (`fwa_lakes_poly` + `fwa_manmade_waterbodies_poly`, no size cut-off), on the patches and in the composition table, decided in #138's body;
- **one backfill** writing `in_wsg` and `in_open_water` together to all 23 published areas, so the publish layer changes its schema and republishes once, not twice;
- the composition bound;
- the README's regional totals recomputed over `in_wsg`, with open water reported beside the floodplain area (#138).

The PR closes both #53 and #138.




## Issue context (#138)

**If we fix it:** a group's floodplain is its own valley, and a reservoir shared by three groups is not published three times.
**If we never do:** PCEA's `all_ff04` item is 84% Williston Reservoir, and 42% of it lies in two groups no region lists (PARA, FINA).

**This is in published data:** `pcea_all_ff04` has been live since stac_floodplains_bc v2.0.0 (2026-10-15).

Found by #125's acceptance outlier screen (2026-10-17): the share of each group's floodplain lying outside its group polygon, over all 23 region groups.

| | median | IQR | PCEA |
|---|---|---|---|
| floodplain outside the group polygon | 1.73% | 1.12–2.42% | **41.7%** (35,197 of 84,334 ha) |

Every other group is between 0.81% and 3.25%. That band is #53's edge effect.

## What it is

- **Waterbody polygons enter the floodplain whole.** Step 1 selects them by `waterbody_key` from the network (`scripts/floodplain_lcc/01_network_extract.R:305`). Step 2 puts their polygons into the floodplain with no spatial filter (`02_floodplain_model.R`, the fallback-cells comment at ~377).
- **Williston is three FWA lake polygons sharing one `waterbody_key`**, one each in PCEA (35,612 ha), PARA (Parsnip Arm, 37,471 ha) and FINA (Finlay Arm, 99,586 ha). Step 1 selects lake and wetland polygons by `waterbody_key` with no group filter (`01_network_extract.R:305-313`), so PCEA's network touching Williston pulls in all three. *(Corrected 2026-10-18: this said one polygon.)* Sampled at 300 m, the floodplain's cells fall in PCEA 15,626, PARA 2,914, FINA 1,420, PINE 31, UPCE 19 and OSPK 10.
- **83.6% of PCEA's `all_ff04` is reservoir or large lake** (FWA manmade waterbodies plus lakes > 1,000 ha, by cell centre). ff02 / ff04 / ff06 are 840.2 / 843.3 / 846.6 km². The three are nearly flat because a reservoir surface floods whatever the factor.
- **It predates whole mode.** The retired `bt_ff04` was 92.1% reservoir and 58.4% outside the polygon.
- **The land cover numbers are not double-counted inside the group.** PCEA's change cells inside its polygon (754.4 ha) equal the patch total. Change cells outside it total 1,700.3 ha.

## Decided (2026-10-18): tag, don't cut

Neither clipping (1) nor excluding reservoirs by a rule (2): the floodplain stays whole and every cell that needs a question answered carries a flag.

- **The 42% outside PCEA is #53's `in_wsg` split** (decided there the same day). Filtering to `in_wsg` drops the PARA and FINA arms, which no region lists.
- **Every open-water surface is flagged as `in_open_water`, with no size cut-off** (named 2026-10-18). A small lake is no more a valley floor than Williston is, so the 1,000 ha threshold used by the outlier screen above is not a rule. It is one context overlay in `config/disturbance.yml`'s `context:` list, the mechanism `in_wetland` already uses: `in_open_water` + `waterbody_poly_id` over `fwa_lakes_poly` and `fwa_manmade_waterbodies_poly` together.
  - **One flag, not `in_lake` / `in_reservoir`, because FWA cannot tell a dammed lake from a natural one.** Williston is in `fwa_lakes_poly`; PCEA has no manmade-waterbody polygons at all, and the manmade table holds dugouts and ponds (BULK 85, MORR 1). A reservoir flag would have missed the reservoir this issue is about. A consumer who needs dam reservoirs looks them up by `waterbody_poly_id`.
  - Lake and manmade polygons do not overlap: 0 ha across BULK, MORR, PCEA, KOTL, NECR, PARA and FINA, with one shared edge (KOTL), measured 2026-10-18.
  - Size is a query: join the id to its area. No carry may be named `area_ha`, which the patch already has (`fp_disturbance_validate()` refuses it).
- **Cell-level, in the composition table** (#108's rule: report by cell, never by the any-touch patch flag), and on the change patches as context.
- **Rivers are not flagged.** The channel is part of the floodplain in this model.
- **Wetlands are already flagged and stay separate** (`in_wetland` + `waterbody_poly_id` from `fwa_wetlands_poly`, #95). A wetland is not open water: it is usually real floodplain, so it is reported beside the floodplain, never subtracted from it. "Open water" means `in_open_water`.
- **FWA never has a spot that is both lake and wetland.** Its waterbody polygons tile: in BULK, KOTL, MORR, NECR and PCEA, wetlands share an edge with a lake in 2,972 pairs and overlap a lake, reservoir or river polygon by 0 ha (measured 2026-10-18). A marshy lake margin is drawn as a lake on one side of a line and a wetland on the other. Where the *imagery* disagrees with the map (IO's Flooded vegetation inside a lake polygon, Water inside a wetland), the composition table already holds it: its rows are per land cover class and per flag, so it is a query, not a conflict. The flags are independent columns either way, so a cell could carry two of them without being counted twice, provided totals are summed over cells, never over flags.
- **Headline numbers report both:** floodplain area, and of which open water.
- Backfilled with #53's `in_wsg`, then republished by the publish layer.

Relates #53, #125.





## Exploration (2026-10-18, plan mode)

- drift 0.20.0 `dft_transition_vectors(zones=)` assigns `patch_id` BEFORE `st_intersection(out, zones_proj)`,
  so the sub-basin clip is the last op and the inside pieces are reproducible exactly without zones.
- Measured floodplain area outside the sub-basin union (primary scenario, vector):
  neexdzii co_ff04 303.1 of 14,204 ha (14 sub-basins); dunc all_ff04 204.5 of 18,521.4 ha; morr all_ff04
  595.1 of 47,931.9 ha. Every floodplain scenario layer is one MULTIPOLYGON row today.
- `fwa_lakes_poly`, `fwa_manmade_waterbodies_poly` and `fwa_wetlands_poly` have identical column lists
  (waterbody_poly_id ... geom).
- provenance-check.R 7c: `outputs.transition_patches == nrow(transition layer)`.
- fp_prov_set() recomputes inputs_hash from a JSON round trip, which moves it (#126) -> in-place edit.
- wetland already carries `waterbody_poly_id`; decided: open water carries it as `open_water_poly_id`.
- Decided: unclip everywhere; neexdzii parity restated over patches with a sub-basin.

## Errors Encountered

| Error | Resolution |
|-------|------------|
