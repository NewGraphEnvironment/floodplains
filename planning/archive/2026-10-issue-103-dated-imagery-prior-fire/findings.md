# Findings — Dated orthophotos and air photos as review themes, and prior-fire regrowth attribution (#103)

## Issue context

**If we do it:** reviewers label #93's pilot points against imagery that is both higher resolution and dated, not only 10 m Sentinel-2 chips. Regrowth after an older fire also stops reading as unexplained change in 2017–2023.
**If we never do:** labels rest on 10 m chips and undated basemaps. Rangeland→Trees and similar "regrowth" transitions stay in the unattributed residual even where a pre-2017 fire explains them, which inflates exactly the number #93 is trying to measure.

## Problem

#93's review project (PR #102) gives the reviewer two kinds of imagery. Sentinel-2 chips are dated but coarse (10 m). Esri, Google and Bing are sharp but undated. We hold two dated, higher-resolution sources and use neither:

- **BC orthophotos** via our STAC, our private orthophoto STAC (`<private ortho STAC>`).
- **Historic air photos**, through the `fly` package: `fly_select`, `fly_footprint`, `fly_overlap`, `fly_coverage`, `fly_fetch`, `fly_georef`.

Separately, **fire attribution is windowed to the change interval** (`cfg$change_interval`, 2017–2023). A fire a few years *before* 2017 (say 2010–2016) explains post-fire **regrowth** inside the window: Rangeland or Bare → Trees, and shrub transitions. Today that regrowth lands in "not attributed".

## What

1. **Find the overlapping imagery** for the #93 sample points (start with NECR): orthophotos from our private orthophoto STAC, air photos via `fly`. Record per point which dated images cover it, and when.
2. **Load them into the review project as map themes where they make sense.** One theme per epoch or source. That means the source has to cover a useful share of points; a single photo over two points doesn't earn a theme. Follow how rtj does it: `scripts/gis/stac_raster-add` and the map-theme work (rtj#327), and the Nelson project (`nelson_20260826`, KOTL+LARL+SLOC, rtj#213) as the worked example.
3. **Fire regrowth.** Tag transition patches with *prior* fires, not only in-window ones. One option is a separate lookback (e.g. `in_fire_prior` + fire year), kept apart from in-window `in_fire` so the cause semantics do not blur. It also feeds a regrowth stratum for the accuracy sample.
4. **Windows are not fixed.** `reference/necr/windows.csv` (August; 2017 August–September) can change if dated ortho or air-photo epochs argue for different reference years. Chips cache per point, so re-chipping costs only the new windows.

## For the planning pass

- **Ownership.** Does point-to-imagery overlap belong in `fly` (`fly_coverage`/`fly_overlap` may already do it), in `drift`, or here? Do not re-implement either package here.
- **Prior-fire lookback.** How long (5 / 10 / 15 years), and should it stay a context-like flag or become a cause? `fp_disturbance_validate()` currently enforces the causes/context split (#95).
- **Data contract.** Does the prior-fire tag change the published transition layer, and with it the STAC schema in `stac_floodplains_bc`? The coupling stays one-way.
- **Strata.** Is a regrowth stratum a redraw? A redraw moves points under the same ids, and `sample_draw-pilot.R` refuses to redraw over labels. So this has to be decided **before** labelling starts.

Relates: #93, #95, #100, rtj#213, rtj#327


(Private endpoint and repo name redacted: floodplains is public, and the ortho repo's CLAUDE.md
forbids naming either from a public repo.)

## Plan-mode measurements (2026-10-01)

Probes: scratch scripts, not committed.

- **Ortho**, private STAC, read through `FP_ORTHO_STAC`. Over the NECR sample bbox it returns 777
  items, all from 2021, all COGs at 0.15 m. They cover **214 of 450** sample points. The COGs read
  over `/vsicurl/` as YCbCr JPEG with 5 overview levels.
- **Air photos**: 16,964 BCDC centroids in the sample bbox buffered by 5 km. `fly_footprint()`
  could not size 1,466 of them, all digital colour: 1,380 from 2012 and 86 from 2015. Those need a
  DEM.
  - Sample points covered, by decade: 1960s 33, 1970s 424, 1980s 449, 1990s 450, 2000s 450,
    2010s 13 (2019 only, from the frames it could size).
  - By year from 2000: 2000 → 450, 2002 → 108, 2005 → 98, 2006 → 113, 2019 → 13.
  - Media by frame: Film BW 3,916, Film Colour 1,424, Digital Colour 19 (counts from the frames it
    could size).
- **Film frames that carry a bearing are skipped by `fly_georef`** unless the per-roll `rotation` is
  known. fly#26 is closed; the table of rotations is fly#53 and still open.
- **The local fire table holds `fire_year` 2017–2025 only** (3,565 rows). The cutblock table is the
  same, 2017–2026 (121,836 rows). Both were loaded filtered to `>= 2017`. bc2pg supports
  `--append` + `--query`.
- **Prior fires from DataBC** (FIRE_YEAR < 2017, polygons touching the floodplain), NECR `ch_ff04`:
  - The area has 4,730 ha of published change, 915 ha of it a gain to Trees.
  - Gain to Trees inside a prior fire, by lookback: 5 yr 21.0 ha · 10 yr 173.7 (19%) · 15 yr 173.7 ·
    20 yr 173.7 · 30 yr 173.7 · all years 370.3.
  - Any change inside a prior fire, by lookback: 5 yr 289.6 ha · 10–20 yr 496.3 · 30 yr 500.4.
  - Inside 2002–2016 fires (bbox query): 283.2 ha of Trees→Rangeland (2011) and 171.5 ha of
    Rangeland→Trees (11002).
  - Tree loss totals 1,957.8 ha, of which 900.9 ha is unattributed. **243.4 ha (27%) of that
    unattributed loss lies inside 2002–2016 fires.**
- **The same measurement for BULK `co_ff04`**: 3,640 ha of change, 833 ha a gain to Trees. Gain
  inside a prior fire is 3.6 ha at every lookback from 5 to 20 years.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `st_transform` on a fetch with a missing CRS during the prior-fire probe | The query returned 0 rows: the table holds only fires from 2017 on. I sized the effect from DataBC directly instead. |
| 87 of 250 2012 air photo frames 'skipped rather than written squashed' by `fly_georef`; diagnosed as a fly defect and filed as fly#88 | **Wrong diagnosis.** The build passed `fly_georef` only the frames being fetched, so frames lacked their roll neighbours, got no bearing, were drawn landscape against portrait thumbnails, and the stretch guard refused them. fly WARNED, and `suppressWarnings()` in the build hid it. Code-check (round 1, phases 4-6) caught it. Verified on frame 219: skipped alone, georeferenced with 218 and 220. fly#88 was corrected and closed as a caller error. The fix passes the year's full frame set, with no warning suppression. |

## Phase 1: prior fires loaded (2026-10-02)

- `fire_load-prior.sh` appended **21,186** rows with `FIRE_YEAR < 2017` (1910s–2010s).
  - Rows from 2017 on: **3,565** before and after.
  - Their md5 was `893d6cc40378a56564eb1fadcaf6b34b` before and after.
  - Log: `scripts/fwapg/logs/20261002_000925_bc2pg_append_fire-prior.log`.
- Prior fires by decade: 1910 263, 1920 3,992, 1930 4,118, 1940 1,901, 1950 1,530, 1960 1,570,
  1970 1,502, 1980 1,410, 1990 956, 2000 1,879, 2010 2,065.
- A second run is refused, because rows before 2017 are now present. Tested.
- `bcdata.log.latest_download` for the fire table now reads 2026-10-02. That row describes the
  append only; the in-window rows still date from 2026-07-16.
- **bcdata logs its connection URL with the password in it.** I redacted it from the committed
  log, and the script now pipes bcdata output through a redaction `sed`. The 2026-07-21 cutblock
  log, committed in #19, DID carry it: `postgres:<default>@localhost`, the container's default.
  I redacted it in this commit. Git history and the public Pages copy still hold the old text.
  The risk is low (localhost-only default), but the password should be rotated if the container is
  ever exposed.
- Backed up `data/necr/floodplain_landcover.gpkg` and took a `disturbance-check.R` snapshot before
  the load (`necr_pre103.rds`, scratchpad).

## Phase 3: NECR re-tagged (2026-10-02)

- `fire_tag.R necr` needed no FORCE. **314 patches (506.4 ha) are `in_fire_prior`.**
  - Fire years: 2015 223, 2010 89, 2014 2.
  - By transition: Trees→Rangeland 282.5 ha, Rangeland→Trees 176.8, Rangeland→Crops 21.4, other <6.
  - Tree loss 1,943.2 ha in all: fire 565.6, harvest 588.9, residual 886.3, of which **242.8 ha
    (27%) is in a prior fire**.
- `disturbance-check.R necr <pre-load snapshot>` is ALL PASS. Cause columns, core columns and WKB
  geometry are all unchanged.
- Log: `scripts/floodplain_lcc/logs/20261002_fire_tag_necr_prior.md`.
- **Round 3 of code-check:** every area not yet re-tagged now fails the live check's "every context
  and lookback column is present" (bulk included). That is expected and forward-only, the same as
  at #95.
- **Schema:** stac_floodplains_bc#6 gained a section (body edit). Lookback columns are context, not
  attribution, are forward-only, and are legitimately all-FALSE in 9 of 23 areas.

## DRAFT, not filed: follow-up floodplains issue on the lookback (per user, 2026-10-02: "file … once we understand")

**Title:** Should prior fire (lookback) become a cause? Decide from the #93 labels

The text to file, once the stratum-19 labels exist:

> #103 tags patches with fires from the 15 years before the change interval (`in_fire_prior`) and
> keeps them out of attribution. In NECR they overlap 242.8 ha (27%) of the unattributed tree loss
> (Trees→Rangeland 282.5 ha inside 2002–2016 fires, mostly from 2015 and 2010) and 176.8 ha of
> Rangeland→Trees. Stratum 19 ("change in prior fire", 453 ha, 30 points) was drawn so the labels can
> say whether that change is real. Then decide:
> - **Real loss** (delayed mortality, snag fall, salvage outside the cutblock window) → promote
>   `fire_prior` to a cause, perhaps split by years-since-fire, and recompute the README attribution.
> - **IO flicker in burned stands** → it stays context, and the finding is evidence for criterion 2/3
>   rather than for attribution.
> - **Regrowth** labelled correctly → no attribution change. Report it as recovery.
>
> Also: the published lookback columns may move on a re-tag (`fire_tag.R` NOTEs it), so pick the
> lookback length here, before other areas are re-tagged.

## Phase 4–6 code-check, round 1 (2026-10-02)

- **HIGH:** the fly#88 misdiagnosis above.
- **MEDIUM:** the build's staleness guard compared mtimes, and git does not keep mtimes, so it
  failed both ways. `imagery.csv` now carries `stratum, cell, map_class`, and the build runs
  `fp_acc_design_check` on it.
- **LOW:** a project built before this change keeps the old form value map in its `.qgs`. That
  affects only the archived `necr_lulc_review_pre103`; the rebuilt project has all values.

## Phase 4–6 code-check, rounds 2–3 and the closing enumeration (2026-10-02)

- **Round 2** found a defect inside the round-1 fix. The content check could not see MISSING rows
  in a sparse index. Fixed: every point is listed, and the point set is checked. It also found:
  - buildvrt counting the tiles requested, not the tiles opened, and leaking hrefs in warnings
    (fixed: `fp_acc_quiet_urls`, a SourceFilename count);
  - a stale georef cache (fixed: `overwrite = TRUE`);
  - patches refreshed on columns only (fixed: refreshed on content, WAL sidecars removed);
  - two doc numbers.
- **Round 3**, an enumeration of 36 sites, found five that do not hold. Two of them sit inside
  round-2 fixes:
  - redaction missed bare and bracketed hosts and IPs (fixed);
  - orthophoto coverage was taken from footprints, and 25 points sit on a zero collar. It is now
    read from pixels: **204, not 229**;
  - the air photo VRT had no source count (fixed);
  - an orphaned layer left its theme behind (fixed);
  - the review build did not check the index (fixed).
- **Closing enumeration (mine): every call that can touch an orthophoto href or the endpoint.**
  - All sit inside `fp_acc_quiet_urls`: `fp_acc_ortho_items`, the index pixel reads, buildvrt,
    warp, `res_m`, and the review `rfp_qgs_raster_add`. The last two were found by this
    enumeration and wrapped.
  - No `http`, objectstore or private host appears in the run logs, `imagery.csv`, the committed
    logs or tracked files.
- **Reviewer spend for #103 so far:** 1 plan review plus 3 code-check rounds (phase 2) plus 3
  (phases 4–6). That is 7 agents, past the ~5 bound. Each round past the second found a real
  defect.
