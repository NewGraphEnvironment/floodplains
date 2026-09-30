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
