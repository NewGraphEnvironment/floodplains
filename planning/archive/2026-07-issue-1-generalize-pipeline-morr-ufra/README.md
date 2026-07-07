## Outcome

Generalized the floodplain + LULC pipeline (`scripts/floodplain_lcc/01-03`) from the verbatim
Neexdzii originals into explicit config-driven `fp_network(cfg)` / `fp_floodplain(cfg)` /
`fp_lulc(cfg)` step functions, with a working `run_area.R` (one `cfg` from `config/<area>/`) and a
`run_areas.sh` multi-area loop. Removed the dangling `index.Rmd` QGIS auto-copy. Proved **Neexdzii
parity** exactly (coho network 678.2 km, floodplain co_ff04 171.0 km², tree loss 943.13 ha, all
within ~0.004% VCA noise). Ran **MORR** (Morice, coho, whole WSG, single-outlet basin) → floodplain
411.1 km², tree loss 433.8 ha (net +250.7 ha); burned to `restoration_wedzin_kwa` Mergin v95. Then
extended to **UFRA** (Upper Fraser): generalized the pipeline to **species** (`fp_network` reads
`access_<cfg$species>`; byte-identical for coho) because UFRA has no coho, only chinook — ran it as
chinook → floodplain ch_ff04 188.2 km², tree loss 544.5 ha; burned to `sern_fraser_2024` Mergin v95.

Two real bugs found in `drift` and filed: **#25** (`dft_stac_fetch` cache key omits the AOI → a
second area silently gets the first area's cached rasters — caught because MORR tree loss came back
implausibly low; workaround: `dft_cache_clear(source=...)` between areas) and **#27**
(`dft_transition_vectors` processes the full raster grid per class → OOM on UFRA's 102.6M-cell /
119 km-wide floodplain; workaround: `fp_transition_vectors_tiled` column-tiling wrapper in `fp_lulc`).
Both are "scales on small AOIs, breaks on large ones" issues — a recurring theme worth watching when
this pipeline moves to bigger watershed groups.

Closed by: commits 0ebe0e4 (generalize) · dc2f508 (Neexdzii parity) · 0270c4b/7ca2855/fe85ff6/98f586d
(MORR + cache diagnosis) · e0a3d41 (UFRA + species + tiling). Branch:
1-generalize-pipeline-to-aoi-driven-prove.
