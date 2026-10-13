# neexdzii parity fixture re-baselined on flooded 0.7.0's pinned DEM grid

**2026-10-13 · issue #117 · flooded#67 (flooded 0.7.0, github@698042e)**

flooded 0.7.0 builds the DEM on a fixed grid (30 m, aligned to multiples of 30) and pins the datum
step. Before it, GDAL picked the grid from source edges that PROJ had transformed, and PROJ 9.8.1
routes NAD83(CSRS) to NAD83 through WGS 84, so the grid moved about 1.3 m with no data change. This
run re-baselines the parity fixture on the pinned grid and checks that it reproduces.

## What was run

Raw run logs are session scratch, not committed. This file is the record.

| leg | command | launched (UTC) |
|---|---|---|
| snapshot | `cp data/neexdzii/provenance.json` (record from 2026-09-02 / 10-02) | before run 1 |
| run 1 | `caffeinate -s Rscript scripts/run_area.R neexdzii` (steps 1,2,3) | 22:10:59 |
| run 2 | `caffeinate -s Rscript scripts/run_area.R neexdzii 2,3` | 22:18:28 |

Each leg was gated on zero in-band errors (`Execution halted` / `^Error`) and on every floodplain,
landcover and composition `run.datetime_utc` falling after the leg's launch time, never on the
wrapper's exit code or the file mtime.

Toolchain recorded in every new entry's `run.toolchain`: terra 1.9.50, sf 1.1.2,
`gdal` 3.8.5 / `proj` 9.5.1 / `geos` 3.13.0 (sf's), `gdal_terra` 3.13.0 / `proj_terra` 9.8.1.

## Result

**New contract:** coho-3 network **673.5 km**, floodplain `co_ff04` **142.0 km²**, floodplain
tree loss **773.4 ha**.

| | 2026-09-01 contract | 2026-10-13 |
|---|---|---|
| network (km, segments) | 673.48, 1,915 | 673.48, 1,915 (content digest identical) |
| `co_ff04` (km²) | 142.823 (153,836 cells at 30.46984 m) | 142.040 (157,822 cells at 30 m) |
| `co_ff02` / `co_ff06` valley cells | 141,504 / 161,555 | 144,228 / 165,698 |
| DEM | 6,533,563 cells, res 30.46984 m | 3,474,262 cells, res 30 m, origin a multiple of 30 |
| transition patches | 2,032 | 2,018 |
| tree loss (ha, `from_class == "Trees"`) | 770.02 | 773.43 (788 patches) |

`co_ff04` moved −0.55% and tree loss +0.44%. That move spans every flooded release from 0.5.0 to
0.7.0, not the grid pin alone, and no run isolated the pin's share. It is recorded as a fresh
contract, not as a delta attributable to one cause.

**Reproduction:** run 2 against run 1, every floodplain (`co_ff02`, `co_ff04`, `co_ff06`) and
landcover (`co_ff04`) entry has an identical `inputs_hash` and `outputs_hash`, including
`dem_content_sha256` (`sha256:192ea21e380f…`), and the composition's `outputs_hash` is identical.
Every run stamp moved. This is one machine and one toolchain. Across GDAL 3.8.5 and 3.13.0,
flooded#67 measured agreement to 0.12 mm per cell, which is not byte identity.

`provenance-check.R neexdzii` and `composition-check.R neexdzii` both pass.

## What moved, field by field (snapshot → run 1)

- **network[co3]:** `outputs` unchanged. `inputs_hash` moved through package stamps only:
  `fresh` 0.33.0 → 0.39.0, and `link.sha` became unresolved (`unresolved_version_mismatch`: the
  checkout's version differs from the installed one). No network content changed, so no data change
  is mixed into the floodplain move.
- **floodplain[\*]:** `dem_content_sha256`, `dem_ncell`, `dem_res_m` and the `flooded` stamp
  (0.5.0 → 0.7.0) in `inputs`; `floodplain_content_sha256` and `valley_cells` in `outputs`.
  Nothing else.
- **landcover[co_ff04]:** the three `classified_content_sha256` digests (the classified rasters
  are masked to the floodplain) and the transition digest and patch count. `item_hash` and every
  drift field unchanged.
