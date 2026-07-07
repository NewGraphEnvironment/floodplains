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
- **Phase 2 complete — PARITY GATE PASSED.** Ran `Rscript scripts/run_area.R neexdzii` end-to-end
  against local `fwapg` (`fresh-db` container, db `fwapg`) + `link` 0.44.1. Reproduced all three
  known-good numbers within ~0.004% VCA noise:
  - network **678.2 km** (1936 segments) → −0.003%
  - floodplain co_ff04 **171.0 km²** → +0.004%
  - tree loss **943.13 ha** (2263 patches) → +0.000%
  - Segment count (1936) matches the archived rwk figure. The generalization is faithful.
  - Env for the run: `PGHOST=localhost PGPORT=5432 PGDATABASE=fwapg PGUSER=postgres PGPASSWORD=postgres`.
    Packages: link 0.44.1 / flooded 0.3.2 / drift 0.2.2 / fresh 0.32.0.
- **Phase 3 in progress — MORR.**
  - Resolved: whole WSG (issue default; `subset: null`). MORR step 1 (network, whole-WSG NULL-subset
    branch) ran clean → **1295.6 km**, 4877 coho order-3+ segments (orders 3-8), 412 waterbodies.
    This exercised the `subset: null` code path that Neexdzii parity did not.
  - Break points: user chose **single outlet basin** (headline numbers now; interior sub-basins
    deferred). Derived the MORR mainstem outlet from the network (Morice River blk 360885316,
    lon/lat -126.746442/54.410770) and verified it delineates 4382.2 km² ≈ whole MORR group
    (4379.1 km², 100.1%) capturing 4877/4877 segments. Wrote `config/morr/break_points.csv` (1 row).
  - Steps 2-3 complete (exit 0). MORR floodplain EXTENT (valid, steps 1-2): co_ff04 **411.1 km²**
    (co_ff02 379.0, co_ff06 432.4), network 1295.6 km.
  - ⚠️ **MORR LULC/tree-loss is INVALID** — `drift::dft_stac_fetch` classified only ~1,199 ha ≈ 3%
    of the 41,113 ha floodplain (one 5.9×10.2 km tile near the confluence; floodplain spans
    84×87 km). The 22 ha "tree loss" reflects only that pocket, not the floodplain. See findings.md.
    Verified DEM/step-2 is NOT the cause: MRDEM-30 fully covers the floodplain (443,975 valley
    cells = 41,113 ha across the full 86×87 km, 2272 polygon parts following the whole network).
    Neexdzii LULC was 104% covered → parity unaffected.
- **Root cause found + fixed (workaround).** MORR LULC bug was NOT mosaicking — it was a
  `drift::dft_stac_fetch` **cache-key collision** (caches per source+year, no AOI; MORR silently got
  Neexdzii's cached rasters masked to MORR). Proven via cache extent = Neexdzii bbox. Filed
  **NewGraphEnvironment/drift#25** (cache key must include AOI; also `force=TRUE` can't overwrite).
- **Resumed:** `dft_cache_clear(source="io-lulc")` + re-ran `run_area.R morr 3`. Coverage restored
  3% → full (42,097 ha/yr classified). **Corrected MORR:** tree loss **433.8 ha**, tree gain
  684.5 ha (net +250.7 ha greening), ag expansion 411.2 ha. Real Morice floodplain dynamics, not the
  Bulkley agricultural signature the poisoned cache produced. No separate large-AOI problem.
- **Phase 3 complete (valid).**
- **Phase 4 complete + synced.** Copied the 4 MORR gpkgs into `…/restoration_wedzin_kwa/morr/`, then
  (at user's direction, overriding the issue's "local only, do NOT sync yet") pushed to Mergin:
  previewed `rfp_mergin_status` (only the 4 morr/ files pending, no stray WIP), ran `rfp_mergin_sync`
  → **v95** on `newgraph/restoration_wedzin_kwa`; status clean after. Needed `uv sync` to build the
  rfp mergin CLI venv (installed pkg location) first.
- **All 4 phases done.** Issue #1 core scope delivered: generalized config-driven pipeline, proven
  Neexdzii parity, MORR run (extent + valid LULC). Ready for `/planning-archive` + PR.
  Open follow-ups: drift#25 (cache fix), MORR interior sub-basins, MORR own project, S3/04-05 (deferred).

## Session 2026-07-06 (cont.) — UFRA (Upper Fraser), chinook, burn to sern_fraser_2024

- Generalized the pipeline to **species**: `fp_network` now reads `access_<cfg$species>` instead of
  hardcoded `access_co` (guards the code as a short lowercase token before SQL interpolation). For
  `species: co` the SQL is byte-identical → Neexdzii/MORR coho results unaffected.
- UFRA has **no coho** (access_co unmodelled in the Upper Fraser) but a full **chinook** model
  (access_ch: 96,300 streams). Per user decision, ran UFRA as **chinook** (`config/ufra/`: species
  ch, ch_ff* scenarios, primary ch_ff04, whole WSG single-outlet basin). Outlet break point: exact
  Fraser tip failed frs_watershed_split (boundary edge case) → nudged 1 segment up, delineates
  6761 km² = 100% of group.
- **UFRA step 3 OOM'd** at `drift::dft_transition_vectors` (full 102.6M-cell grid × 56 classes;
  UFRA floodplain spans a 119 km bbox so trim can't shrink it). Fixed with a **column-tiled**
  wrapper `fp_transition_vectors_tiled` in `fp_lulc` (memory-bounded; single-tile = identical output
  for small areas). Filed **drift#27** for the proper in-package fix.
- **UFRA chinook results** (whole WSG): network 807.7 km; floodplain ch_ff04 **188.2 km²** (ch_ff02
  167.5, ch_ff06 202.8); tree loss **544.5 ha**, gain 718.9 ha (net +174.4), ag 490.0 ha; LULC
  coverage 104% (cache cleared first — drift#25 guard).
- **Burned to sern**: `mergin download`ed the 1.6 GB `newgraph/sern_fraser_2024` (not cloned
  locally), copied the 4 UFRA gpkgs to `sern_fraser_2024/ufra/`, previewed status (only those 4),
  `rfp_mergin_sync` → **v95**.
