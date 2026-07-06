# Progress — Generalize pipeline to AOI-driven, prove Neexdzii parity, run MORR (#1)

## Session 2026-07-06

- Plan-mode exploration (3 Explore agents: pipeline scripts 01–05, config/structure, rwk + link
  reference) — phases approved by user.
- Decisions locked: explicit `fp_*(cfg)` step functions (not ambient/sourced context);
  `index.Rmd` QGIS auto-copy removed from the pipeline entirely; scope = steps 1–3 only (04/05
  deferred).
- Created branch `1-generalize-pipeline-to-aoi-driven-prove` off main.
- Scaffolded PWF baseline from issue #1 with approved phases.
- **Phase 1 complete.** Refactored 01/02/03 into `fp_network(cfg)` / `fp_floodplain(cfg, scenarios)`
  / `fp_lulc(cfg, scenario)`; added `fp_read_config()` + working dispatch in `run_area.R`; added
  `primary_scenario: co_ff04` to both area.yml; wrote `scripts/run_areas.sh` (soft-fail loop);
  rewrote `floodplain_lcc/README.md`; removed the broken `index.Rmd` QGIS auto-copy from all three.
  - Verified: all R/shell files parse; `fp_read_config` builds correct cfg for both areas (Neexdzii
    subset populated, MORR subset NULL); the three step files source and define `fp_*` with correct
    signatures. Full pipeline run is Phase 2 (needs fwapg + internet).
- Next: Phase 2 — run `Rscript scripts/run_area.R neexdzii` and check parity (678.2 km / 171.0 km²
  / 943.13 ha).
