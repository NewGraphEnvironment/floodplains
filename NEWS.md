# floodplains 0.1.15 (2026-10-18)

* #125's acceptance checks ran on the Fraser (13 groups), Peace (3) and Columbia (4) whole-network
  runs, read-only on their outputs. They ran after stac_floodplains_bc v2.0.0 had published the
  items, so they checked live data and gated no release.
  * `scripts/floodplain_lcc/region_checks-run.sh <region>` runs the per-group checks, and
    `region_acceptance-report.R <region>|all` derives every table from disk. Both reproduced the
    Skeena log first.
  * Every group passes `provenance-check.R` and the `all_ff04` disturbance section. The new failures
    each have an issue: PCEA's Williston Reservoir spill (#138), the bridge check's union proxy
    (#139) and NECR's accuracy scenario (#140). The imagery look is #141.
  * `habitat_join-query.R` attributes every floodplain cell in all 20 groups. KOTL, LARL and SLOC
    have unmatched habitat rows from a 2026-10-17 `fresh_default` rebuild (#123).
  * Logs: `scripts/floodplain_lcc/logs/20261017_whole_network_{fraser,peace,columbia}.md` and
    `20261018_habitat_join-query_*.md`.
* The Peace and Columbia region configs, as reconciled by their 2026-10-15 runs, are committed with
  the run logs (`20261015_run_region_{peace,columbia}.log`).

# floodplains 0.1.14 (2026-10-15)

* The habitat join's position join now comes from `flooded::fl_valley_join()`
  (NewGraphEnvironment/flooded#83) instead of the local `fp_hj_join_range()` (#104).
  * `habitat_join-query.R` and `habitat_join-demo.R` stop unless flooded is above 0.7.2; install the
    release with `scripts/packages.R`. Per-cell flags and tie counts are identical to the old join on
    DUNC, MORR, KISP and BULK.

# floodplains 0.1.13 (2026-10-14)

* `run_region.R` runs a region as the whole stream network: `network: whole` in a region file makes
  every group `species: all` at order >= 2, attributed by `blue_line_key` (#125, #104).
  * The species pre-pass is skipped. A count of the group's segments in `network_source` stands in,
    so a group the schema lacks is a loud SKIP. The region owns `species`, `attribute_by` and
    `min_order` (default 2, never lower).
  * A whole region converts a species area in place and appends the `all_*` scenario rows, carrying
    the species rows' citations. A species region still refuses `all` both ways, and whole mode
    refuses a `targets:` block naming a species scenario.
  * All four region files are whole-network. KISP folds into `skeena.yml`, DUNC joins
    `columbia.yml`, and Columbia drops `network_guard: warn`.
  * Skeena ran whole-network on flooded 0.7.0: `all_ff04` BULK 660.0, MORR 479.3, KISP 324.4 km²
    (`scripts/floodplain_lcc/logs/20261014_whole_network_skeena.md`).
* The region cache calls a group complete only when its records are this config's finished run: a
  floodplain on flooded 0.7.0's grid, a network read with the configured schema and `min_order`, and
  a landcover record newer than both. A group chosen to re-run has its summary removed first. Files
  sitting together on disk were being read as one run.
* `fp_region_mode()` reads region keys with `[[`: `reg$network` partial-matched `network_source` and
  refused an ordinary species region. The coverage CSV no longer aborts when a group is skipped.

# floodplains 0.1.12 (2026-10-14)

* Step 2 caches its DEM per area and species, as `data/<area>/dem_<sp><order>.tif` with a JSON
  sidecar (#122). NRCan's bucket had been serving MRDEM-30 at ~145 KB/s, so BULK's fetch took
  37 min of every re-run.
  * The key covers the streams' geometry, buffer, CRS, source URL, the object's Last-Modified and
    ETag, the flooded version and everything `fp_toolchain()` records. A hit also needs the file
    to digest as recorded. A cached run still makes one HEAD request, and fails closed without it.
  * The driver now owns the DEM URL (`FP_DEM_SOURCE`) and records it as `inputs$dem_source`;
    `run$dem_cache` records the hit or miss, key, path and object version.
  * `attribute_tag.R` reads the same cache at the buffer step 2 recorded, and stops unless the DEM
    digests as step 2 recorded.
  * `provenance-check.R` 7c reconciles `dem_content_sha256` against the cached file.
    `dem_cache-check.R` asserts the cache offline (`LIVE=1` adds a real round trip).

# floodplains 0.1.11 (2026-10-13)

* Step 2 now requires flooded >= 0.7.0, whose DEM grid is pinned, and provenance records the GDAL
  and PROJ that terra links (#117).
  * Before 0.7.0 the DEM grid followed PROJ's NAD83(CSRS) to NAD83 operation and moved about 1.3 m
    between PROJ 9.5.1 and 9.8.1 with no data change. Every step-2 output moves once when re-run.
  * `run.toolchain` gains `gdal_terra` and `proj_terra` beside sf's fields, and
    `provenance-check.R` requires them on entries whose step ran after the cutover.
  * `attribute_tag.R` refuses a delineation on the other grid, in either direction, by name.
  * The neexdzii parity contract is re-baselined: 673.5 km, 142.0 km², 773.4 ha.

# floodplains 0.1.10 (2026-10-13)

* An in-place raster repair now moves the landcover run stamp with the bytes it rewrote, and
  necr and kotl are re-stamped so they can be staged again (#126).
  * `raster_strip-tags.R` reconciles every landcover entry whose rasters are newer than
    `run.datetime_utc`. Each late raster must still match its recorded content digest. The stamp
    moves to the newest one's floored mtime, and `run.repairs` records the repair and the stamp
    it replaced. A late file the current run did not repair needs `BACKFILL=1`.
  * The re-stamp refuses to move past a floodplain re-run, because `fp_composition.R` reads the
    same stamp as "when step 3 ran".
  * `provenance-check.R` fails a raster newer than its run stamp.

# floodplains 0.1.9 (2026-10-12)

* Whole-network floodplains keyed by `blue_line_key`, piloted on DUNC (#104, #120).
  * **`species: all`.** A reserved token for the whole stream network at order ≥ `min_order`
    (2) with no access join. It sits in the species slot, so every species-keyed name carries it:
    `streams_all2`, `all_ff04`, `all_ff04_by_blue_line_key`, `network[all2]`. Step 1's read is
    now `fp_network_sql()`, whose species branch `whole_network-check.R` pins byte-identical to
    the previous SQL, so existing areas do not move. A whole-network area must set
    `attribute_by: blue_line_key` and a `network_source`; step 2 refuses flooded < 0.6.4, and
    region runs refuse the token until they learn the mode (#123).
  * **Habitat is a table, not a column on the floodplain.** Step 1 writes `habitat_link` into
    `aquatic_network.gpkg`: link's per-segment flags per species, keyed by FWA position at every
    order, with a `habitat` provenance sibling that records the FWA version beside it.
    `habitat_join-query.R <area> [species]` joins it by position to the blue-line layer.
  * **DUNC, the first whole-network area.** `all_ff04` is 185.0 km², and 1,942 of 2,236 blue
    lines carry floodplain. Step 2 took 8.9 min, its blue-line attribution ~3.3 min on flooded
    0.6.5. Bull trout spawning floodplain is 5,101 ha by position against 16,907 ha by blue line.
    `composition-check.R dunc` fails its 1% bound at +4.67%: 1.1% of the floodplain lies past the
    group polygon (#53). DUNC is not published: `stac_floodplains_bc` refuses an `all_ff04` key
    (#123).

# floodplains 0.1.8 (2026-10-10)

* Whole-FWA floodplain probe on MORR (#110), which gates #104.
  * **What it measures.** `floodplain_probe-run.sh <area>` delineates one scenario from five
    networks (all of `fresh.streams`, order ≥ 2, order ≥ 3, bcfp's bypass predicate, the species
    network) on one common DEM. It times the DEM fetch, the VCA and each attribution, each in its
    own process for a peak RSS. An anchor proves the probe reproduces step 1's network and a
    same-day `fp_floodplain()` replay. Steps 1–3 and every published output are untouched.
  * **What it found on MORR `co_ff04`.** The VCA takes under 3 min at every floor; attribution
    is the cost (87 min for all streams, 33 at order ≥ 2), and about 13 min of each scenario is
    flooded's `complete = TRUE` fallback. Order ≥ 1 is ruled out on cost. A whole-network
    floodplain is not a superset of the species cut (flooded#68). The verdict between order ≥ 2
    and order ≥ 3 waits on a visual read: `research/whole_fwa_floodplain.md`.
  * **The published floodplains do not reproduce on today's toolchain** (#117, flooded#67). GDAL
    3.13 picks a reprojected DEM grid ~1 m off the one GDAL 3.8.5 picked, isolated on one
    machine, and MORR `co_ff04` comes out 0.42% smaller.

# floodplains 0.1.7 (2026-10-09)

* Esri Wayback imagery at the **capture** nearest each endpoint, per NECR accuracy review point (#115).
  * **Capture, not release.** `wayback_index-capture.R` reads all 197 releases' capture metadata
    and writes `reference/<area>/wayback.csv`. 243 of 480 NECR points gain sharp imagery within
    ±1 year of 2017, where the nearest before was the 2012 air photo.
  * **Local chips QGIS can draw.** `wayback_build-chips.R` fetches them with GDAL (QGIS cannot
    follow Wayback's relative redirects, qgis/QGIS#54161) into `dated/wayback_<year>/<review_id>.tif`.
    Each chip is clipped to its point's Voronoi cell with nodata: a VRT ignores source masks when it
    composites. The build checks the pixel under every point is that point's own chip.
  * **In the review project**, `<year> Esri capture (nearest per point)` themes, and each cell is
    labelled with its capture date. `labels.gpkg` is untouched.
  * **New label value `esri_dated`**, apart from the undated `esri` basemap that labelling-key rule
    5 caps at low.
  * **Fix:** `fp_acc_link_tree` never relinked a rewritten file for reviewer B. Base `file.info()`
    has no inode column, so the test was `identical(NULL, NULL)`.

# floodplains 0.1.6 (2026-10-06)

* Blind, randomised, cell-level NECR accuracy review (#111), ready for rtj#367 to put on Mergin.
  * **Blind working copy.** The labels layer carries an opaque, shuffled `review_id` and no design
    column, because `point_id` encodes the stratum. `reference/<area>/review_key.csv` maps it back.
  * **Pre-registered labelling key** in `research/landcover_accuracy.md`, quoting IO's class
    definitions. Hay is Crops and grazed pasture is Rangeland, as IO's legend says.
  * **The 10 m cell is drawn** for every point.
  * **The map's answer stays hidden.** IO's change patches and the FWA wetlands appear only in the
    `9 After labelling` theme.
  * **Themes read in working order** in the drop-down.
  * **A second labeller works in a separate 48-point project.** Agreement is reported, never
    estimated from.
  * **The export decides labeller A or B** from what the working copy holds.

# floodplains 0.1.5 (2026-10-02)

* Agricultural Land Reserve and floodplain composition (#108; NECR, BULK, neexdzii).
  `scripts/fwapg/alr_load.sh` loads the ALR as a frozen, dated snapshot. Change patches gain
  `in_alr` + `alr_poly_id` as a context overlay, so they are never a cause. A new non-spatial table,
  `composition_<scenario>_<from>_<to>`, counts every classified cell by class pair, by status
  (stable/change/sieved/nodata), and by whether its centre lies in the floodplain, an FWA wetland
  and the ALR. Every "share of the floodplain" or "share of its change" is now a sum over that table
  (`fp_composition_summary()`), never off the any-touch flags, which overstate change in the ALR by
  about 5%.
  * **How it is built.** Step 3 builds the table, and `composition_build.R` backfills from rasters
    on disk. Both refuse before writing unless the rasters, the span and the floodplain match the
    landcover record.
  * **Provenance.** The table is recorded as a `composition` block inside `landcover[<scenario>]`
    in `provenance.json`.
  * **Region runs** now resume on the primary scenario's own summary.
  * **Publishing.** The table publishes with the next stac rebuild (stac_floodplains_bc#70).

# floodplains 0.1.4 (2026-10-02)

* Channel-migration probe (#106; NECR, BULK). `scripts/floodplain_lcc/channel_probe-migration.R <area>`
  applies a rule pre-registered in `research/channel_migration.md` to IO's Water-involving change. It
  asks whether long, thin, channel-adjacent erosion/deposition strips separate from flicker and
  misregistration. On NECR and BULK rule v2 does not separate: the strips are less persistent than
  other wide water change, and they do not face each other across the channel. That is a result
  about the rule on two unlabelled groups, not about IO. #106 stays open for labelled review, and no
  `in_channel_change` tag is built. Nothing published changes.

# floodplains 0.1.3 (2026-10-02)

* Prior fires and dated reference imagery (#103; NECR). A new `lookback:` list in
  `config/disturbance.yml` tags transition patches with fires from the 15 years before the change
  window (`in_fire_prior`), reported beside the unattributed share and never counted as a cause:
  in NECR it overlaps 27% of unattributed tree loss. The NECR accuracy sample is redrawn with a
  "change in prior fire" stratum (480 points, before any label), and the review project gains a
  2021 orthophoto (204 points, 0.15 m) and 2012 air photos (all 480 points), each with a map theme.

# floodplains 0.1.2 (2026-10-01)

* Measure the composite windows and build the review chips for IO LULC accuracy (#93; NECR).
  `window_count-clear.R` counts clear days with drift >= 0.20.0, and a rule pre-registered before
  any count ran writes `reference/necr/windows.csv`. The result is August, with 2017 widened to
  August–September, so HLS is not needed. The 1,800 dated Sentinel-2 chips are in the review
  project. Labelling, the estimates and the verdict remain.

# floodplains 0.1.1 (2026-09-29)

* Measure IO LULC's accuracy inside the floodplains (#93, phases 1-6; NECR first).
  `scripts/landcover_accuracy/` and `reference/<area>/` do the measuring, and
  `research/landcover_accuracy.md` holds the results. The criteria for classifying land cover
  ourselves were pre-registered before any result.
  - Drought years were measured from unregulated gauges. 2023 is the low-flow year, and it is the
    IO change endpoint.
  - IO misses 25.5% of qualifying clearcut area.
  - A 450-point stratified reference sample and an rfp QGIS review project are ready for
    labelling.
  - The review scripts carry labels to `labels.csv`, and the estimate turns them into
    error-adjusted areas and the verdict.
  - The composite windows wait on drift#92.
  - `research/README.md` now keeps one topic file per question, revised in place (#86).

# floodplains 0.1.0 (2026-09-29)

First versioned release. The driver as it stands: per-area config (`config/<area>/`) and region
runs (`config/regions/`) drive three steps -- network extraction (`link`), VCA floodplain delineation
(`flooded`), and STAC land cover classification and change (`drift`) -- with per-area run provenance
(`provenance.json`) and fire and harvest attribution of change patches. Earlier work is recorded in
`planning/archive/`, one directory per issue.

* Transition patches carry undated context overlays alongside the disturbance causes: `in_wetland` +
  `waterbody_poly_id` from FWA wetlands, via a new `context:` list in `config/disturbance.yml`.
  Context locates change and never counts toward attribution. `fire_tag.R` now re-tags the published
  layer in place and refuses to move a cause column (#95).
