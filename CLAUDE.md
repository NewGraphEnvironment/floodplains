# floodplains

Reusable floodplain delineation + land cover change detection across BC watershed groups.
Centralizes the workflow first built in `restoration_wedzin_kwa_2024` (Neexdzii Kwa) so it runs
per-area from one codebase. See `README.md` for the full design.

## Core principle

**Method in packages, driver in this repo.** The modelling lives in `link` (network),
`flooded` (VCA floodplain), `drift` (STAC LULC + transition). This repo is a thin, config-driven
driver + provenance layer. Do NOT re-implement package logic here — extend the package.

## Layout

- `scripts/floodplain_lcc/01-05` — the pipeline (copied verbatim from rwk; being generalized to AOI-driven)
- `scripts/run_area.R` — top-level runner: `Rscript scripts/run_area.R <area> [steps]`
- `config/<area>/` — per-area config: `area.yml` + `flood_scenarios.csv` + `break_points.csv`
- `data/<area>/` — outputs (gitignored)

## Areas

- `neexdzii` — **parity fixture**. The generalized pipeline must reproduce the known-good
  Neexdzii numbers (coho-3 network 678.2 km, floodplain co_ff04 171.0 km², floodplain tree loss
  943 ha) before any new area is trusted.
- `morr` — Morice watershed group, first new area.

## Prerequisites (when running)

Local `fwapg` (libpq env vars); `link` ≥ 0.44.0, `flooded`, `drift`, `fresh`; internet for the
national MRDEM-30 (`flooded::fl_dem_aoi()`) and Microsoft Planetary Computer STAC.

## Conventions

Run `/claude-md-init` to sync New Graph soul conventions below the marker.

<!-- BEGIN SOUL CONVENTIONS — DO NOT EDIT BELOW THIS LINE -->
