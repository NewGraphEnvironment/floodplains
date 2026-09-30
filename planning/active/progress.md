# Progress — Measure IO LULC accuracy (#93)

## Session 2026-09-29

- Plan-mode exploration; phases approved by user. Gate decisions: PR is "Part of #93" (#93 stays
  open for labelling); pilot 14 strata × 30; labels in gpkg form + committed `labels.csv`
- Created branch `93-measure-io-lulc-accuracy` off main
- Scaffolded PWF baseline from issue #93 with approved phases
- Next: start Phase 1
- Phase 1 committed (9b05604): criteria pre-registered, research/README naming (#86)
- Phase 2: drift upgraded 0.17.1 → 0.19.0. `aggregation="count"` returns reflectance → filed
  drift#92; guard landed (f2e3dd2). Window measurement held
- Phase 3: HYDAT 2024-04-16 → 2026-07-17 (machine change, as planned). 2023 = the low-flow year
  (3/4 free-flowing gauges in the lowest quintile); 08JC001 regulated, ranks 2023 at 0.45
- Plan review landed (review-plan.md): footprint population + sieved stratum, cell-level wetland,
  map_class naming, operational defs → Phase 1b committed (0e2164e) before any result
- Phase 4: harvest omission IO 0.255 / published 0.411 over 92 ha → criterion 4 does NOT hold;
  fire 0.314. Inside FWA wetlands IO says FV 0.3–0.9%, Trees/Rangeland flicker 7 pts/yr
