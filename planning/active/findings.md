# Findings — Wetland context flag on transition patches: undated context: overlays (in_wetland from FWA wetlands) (#95)

## Issue context

## Problem

Wetland-related change patches cannot be found by attribute. #92 decided how to flag them, and #93 needs the flag to build its wetland strata. It was carved out of #92 so it can ship alone, ahead of the report.

NECR scale for context (2026-09-27): about 65 ha left Flooded Vegetation 2017→2023 (Rangeland 30.1 ha over 104 patches, Water 28.4 ha) and about 35 ha entered it.

## Design (decided in #92)

**Two independent signals, both kept:**

- **Class-based:** `from_class == "Flooded Vegetation"` (or `to_class`). This is already on every patch and needs no new column. It is what IO LULC says the pixel was.
- **Mapped-wetland overlay:** `in_wetland` plus carried attributes from `whse_basemapping.fwa_wetlands_poly` (already in fwapg). It catches wetlands IO never labelled Flooded Vegetation, such as a treed or shrubby wetland labelled Trees or Rangeland.

**Mechanism: an undated `context:` list in `config/disturbance.yml`, not an entry under `sources:`.**

- `sources:` is read as *causes*:
  - `fp_disturbance_report()` counts every `in_<source>` as explaining tree loss and leaves the rest as the residual.
  - `fp_readme_sources()` builds the README attribution figure from the same list.
- An `in_wetland` there would shrink the "not attributed" share for a reason that explains nothing.
- A separate `context:` list is invisible to both by construction.
- `fp_disturbance_tag()` reuses its fetch, intersect and carry path for it. `.dst_fetch()` (`scripts/floodplain_lcc/fp_disturbance.R:27`) skips the year predicate when `year_col` is absent. A `year_col` stays required for `sources:` entries: an undated cause would be a config error and should be refused, not silently un-windowed.

## Found while scoping: `fire_tag.R` still writes the #55 orphan

`scripts/floodplain_lcc/fire_tag.R` (the CLI to re-tag without the STAC fetch) writes a sibling `transition_<scenario>_<span>_disturbance` layer (lines 40–41). That is exactly the legacy class #55 swept with `gpkg_prune-legacy.R`. Step 3 has since tagged onto the main transition layer, so a re-tag through this CLI recreates an orphan and leaves the main layer without the new column.

Fix it here, because re-tagging existing areas with `context:` is the obvious use of this CLI: write onto the main layer, the same as step 3.

## Scope

- `config/disturbance.yml`: add the `context:` list with a `wetland` entry (`table`, `geom_col`, `carry`, no `year_col`). Document in the header why it is separate from `sources:`.
- `fp_disturbance_tag()`: tag `context:` entries (no year window). Step 3 (`03_lulc_classify.R:221`) and `fire_tag.R` both pass them through.
- `fire_tag.R`: write onto the main transition layer, not a `_disturbance` sibling.
- Carried attributes: decide which `fwa_wetlands_poly` columns are worth carrying, at minimum the feature id. Keep it small, because every carried column is a STAC schema column.
- STAC: the transition layer gains `in_wetland` plus the carried columns, so stac_floodplains_bc#6 needs to know. The coupling stays one-way: nothing here calls the publish layer.
- Measure, rather than assume, how much of NECR's FWA wetland area sits inside the `ch_ff04` floodplain. The delineation seeds wetlands (`wetlands = TRUE`, `wetland_filter = network`).

## Acceptance

- NECR's transition layer carries `in_wetland` and its carried columns, and wetland-related patches filter by attribute.
- `fp_disturbance_report()` output and the BULK attribution figure are **unchanged** with the `context:` list present. That proves a context entry cannot leak into attribution. Include a must-fail arm: moving `wetland` under `sources:` must change the residual.
- A `sources:` entry with no `year_col` is refused.
- Re-tagging via `fire_tag.R` leaves no `_disturbance` layer in the gpkg, and `gpkg_prune-legacy.R` with `DRY=1` reports nothing to prune.
- CLAUDE.md's disturbance bullet names the `context:` list.

Relates: #92 (report, split from its wetland section), #93 (uses the flag for strata), #55, stac_floodplains_bc#6



## Phase 1: a check that could not fail (2026-09-28)

The first draft's `refused()` accepted ANY error, so every "is refused" arm PASSED against a
`fp_disturbance_validate()` that did not exist yet ("could not find function" is an error). The
mirror, `!refused()` for the "is accepted" arms, passed for the same reason. Fixed: refusal must be
the guard's own condition class (`fp_disturbance_config_error`), and acceptance must mean the call
ran. Re-run: zero PASS lines before Phase 2 -- red for the right reason.

## NECR: how much FWA wetland sits in the floodplain (measured 2026-09-28)

The issue asked this to be measured rather than assumed, and the assumption would have been wrong.
The first draft of the `disturbance.yml` comment said "most sit inside the floodplain already"; it
was removed before commit because it had not been measured.

- NECR FWA wetlands: 4,495 polygons, 16,291.8 ha.
- Inside the `ch_ff04` floodplain: 6,290.3 ha, **38.6% of wetland area**. 1,118 polygons touch it.
- Wetland is **15.9%** of the 39,651.5 ha floodplain.

So the delineation's `wetlands = TRUE` seeding does not put most wetland inside the floodplain;
it seeds only network-connected wetlands (`wetland_filter = network`). `in_wetland` therefore flags
patches in about a sixth of the floodplain's area.

Snapshots for the Phase 4 comparison: `snap_{necr,bulk}.rds` (the transition layers' attribute
tables) and byte copies of both `floodplain_landcover.gpkg`, in the session scratchpad. Both gpkgs
had exactly one live transition layer and no legacy `_disturbance`/`_fire` layer. Columns on both:
`patch_id, transition, area_ha, name_basin, from_class, to_class, in_fire, fire_year, fire_number,
in_harvest, harvest_start_year_calendar, wsg, species, scenario`. That is FP_PATCH_CORE plus the
two sources' columns, exactly.

## Review record, Phase 2 (plan review + /code-check rounds 1-3)

| Round | Findings | Fixed | Accepted | Inside previous fix? |
|-------|----------|-------|----------|----------------------|
| plan review | 13 | 10 | 3 (followed up as #96; 2 folded into later phases) | — |
| 1 | 2 | 2 | 0 | — (both pre-existing, on the new wetland path) |
| 2 | 2 (+1 comment) | 3 | 0 | **y** — silent carry drop inside the typed-NA fix |
| 3 | 3 | 3 | 0 | **y** — missing-column residual inside the Reduce-init fix |

**Mechanism (round 3):** a lookup by NAME returns something other than what was meant, and R keeps
going. `$` partial-matches, `[[` of an absent column is NULL (which drops a column on assignment and
empties a mask when OR-ed), `patch_id` looks like a key and repeats across sub-basins, and Postgres
and GeoPackage fold identifier case.

**Terminated by enumeration, not by a quiet round.** Every `[[`/`$` in fp_disturbance.R, parsed
with getParseData (35 lines):
- entry-field reads: exact `[[`, keys whitelisted (FP_DST_ENTRY_KEYS). Absent optional keys are
  intended NULL, and required ones are checked.
- `poly[[a]]` is guarded by the lost-carry refusal.
- `loss[[ic]]` is guarded by the absent-column refusal.
- the report's patch columns moved from `$` to `[[` plus a presence check.
- the remaining `$` uses are `inter$._ov` (an assignment) and `dom$._row` (a tibble, which does not
  partial-match).

The cfg side is swept by the check itself (no cfg key prefix-relates to `disturbance` or
`context_overlays`). The sweep's one other hit is #97, which predates this work.

Out of scope, noted by round 3: the dominant-feature pick breaks exact overlap ties by SQL row order
(no ORDER BY). This is unchanged by #95, and fire_tag.R's compare-before-write would surface it as a
refused re-tag rather than a silent change.

## Errors Encountered

| Error | Resolution |
|-------|------------|
