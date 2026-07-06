# Progress — Generalize pipeline to AOI-driven, prove Neexdzii parity, run MORR (#1)

## Session 2026-07-06

- Plan-mode exploration (3 Explore agents: pipeline scripts 01–05, config/structure, rwk + link
  reference) — phases approved by user.
- Decisions locked: explicit `fp_*(cfg)` step functions (not ambient/sourced context);
  `index.Rmd` QGIS auto-copy removed from the pipeline entirely; scope = steps 1–3 only (04/05
  deferred).
- Created branch `1-generalize-pipeline-to-aoi-driven-prove` off main.
- Scaffolded PWF baseline from issue #1 with approved phases.
- Next: start Phase 1 — `fp_read_config()` + refactor `01_network_extract.R` → `fp_network(cfg)`.
