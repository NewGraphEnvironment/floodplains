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
