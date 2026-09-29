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
