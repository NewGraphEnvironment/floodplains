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

## Phase 3-4: live re-tag of NECR and BULK (2026-09-29)

**CORRECTION (same day, code-check P3-4 round 1).** The first live pass recorded below was
**wrong about geometry**. `st_read()` defaults to `promote_to_multi = TRUE`, and step 3 writes a
**mix** of POLYGON and MULTIPOLYGON under a `GEOMETRY` declaration. `fire_tag.R` read it promoted,
put that back as "the published geometry", and wrote the layer declared MULTIPOLYGON:
NECR 3,947 POLYGON + 1,745 MULTIPOLYGON became 5,692 MULTIPOLYGON, and BULK 5,024 + 2,137 became
7,161. The check's "0 rows differ" was real and meaningless: it read BOTH sides promoted. That is
"verification that reads its own output" -- the reference went through the same lossy reader as
the subject.

Repair:
- both readers now pass `promote_to_multi = FALSE`
- the check also compares the declared geometry type
- must-fail: a snapshot of the pre-re-tag backup against the promoted layer gives 2 FAIL (declared
  type, and 3,947 WKB rows)
- both gpkgs restored byte-for-byte from the pre-re-tag copies (no sidecars, rollback-mode header),
  then re-snapshotted, re-tagged and re-checked: ALL PASS, including NECR against the ORIGINAL
  backup's snapshot

The table below stands (the attribute values never moved).

**The first NECR re-tag was REFUSED by the compare-before-write, correctly.** The tagger intersects
on `st_make_valid()` output, which rewrote all 5,692 NECR geometries even though **0** were invalid
(ring normalisation; some MULTIPOLYGON came back POLYGON; areas unchanged). Step 3 does that once
before its first write. A re-tag has no reason to do it again, so `fire_tag.R` now puts the
published geometry back on the tagged attributes. The live check's WKB before/after comparison is
the external proof: 0 rows differ on both areas.

Re-tag results. Cause columns are identical to the snapshot on both areas, verified by
disturbance-check.R's live section:

| area | patches | tree loss | in_fire | in_harvest | residual | in_wetland |
|---|---:|---:|---:|---:|---:|---:|
| necr | 5,692 | 1,943.2 ha | 565.6 ha (29%) | 588.9 ha (30%) | 886.3 ha (46%) | 1,820 patches, 2,482.8 ha |
| bulk | 7,161 | 1,565.1 ha | 66.1 ha (4%) | 509.8 ha (33%) | 1,025.4 ha (66%) | 1,231 patches, 1,252.4 ha |

BULK's report is byte-identical before and after, so the README attribution figure's inputs did not
move. NECR's `in_wetland` covers **53%** of its 4,712.6 ha of change, far more than wetland's 15.9%
share of the floodplain area, because a patch is flagged when it TOUCHES a wetland.

Also verified:
- the live comparison's must-fail arm: a doctored snapshot (one `in_fire` flipped, one WKB altered)
  gives 2 FAIL
- `gpkg_prune-legacy.R` with `DRY=1` finds nothing on either area
- `bridge-check.R` passes on necr/ch_ff04 and bulk/co_ff04
- `provenance-check.R` passes on both

## Review record, Phases 3-4 (/code-check P3-4 rounds 1-2)

| Round | Findings | Fixed | Accepted | Inside previous fix? |
|-------|----------|-------|----------|----------------------|
| 1 | 2 | 2 (+ data restored) | 0 | **y** -- promote_to_multi, inside "keep the published geometry" |
| 2 | 3 | 3 | 0 | **y** -- fp_same_values' 15-digit compare, inside this phase's own helper |

**Mechanism:** a reader or writer DEFAULT transforms data in transit, and a check that reads both
sides through the same default cannot see it. **Terminated by enumeration.** Round 2 compared the
re-tagged layers against the pre-re-tag copies in SQLite directly, bypassing sf, over every artefact
of the round trip. Here is how each is now held:
- geometry blobs: WKB read unpromoted, compared (was: promoted on both sides)
- attribute values: exact doubles for numbers (was: 15 significant digits)
- declared field types, per column: PRAGMA table_info, compared; BOOLEAN -> typed is allowed for carries only
- declared geometry type + srs_id: gpkg_geometry_columns, compared
- column set: a dropped snapshot column FAILs (was: silently intersected away)
- row set: (name_basin, patch_id) key, compared
- rtree, gpkg_contents extent + last_change, fid mapping: verified identical by round 2, not in the check
- layer order in gpkg_contents: CHANGES (the re-tagged layer moves last). No script in either repo
  reads layers by position. Accepted.
- Integer64 / datetime / NULL-geometry fields: none in any of the 21 areas' transition layers
  (round 2's scan), so these defaults have nothing to act on.

Each new arm was shown to FAIL: a doctored snapshot (MEDIUMINT type, srs 3005, extra column) gives 3
FAIL; a schema-less snapshot gives 1 FAIL rather than passing vacuously; and
`fp_same_values(0.1 + 0.2, 0.3)` is FALSE.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| fire_tag re-tag promoted every POLYGON to MULTIPOLYGON; check blind (both sides promoted) | `promote_to_multi = FALSE` in both readers + declared-type compare; gpkgs restored from backup and re-tagged |
| `fire_tag.R necr`: REFUSED, `<geometry>` would change | `st_make_valid()` rewrites valid geometry; re-tag keeps the published geometry |
| Offline arms passed against a function that did not exist | `refused()` matches the guard's condition class; `accepted()` requires the call to run |
