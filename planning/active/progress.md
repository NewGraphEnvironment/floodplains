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
- Phase 5: strata builder + toy check (18 cases, 5 must-fail arms; a mutant demoting wetland
  precedence fails 2 checks). NECR pilot: 450 points / 15 strata, redraw byte-identical
- /code-check round 1: 2 bugs + 1 fragile, all fixed (stable FV → stable wetland, NA not 0 for a
  failed window month, NA-safe sync guard); sample redrawn. Finding → #100: only 48.9% of NECR
  harvest-attributed tree loss lies inside a cutblock (fire 94.2%)
- Phase 6 in progress: rfp builds the review project when given real layers (FWA wetlands/rivers/
  lakes); a bare project is refused by rfp's own guard. Form QML + RGB QML written. Chip timing run:
  2017 Jul–Aug has 0–1 scenes under 20% cloud at some points → windows really do need measuring
- /code-check rounds 2–4: R2 found a defect inside the R1 fix (empty month vs failed fetch) →
  status column; R3 named the mechanism (absent/not-evaluable/nominally-same folded into a definite
  value) + 53-row enumeration, 4 defects fixed (point_id is not an identity → design check;
  3-valued criterion 1; causes from design.json; chips before project); R4 re-walked 75 rows,
  0 defects → terminal. 6 review agents total (1 plan + 4 code-check + this is over the ~5 bound)
- Phase 6: project built with rfp (3005 display layers), form verified in the .qgs XML; headless
  QGIS load not achieved (bundled python numpy import) → manual open is the remaining check
