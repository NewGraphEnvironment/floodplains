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
