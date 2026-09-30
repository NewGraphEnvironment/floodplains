# research

Durable synthesis memos for method-evaluation experiments — the SRED-facing "what did we
learn and what did we decide" layer that outlives any single issue's planning archive.

- One topic file per question, **revised in place** — git is the version record
  (`git log --follow research/<topic>.md`).
- Naming: `<topic>.md`, revised in place, from 2026-09-06.
  Files dated before that carry a `yyyymmdd_` prefix; they are not being renamed.
- The file carries the **question, method, results, and decision** in one place, a provenance
  line under the H1 (verified date, issues, what produced it), and cites the committed evidence
  logs (`scripts/<module>/logs/`) that hold the raw measurements.
- The per-issue **PWF** (`planning/`) holds the iteration/uncertainty narrative; this dir
  holds the distilled verdict so it stays browsable after the PWF is archived.

Three homes, each one job: **PWF = the story, `scripts/<module>/logs/` = the measurements,
`research/` = the durable verdict.**

## Index

| file | covers |
|---|---|
| [`landcover_accuracy.md`](landcover_accuracy.md) | How right IO LULC is inside our floodplains: pre-registered criteria for classifying ourselves, measured composite windows and drought years, free reference from fire/harvest/FWA wetlands, and the stratified reference sample (#93) |
| [`20260711_lulc_tile-fetch-benchmark.md`](20260711_lulc_tile-fetch-benchmark.md) | Tiled STAC fetch (`tile_size`) benchmarked and rejected: slower at every tile size on every AOI (#8) |
