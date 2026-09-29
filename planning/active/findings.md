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



## Errors Encountered

| Error | Resolution |
|-------|------------|
