# floodplains

Reusable floodplain delineation + land cover change detection across BC watershed groups.
Centralizes the workflow first built in `restoration_wedzin_kwa_2024` (Neexdzii Kwa) so it runs
per-area from one codebase. See `README.md` for the full design.

## Core principle

**Method in packages, driver in this repo.** The modelling lives in `link` (network),
`flooded` (VCA floodplain), `drift` (STAC LULC + transition). This repo is a thin, config-driven
driver + provenance layer. Do NOT re-implement package logic here — extend the package.

## Layout

- `scripts/floodplain_lcc/01-03` — the generalized pipeline. Each defines one config-driven step
  function taking a single `cfg`: `fp_network(cfg)` (01), `fp_floodplain(cfg)` (02), `fp_lulc(cfg)`
  (03). Zone-stratified LULC + sub-basin prioritization are possible future steps — not yet built.
- `scripts/run_area.R` — top-level runner: `Rscript scripts/run_area.R <area> [steps]`. Builds one
  `cfg` via `fp_read_config(area)` and dispatches the step functions. Steps default `1,2,3`.
- `scripts/run_areas.sh` — thin multi-area loop (per-area soft-fail + timestamped logs).
- `scripts/run_region.R` — batch runner over a region of watershed groups (`config/regions/<region>.yml`):
  a pre-pass resolves one species per WSG (first in the ordered `species` preference modelled at
  `order ≥ min_order`, via province-wide `fresh.streams_vw_bcfp`), generates each group's config,
  runs the pipeline per-WSG (soft-fail + log), and writes a coverage CSV. Resumable — a group whose
  `lulc_summary.rds` exists is skipped (`FORCE=1` redoes). `scripts/floodplain_lcc/fp_region.R` holds
  `fp_wsg_subbasin` (the whole-WSG sub-basin = group polygon).
- `config/<area>/` — per-area config: `area.yml` + `flood_scenarios.csv` (+ optional `break_points.csv`;
  absent ⇒ whole-WSG single sub-basin = group polygon, present ⇒ interior sub-basins).
- `config/regions/<region>.yml` — a region = a named set of WSGs + ordered `species` preference.
  `run_region.R` **reconciles** each group's `area.yml` against the region file — it does not
  regenerate it (#44). The region owns `FP_REGION_OWNED` (`fp_region.R`): `name`,
  `watershed_group`, `species`, `min_order`, `schema`, `primary_scenario`, `network_source`,
  `network_guard`, `attribute_by`. The **area** owns everything else, so `subset`, `tile_size`,
  `targets`, a second species' scenario rows, citations, `break_points.csv` and every **comment**
  all survive a region run. Region-owned keys are stripped and re-applied rather than merged, so a
  region file that drops `network_source` actually clears it downstream — a plain merge would leave
  it stale and the group would keep GRABbing when it was meant to BUILD. `flood_scenarios.csv` is
  created when absent and **appended** to when the resolved species has no rows; existing rows are
  never rewritten. Still, a group whose species differs from the region's preference needs its
  **own** region file with the same `region:` label (e.g. `skeena_ch.yml` for KISP chinook) —
  listing it in an existing one would point the region-owned keys at the wrong species. The publish
  layer derives its WSG→region roster from these files.
  **`DRY=1` writes nothing at all** — it prints the per-group reconciliation it would perform and
  exits. It used to write configs before the dry gate, so the preview was as destructive as a real
  run; that is what #44 was. `scripts/floodplain_lcc/region_config-check.R` asserts all of the
  above with no database (`fp_region_plan` is pure, which is why it can be checked at all).
- **Per-watercourse attribution (#40):** optional `attribute_by:` in `area.yml` (or the region
  file — carried through like `network_source`) naming a column of the stream network. Step 2 calls
  `flooded::fl_valley_attribute()` (needs flooded ≥ 0.4.0) on the **primary scenario only**, passing
  the scenario row's `max_width`/`cost_threshold` so thresholds match the delineation, and writes
  `<scenario_id>_by_<column>` with the item key plus the grouping column. Absent ⇒ unchanged.
  The delineation is **not** recomputed per group — re-running the VCA on a subset moves the
  boundary (the flood surface interpolates from every seed), so "this river's floodplain" must be
  an attribution of a fixed delineation. **Rows overlap by design** (MORR: 43.6% of the floodplain
  is claimed by more than one watercourse). Measured on MORR at 16.5M cells: attribution costs
  12–14× the delineation, but **85% of that is k-independent** (0.39 s per extra group), so
  `blue_line_key` (k=340, no NA group) is affordable where `gnis_name` (k=33) pools 54% of the area
  into one unnamed group.
- **Item key on every published layer (#30):** `wsg`, `species`, `scenario` — mirroring the STAC item
  id. The same key is a STAC *property* (select items) and a gpkg *column* (separate rows after
  merge), so many areas fetch-and-append into one gpkg and stay separable by attribute; adding an
  area/species never touches a QGIS project. Written at generation time in 02 (scenario delineation
  layers) and 03 (classified + transition). Layer names stay producer-keyed — generic names inside a
  per-area gpkg would collide across species and undo #23's per-layer replace; flattening to generic
  layers is a **downstream merge-time** concern. `scripts/floodplain_lcc/gpkg_backfill-wsg.R <area>`
  migrates pre-existing outputs (idempotent **by value**, so a re-run repairs a wrong value).
- `scripts/floodplain_lcc/fp_disturbance.R` — `fp_disturbance_tag`: config-driven, layer-agnostic
  disturbance attribution (#19). Step 3 tags each transition patch with the overlay layers in the
  shared `config/disturbance.yml` (province-wide DataBC layers loaded into fwapg via `bc2pg`):
  `in_<name>` + carried attrs from the dominant overlapping feature, windowed to `cfg$change_interval`
  (default 2017–2023). Additive — a patch may match several sources (salvage = fire AND harvest); the
  residual (matches none) is the classification-noise floor. Opt-in by file presence (no yml ⇒ step 3
  unchanged, no DB conn). `fire_tag.R <area> [scenario]` re-tags every transition layer of an area
  without the STAC fetch and writes back onto the **main** layer (it used to write a `_disturbance`
  sibling -- #55's orphan class, recreated on every run). It keeps the published geometry, because
  the tagger's `st_make_valid()` rewrites all of it (NECR: 0 of 5,692 invalid, all 5,692 rewritten),
  and it **refuses to write if any cause column would change** (`FORCE=1` overrides), since the
  layer it replaces is published. **Read transition layers with `promote_to_multi = FALSE`:** step 3
  writes a *mix* of POLYGON and MULTIPOLYGON declared `GEOMETRY`, and `st_read()`'s default promotes
  every POLYGON. The first live re-tag did exactly that to necr and bulk (3,947 + 5,024 geometries,
  layer re-declared MULTIPOLYGON) while the check passed, because it read both sides promoted; both
  were restored from byte copies. `disturbance-check.R`'s comparison now reads the schema from the
  gpkg's own tables (`PRAGMA table_info`, `gpkg_geometry_columns`) so no reader default can hide a
  change. **Fire + harvest wired; pest deferred.** Harvest resolves ~30–36% of floodplain tree
  loss previously in the "noise" bucket. **Measured 2026-09-04 on BULK's current output** (the
  2026-09-02 re-run, 1,565.1 ha of tree loss): fire **4.2%** / harvest **30.3%** / not yet
  attributed **65.5%** by area. The 5 / 36 / 62 stated here before was pre-re-run and is dead, not
  superseded. It is now computed at figure-build time into `fig/attribution.png` and stated in no
  prose, which is the only version of this that stays true (#77). The transition
  layer now carries N disturbance attrs → the STAC schema must too (stac_floodplains_bc#6).
  **Context overlays (#95) are tagged by the same code and are NOT causes.** A second list,
  `context:`, holds undated layers that say where a patch is, not why it changed -- today
  `in_wetland` + `waterbody_poly_id` from `fwa_wetlands_poly`. `cfg$disturbance` stays the causes
  and `cfg$context_overlays` the context (never `disturbance_context`: `$` partial-matches, so with
  no sources `cfg$disturbance` would have returned the wetlands and step 3 would have logged them
  as causes -- caught in review before any run).
  `fp_disturbance_validate()` enforces the split at config load: a source must have `year_col`, a
  context entry must not, entry keys are whitelisted (`filtr:` would run a source unfiltered), and
  no carry may land on a patch column -- case-folded, since Postgres and GeoPackage fold case and
  `fwa_wetlands_poly.area_ha` would have overwritten the patch's area. The report refuses a context
  entry and a missing `in_` column (which read as a 0 ha residual). Carried attributes join back
  by **row**, never `patch_id`, which repeats across sub-basins. `disturbance-check.R` asserts all
  of it offline, each rule with a must-fail arm, plus a live section with a snapshot mode it owns.
  **Forward-only, and often "not until forced":** necr and bulk are re-tagged. Any other area gains
  `in_wetland` on its next step 3 run, or from `fire_tag.R` **only where its cause columns would
  not move** -- `mcgr` and `pine` carry no cause columns at all, so `fire_tag.R` refuses them, as it
  refuses any area whose fire or cutblock table has changed since it was tagged; those need step 3
  or `FORCE=1`. `run_region.R` also skips a group whose `lulc_summary.rds` exists. `in_wetland` sits on **changed**
  patches only (`changes_only = TRUE`), so "stable land inside a wetland" needs its own overlay.
- `data/<area>/` — outputs (gitignored)
- `README.Rmd` → `README.md` + `index.html` (Pages), with `scripts/readme_functions.R` (readers +
  gated figure builders), `scripts/readme_determinism-check.sh` and
  `scripts/readme_content-check.py`. See the two README subsections under `## Working conventions`.
- **Two orthogonal explosions, and the bridge between them (#54):** the floodplain is exploded two
  incompatible ways. `<scenario>_by_<attribute_by>` is one row per watercourse and rows **overlap**
  by design (#40); `transition_<scenario>_<span>` is one row per change patch and rows are
  **disjoint**. Neither answers "how much tree loss belongs to *this* river" alone, and the naive
  spatial join overcounts by up to 94% (MORR attribution rows sum to 795.8 km² over a 411.1 km²
  floodplain). Step 3 writes a non-spatial `patch_watercourse_<scenario>_<span>` table beside the
  patches: one row per (patch, watercourse) pair. **Two fractions, and only one is additive** —
  `overlap_frac` ("what share of this patch does this watercourse cover?", sums to ~2.3 per patch
  because the rows overlap) and `apportion_weight` ("what share is credited to it?", sums to exactly
  1). Weighting by `overlap_frac` overstated MORR tree loss by 83%; `apportion_weight` reconciles to
  431.82 vs 431.87 ha. Three consumer semantics: **inclusive** (every patch touching a river),
  **apportioned** (weight, additive), **exclusive** (`overlap_frac == 1`). Coverage is checked as a
  **union** (`max(overlap_frac)`, 0.966 on MORR) — summing overlap would report ~2.3× and mean
  nothing. `bridge-check.R` asserts it. Absent `attribute_by` ⇒ no bridge **and any existing
  `patch_watercourse_*` layer is removed** — it would otherwise describe a relation the current
  config does not produce (#55's orphan class). That matters because `attribute_by` is
  region-owned: dropping the line from a region file clears it in every group, and the next step-3
  run deletes every group's bridge. Not "step 3 unchanged", which is what this said before #63.
  **The bridge writer had never run on a subset area.** #54's per-tenant-key fix hoisted the patch
  key into a standalone vector *before* the zero-area filter and reused it after, so a single
  sliver pair — 9.9e-5 m², which `round(ov_ha, 4)` sends to `0.0000` ha — left the key one element
  longer than the frame and aborted step 3. It landed one minute after the last neexdzii run, and
  neexdzii is the only multi-sub-basin area, so nothing exercised it until #63. A key that lives
  outside the frame it indexes goes stale the instant that frame is filtered.
- **Legacy layers do not clean themselves up (#55).** #23 made gpkg writes per-layer so a second
  species cannot wipe the first — which means a layer whose *name* goes obsolete is never removed.
  Disturbance attribution used to write `_disturbance` / `_fire` siblings and now writes onto the
  main transition layer, stranding 6 orphans across morr and bulk with matching row counts (BULK's
  were 9,045 each, same as the current layer, which is why they went unnoticed).
  `gpkg_prune-legacy.R <area>` sweeps them: idempotent, `DRY=1` reports, and it removes **only** an
  explicit name pattern — a script that deletes layers it does not recognise is worse than the
  orphans it cleans.
- **Run provenance per area (#33):** every run writes `data/<area>/provenance.json` — what produced
  the outputs, for `stac_floodplains_bc` to publish as STAC item properties (`stac#17`). Three
  sections written by the step that knows the facts, because steps run independently
  (`run_area.R morr 3` is normal) and key differently: `network[<sp><order>]`,
  `floodplain[<scenario>]`, `landcover[<scenario>]`. Each splits into **`inputs`** (a function of
  the inputs, byte-stable across reruns, summarised by `inputs_hash`) and **`run`** (the run event,
  free to vary) — #52's rule applied one level earlier, and the only reason the acceptance
  criterion is checkable at all, since a whole-file comparison could never pass with a timestamp
  in it. `scripts/floodplain_lcc/fp_provenance.R` is the writer (`fp_prov_set` merges one
  section per step, atomically); `provenance-check.R` enforces the split with no database, and
  every one of its 39
  assertions is exercised against input built to break it — including §5b, which constructs the
  DATABASE value shapes offline (`pq__text`, an empty pg array, a quoted comma, timezone
  stability), because no hand-built fixture contains a driver value and that is how a `text[]`
  column reached `main` able to abort step 1 on its first real run.
  **The network section records link's LOG ROW, read wholesale — it does not re-derive anything.**
  link's `config_hash` is a hash over 17 files plus the config name and species list, so a
  self-computed SHA of `config.yaml` would match nothing in `fresh.log` and the two records could
  never be joined. `lnk_log_read()` is a `SELECT *`, so a column the DATABASE has arrives whether
  or not the installed link names it — which is why link#264 is off this issue's critical path,
  and why the row is never destructured into named fields.
  **The landcover fingerprint is a digest of the classified rasters, NOT the STAC item ids.**
  Both #33 and stac#17 originally named drift's `stac_cache_key()`, which hashes the AOI and the
  request parameters and nothing about the response — so an upstream reprocess leaves it
  unchanged, the exact drift the issue exists to catch. Item ids fail the same test and it is not
  obvious: measured live, an io-lulc id is `<tile>-<year>`, the blob path is fixed, and there is
  **no `created` and no `updated` property**, so an in-place re-derivation is byte-identical in
  every id and href. `classified_<yr>.tif` is the landcover as it actually entered the model
  (one changed cell moves the hash), so it measures the output rather than restating the request —
  and it closes the cache-hit hole for free, where the recorded items describe today's query while
  the raster came from a cache written weeks ago. The ids stay, labelled an identity.
  **`nge:landcover_key` should be the raster digest, and IS NOT — it publishes `item_hash` (#64).**
  `stac_floodplains_bc/scripts/fp_provenance.R` maps `landcover_key` to `inputs$item_hash`, a hash
  over the resolved STAC **item ids** — the one field established above as an identity that cannot
  fail when the upstream re-derives in place. The sentence "should be the raster digest" has never
  been true of what ships. Switching it is the publish layer's change, not this repo's; the coupling
  stays one-way.
  **The digest itself was a CONTAINER hash until #64, and is now a CONTENT hash.**
  `fp_raster_content_sha256()` digests cell values plus geometry in fixed 512-row blocks —
  **`block_rows` is part of the contract**, since the digest is over per-block hashes. It replaced
  `digest(file = )`, whose byte-determinism claim holds **within one toolchain and fails across
  two**: measured 2026-09-02 on two machines running the identical commit against the same database,
  28,291,615 cells per year, **zero differing**, identical extent/CRS/resolution/LZW/block
  size/palette — and a different digest, by exactly +10,028 bytes every year. That was TIFF tag
  **42112 (`GDAL_METADATA`)**, 382 bytes under terra 1.9.34 and 5,396 under 1.9.11, the older terra
  carrying the gdalcubes NetCDF attributes into the header. Same GDAL 3.8.5 on both.
  **The tag was the symptom; the cause defeats a naive content hash too.** `terra::readValues()`
  does not promise a storage type, and the trigger is **the PAM `.aux.xml` sidecar**, not the terra
  version — measured on ONE terra (1.9.34) reading the SAME file, changing nothing else:

  ```
  GDAL_PAM_ENABLED unset -> storage.mode "double",  NaN 324891, NA 324891
  GDAL_PAM_ENABLED=NO    -> storage.mode "integer", NaN 0,      NA 324891
  ```

  GDAL writes that sidecar as a side effect of anyone opening the file, so the storage type of a
  raster's values depends on who has looked at it. The two sides of the #63 comparison differed in
  exactly that way — one had a sidecar, the copied one did not — so **the earlier attribution to
  terra 1.9.34 vs 1.9.11 was never isolated and should not be repeated.**
  `v[is.na(v)] <- NA_real_` is the line that collapses `NaN` and `NA_real_`; `as.double()` beside it
  is defensive, and honestly subsumed — assigning a double promotes the vector whatever the index
  selects. **The gap is invisible to every value comparison** — `all.equal()` is TRUE,
  `sum(a != b, na.rm = TRUE)` is 0, NA counts match. Only `identical()` separates them.
  `provenance-check.R` §5c pins container-invariance with two writes under different `metags()`, and
  **§5d pins the normalization itself in pure R** — because §5c reads both fixtures with the same
  terra in one process, so it passes with both lines deleted.
  **`terra`, `sf` and GDAL are now recorded — in `run`, not `inputs`.** They were absent entirely,
  which is why the divergence was undiagnosable from the record. They stay out of `inputs` on
  purpose: a terra version legitimately differs between two machines that agree on every cell, so
  hashing it would reintroduce the churn #64 removes, one field over.
  Two things that cannot be recorded, and are recorded as absent rather than guessed: the **DEM
  URL** (`fl_dem_aoi()` builds it in its body, and `terra::sources()` on its cropped-and-projected
  return is `""` in memory or a *random per-process temp path* when terra spills — a
  plausible-looking string that would differ every run) and a **package git SHA** where the
  checkout's version does not match the installed one (the link checkout is 0.49.0, installed
  0.47.3, so its HEAD describes code that did not run — a confident wrong SHA is worse than NA).
  `sha_source` names which tier answered so an NA is diagnosable.
  **Forward-only** — an area carries a block once re-run; `run_region.R` treats a missing
  `provenance.json` as cache-invalidating so a resumable region run backfills as it goes, rather
  than the cache freezing the rollout out. Areas and species must run **sequentially**: the writer
  is a read-modify-write over one file and detects a concurrent change by mtime rather than losing
  it silently.
  **VERIFIED LIVE 2026-09-02 (#63)** — neexdzii A/B on m1 plus the same pipeline on m4 reading m1's
  database. `inputs_hash` identical per entry across two passes, `run.datetime_utc` moving, parity
  unmoved at 673.5 km / 142.8 km² / 770.0 ha, and `provenance_ab-compare.R` in-repo so it is
  re-derivable. Evidence: `scripts/floodplain_lcc/logs/20260902_provenance_live-verify_neexdzii.md`.
  Four things the offline half could not have reached:
  **(a)** `lnk_log_read()` returned **30 columns against an installed link naming 26**, unchanged
  across a 0.47.3 → 0.50.0 reinstall — the wholesale-read design demonstrated rather than asserted;
  **(b)** #33 §5 predicted `run_uid` null and it is **populated**, and the issue conflated
  `link_log$link_sha` (written by link at pipeline time, populated) with `fp_pkg_stamp("link")`
  (describes the *installed* package, correctly NA while install and checkout disagreed);
  **(c)** the network `inputs_hash` matched **across two machines** — but see #65, it would have
  matched even if they had read different networks, because `link_log` is a *sibling* of `inputs`
  and so `config_hash`/`run_uid`/`link_sha` are excluded from the hash;
  **(d)** the guard could not gate completeness. Every property was *"every entry PRESENT is
  well-formed"*, so the file left by a run that aborted in step 3 — **4 of 5 entries** — passed, and
  the `-nt` mtime gate passed too because step 2 writes before step 3 runs. `provenance-check.R`
  now derives the expected entry set from the area config and asserts it. **Neither gate is
  sufficient alone; the in-band error count is the only one that caught the abort.**
- **`inputs` answers "same ingredients?", `outputs` answers "same answer?" — and one hash cannot
  do both (#65).** Provenance recorded the recipe and not the cake: two of the three sections
  hashed a *description of the job*. The network's hashed set held the watershed group, the
  species, the schema name and package versions — nothing derived from the network's content, and
  `link_log` is a **sibling** of `inputs`, so even `config_hash` and `run_uid` sat outside the
  hash. The floodplain's was VCA parameters plus `dem_ncell`/`dem_res_m`, which pin the **grid**,
  not the elevations: NRCan re-derives MRDEM at the same footprint and resolution, we cut a
  different floodplain, and not one character moves. So every section now carries `outputs` +
  `outputs_hash` beside `inputs` + `inputs_hash`, and **`outputs` is never folded into
  `inputs_hash`** — "same answer from different data" (the change fell outside our AOI) is worth
  knowing separately from "different answer", which is worth knowing louder.
  **The network's input digest is taken PRE-subset and its output digest POST-subset**, because
  the reach subset is `st_transform` + `st_intersects` — PROJ and GEOS. A post-subset digest in
  `inputs` would make `inputs_hash` a function of the sf build, which is the cross-machine churn
  #64 removed arriving one field over; 01 already sites the freshness guard pre-subset for the
  same reason. **Measured, and it is the cheapest test in the repo:** neexdzii and bulk are both
  `fresh` GRABs on WSG BULK, one subset and one whole group, so neexdzii's *pre*-subset digest
  must equal bulk's whole-WSG digest and its *post*-subset digest must not. Both hold to the byte
  (`37edc39d…` shared, `fa4d47ea…` neexdzii's own), and both reproduce the pre-change artefacts
  exactly.
  **The key is `(blue_line_key, downstream_route_measure)`, NOT `id_segment`** — a deliberate
  departure from #65's own wording. `id_segment` is numbered per watershed group *during
  generation*, so a link rebuild that renumbers would churn the digest on every BUILD and destroy
  the byte-stability the field exists to provide. The composite is FWA-native and is already what
  `cfg$subset` keys on. The value columns are what step 2 **consumes** — `upstream_area_ha` feeds
  the bankfull regression and `map_upstream` the precipitation raster — so a network with the same
  accessible segments and different upstream areas cannot hash the same.
  **`link_config_name` was a hardcoded lie on every GRAB.** 01 asserted the literal `"default"`;
  measured live, neexdzii recorded `default` beside a log row saying `bcfishpass`, and the two
  differ in the natural-barrier set (`bcfishpass` opts in `subsurfaceflow`, the default bundle
  leaves it off). The published provenance therefore claimed the NewGraph methodology for a network
  built under the config this repo explicitly declines to use. It is now resolved from the log row,
  **on the `grab` predicate and not on log presence** — falling back to the build literal "when
  there is no log row" reproduces the defect exactly where it lives, since that is what a GRAB
  source with no log table looks like. `link_config_name_source` names the tier. The `.stamp.md`
  sidecar carried the identical wrong claim and now states the resolved config plus, on a GRAB, an
  explicit note that the config block above describes the **local** bundle.
  **A guard whose two halves are assigned from each other is not a guard.** Asserting
  `inputs$link_config_name == link_log$config_name` cannot disagree once one is derived from the
  other, and whether it fired would depend on statement order. The arm with an external reference
  is *a GRAB may never report `link_config_name_source = "built_literal"`* — it is claiming a
  methodology this machine did not run. The BUILD branch is pinned the other way, by parsing 01's
  own `LNK_BUILD_CONFIG` literal.
  **`sha_source` was free text carrying a `$HOME` path into the hashed half.** Every floodplain
  and landcover entry read `"unresolved (checkout at /Users/…/flooded is 0.6.0, installed is
  0.5.0)"` — machine-local, and #63 measured m1 and m4 disagreeing on that string alone while
  every substantive field matched. It makes the cross-machine criterion **unreadable**: a real
  content difference and a sibling checkout being one release ahead are the same observation. Now
  a closed vocabulary, with the detail sent to the console where naming a path is free.
  **Signed zero moves a digest, and `identical(-0, 0)` is TRUE.** Written as a premise — the
  obvious assumption is that it cannot matter — and the assertion went **red**: `digest()` hashes
  *serialized bytes*, which the two zeros do not share. Unreachable for the Int8 landcover and live
  for the float rasters #65 adds, the floodplain mask being half zeros. `fp_norm_block()` gains a
  third line; `provenance-check.R` §5d pins it with the un-normalized case as the must-fail.
  **`schema_version` was asserted nowhere** and is rewritten on every read, so a bump plus a
  partial re-run labels v1 sections v2 — and the publish layer is downstream of that label. The
  version check alone cannot see it; it is deliberately **paired** with the declared-key check,
  which reports the missing `outputs` block. Neither is sufficient alone.
  **`02` now pins `datatype = "FLT4S"`** on the floodplain write. Unpinned, a terra version
  choosing a different on-disk type moves the nodata sentinel and the digest with zero cells
  changed — #64 with a new cause. Measured byte-identical with and without the argument, so no
  shipped artefact changed. **Vector outputs stay out** (#72): a GeoPackage layer has no
  guaranteed row order and carries floats, so it needs an ordering and precision contract we would
  then have to keep forever. The network's output digest is exempt only because it is taken over
  the same non-geometric key its input digest uses.
  **Forward-only, so the fields do not exist until a step runs again** — `stac_floodplains_bc`
  needs its own change for `schema_version = 2` and the `outputs` sibling, and the coupling stays
  one-way.
- **Byte-deterministic gpkg writes (#45):** GDAL stamps `gpkg_contents.last_change` with wall-clock
  time, so two writes of identical data differ — a rerun was indistinguishable from a change, and
  `file:checksum` downstream would churn every build (GeoPackage is 72% of the published bucket by
  size). `scripts/fp_gpkg.R` pins `OGR_CURRENT_DATE` to a fixed epoch. Pinned via the **environment**,
  not per-call `config_options`: GDAL reads config options from the env, so one call covers all 13
  `st_write` sites plus anything added later, where per-call args go silently incomplete on the 14th.
  Called at **four** entry points — `run_area.R`, `run_region.R`, and the two standalone CLIs
  (`gpkg_backfill-wsg.R`, `fire_tag.R`), which do **not** source `packages.R`.
  `gpkg_determinism-check.R` asserts it (`FP_GPKG_NO_PIN=1` runs the cold path, which must fail).
  **The guarantee is bounded:** a full rebuild into an *absent* file is byte-identical; rewriting one
  layer into an *existing* gpkg is not. `VACUUM` does not close that — it isolates the difference to
  3 SQLite header bytes (change counter, schema cookie, version-valid-for), which are write-history
  counters and cannot be normalized to content, so it was not adopted. Byte equality answers "same
  build?", not "same content?"; the latter needs a content hash over normalized geometry. **"GeoTIFF
  output was measured already deterministic" used to close this bullet and was falsified twice** —
  by #65's `datatype` pin and then by #83; raster container pins live in `scripts/fp_raster.R`.
- **The raster CONTAINER is pinned too, and it is not a function of which terra ran (#83).** Step 3
  writes `classified_<yyyy>.tif` from a SpatRaster drift hands back backed by a gdalcubes NetCDF
  cube (`terra::mask(terra::rast(<year>_<key>.nc), aoi)`). terra **1.9.11** carries that cube's CF
  attributes into TIFF tag 42112 and **1.9.34** does not — measured, 30 tags on all seven years of
  `necr` and `kotl` (m4) and none on `bulk` and `lnth` (m1). Two of the thirty **contradict the file
  they sit on** (`data#type = float64`, `data#_FillValue = nan` on a Byte raster whose nodata is
  255) and `NC_GLOBAL#process_graph` leaks the producing session's `/tmp/Rtmp…` path;
  `stac_floodplains_bc` COGs these with a `CreateCopy`, so they reach the published assets.
  **The #79 split-run had already paid for the isolation** — m4 was levelled to m1 on `drift`, `sf`
  and `gdalcubes`, leaving terra as the only variable — so the discriminator was read out of each
  area's own `provenance.json` rather than measured again. That field exists for this (#64).
  **The divergence is on the READ side.** `terra::rast(<.nc>)` yields zero metags on 1.9.34, while
  `writeRaster` propagates faithfully on both — a dirty raster read and written straight through
  keeps all 30. So on m1 the strip is a **no-op** and no live run here can demonstrate the fix; what
  carries the assurance is `fp_rast_write()` re-reading the file it just wrote and refusing to
  continue, which does not require trusting the strip. Its message names the **toolchain**, never
  `raster_strip-tags.R`: that script repairs a completed run, and a run aborted on its first year
  has written no gpkg layers and no provenance, so repairing and re-running would abort identically.
  **`transition.tif` is clean on both terras, and "it builds a new raster" is NOT why.** `crop()`,
  `mask()` and `deepcopy()` all build new rasters and **preserve** metags — `mask()` is how the tags
  arrive. Value-rewriting ops (`classify`, `app`, `ifel`, arithmetic, `patches`) drop them, and
  `dft_rast_transition()` is one.
  **The guard reads through GDAL, never `terra::metags()`** — terra is the library under suspicion,
  so a guard built on it reports clean exactly where the strip fails. It reads with
  `GDAL_PAM_ENABLED=NO`: GDAL merges a `.aux.xml`'s dataset `<Metadata>` block into the default
  domain, so without that a sidecar written by anyone *opening* the raster in QGIS makes a clean file
  report dirty — and a TIFF rewrite cannot remove a sidecar tag, so the file would be "repaired" and
  report dirty forever. `provenance-check.R` §5f pins all of it with a must-fail arm, and §7 now
  re-derives every `classified_content_sha256` from its raster — the one recorded digest that had
  never been reconciled against its artefact, its year *set* being asserted against `inputs$years`,
  both written by the same run.
  **`raster_strip-tags.R <area>` reconciles what was already written** (idempotent, `DRY=1`), and
  the 14 files in `necr` and `kotl` are done —
  `logs/20260905_raster-tags_strip_necr-kotl.md`. **The band category names are NOT in the TIFF**;
  they live only in the `.aux.xml` PAM sidecar, which is where `stac_floodplains_bc` reads the RAT
  from (stac#34/#35). The first draft of the repair deleted that sidecar as a regenerable statistics
  cache and the class labels went with it, silently, with the content digest agreeing — so the
  script renames both files and asserts `terra::cats()` survived. It permits exactly **one**
  band-section difference, the nodata palette entry `255: 0,0,0,0` → `255: 255,255,255,0` (alpha 0
  both ways, a property of the round-trip), and aborts the file on any other.
  **`gdal_edit.py -unsetmd` was rejected on a measurement that was wrong** and the correction is
  worth more than the verdict: it was reported as destroying the RAT, and it does not — the test had
  copied the `.tif` **without** its sidecar and compared it against an original that had one; all
  256 category rows survive it. It
  stays rejected because it grows the file ~54 kB per invocation and needs `osgeo` bindings nothing
  else here uses. `necr` and `kotl` need a COG rebuild in `stac_floodplains_bc` (stac#59) to pick
  the repair up; the coupling stays one-way.
- `scripts/publish_hint.R` — `fp_publish_hint()`: after a run producing publishable outputs (steps 2
  or 3) the runners print the stac release sequence (`run_pipeline.sh` rebuild → `catalogue_release.sh`
  publish; order matters, releasing without rebuilding ships a stale catalogue). `run_region` sets
  `FP_NO_PUBLISH_HINT=1` for its per-WSG children and prints once for the batch (#32).
  **Do NOT wire this repo to call the publish layer.** The coupling is deliberately one-way —
  `stac_floodplains_bc` PULLS from `$FLOODPLAINS_DATA`; floodplains knows nothing about it beyond
  that printed message. Shelling out to the sibling repo would make the dependency circular and
  break the layering (a driver reaching into the publish layer). The hook is advisory by design.

- **Annual LULC series per area (#79):** optional `lulc_annual: true` in `area.yml` makes step 3
  fetch **every** year of `change_interval` (2017–2023) instead of the endpoints plus midpoint.
  Absent ⇒ unchanged. The **transition does not move** — it is measured endpoint-to-endpoint from
  `change_interval`, never from the fetched set — so the flag adds classified years and nothing
  else; verified on all four areas by digest, not by assumption. Area-owned, deliberately: the
  annual areas span three regions, so a region file must never set or clear it
  (`region_config-check.R` asserts it survives a region run). `FP_LULC_ANNUAL` overrides at
  runtime, and is **inherited by `run_region.R`'s children**, so setting it for a region run flips
  every not-yet-cached group with no trace in any `area.yml`.
  **It is a ONE-WAY DOOR per area.** Turning it back off strands four `classified_*` gpkg layers
  and four `.tif`s: writes have been per-layer since #23 and `fp_dir` is never cleaned, so nothing
  removes a layer whose year the config dropped (#55's orphan class, and
  `gpkg_prune-legacy.R`'s transition-only pattern does not sweep it). `provenance-check.R` 7c now
  reconciles the on-disk tif **and** gpkg layer year sets against `inputs$years`, so the revert is
  *detected* rather than merely warned about in a comment — every other check on that field is
  internal, comparing two values the same run wrote.
  **A present-but-empty key is refused.** `lulc_annual:`, `~` and `null` all parse to `NULL`, which
  an `is.null()` guard skips and `isTRUE()` reads as off — an `area.yml` that reads as annual
  running three years, silently. The guard keys on `%in% names(cfg)` for exactly that.
  **Annual is not free, and the fetch is not the cost.** `terra::as.polygons()` runs once per year
  (7× not 3×) and Pass 2 re-crops the whole grid per year; on a whole-WSG area that is the entire
  grid again. Measured 2026-09-05: peak RSS **does not track grid size** — KOTL (203 Mcells of
  bbox) peaked at 54.3 GB and BULK (168) at 20.6 GB, on different hosts. Plausibly terra sizing its
  working set against available RAM; it was **not isolated**, so do not quote either as a per-area
  requirement. 64 GB sufficed for the largest area run on it.

Adding an area = adding `config/<area>/`; no code change. `area.yml` carries `species` (drives
`access_<species>` in 01 — `co`, `ch`, …), `watershed_group`, `min_order`, `schema`,
`primary_scenario`, and `subset` (blk+drm for a reach, or `null` for the whole WSG), plus the
optional `tile_size`, `attribute_by` and `lulc_annual`.

**Multiple species per area coexist in one `data/<area>/` (#23).** Outputs are keyed by species
(`streams_<sp><min_order>`) and species-prefixed scenario id (`co_ff04`, `ch_ff06`); each run writes
per-layer (`append=file.exists + delete_layer=TRUE`, no whole-file wipe), so a second species lands
alongside the first without destroying it. Run a non-default species via env overrides (no config
edit): `FP_SPECIES=ch FP_PRIMARY_SCENARIO=ch_ff06 Rscript scripts/run_area.R <area>` — the area's
`flood_scenarios.csv` must carry that species' rows (step 2 runs only rows whose `species` matches).
Coexistence is data-layer only (steps 01/02/03).

## Areas

- `neexdzii` — **parity fixture** (coho, BULK subset). The pipeline must reproduce the known-good
  numbers before any new area is trusted.
  **Re-baselined 2026-09-01** — coho-3 network **673.5 km**, floodplain `co_ff04` **142.8 km²**,
  floodplain tree loss **770.0 ha**. The previous contract (678.2 km / 171.0 km² / 943.13 ha) is
  **dead, not merely superseded**: it was produced by flooded ≤ 0.4.1, whose bankfull regression was
  fed hectares where Hall et al. specify km² and mm where they specify cm/yr — width 8.22× and depth
  3.59× too large on every run the package ever did, so `ff04` was delineating ~14.4× bankfull depth
  against Hall's field-validated 3. Two things moved at once (flooded 0.5.0 **and** the switch to
  link's rebuilt `fresh` network), so the change cannot be attributed to either alone — but the
  network moved 0.7% and the floodplain 16.5%, so the bankfull fix dominates.
  **The retention corroborates independently:** neexdzii keeps **83.5%** of its old `co_ff04`, and
  flooded's own NEWS reports **84.7%** for Parsnip on MRDEM-30 — a different watershed, same DEM,
  within 1.2 points. Record the new numbers as a fresh contract, never as a delta from the old.
- `morr` — Morice watershed group (whole WSG). **Coho + chinook coexist** in `data/morr/` (#23).
  **Remodelled 2026-09-01** (flooded 0.5.0 + `fresh` network): coho `co_ff04` **357.7 km²**
  (87.0% of the old 411.1), tree loss **308.7 ha**; chinook `ch_ff06` **371.6 km²** (85.9% of 432.4),
  tree loss **342.6 ha**. `ch_ff06` and `co_ff06` are **identical** — MORR's coho and chinook
  accessible networks are the same 4,877 segments, so species differs only in which scenario is
  primary.
- `ufra` — Upper Fraser (**chinook** — coho is unmodelled up there; `access_ch` exists). Run:
  floodplain ch_ff04 188.2 km², tree loss 544.5 ha. Burned to `sern_fraser_2024` Mergin.
- `bulk` — whole Bulkley watershed group (coho, `network_source: fresh`, `attribute_by:
  blue_line_key`). **The whole group neexdzii is a subset of**, which makes the pair the cheapest
  standing test in the repo: same WSG, species and min_order, one subset and one not, so a
  provenance field taken *before* the subset must agree across the two areas and one taken *after*
  must not (#65 uses exactly this, and `provenance-check.R` 7c asserts the whole-WSG half of it).
  **Re-run 2026-09-02** under #65: coho-3 network **2205.7 km / 6,858 segments**; floodplain
  `co_ff02` **344.7 km²**, `co_ff04` **386.5 km²**, `co_ff06` **414.6 km²**; 7,161 change patches,
  gross floodplain tree loss **1,565.1 ha** 2017→2023. Published to STAC, which is why it was the
  second area chosen for #65's live verification — the one whose provenance a consumer is most
  likely to be reading. **`lulc_annual: true` since 2026-09-05** (#79): step 3 re-run for the full
  2017–2023 series. The transition did not move — 7,161 patches, `transition_content_sha256` and
  `outputs_hash` byte-identical to the 09-02 record — so every number above still stands. bulk is
  also `readme_functions.R`'s `FIG_AREA`, so its transition layer must keep `in_fire`/`in_harvest`
  or the attribution figure builder **stops**.

Whole-WSG areas use the **FWA group polygon** as the single sub-basin (`fp_wsg_subbasin`; no
`break_points.csv` needed). The earlier single-outlet break point does NOT generalize — delineating
upstream of the mainstem outlet over-shoots a tributary group 2–40× (only headwater groups like
MORR/UFRA happened to work). Interior sub-basin delineation is deferred. Pick species by which
`access_<species>` column the fwapg schema populates — the region pre-pass does this automatically.

**Fraser region** (`sern_fraser_2024`, chinook): LCHL, LSAL, WILL, TABR, UFRA, NECR, MORK, FRAN,
BOWR, MCGR plus THOM, LNTH, UNTH (the Thompson groups, added 2026-09-03) — **13 groups**.
`ch_ff04` totals **3,127 km²** across the 12 that have been re-run on `flooded` >= 0.5.0.
The former figure (3,366 km² over 10 groups) is **dead, not merely superseded** — it was produced
under the bankfull units defect, same class as the neexdzii contract in `README.md`. The gross
tree-loss figure that sat beside it (15,022 ha) is pre-correction too and is **not restated here
because it has not been recomputed**; recompute before quoting it. MCGR is excluded from the
3,127: it is still on its 2026-07-12 pre-0.5.0 output (290 km², over-mapped) and cannot be re-run
(#76).

**Columbia region** (`columbia.yml`, **bull trout**): KOTL 707.8 km², LARL 306.9, SLOC 129.6 at
`bt_ff04`. ch/co/st/salmon are unmodelled here — verified empirically (`access_* = -9`, the "not
modelled" SENTINEL, not NULL) rather than inferred from the barrier history (Grand Coulee / Chief
Joseph 1942; Bonnington Falls). Two traps this region exposed, both documented in `columbia.yml`:

- **`species:` is an ordered preference resolved FIRST-modelled, not BEST-modelled.** `access_bt`
  > 0 in all three groups, so `bt` always wins and the listed `wct` never fires — even in KOTL
  where wct has the longer accessible network (2,037 vs 1,920 km). To model wct too, add a SECOND
  region file with the same `region:` label (the `skeena_ch.yml` pattern), not a second entry.
- **The GRAB freshness guard fires on config difference, not just staleness** (#37). Columbia GRABs
  from `fresh_default` (link ≥ 0.45.0) and needs `network_guard: warn`: it diverges +1.8/+2.5/+6.6%
  from the bcfp reference, but across all 49 groups in both schemas the `default` bundle runs a
  median **+0.7%** over bcfp (IQR +0.1–2.6%) because `default` leaves `subsurfaceflow` OFF as a
  natural barrier where `bcfishpass` opts it in. The 2% default tolerance is tighter than the real
  spread, so ~a quarter of groups trip it against a perfectly fresh source.

`run_region.R` carries `network_source` / `network_guard` from the region file into each group's
`area.yml` on every invocation, so hand-editing them **there** is overwritten on the next region run
(they are region-owned — see the ownership rule above), and the `FP_NETWORK_*` env overrides leave
the choice unreproducible. Set them in the region file.

## Prerequisites (when running)

Local `fwapg` (libpq env vars); `link` ≥ 0.44.0, `flooded`, `drift` ≥ 0.10.0, `fresh`, `terra`
≥ 1.8-10; internet for the national MRDEM-30 (`flooded::fl_dem_aoi()`) and Microsoft Planetary
Computer STAC. **`drift` ≥ 0.10.0 is a CORRECTNESS floor, not a feature one** — 0.6.0 was merely
where `dft_stac_fetch` gained `tile_size`, but before **0.10.0** the fetch issued a single
`get_request()` with no paging, so an AOI whose item set spans more than one page was built from a
partial collection: a wrong raster, silently, with `item_ids_complete` structurally unable to
report it (#81). `fp_lulc` asserts the floor.

## Running gotchas (learned the hard way, issue #1)

- **Two drift scaling bugs, both now FIXED — keep the verify-coverage habit.** `dft_stac_fetch`
  used to key its cache on source+year only (no AOI), so a second area silently reused the first
  area's rasters (drift#25, fixed in drift 0.2.3 — cache key now hashes the AOI). And
  `dft_transition_vectors` used to process the full raster grid per transition class and OOM on
  wide-bbox floodplains (drift#27, fixed in drift 0.2.4 — single `terra::patches()` pass, hence the
  terra ≥ 1.8-10 floor). And large-floodplain LULC exhausted memory in the transition (drift#34,
  fixed in drift 0.4.0 — streaming `dft_rast_transition` + `changes_only`, which `fp_lulc` passes).
  The class of failure was "scales on small AOIs, breaks on large ones" — so still **verify LULC by
  checking classified coverage ≈ floodplain area** before trusting numbers when scaling to new groups.
- **Wrap long runs in `caffeinate -s`.** The big-floodplain STAC fetch is ~30 min and download-bound
  by default (it downloads the whole floodplain *bounding box* — ~10× the floodplain). drift 0.6.0
  ships `dft_stac_fetch(tile_size=)` (drift#36), exposed as an **opt-in per-area `tile_size:` in
  `area.yml`** (absent ⇒ unchanged bbox path). **It was benchmarked under #8 and REJECTED — do not
  reach for it to speed up a slow fetch.** Tiling is *slower* at every tile size on every AOI tested:
  neexdzii full step-3 **6.3× slower** (66 min vs 10.5), FRAN direct fetch 0.79× at 20 km and 0.31×
  at 10 km. The reason is geometric and robust — a floodplain is a thin diagonal corridor, the worst
  case for square tiling: coarse tiles blanket the bbox with no download saving but N× per-tile
  overhead, fine tiles hug the corridor but explode round-trips. Accuracy was never the issue
  (≥ 99.999% agreement, no seam band). The knob stays wired but **off**; the bbox waste has to be
  fixed **in-cube** (drift#36 `filter_geom`), still blocked by gdalcubes#110 (OPEN — segfault on
  compute, 0.7.4 macOS arm64). Verdict: `research/20260711_lulc_tile-fetch-benchmark.md`. Long
  background jobs get killed by macOS idle sleep — `caffeinate -s Rscript scripts/run_region.R
  <region>` (the resumable runner picks up any interrupted group).

## Working conventions

### The database is a Docker container — check the right transport before declaring it down

`fwapg` runs as the **`fresh-db` container** (postgis), published on `0.0.0.0:5432`. Two ways to
conclude wrongly that it is down, both hit on 2026-09-01:

- **`pg_isready` with no `-h` tests the unix socket** at `/tmp`, which a containerised server does
  not create. It answers `/tmp:5432 - no response` while `pg_isready -h localhost` answers
  `accepting connections`.
- **The `PG*` variables live in `~/.Renviron`,** which R reads and **bash does not**. So a `psql`
  probe from an agent shell has no host, port, or database and falls back to the same socket —
  while the R pipeline, three lines away, connects fine.

Both failures are about the probe, not the server, and both look identical to a real outage. Check
`docker ps` and `pg_isready -h localhost` before concluding anything; to use `psql` from bash,
export the vars first:

```bash
eval "$(grep -E '^PG(HOST|PORT|DATABASE|USER|PASSWORD)=' ~/.Renviron | sed 's/^/export /')"
```

The cost of getting this wrong is not just a wasted check. It sent a genuine step-1 bug — a
`text[]` column aborting the provenance write — into `main`, because the one code path that would
have caught it was believed to be unreachable.

### A verification that genuinely cannot run becomes its own issue — the parent still closes

When a check truly cannot be run (an in-flight `link` rebuild writing to the schema this repo
GRABs from, a machine without the container), file it as its own issue carrying the exact
commands, the gating, and the specific questions it should answer — then let the parent issue
close and name the follow-up in the PR body and the merge report.

**Why:** the two alternatives are both worse. Holding the parent open misrepresents finished
design as unfinished and blocks whatever depends on it — #33 gates
`stac_floodplains_bc#17`. Merging silently is worse still, because a closed issue reads as
verified. #63 is the worked example — and also the cautionary one: it was filed on a false
premise, so **establish that the check is really blocked before filing**, or the issue documents
your diagnostic error as a project constraint.

**How to apply:** do everything that *is* offline-verifiable first and say what it covered — #33
shipped a guard with every assertion exercised against input built to break it, plus a live-STAC
A/B, with no database at all — so the gap was narrow
and nameable rather than "untested". Gate any run on the **in-band error count and the output
mtime**, never on the wrapper's exit code: a run that crashed before writing makes an A/B compare
a stale file against itself and pass.

### The two READMEs are complementary, and the boundary is a rule (#77)

**Each repo states only what it owns, and neither restates the other's numbers.** `floodplains`
owns the model — VCA, flood factors, what "accessible" means, the uncertainties, how to re-run,
provenance. [`stac_floodplains_bc`](https://github.com/NewGraphEnvironment/stac_floodplains_bc)
owns the catalogue — the item model, how to get the data, counts, extent, version, and the
licence and attribution of the published products. The same rule is written into that repo's
`CLAUDE.md`, and it cuts both ways: its safety summary restates this repo's attribution
percentages, which #77 leaves open.

**Why:** `floodplains` said "20 items live" while the collection served 23, and listed 10 Fraser
groups where `config/regions/fraser.yml` listed 13. Neither was a typo — both were true when
typed, and nothing regenerated them. A number copied across the boundary has no mechanism keeping
it honest, so the failure mode is **recurrence**, not the current wording.

**How to apply:** every fact this README states is either regenerated from committed config at
render time (`fp_readme_roster()` reads `config/regions/*.yml`, `fp_readme_scenarios()` reads
`config/<area>/flood_scenarios.csv`) or it is a link. `scripts/readme_content-check.py` greps
both rendered targets for an item count, a collection extent and a collection version, so a
restatement fails a check rather than waiting to be noticed.

### The README is generated, and both of its targets are committed artifacts

`README.Rmd` renders `README.md` (github_document) **and** `index.html` (html_document,
`self_contained`), which GitHub Pages serves at
<https://www.newgraphenvironment.com/floodplains/> from `main` at `/`. `.nojekyll` is committed
so Pages serves the file rather than running Jekyll over the tracked `.md` files under
`planning/`, which outnumber everything else in the repo; there is no `CNAME` — the org user site owns the domain and every project page
inherits it.

**The site is served from the repo ROOT, so every tracked file is a public URL.** Verified
2026-09-05: `/floodplains/CLAUDE.md`, `/floodplains/planning/README.md` and
`/floodplains/research/README.md` all return 200 under the org domain. The repo was already public
on GitHub, so nothing became secret-exposed — what changed is the *discoverability profile*: these
are indexable paths on `newgraphenvironment.com` now, not files behind a GitHub UI. Treat anything
committed here as published. Machine-local memory stays the home for infrastructure identifiers,
run state, and anything about a person's plans.

Two params, both defaulting **FALSE** and for different reasons. `rmd_on` switches the targets,
and `README.md` is the artifact an accidental Knit would destroy. `update_figs` gates the figure
builders, which read the gitignored `data/bulk/` — so a routine render needs no data, no database
and no network, and `fp_fig_require()` **stops** rather than emitting a page with holes when a
committed PNG is missing.

**Never plot inline.** Figures are written to `fig/` by a gated builder and pulled in with
`knitr::include_graphics()`. A plotting chunk lands the `.md`'s image in `README_files/`, which is
gitignored, so the page renders on the author's machine and shows a broken image everywhere else —
and both rendered files still hash identically, which is why
`scripts/readme_determinism-check.sh` checks for that directory **by name** rather than through
`git status`. Measured: the porcelain form reported OK with `README_files/` sitting on disk.

## Conventions

Run `/claude-md-init` to sync New Graph soul conventions below the marker.

<!-- BEGIN SOUL CONVENTIONS — DO NOT EDIT BELOW THIS LINE -->

# Code Check — R
Traps in R: the language and base/utils behaviour, package internals (`R CMD build`, `.Rbuildignore`, roxygen, lintr, `data-raw/`, testthat, pak), and the DBI/duckdb/arrow data layer.

*Index only: each rule's heading and first sentence. The full text is `~/Projects/repo/soul/conventions/code-check-r.md`; read it before writing or reviewing code in its area. `/code-check` loads it in full.*

### Read-back shape must match write-back shape
A script that reads a file, transforms it, and writes it **back to the same path** is idempotent only if the reader accepts the shape the writer produces.

### Moving prose into a code chunk hides it from tools that scan the document
- Tools that scan an R Markdown document for prose — citation detection, cross-references, spell-check, word counts — skip code chunks.

### `fs::dir_ls(glob = )` matches the FULL path, so a bare filename pattern matches nothing
- `fs::dir_ls(dir, glob = "form_*.gpkg")` returns **zero** for a directory full of `form_*.gpkg` files.

### `glue()` trims common leading whitespace
- `glue::glue()` strips the common indentation of its input, so a template whose output must preserve exact indentation (XML, YAML, Makefiles, Python) comes out subtly wrong — valid-looking, wrongly indented.

### `f(g(x)) <- v` needs a `g<-`, not an evaluated `g(x)`
- R parses **any** call on the left of `<-` as a replacement function, all the way down.

### A replacement function on an `xml_missing` node is a silent no-op
`xml2::xml_find_first()` returns an `xml_missing` object when nothing matches — not `NULL`, not an error.

### `download.file(quiet = TRUE)` never tells you the HTTP status — read it from `curl`
Read an HTTP status from `curl::curl_fetch_disk()`'s `status_code`, never from `download.file()` messages, whose first warning unwinds a `tryCatch` before the status arrives and whose quiet error omits it.

### `on.exit()` at a script's top level never fires
- `on.exit()` registers a handler on the *current frame*.

### A `data-raw/` script must load the source tree, not the installed package
- `requireNamespace("pkg")` succeeds whenever **any** version is installed, so a guard shaped like `if (!requireNamespace("pkg")) pkgload::load_all()` silently runs against the installed one.

### `lintr` also resolves against the installed package, not the source tree
A lint warning of `no visible binding` for a constant added on this branch is usually the installed package being stale; check `exists(name, asNamespace(pkg))` and reinstall before changing any code.

### Regenerated binaries churn git even when nothing changed
- Formats that embed a creation timestamp or other run-varying metadata produce a different file on every rebuild.

### Tests that silently do not run
`expect_snapshot()` **skips on CRAN**, and `testthat` treats a non-interactive run as CRAN by default.

### A `skip_if_not()` skips only its own `test_that()` block
Before blaming a failure, or its absence, on a skip, find the `test_that()` block the skip sits in.

### `expect_gt()` and friends take no `info` argument
`expect_true()`, `expect_false()` and `expect_equal()` accept `info =`; the comparison expectations — `expect_gt`, `expect_lt`, `expect_gte`, `expect_lte` — do not, and passing one is an **error**, not a warning:

### pak Behavior
- pak stops on first unresolvable package — all subsequent packages are skipped

### Reproducibility
- Branch pins (`pkg@branch`) are not reproducible — document why used; the fuller pin policy (no suffix by default, never a bare SHA) is under "Two repos pinning the same remote" below

### A duplicate knitr chunk label fails the build, and reading the diff will not find it
Chunk labels must be unique **within a document**.

### `R CMD build` ships every top-level directory not in `.Rbuildignore`
- Internal coordination directories — `comms/`, `research/`, `planning/`, `dev/` — land in the tarball and therefore in the library of anyone installing from GitHub.

### `R CMD build` ships the `.git` FILE when you build from a worktree
A package built from a `git worktree` ships `.git` (a file holding the developer's absolute path), because R excludes only a `.git` directory; list `^\.git$` in `.Rbuildignore`.

### `.Rbuildignore` has no comment syntax — every line is a live regex
`tools:::inRbuildignore` loops over every non-empty line and ORs `grepl()` of it against the file list.

### Base name shadowing in formal args
- Avoid `names`, `length`, `data`, `c`, `t`, `T`, `F`, etc. as formal argument names.

### Cross-function consistency for label/string normalization
- When two functions in the same package both decide whether a string is a "system value" (or any normalized form), they MUST use the same comparison.

### `$` on a list partial-matches, so a longer sibling key answers for a missing one
- `x$foo` on a list returns `x$foo_bar` when `foo` is absent and `foo_bar` is the only key with that prefix.

### A database driver's value is not a base R type — and it fails twice
A column fetched through DBI does not arrive as the base type its SQL type suggests.

### arrow dplyr backend: no grouped slice — bridge to duckdb
- arrow's dplyr backend errors on grouped `slice_max`/`slice_min` (`arrow_not_supported("Slicing grouped data")`).

### as.POSIXct on a Date pins UTC midnight; on a character it uses the machine zone
Construct instants explicitly: a `Date` always becomes UTC midnight whatever `tz =` says, and a character with no zone is read in the machine's zone, so pass `tz =` at parse time.

### as.POSIXct on character infers ONE format for the whole vector
- `as.POSIXct(x)` on a character vector picks a single format by finding the first candidate that parses **every** element — and `strptime` **ignores trailing characters**.

### Inserting a helper between a roxygen block and its function rebinds `@export`
- roxygen2 attaches a block to **whatever object follows it**.

### open_dataset(unify_schemas = TRUE) requires aligned types
- Cross-prefix/file schema unification only merges what types allow: `timestamp[us, tz=UTC]` will not merge with naked `timestamp[us]`, `Grade: string` not with `Grade: double`.

### duckdb larger-than-memory dedup: shard the work — settings won't save you
- duckdb's **window operator** (QUALIFY row_number ...) does not spill enough to survive big partitions (OOM'd an 8 GB limit on a ~124M-row input).

### `nzchar(NA)` is TRUE — non-empty checks silently pass NA
- `nzchar(NA)` returns `TRUE`, so the natural "is this cell filled in" test — `all(nzchar(trimws(x)))` — waves through a column full of `NA`.

### A `for` loop that builds `aes()` captures the loop variable lazily
`aes()` quotes its arguments, so `aes(fill = lab[i])` is not evaluated until the plot is drawn — by which time `i` holds its **last** value.

### `paste()` with a zero-length argument returns length ONE, not zero
`paste0("x", character(0))` is `"x"`, so a key built per element gains one phantom member when the vector is empty; guard the empty case before building keys.

### `strsplit()` drops a trailing empty field, so a trailing separator vanishes
Leading empties survive and trailing ones do not, which is what makes it hard to reason about from memory.

### `identical()` on two reader results tests the reader, not the file
`identical(read_csv(f), read_csv(f))` can be **FALSE** for the same unchanged bytes: readr tibbles carry a `problems` attribute — an external pointer — that differs between reads (readr 2.2.0; `spec` is identical, measured).

### Under `R CMD check`, tests run from a temp dir against the INSTALLED package
Two shapes, both green under `devtools::test()` and broken under `R CMD check`, `devtools::check()`, a tarball check, or an installed-tests run — the direction that costs the most time.

### `dbConnect(SQLite(), path)` CREATES the file, so a read has a write side effect
SQLite creates a database on connect.

### CSV whitespace: `trim_ws` and `strip.white` do not do what the name suggests
- `readr::read_csv()` defaults to **`trim_ws = TRUE`** and silently strips leading and trailing whitespace.

### `R CMD check` rejects a filename containing a space
- "checking for portable file names" fails on any file in the built package whose name has a space.

### `sort()` and `order()` collate by `LC_COLLATE`, so a canonical form is locale-dependent
Character sorting in R is locale-sensitive by default, which makes any *canonical* string built by sorting — an XML node with its attributes ordered, a joined key, a manifest — a function of the session's locale rather than of the data:

### A library call that dispatches on a global option is not a pure function
A function whose *units* or *algorithm* are chosen by a session-wide setting behaves differently depending on what the caller did before reaching your code.

### `identical(-0, 0)` is TRUE in R, and the two still digest differently
A hash over R's serialized bytes — which is what `digest::digest()` takes by default — separates positive and negative zero, even though every value comparison says they are the same.

### Two repos pinning the same remote at different tags is an unsolvable install
`Remotes:` pins are per-repo, but resolution is global.

### `file(open = "wb", encoding = )` does not re-encode on write
The `encoding` argument to `file()` governs how bytes coming *in* are interpreted.

### A scalar helper called from `glue()` or `mutate()` recycles instead of erroring
`glue()` vectorises over its inputs.

### Never name a durable artifact by a hash the library reserves the right to change
`rlang::hash()` carries **no cross-version stability guarantee**, and rlang says so in its own NEWS for 1.3.0:

### `vapply(..., USE.NAMES = FALSE)` strips ALL dimnames, row names included
A named `FUN.VALUE` looks like it guarantees row names on the returned matrix.

### `source()`ing a config into the render environment leaks it into the next render
`source(params$config)` inside an Rmd puts every config value into the environment `render()` evaluates in.

### One very long table cell hangs paged.js, and it presents as a Chrome timeout
A ~600-character free-text field in a `kable` cell wedged `pagedown::chrome_print` indefinitely.

### `stats::aggregate()` has three separate silent behaviours, and each fails in a different direction
All three measured on R 4.5, all three met inside one 800-line script (drift#67).

### `deparse(body(f))` excludes formal defaults, so a body scan cannot see a default
A guard that scans function bodies for a forbidden literal is blind to that literal in a **signature**.

### `deparse()` re-encodes non-ASCII, so it answers about itself rather than the file
Scan R source for non-ASCII the way `R CMD check` does (`tools:::.check_package_ASCII_code()`: raw lines, comments skipped), not through `parse()` and `deparse()`, which turn `\uXXXX` escapes into literal characters and back.

### `package_version()` errors on a pre-release version string
`package_version("3.9.0beta1")` raises rather than returning `NA`, so strip a pre-release suffix before asserting a version floor.

### `tryCatch(warning = )` DISCARDS the value the expression produced
A `warning =` handler is not a filter — it replaces the whole expression, so a call that **succeeded** and merely warned returns the handler's value and the result is thrown away.

### `match()` treats NA as a matchable VALUE, so two unknowns join to each other
`match(NA, c("1", NA))` is **2**.

### `expect_message(expr, regexp)` checks only the FIRST condition, so a progress line hides the message under test
testthat 3e captures the first message the expression emits and matches the regexp against **that one**.

### `pak` refuses to install a package that needs no compiler
`pak::pak()` routes through `pkgbuild::check_build_tools()`, which fails with *"Could not find tools necessary to compile a package"* whenever `xcode-select -p` points at `/Applications/Xcode.app/...` while the Command Line Tools are what is actually installed — **regardless of whether the package has any compiled code**.

### `as.integer("NaN")` is `0`, and `as.integer(NaN)` is `NA`
The string round trip is the bug.

### `expect_false(identical(x, y))` cannot fail when the two are different types
`identical()` is type-strict, so it is already `FALSE` for any pair that differs in storage mode — and an assertion that the defect would make *true* then cannot fire.

### `unlist()` prefixes a `split()` group's name, so reassembling by name silently yields all-NA
Putting per-group results back in input order by naming them looks right and returns nothing:

### `tolerance` in testthat is RELATIVE, so it pins a published figure far more loosely than it looks
`expect_equal(x, 12.529, tolerance = 2e-2)` accepts anything within **two percent** — so a figure published to three decimals survives drifting to `12.629`.

### `cli` reads `{.name}` as a STYLE, not a variable, and a fold can swallow an interpolation
Two ways a `cli` message loses a value.

### `[[` on a named ATOMIC vector with an absent key is an error, not `NULL`
A list returns `NULL` for a missing `[[` key.

### `data.frame()` recycles a scalar against a zero-length column
It does not yield a 0-row frame — it raises, because a length-1 column and a length-0 column cannot be recycled together:

### A dot-prefixed column name can be swallowed by the verb's own formal
`mutate(x, .d = expr)` does not create a column called `.d`.

### `summarise()` and `mutate()` evaluate in order, so a later argument sees the summarised column
Once `frames = sum(frames)` has run, `frames` inside the next argument is that one-row sum, not the group's vector.

### `\<` and `\>` are word boundaries in R's default regex, not escaped `<` and `>`
Leave `<` and `>` unescaped when you build a pattern from data.

### `tempfile()` lives in the session tempdir, so a path printed in an error names a file R is about to delete
R removes its session `tempdir()` on exit, including after `stop()`.

### R's `yaml` returns a mixed int/float sequence as a list, not a numeric vector
`yaml::read_yaml()` simplifies a sequence to a vector only when every element has the same type, so `[0.164, 9999]` comes back as `list(0.164, 9999L)` while `[0.0, 9999.0]` is `c(0, 9999)`.

### testthat's failure snapshots land in `tests/` and ride in on `git add -A`
testthat 3e writes `tests/testthat/_problems/*.R` and `tests/testthat/testthat-problems.rds` when tests fail.

### A pick whose `ORDER BY` ends on a key that is not unique in the group returns an arbitrary row
`DISTINCT ON (k) … ORDER BY k, a, b` is deterministic only if `(a, b)` is unique within each `k`.

### `sprintf("%g", x)` writes `Inf` and `NA` into SQL as bare words, which Postgres reads as column names
A numeric formatter such as `sprintf("%.10g", x)` has no SQL form for non-finite values, so an open-ended range (`c(min, Inf)`, typically a blank `max` filled with `Inf` by a params loader) produces `x <= Inf`, and Postgres fails with `column "inf" does not exist`.

### An `information_schema` lookup by the literal table name misses what Postgres resolves
`WHERE table_schema = 's' AND table_name = 'T'` compares the text you passed, but Postgres folds unquoted identifiers to lower case, puts temp tables in `pg_temp_N`, and resolves unqualified names through `search_path`.

### Rscript reads a script as it runs, so never edit a script while a run of it is in flight
Copy the script and run the copy (`cp scripts/x.R "$TMPDIR/x_frozen.R" && Rscript "$TMPDIR/x_frozen.R"`) for anything long-running, or leave the file alone until the run exits.

### A range total taken as the difference of two large running totals loses the small ranges
Sum a range directly (segment tree, per-range `sum()`, or grouped sums) rather than as `cumsum[hi] - cumsum[lo]` when ranges are small relative to the running total.

### A `pkg::` call in a test passes `devtools::test()` and fails `R CMD check` if `pkg` is undeclared
`R CMD check` warns "'::' or ':::' import not declared from" for any package a test reaches with `::` that `DESCRIPTION` does not list, and under `error-on: "warning"` that reddens every runner.

### Inside a dplyr verb, a column named like a local variable wins
Inject a local value into a data-masked verb with `!!x` or `.env$x`, never a bare `x`: `transmute(d, aoi_id = id)` inside `for (id in ids)` reads the frame's own `id` column whenever one exists, with no warning, and the result is well-typed and plausible.

# Code Check — Shell
Tool-level traps in bash, sed, git and `gh`, and in the host toolchain those commands depend on.

*Index only: each rule's heading and first sentence. The full text is `~/Projects/repo/soul/conventions/code-check-shell.md`; read it before writing or reviewing code in its area. `/code-check` loads it in full.*

### `git diff a..b` compares TIPS; a change on `a` shows up as the branch's
Use three-dot `git diff a...b` for what a branch changed; two-dot compares the tips, so changes that landed on `a` show up as the branch's, inverted.

### git pathspec excludes: use the long form
- `:!path` is short-form magic, and git keeps parsing magic characters after the `!`.

### `sed 1d f1 f2 f3` strips only the FIRST file's header
`sed` treats multiple file arguments as one concatenated stream, so a line-address script applies once across the whole set rather than per file.

### `sed -n '/X/,$d' file` prints nothing at all
`-n` suppresses auto-print, and `d` only deletes — so nothing is ever emitted and the output is empty.

### Reading a file line-by-line drops the last line without a trailing newline
- `while IFS= read -r line; do ...; done < file` skips a final line that has no newline after it.

### Empty arrays under `set -u` on bash 3.2
- macOS still ships bash **3.2**, where `"${ARR[@]}"` on an empty array is an unbound-variable error under `set -u`.

### Quoting
- Variables in double-quoted strings containing single quotes break if value has `'`

### Heredoc precedence in pipelines
- `cmd1 | cmd2 <<EOF` — the heredoc binds to `cmd2` (the rightmost simple command).

### Paths
- Hardcoded absolute paths (`/Users/airvine/...`) break for other users

### Diagnose env/PATH problems in the shell that actually runs, not the ambient one
- Get ground truth **before** forming any theory: `env -i HOME=$HOME TERM=$TERM bash -lc 'echo $PATH | tr ":" "\n" | nl'` (swap in `zsh` to check the other side).

### Parallel writers sharing one output file interleave mid-record
- `xargs -P N ... >> shared_file` (or any fan-out where N processes append to the same fd/path) is only safe while each record fits in a single `write()`.

### `mktemp` template needs enough X's, and a failed `mktemp` leaves an empty var
- BSD/macOS `mktemp -d -t <name>` requires the template to contain at least 3 `X`s (`XXXXXX` is the safe default).

### `cmd dir/*` dies on ARG_MAX at scale — and only after the expensive work succeeded
- A glob expands to argv.

### A `curl` in a parallel fan-out needs `--max-time`
- Without it, one hung connection pins a worker slot indefinitely.

### BSD vs GNU sed/grep portability (macOS hits this constantly)
- macOS ships BSD `sed`/`grep`.

### On this Mac `stat` and `date` are GNU, so the same flag letter means something else
Here Homebrew puts GNU coreutils ahead of `/usr/bin`, so BSD-style `stat -f` and `date -r <epoch>` mean something else; prefer a flavour-free form (`find -newermt`, `python3`), or call the binary by absolute path.

### `&` binds to the whole `&&` list, so assignments never reach the parent
- `cmd1 && VAR=$(...) && nohup prog > "$VAR.log" & disown` backgrounds the **entire list**, not just `nohup`.

### `gh` CLI
- **`gh pr create` resolves branch from CWD, not `--repo`**.

### On a fork, `main` may track upstream by design — comparing it answers nothing
`gh api repos/ORG/REPO/compare/upstream:main...ORG:main` returning `ahead: 0, behind: 0, status: identical` reads as *"this fork has no local work"*.

### A destructive setup and its undo must not share one timeout-able command
Never chain a destructive setup and its undo (`git stash && slow && git stash pop`) in one timeout-able command; compare with `git show HEAD:path`, or restore from one `trap … EXIT` handler guarded by a flag set once the setup happened.

### `git checkout <path>` restores from the index, not from HEAD
After a `git add`, `git checkout <path>` reinstates the broken *staged* copy — so the "fix" reproduces the failure and reads as though the edit was wrong.

### A value validated with one numeric grammar and consumed with another
Normalise a numeric string once (digits only and at most 9 of them, then `x=$((10#$x))`, then a bounded range): `test` reads base 10, `$(( ))` reads a leading zero as octal and wraps past 2^63.

### `wait` with no argument waits for every background job in the shell
Wait on the PIDs you started (`wait "$pid"`), because a bare `wait` also blocks on every other background job in the shell.

### `if ! cmd; then rc=$?` captures the negation, not the command
Inside the branch, `$?` is the status of the `!` compound — which is **0 by construction**, because the negation succeeded.

### A `pgrep -f` waiter matches its own command line, so it never exits
Wait on a PID with `while kill -0 "$PID"; do sleep 30; done`, never on `pgrep -f "job"`, whose pattern matches the waiting loop's own command line so it never exits.

### `timeout` is GNU coreutils — a portable deadline
An assertion around something that might hang can only pass or hang, never fail (`code-check.md`, "Restore the bug and prove the guard fires").

### `aws s3 cp` cannot tell a missing key from a missing bucket
`aws s3 cp` gives one exit 1 and 404 text for a missing key and a missing bucket, so probe `s3api head-bucket` then `head-object`: only a 404 from a reachable bucket means absent; a 403 is permissions.

### A verification command can be shadowed by a shell function or alias
- The shell is initialized from the user's profile, so `diff`, `grep`, `ls`, `cat` and friends may resolve to a wrapper rather than the binary you assume.

### psql does not interpolate `:'var'` inside a dollar-quoted string, and `\quit N` exits 0
Two traps in the same file type, both of which read perfectly and fail at run time.

### A second `trap … EXIT` replaces the first
`trap` registers **one** handler per signal.

### A `local` statement cannot read a variable it is assigning in the same statement
`local a="$1" lab="$2" m="/tmp/marker_${lab}"` expands `${lab}` **before** `lab` is assigned.

### Inside an `EnterWorktree` session, the Bash tool refuses command text that names git
The harness applies an isolation guard to a session that entered a worktree: *"a worktree-isolated session's git operations must target its own worktree."*

### A `git filter-repo` seed carries the source repo's tags, and a path sed misses the language's path constructor
Two traps from seeding one repo out of another's history (fish_passage_template_reporting#236, 2026-09-02), both silent.

### `git check-ignore -v` prints the matching pattern, and its exit status is not a per-file verdict
`-v` reports the **last matching pattern**, negations included.

### `sips -Z` scales up as well as down
`sips -Z N` resamples so the longest side is N — in **either** direction.

### Assert capabilities, not versions — a tool upgrade can remove one silently
A tool upgrade across the fleet can remove a capability without reporting failure.

### An amd64-only image needs `--platform`, and it works on your machine because it is cached
`docker run` resolves from the local image store before it reaches a registry, so on an arm64 Mac an amd64-only image runs fine once pulled — **and the command that pulled it is not necessarily the one in the code.**

### Headless Qt in a container needs `QT_QPA_PLATFORM=offscreen`, and without it the run hangs or crashes
Pass `-e QT_QPA_PLATFORM=offscreen` to any `docker run` that starts QGIS or another Qt program with no display.

### `s3cmd ls` given several paths lists only the FIRST, and says nothing
Query one path per `s3cmd ls` call, or `--recursive` on the prefix and `grep`: given several paths it lists only the first, with exit 0.

### `grep -c` prints the count AND exits 1 when it is zero
Write `n=$(grep -c …) || n=0`, never `|| echo 0` inside the substitution: `grep -c` already prints `0` and exits 1, so that fallback appends a second line, while the bare assignment aborts a `set -e` script.

### A failed `git fetch` leaves the comparison you make next reading stale refs
`git fetch` and the check that follows it are two commands, and nothing links them.

### macOS `/usr/bin/awk` aborts when a regex meets a byte slice that cuts a multibyte character
Test a `substr()` slice with `==`, never with `~`, `match()` or `sub()`: the stock macOS awk counts bytes in `substr()` but converts a regex operand to wide characters, and a partial UTF-8 sequence kills the whole program.

### A variable in a sed replacement is parsed, so its `\` and `&` are not literal
Never interpolate data into the replacement half of `sed "s#…#$var#"`: sed reads `\(` as `(`, and `&` as the whole match, so the line written is not the value held.

### A fetch can fail and still deliver the commit, so when you need an object, test the object
When the goal is a specific commit, resolve its sha first (`git ls-remote`) and test `git cat-file -e "$sha^{commit}"` after the fetch rather than the fetch's exit status.

### A default `GIT_SSH_COMMAND` outranks the machine's own ssh choice
Supply a default ssh command only when `GIT_SSH_COMMAND`, `core.sshCommand` and `GIT_SSH` are all unset.

### `curl -o` without `-L` saves the redirect page as the download
`curl` does not follow redirects unless it is given `-L`, and it exits 0 on a 3xx.

### `conda run` captures its child's output, so a pipe gets nothing
`conda run -n env cmd` buffers the child's stdout and re-emits it, and that re-emission does not reach a pipe.

# Code Check — Spatial
terra, sf, bcdata, GDAL/OGR CLIs.

*Index only: each rule's heading and first sentence. The full text is `~/Projects/repo/soul/conventions/code-check-spatial.md`; read it before writing or reviewing code in its area. `/code-check` loads it in full.*

### Negative coordinates get parsed as CLI options — every BC bbox hits this
- BC longitudes are all negative, so `--bounds -124.73 49.485 -124.595 49.565` fails with `Error: No such option: -1`.

### bcdata: an empty result raises AttributeError, it does not return an empty collection
- A bbox query matching nothing exits non-zero with `AttributeError: You are calling a geospatial method on the GeoDataFrame, but the active geometry column to use has not been set.` — geopandas complaining about an empty frame, several layers below the query.

### bcdata: `BBOX()` rejecting a bbox that is a length-4 numeric vector — seen once, unquoting fixed it
If `bcdata::BBOX()` rejects a length-4 numeric bbox as not a length-4 numeric vector, try unquoting it with `!!`; this was seen once and the mechanism is not established.

### terra: operator dispatch and edge cases in package code
- **SpatRaster `%in%` is not dispatched when terra is *imported* (only when *attached*).**

### terra: `extract()` returns no row for ground beyond the raster, and counts cells by centre
- Two traps in one call, and both make a partial result look complete.

### A `...` constructor may discard trailing arguments based on the class of the first one
- A constructor that takes `...` is free to branch on **what its first argument is** and build the result from that alone.

### terra: `mask()` is `touches = TRUE`, so two "clip to the polygon" routines disagree by a cell ring
Swapping one polygon clip for another looks like a refactor and is a **methodology change**.

### terra: `sources()` on a derived raster is `""` or a random temp path, never the input
- A raster that came out of `crop()`, `project()`, `mask()`, or arithmetic is **derived**, so it has no source file.

### `sf::st_as_binary()` returns a LIST of raw vectors, so `is.raw()` on it is FALSE
The obvious way to feed WKB into a canonicalizer is a `is.raw(x)` branch that hex-encodes it.

### Canonicalize geometry before hashing it — ring order and orientation are not fixed by topology
`code-check.md`'s cache-key row prescribes hashing WKB (`sf::st_as_binary(sf::st_geometry(x), endian = "little")`) rather than the sfc object.

### sf: `st_join(largest = TRUE)` ignores the join predicate
`st_join(largest = TRUE)` matches by intersection area whatever `join =` says, and drops zero-area geometries, so point and line overlays cannot use it.

### sf: name validation must account for the geometry column
- The active geometry column is a named entry in `names(x)`, but its name is **not fixed** — `"geometry"` from `sf::st_read()` of some sources, `"geom"` from a GeoPackage/PostGIS layer, `"geometry"` or `"_ogr_geometry_"` elsewhere.

### sf: `st_intersection()` / `st_difference()` return a GEOMETRYCOLLECTION that QGIS will not draw
- Intersecting or differencing two polygon layers yields a `GEOMETRYCOLLECTION` wherever the inputs *also* touch along a line or at a point.

### sf: reproject the polygon to get a lat/lon bbox, never transform the projected bbox corners
- To hand a geographic (EPSG:4326) bounding box to a bbox-filtered query (WFS/OGC features, `?bbox=`), reproject the whole AOI **geometry** then take its bbox: `sf::st_bbox(sf::st_transform(aoi, 4326))`.

### An offset regex must be anchored to a time, or a date looks like a zone
- Refusing or stripping a trailing UTC offset with something like `[+-][0-9]{2}(:?[0-9]{2})?$` also matches the end of a plain ISO date: `"2026-08-15"` ends in `-15`, which reads as a −15 hour zone.

### A reader that accepts a UTC offset may not be applying it
GDAL accepts a UTC offset in a GeoPackage `DATETIME` and silently drops it, returning wall-clock digits that are then read in the machine's zone, so one file gives a different instant on every machine.

### Ask the file about its field names, not R
`sf::st_read()` returns a data frame, and R makes column names syntactic on the way in.

### QGIS embeds a layer's style in the `.qgs`, so rewriting the `.qml` sidecar changes nothing
A `.qgs` carries each layer's style **inside** its `<maplayer>` node — the sidecar's children are copied in when the layer is declared.

### A GeoPackage is a SQLite database, and that leaks in three ways
Writing to one directly (a `layer_styles` row, an attribute fix) is a plain `INSERT` and needs no GDAL.

### The same leak reaches R and OGR SQL, and a GeoPackage's bytes are not its content
Edit a live GeoPackage through GDAL (`ogrinfo -sql`) rather than RSQLite, and assert row state rather than `dbExecute()`'s count, which includes trigger writes.

### Restoring a GeoPackage from a copy: refuse sidecars before the first read, delete them before the copy-back
A byte copy of the main file is a snapshot only when no `-journal`, `-wal` or `-shm` exists and the header is in rollback mode (bytes 18-19 = `01 01`).

### A coordinate stored as an attribute can disagree with the geometry it describes
A spatial layer that also carries `LATITUDE` / `LONGITUDE` columns has the same fact twice, and nothing keeps them consistent.

### GeoJSON in a projected CRS is silently non-portable
`sf::st_write()` and `ogr2ogr` will write GeoJSON from a projected object and emit a `crs` member naming it:

### `sf::st_perimeter()` needs lwgeom on projected data, and lwgeom is not a dependency of sf
An exported sf function whose body branches on `requireNamespace("lwgeom")` is an undeclared dependency: `R CMD check` does not report it, and a test suite cannot see it on a machine that happens to have lwgeom installed.

### terra keeps a result in memory whenever it fits, so a per-class loop over a large grid accumulates full-grid rasters
`ifel()`, `focal()`, arithmetic and `rasterize()` return in-memory SpatRasters whenever the result fits under `memfrac` (60% of RAM by default).

### `geom_sf(data = NULL)` draws nothing, silently
A `NULL` `data` argument does not error and does not warn — the layer inherits the plot's data, which for `ggplot()` with no global data is empty, so it contributes a **zero-row layer**.

### terra: `app()` calls a vector-tolerant `fun` once per CELL, and reads a 5-column return on a 5-column raster as transposed
Two contracts inside `terra::app()` that read as the opposite of what they are, both measured on terra 1.9.34 (drift#9, 2026-09-05):

### terra: `levels<-` and `coltab<-` copy before they strip; `set.cats(NULL)` is the in-place form
`levels<-` and `coltab<-` deep-copy before stripping, so a caller-untouched test cannot fail under them; `terra::set.cats(r, layer = i, value = NULL)` strips in place and mutates whatever raster it is given, so use it on a copy you own.

### terra `metags()`: the empty case is `NULL`, and the sidecar is half the artefact
Three measured facts about raster **container** metadata, all of which fail quietly (floodplains#83, 2026-09-05, terra 1.9.34 / GDAL 3.8.5).

### `ggmap`: a fixed `zoom` silently crops points off the basemap, and `calc_zoom()` does not fix it
`ggmap::get_map()` fetches ONE fixed-size image at whatever `zoom` it is given.

### terra: `zonal()` outside its six-function fast path materializes the WHOLE grid in R
`terra::zonal()` dispatches to C++ only when `fun` is one of `max`, `min`, `mean`, `sum`, `notNA`, `isNA`.

### sf: close a rotated ring by copying the first vertex, never by recomputing it
Rotating a polygon by multiplying its whole vertex matrix — `xy %*% rot` — looks exact, and for a ring built closed it is not.

### terra: `plot(type = "classes", levels =, col =)` maps colours by POSITION, per layer
A `levels`/`col` pair is not a value-to-colour mapping.

### terra: `wrap()` carries the tempfile basename in `varnames`, so a committed artifact churns
Set `varnames` and `longnames` before `wrap()` or writing a raster produced with `filename = tempfile()`, or the random tempfile basename makes a committed artifact change on every run.

### `terra::plot()` leaves the device in a state where a keyword-placed `legend()` draws nothing
`graphics::legend("topleft", …)` after a `terra::plot()` or `terra::plotRGB()` **silently draws nothing** — no error, no warning, and the rest of the figure renders normally.

### A name is not a key: `GNIS_NAME` matches features all over BC
`filter(GNIS_NAME == "Buck Creek")` returns every Buck Creek in the province.

### `sf::st_read()` on a KML drops `<SchemaData>`, silently
GDAL has two KML drivers and picks `KML` by default, which does not read the `<SchemaData>` block.

### GDAL applies `-srcnodata` and an alpha mask together, and the mask loses
Two ways of saying "these pixels are not data" reach `gdalwarp` independently, and giving it both is not an error — it is an instruction to do both.

### `parallel::mclapply()` over a remote raster aborts every fork on macOS, and the wrapper exits 0
GDAL's curl handles do not survive a fork.

### terra: `align()` defaults to `snap = "near"`, so the aligned window need not contain the input
`terra::align(e, r)` snaps each edge of `e` to the **nearest** cell boundary of `r`, which moves an edge *inward* as readily as outward.

### GDAL reserves 3,276 MB per process before reading a cell, and PSOCK workers outlive their master
Two independent reasons a parallel raster job uses far more memory than its data, both measured 2026-09-20 on a 64 GB machine (fly#58) while a sweep was killed four times.

### `terra::distance(x, target = NA)` measures FROM the NA cells, so every data cell reads 0
Reaching for it to answer "how far is each data cell from the nearest nodata" gives the opposite: `distance()` fills the **target** cells with their distance to the nearest non-target, so data cells come back `0` and any `dist < threshold` test is true everywhere.

### `summarise()` on a grouped `sf` returns an `sf`, and the geometry rides into your CSV
`dplyr::summarise()` dispatches to `summarise.sf` on an `sf` object.

### A raster's drawn footprint is its valid data, not its extent
Before comparing a rendered shape against a raster, get the raster's valid-data window, not its bbox.

### `sf::gdal_utils()` does not raise when GDAL cannot open the source
Test the result before parsing it: `gdal_utils("info", ...)` on a source GDAL cannot open - an unreachable url, a missing key - **warns and returns `character(0)` or `NA`**, and the next `jsonlite::fromJSON()` dies with *"invalid char in json text"*, which names nothing about the cause.

### A shift measured on one grid is wrong when applied on another
Apply a displacement in the CRS it was measured in: transform the point there, add the shift, transform back.

### Writing KML: `<color>` is `aabbggrr`, and a remote icon href renders nothing offline
Do the hex swap in **one** helper and omit `<Icon><href>` entirely.

### `rio cogeo validate` exits 0 when the file is NOT a valid COG
It reports the verdict in text and returns success either way, so the exit status carries no information at all:

### `terra::rast()` on a SpatRaster returns an empty template, not a copy
Pass a SpatRaster through as is (`if (inherits(x, "SpatRaster")) x else terra::rast(x)`): `rast(x)` on one builds a new raster with the same geometry and **no values**, so a function that normalises its input with `terra::rast()` silently receives an all-empty grid when handed an object rather …

### `terra::rasterize(filename = , datatype = <integer>)` writes the background as 0, not NA
Rasterise in memory and then `writeRaster(datatype = …)`: written directly through `filename` with an integer `datatype` (INT1U, INT2S), cells no polygon covers come out as 0, while the file's NoData is 255, so they read back as data (terra 1.9.46 and 1.9.50; rspatial/terra#2195).

### GDAL's `average` warp across a rotated CRS weights the wrong pixels; average in the target CRS instead
To take class fractions or means from a fine grid in one CRS onto a coarse grid in another, resample nearest onto a grid aligned with the target and `fact` times finer (`terra::disagg(terra::rast(target), fact)`), then `terra::aggregate(fact, mean)`.

# Code Check Conventions
Structured checklist for reviewing diffs before commit.

*Index only: each rule's heading and first sentence. The full text is `~/Projects/repo/soul/conventions/code-check.md`; read it before writing or reviewing code in its area. `/code-check` loads it in full.*

## Mechanisms
Fourteen shapes that keep producing bugs.

### A guard that fails toward pass
A check decides whether to do something consequential — cut a tag, run a migration, report a sweep clean.

### A fixture that cannot reach the failure mode
Hand-picked fixtures test the cases you thought of.

### A proxy is not the property
A condition that stands in for the thing you actually want.

### Verification that reads its own output
A check whose reference was produced by the thing it checks cannot disagree with it.

### A guard's scope, escape hatches, and remedies
Every guard grows the things that silently disable it.

### A fix lands in one of two callers that share a harness
Two entry points over one library, two workflows over one action, two scripts sourcing one shell lib.

### Restore the bug and prove the guard fires
A test that stays green against the code it was written to reject is decoration, and reading it will not tell you.

### A shared working tree, and what generators leave in it
A working tree has one checked-out branch.

### A wrapper's exit is not the work
A wrapper reports its own exit.

### Zero-length, empty, and unset are three different things
`paste0(character(0), "x")` is `"x"` — one phantom row from an empty frame.

### The probe is broken before the world is
When an ad-hoc probe reports that long-shipped code is broken, the prior belongs on the probe.

### Written data outlives the fix
Changing the writer changes nothing already written.

### Serialization loses meaning silently
Set `na=` and `null=` explicitly on every writer, because a serializer's default for no value is usually a valid-looking value (`"NA"`, `{}`, `'None'`) that every schema check accepts.

### One fact derived twice
A count taken from one artifact and the things counted produced from another, with a guard comparing the two.

## Rules that stand alone
General, and not an instance of a mechanism above.

### Do not edit files a long test run is reading
- `devtools::test()` (and most runners) load each test file **when they reach it**, not at launch.

### Test a persistent change through its per-process override first
A setting that is changed once and persists — `xcode-select -s`, a git config key, a registered default, an installed symlink — usually has an environment variable or flag that overrides it **for one process**.

### Adopting Existing Config
When importing config from one location into a canonical one (legacy `~/.bash_profile` → dotfiles repo, old script's env → repo, another project's `settings.json` → soul):

### Test the cold/create path of idempotent code, not just the warm no-op
- Idempotent provisioning code (a resolver-file writer, a config installer, a "create unless present" block) has two paths: the **cold** path that actually creates/writes, and the **warm** path that detects "already present" and skips.

### Fetch an expiring credential just before its first use, not at job start
Put the step that fetches short-lived credentials immediately before the first step that uses them.

### Do not write to an artifact a human is testing on
- Handing someone a deployed thing to test — a synced project, a staging database, a preview build — and then continuing to push changes into it makes two writers for one artifact.

### Percent-encode a URL at construction, not at consumption
- A URL built by string-concatenation from filenames inherits whatever those filenames contain.

### A preview flag is only safe if it previews
- `--dry-run`, `DRY=1`, `--plan` conventionally mean "show me what would happen".

### Bare `y`, `n`, `on`, `off`, `yes`, `no` are booleans in YAML 1.1
- The YAML 1.1 core schema resolves `y`, `Y`, `n`, `N`, `yes`, `no`, `on`, `off`, `true`, `false` (and their case variants) to **booleans**.

### Documentation Staleness
- Moving/renaming scripts: update CLAUDE.md, READMEs, usage comments

### An ordered dispatch makes severity ordering load-bearing, and nothing enforces it
A `CASE`, an `if/elif` chain, or any first-match dispatch that reports a *verdict* carries an unwritten invariant: every serious arm precedes every advisory one.

### A link to a repo-hosted artifact must be *tracked*, not merely present
When the published site **is** the repository — GitHub Pages serving `docs/`, or a `raw.githubusercontent.com` URL — the question "does this file exist" is the wrong predicate.

### An assertion that matches an interpolated value cannot see the claim around it
`expect_error(f(x), "some_column")` looks like it pins the guard.

### A pluralisation marker takes the quantity of whatever was substituted last
`cli`'s `{?a/b}` reads the most recent quantity in the string, and **any** substitution resets it — including a length-1 one that is not what the marker is about.

## Security

### Process Visibility
- Secrets passed as command-line args are visible in `ps aux`

### Secrets in Committed Files
- `.tfvars` must be gitignored (contains tokens, passwords)

### Firewall Defaults
- `0.0.0.0/0` for SSH is world-open — document if intentional

### Credentials
- Passwords with special chars (`'`, `"`, `$`, `!`) break naive shell quoting

### Gitleaks pre-commit hook
Configuration patterns and false-positive handling for the `gitleaks` pre-commit hook (kdot's Brewfile ships `gitleaks` + `pre-commit`; cyclops standardizes the hook):

### "Public bucket" ≠ listable: GetObject vs ListBucket
- A bucket policy granting only `s3:GetObject` on `bucket/*` makes exact-key fetches public but NOT listing — and dataset discovery (`arrow::open_dataset()`, duckdb globs, STAC `/vsicurl/` directory reads) requires `s3:ListBucket` on the **bucket ARN** (no `/*`; it's a bucket-level action).

## Spreadsheets and PDFs

### A stored value is not wrong just because the raw number looks wrong
Before reporting that a spreadsheet value is off by a factor, check the cell's **number format**.

### Verify PDF links from the annotations, not the extracted text
`pdftotext` returns anchor text, not the href.

### Extracted PDF text carries corrupted glyphs, and a tolerant parser turns them into wrong numbers
Never strip non-digits to clean a number extracted from PDF text: corrupted glyphs (an `O` for a `0`, a Private Use Area micron sign) become plausible wrong values, so anchor on the label and check against an independent identity.


# NGE Feature Workflow

For non-trivial issue-driven work, follow this checklist. Each step exists for a reason — skipping leads to rework, broken builds, and avoidable bugs that we've hit repeatedly.

## The Sequence

1. **Start with `/planning-init <N>`** — given an issue number, enters plan mode for codebase exploration, presents a phase breakdown for user approval, then scaffolds branch + PWF baseline with the approved phases. One command replaces the manual issue → explore → plan → branch → scaffold dance.
2. **Write robust tests first** — failing tests that reproduce the issue or document the new behavior. Tests are the contract; they fail until the work makes them pass.
3. **Name with intent** — functions, parameters, internal helpers carry the naming style of the package they live in. Look at existing exports as the guide; consistency over cleverness. For files rather than functions — shell scripts and operational R scripts under `scripts/` or `data-raw/` — the standard is the `noun_verb-detail` pattern in `newgraph.md`, noun first.
4. **Examples that run** — every exported function gets a runnable `@examples` block. Pkgdown renders them; CI executes them. An example that doesn't run is documentation rot.
5. **Code-check before each commit** — `/code-check` on staged diff. Catches what tests miss: edge cases, hard-coded paths, unguarded variables, security issues.
6. **Atomic commits** — each commit bundles code change + checkbox flip in `task_plan.md`. The diff and the progress live in the same commit; `git log -- planning/` tells the full story.
7. **`/planning-archive` when complete** — moves PWF to `archive/YYYY-MM-issue-N-slug/`, creates a fresh `active/`. Then `/gh-pr-push` opens the PR; `/gh-pr-merge` handles the release bookkeeping.

## Where the checkpoints are not

Step 1's plan approval is the authorization for every step after it. Run steps 2–7
through to the **open PR** without stopping to report between phases — the merge in
step 7 is outside the mandate unless the instruction includes it; put the decisions that
genuinely change what gets built at the plan gate, batched, with a recommendation
first; report once when the PR is open. The rule, its boundary (before a plan
exists, a question wants an answer) and its exceptions are `karpathy.md` §8.

## Re-read origin before you open the PR, not just before you cut the branch

Verifying local is current with origin (`code-check-shell.md`, "Before you *cut* a
branch") protects the branch point. It
says nothing about the build window, which is where a parallel session lands: measured
once, a second session filed, built and merged the same feature in 18 minutes, entirely
inside the first session's planning phase, and merged 15 seconds before its first
commit. Both sessions' pre-flight checks passed and both were correct when they ran; the
duplicate surfaced hours later as a version-bump conflict across eight files.

Before opening a PR, and again before merging:

```bash
git fetch -q origin
git log --oneline HEAD..origin/main          # what landed while you worked
git diff origin/main -- DESCRIPTION NEWS.md  # a version you did not bump
```

**A version bump you did not make is the tell**, and usually the only one — the tree is
clean, the branch is healthy, and nothing in git hints that someone solved your problem
an hour ago.

On a collision, do not resolve conflicts file by file. The merge conflict hides the
useful question, which is *which body of work survives*. Ask, then re-land the delta on
top of what shipped; two independent attempts at one problem are usually complementary
rather than redundant, and a mechanical resolution keeps whichever half git preferred.

## An issue number you did not file yet is somebody else's

GitHub allocates one sequence across issues **and** PRs, on creation. So a number
written down before the issue exists — a branch name, a code comment, a config header,
a commit trailer — is a reservation nobody honours, and in an active repo it will
eventually name a real issue about something else entirely.

That is the expensive direction. A number pointing at *nothing* is obvious; a number
pointing at a **stranger's issue** resolves, renders as a link, and reads as provenance.
Nothing downstream checks that the issue it names has anything to do with the code
beside it.

Measured 2026-09-08 in rtj. Work with no issue was branched as `322-sern-thompson-2026`
on a guess, and four `rtj#322` citations went into a `project.yml` header and two
shared-library comments. A parallel session then filed #322 — about a STAC registration
script. Every citation was wrong, all four looked fine, and the real issue for the work
(#319) went uncited until the merge.

- **Cite an issue only after it exists.** If the work has no issue and does not warrant
  one, write no number: a comment that explains itself is better than a wrong pointer.
- **Before merging, resolve every issue number the branch introduces** and check the
  title is about this work — one call, and it is the only thing that separates a good
  citation from a plausible one:

  ```bash
  git diff --stat origin/main...HEAD >/dev/null   # three-dot: the branch's own changes
  git diff origin/main...HEAD | grep -oE '(^\+.*)(rtj|rfp|gq|soul|link)#[0-9]+' \
    | grep -oE '[a-z_]+#[0-9]+' | sort -u
  # then, per hit:
  gh issue view <N> --repo NewGraphEnvironment/<repo> --json title -q .title
  ```

- **Name the branch for the work when there is no issue** (`sern-thompson-2026`), and
  rename it once one exists — `git branch -m` before the first push costs nothing.

Sibling of the section above: both are parallel sessions moving underneath work that
looked settled when it started.

## The version lives in one place

Do not restate the current version in `README.md` or `CLAUDE.md` prose. A version
string typed into prose drifts from the moment it is written — the release step
maintains `DESCRIPTION` and `NEWS.md`, and one report repo's
`CLAUDE.md` was found eight minor versions behind, its `README.md` one behind, with both
canonical files correct. Link to `NEWS.md` instead. Where a claim genuinely must stay in
prose, `/gh-pr-merge` step 7 greps for the previous version string outside the two
canonical files and updates the prose restatements it finds, reporting each.

## When to Skip

For one-line typo fixes, version-bump-only PRs, or trivial documentation edits, the full workflow is overhead. Use judgment. The threshold is roughly: **multi-step issue, multi-file change, or anything that requires scoping** → use the workflow.

## Skills That Slot In

- `/planning-init <N>` — start
- `/planning-update` — sync checkboxes mid-session
- `/code-check` — before every commit
- `/planning-archive` — when issue closes
- `/gh-pr-push` — open the PR
- `/gh-pr-merge` — merge with release bookkeeping

## Issue bodies get edited, not appended

When work changes what an issue should say, **edit the body**. Don't add a
comment that corrects it, and retitle when the scope moves.

**Why:** an issue is read as a spec by whoever picks it up. A body saying one
thing with a comment three screens down saying the opposite costs the reader the
reconciliation, every time.

**How to apply:** `gh issue view N --json body -q .body` into a file, revise,
`gh issue edit N --body-file`. Name what changed and why when the correction is
load-bearing — the goal is a body that reads correctly top to bottom, not an
erasure of history. Comments are for genuine commentary: a merge notice, a
cross-repo pointer, a question. Applies to PR bodies too. Commit messages are
immutable history and are never rewritten this way.

**The failure mode that keeps recurring: research findings feel like
commentary.** They are not — they are the spec. If a finding changes what
someone would *build*, it belongs in the body, with the durable version in
`research/` and the body linking to it. What `research/` holds, how a file is
named and what its header carries is `planning.md`, "`research/` — what is
known, outliving the issue that found it".

**Bodies drift at the moment work finishes, not while it is in flight.** Four
instances in a single day of rfp work, all of the same shape — the code learned
something and the issue did not:

| drift | what a reader saw |
|---|---|
| premise disproved by measurement | an issue arguing for a fix that was no longer needed |
| a conclusion asserted in the body but never landed in code | body and tree contradicting each other |
| the shape of the work moved during exploration | a spec describing a design nobody built |
| a decision made and shipped, body still listing options A–D | "decision needed" on a decision a year old |

Vigilance does not catch this, because the drift happens exactly when attention
moves to the merge. `/gh-pr-merge` reconciles at that moment — see its step 3b.

## Why This Exists

We've hit snags repeatedly when half-doing this — branches that mix concerns, tests bolted on after, code-check skipped (and then a bug ships in the diff), examples that fail in pkgdown. Each step is small; the cumulative reliability gain is real. The convention is here so it becomes the default expectation, not a thing the user has to remind every session about.


# LLM Behavioral Guidelines

<!-- Source: https://github.com/forrestchang/andrej-karpathy-skills/main/CLAUDE.md -->
<!-- Last synced: 2026-02-06 -->
<!-- These principles are hardcoded locally. We do not curl at deploy time. -->
<!-- Periodically check the source for meaningful updates. -->

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

Some rules here fence their citations in a `<!-- evidence -->` block, which a repo's
`CLAUDE.md` omits and `/code-check` reads in full. A new citation goes inside that
rule's block, creating one at the end of the rule if it has none; the remedy stays in
the rule. `code-check.md`'s header states the rule once, and
`skills/compact-prep/SKILL.md` step 5 carries the habit.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

## 5. You Have No Clock Between Tool Calls

**Every duration claim comes from `date`, never from how much waiting felt like
it happened.**

Background `sleep` returns immediately from the agent's side, and the number of
times you have polled is not evidence of elapsed time. Two consecutive tool
calls can be 15 seconds apart by the clock while feeling like ten minutes of
waiting.

The failure is stating it out loud before checking. Observed 2026-08: a CI run
was reported to the user as "pending for over an hour — unusually long, probably
a stuck runner", after roughly eight background sleeps. One `date -u` showed the
run was **three minutes old** and entirely normal. The whole diagnosis — stuck
runner, duplicate triggers, something wrong with the workflow — rested on a
duration that had been invented.

**How to apply:** before saying *any* duration — "still running after N
minutes", "this has been X a while", "longer than usual" — run `date -u` and
subtract a real start time. `gh run list --json createdAt` gives it for CI. If a
claim about slowness would change what the user does next, it needs a measured
number or it does not get made.

The same rule covers process state. `ps` and task-status listings have both been
observed wrong; check the artifact (an output file's size, its mtime, the
service's own API) rather than the wrapper.

### The same blind spot picks the wrong waiting tool

Not having a clock also makes a **chain of background sleeps** feel like
waiting when it is not. Observed 2026-08 on the same session as the above:
roughly a dozen `sleep 570; check` background tasks were spawned to wait out a
55-minute test suite and then CI. Two consecutive foreground checks printed the
*same minute* — no wall time had passed between them, because the sleeps run
detached and the polling happened around them rather than after them. Every one
of those tasks was waste, and killing them produced a batch of eleven
exit-code-144 notifications that read like failures.

Pick the instrument by how many answers you need:

| you need | use |
|---|---|
| one notification when a condition becomes true | `Bash(run_in_background)` with an `until` loop that exits |
| one per state change, ending on its own | `Monitor` with a command that emits and then exits |
| a value you must have before the next step | a **foreground** call, so the blocking is explicit |
| a long job that notifies when it exits | `Bash(run_in_background)` with the command as plain foreground text: no `&`, no `nohup` |

A repeated `sleep N; grep` is right in none of them. **Tell: if you are about to
spawn a second waiter for the same thing, the first one was the wrong shape.**

A `Monitor` filter must also match the failure states, not just the success
one — silence looks identical to "still running", so a watcher that greps only
for the happy path stays quiet through a crash.

**Never end a backgrounded call's command with a trailing `&`.** A trailing `&` (or
`nohup … &`) with nothing in the same command waiting on it, sent with `run_in_background`,
lets the wrapper exit at once, so the notification reports **exit 0** whatever the job
then does: once it killed the job, and in another session the job ran to completion. Either
way the notification says nothing about the job. Pick one mechanism from the table, never
two. A `&` whose job the same command goes on to wait for, as in `with_deadline()`
(`code-check-shell.md`), is not this, and nor is the `nohup … &` fix in that file's
"`&` binds to the whole `&&` list" rule when the call itself is not backgrounded.

*5 lines of evidence for this rule are in `conventions/karpathy.md`, which `/code-check` reads in full.*

### Don't edit files a long-running suite is still reading

`devtools::test()` and its equivalents load each test file **when they reach it**,
not at launch. A 30-minute run therefore reads whatever is on disk at that moment,
so edits made mid-run are half-applied and the result describes a tree that never
existed.

Cost two full Docker suites (~1 hour) on rfp#178, both reporting `FAIL 1`. The
failure was a test written *during* the run, executing against source from *before*
the fix that made it pass — nearly reported as a regression. **The tell is a moving
denominator:** 3490 passes, then 3496, then 3500, on "the same" tree.

Before a long run, commit. While it runs, do work that touches nothing it reads —
issue bodies, PR text, reading, planning. If an edit cannot wait, kill the run
rather than let it produce a result that has to be re-litigated. And when a long run
fails, get the `file:line` before forming any theory: a mid-flight edit and a real
regression look identical in a summary line.

**It is not only test runners.** `Rscript file.R` parses incrementally too, so editing
any long-running script mid-run resumes the parser at a byte offset into shifted
content. The tell is different and worse: a **syntax error quoting a line that does not
exist**, which reads as a defect in code that is fine. The moving-denominator tell above
needs two runs to see; this one arrives looking like an answer.

*6 lines of evidence for this rule are in `conventions/karpathy.md`, which `/code-check` reads in full.*

## 6. Subagents Are Evidence, Not Dependencies

**Spawn on your own judgment. Don't block on one. Don't trust its status. Verify its claims in both directions.**

### Spawning is your call, not the user's

Deciding to spawn a subagent is an engineering judgment, the same kind as choosing
to write a test or run a grep. **Do not ask permission for it.**

The user is usually not positioned to answer. Knowing whether a fan-out beats a
sequential read requires knowing the shape of the work — which you have and they do
not, so the question forces them to guess at a technical call. Under **Always Away**
it is worse than useless: the work stalls until they wake up, for an answer that was
yours to make. *"I wouldn't be in the know enough to know when that is"*
(airvine, 2026-08-27) is the whole problem in one line.

This does not soften §1's asks — *"if uncertain, ask"* and *"if something is unclear,
stop and ask"*. Those are about **what the user wants**: intent, scope, an ambiguous
requirement, a tradeoff only they can weigh. This is about **how you carry it out**.
Ask about intent; decide about mechanism. A question starting "should I use…" is
almost always the second kind, and almost always yours to answer.

#### Standing authorization: the harness bars the Agent tool by default on Opus 5

Sessions on Opus 5 carry a hardcoded instruction from the CLI itself —
*"Do not call the AgentTool unless the user requested it"* — alongside the same
line for workflows and deep-research. It is not a setting anyone here
misconfigured, and **it cannot be turned off locally**: the string is a literal in the
CLI bundle, gated by remote config. Nothing in `~/.claude/settings.json` reaches it, so
do not spend a turn looking there.

The symptom is a skill quietly doing less than it says: `/code-check` reporting
*"the subagent rounds did not run — your session instruction bars the Agent
tool"*, which is the review the command exists to perform. It reads as a
configuration problem, so the fix gets looked for in the wrong place.

**The clause is conditional, so this convention is the request.** Invoking a
skill that mandates subagents — `/code-check`'s three rounds, the Plan review in
`planning.md` — **is** the user requesting them. Spawn them. This paragraph is a
standing user instruction, written for exactly that purpose (airvine,
2026-08-29), and CLAUDE.md project instructions override default behaviour by
their own terms.

It authorizes the mandated spawns and nothing wider: the bounds in this section
still hold — two or three concurrent, about five per task, no fan-out from a
child — and a workflow or deep-research run fanning out dozens of agents remains
a spending decision that needs an explicit ask.

**Spawn without asking when:**

- A skill or convention mandates it — `/code-check`'s review rounds, the Plan review
  in `planning.md`. That decision is already made; re-asking it is friction carrying
  no information.
- You want fresh eyes on your own work. The mechanism and the measurements behind it
  are in `code-check/SKILL.md`.
- A sweep over many files will **locate** what matters faster than reading serially.
  The sweep finds candidates; it does not replace the read — `planning.md` is
  explicit that agents sometimes report existing files as absent, so read directly
  whatever you are going to act on.
- Independent items can run concurrently and nothing downstream needs them ordered.

**Do it yourself when:**

- One grep answers it.
- The work depends on conversation context a subagent will not have.
- You would sit idle waiting — spawn and keep working, or do it inline.

**Bounds and defaults you enforce yourself, rather than converting into questions:**

- **Two or three concurrent is the working default, and about five per task** is
  where spend stops being incidental. Concurrency and cumulative total are different
  quantities — `/code-check`'s three rounds plus a Plan review plus an ad-hoc sweep
  never exceeds three at once while spending well past a handful. Bound both.
- Past that total, **say so in your next message.** An escape you grant yourself
  silently is not a bound; it has to land in front of the user, after the fact.
- **Do not let a subagent fan out again.** Intent does not enforce this — the child
  decides what it calls — so use the structure: the `Explore` and `Plan` types are
  defined without the `Agent` tool and *cannot* spawn. `general-purpose` can, so when
  you use it (as `/code-check` does), put "do not spawn subagents" in the prompt. The
  one case on record (see "Don't block" below) never had a root cause established, which
  is exactly why this bound is structural rather than advisory.
- Unnamed, delivering by file — `planning.md` carries the mechanics.
- **Report after, not before.** Say what you spawned, and relay what it found (per
  `code-check/SKILL.md` — a subagent's report never reaches the user on its own). A
  user can object to a spawn that already happened; they cannot usefully approve one
  that has not.

**What is genuinely the user's call is budget, not mechanism.** A workflow or
deep-research run fanning out dozens of agents is a spending decision and needs an
explicit ask. Two or three reviewers is not — that is just doing the work.

The cost of a review is the visible half and the benefit is not. Two reviewers over one
conventions draft returned **20 findings** and caught **six** false factual claims in it.
None of that happens if the spawn waits on a user who is away.

*9 lines of evidence for this rule are in `conventions/karpathy.md`, which `/code-check` reads in full.*

### Don't block

Spawn a background subagent, then keep working on the lowest-risk part of the
task — scaffolding, data files, tests. When findings arrive, treat them as a
review of landed work rather than a precondition for starting it.

If a result genuinely must precede the next step, run it synchronously
(`run_in_background: false`) so the blocking is explicit and visible.

Three observed cases where waiting would have been the expensive choice:

- A research agent spawned 5 children and deadlocked for **~3 hours**, still
  reporting as "running". The user caught it, not the agent.
- A `Plan` agent asked to review a `task_plan.md` *before the baseline commit*
  returned after the issue was implemented, reviewed, merged and tagged.
- The same pattern on a later issue: findings arrived after all four phases had
  shipped. Because the work had not waited, this cost nothing — three findings
  were still new and landed as follow-up commits.

That last one is the shape to aim for. Concurrent review is not a degraded
version of blocking review; it is often better, because the reviewer reads real
code instead of a plan.

### Don't trust status

**Never report an agent as "still running" without evidence.** Agent status and
`TaskList` have both been observed to be wrong — `TaskList` reported "No tasks
found" for an agent that was alive and later replied. Check the output file's
mtime before claiming progress, and say what you checked.

**And never record a review as "Clean" on the strength of an idle notification.**
From the parent's side an idle ping is indistinguishable from an agent that had
nothing to say, so a lost review reads as a pass — a whole `/code-check` pass was once
reported as finding nothing while three reviews were stranded, one of which had found
a data-loss bug (measured 2026-08-25; the numbers are in `planning.md`, "Spawn review
agents UNNAMED"). Passing `name` turns a spawn into a persistent teammate that idles
instead of completing; pass it only for a collaborator you will keep messaging, and
shut it down when done. The rule that survives either spawn shape:
the reviewer **writes its findings to a file and reports only the path**, and a
missing or empty file means the round produced nothing and is re-run — never
"Clean". `planning.md` carries the mechanics; `code-check/SKILL.md` applies them.

### Verify claims, in both directions

Subagent output is evidence, not verdict. Both failure modes are real:

- **Acting on a wrong finding.** One labelled BLOCKER — "`glue()` will choke on
  the literal braces in this fragment" — was disproved by a 30-second probe,
  because glue does not re-parse interpolated values. Acting on it would have
  meant rewriting a working generator.
- **Dismissing a late review wholesale.** In that same review 2 of 9 findings
  were real, including a dead link. In a later one, a finding that a
  `path|layername=` check would delete KML/GPX layers was correct, and was
  confirmed against 207 real datasources before the fix landed.

The rule that separates them: **cheap probe first, then act.** Reproduce the
claim before you fix it, and before you dismiss it. A finding you cannot
reproduce is a finding you do not yet understand.

### Fan out inside one process

A workflow that shells out **once per item** costs one permission prompt per item,
unless the command happens to be allowlisted. The same work done **inside one
process** costs one prompt total, and nothing says so until the run is already
going. Measured 2026-09-04 (knowledge#4): a harvest script issuing two `curl` calls
per report inside each subagent meant hundreds of approvals across a run — the user
had flagged it as *"a big time suck last time"* without knowing the cause — while a
sibling script doing the same fetch-download-upload work with Python `urllib` in a
single process cost **one** prompt for the entire run. Same task, same volume, three
orders of magnitude apart in interruptions.

It breaks **Always Away** directly: an unattended run that stops for approval on item
3 of 200 has not failed loudly, it has gone idle, and the wrapper reports nothing.

- **Prefer one process doing N items over N processes doing one.** Loop inside the
  language runtime; shell out once, for the batch.
- Where a per-item subprocess is genuinely required, allowlist its command **before**
  the run, not one refusal at a time during it — the allowlist fixes the commands you
  predicted, and the one that blocks is the one you did not.
- Diagnostic: if a run keeps stopping for approval, look at whether the loop sits
  inside or outside the process boundary before adding allowlist entries.

---

## 7. Evidence, Not Impressions

**Measure before you characterise. Presence is not provenance. "Unknowable" is a
claim.**

Six principles that all fail the same way: something *feels* established — because
it is visible, because it is present, because someone said so — and gets offered
with the confidence of a measurement.

### Measure before you characterise

When a decision turns on **what something contains**, open it and count. Do not
describe it from its structure, from an issue's claim about it, or from a tag list.
A heading tells you a thing is *present*, never that it is *populated* — an empty
`<conditionalstyles/>` and one with rules look identical in a list of child names.

Four instances in one rfp session, each corrected by the user's follow-up question
rather than by review: a tradeoff described as three times its real size; an issue's
stale claim repeated as current; an installed version reported as sixteen releases
behind when a parallel session had updated it eighteen minutes earlier; and "nothing
on main addresses this" from a local `main` three commits behind — one `git fetch`
away from the truth.

**A measurement carries the time it was taken.** One made earlier in the same
session is not a current one, least of all for anything another session can change
underneath it. For anything git-backed, `git fetch` first: reading a local clone and
reporting it as the state of the world is the same error with a longer fuse.

**And before hand-rolling a parser for a probe, check whether the code already has
one.** A bespoke parser silently narrows the population it can see, and the result
looks like a measurement rather than a sample — worse than not measuring, because it
carries a number. Measured 10 of 80 with a hand-written matcher; routed through the
package's own resolver it was 14 of 117.

### Presence is not provenance

When something's **presence** is offered as evidence for **how it got there**, find
the fact that actually discriminates. A QGIS project's `3.30.1` stamp was offered as
evidence a desktop had opened it — but the template it was copied from carries that
stamp, so a never-opened project reads the same. What actually proved it was a
tracking key the template does not contain.

The tell: reaching for the *most visible* fact rather than the *discriminating* one,
because the visible fact is consistent with the conclusion. **Consistency is not
support.** Before offering "X shows Y", ask what else would produce X. If anything
would, X is not evidence.

When the user pushes back on an inference, re-derive rather than defend. The
conclusion often survives; the reasoning that reaches it is usually different.

*5 lines of evidence for this rule are in `conventions/karpathy.md`, which `/code-check` reads in full.*

### Documents that share an ancestor corroborate nothing

Sibling of the rule above, one level out: there a *fact* was consistent with the
conclusion, here several *documents* are. Finding the same claim in three places
feels like triangulation and is not — if one was written from another, they are one
source wearing three hats, and the agreement is a copy, not a confirmation.

**The tell is agreement with no independent derivation.** Ask of each restatement:
what did its author read? If the answer is "one of the others", the count is one.
Prose repeats; code does not, so the discriminating check is almost always to read
the thing the prose describes.

**The release note is where this costs the most, because its readers cannot check it.**
Where a release note is written from the issue rather than from the artifact, its numbers
have been copied rather than derived, and no reader is positioned to notice.

Five habits:

- **Derive every number in a release note from the artifact it describes**, at the moment you
  write it. Not from the issue, not from the last release's notes, not from memory.
- **For any sentence of the form "you can tell X by looking at Y", check that Y actually
  separates X from not-X.** A discriminator that fires on everything discriminates nothing,
  and it reads as helpful right up until someone relies on it. A checksum over a re-encoded
  artifact is the standing example: it answers "are my bytes current" and can never answer
  "did the values change".
- **A carve-out is a number too, and reasoning one from the shape of a literal understates
  it.** Run the check over the population before writing the exception. A literal naming two
  excluded items does not mean every other input is covered: it names *two*, so a one-item
  tree is always missing at least one of them — including each of those two, which are
  missing each other — and the coverage is **zero for every one-item tree**, not merely
  capable of being zero. That error runs in the direction that understates the reach of a
  defect, in the document a reader uses to decide whether to backport.
- **When a document states a quantity or a scope, read the code that produces it
  before repeating it.** Especially a status section — it describes a moment, and
  nothing fails when the moment passes.
- **When you find one instance stale, grep for the sentence, not the file.** A claim that
  sits in three documents is not fixed by repairing the one that was quoted; the other two
  still read as authoritative.

*31 lines of evidence for this rule are in `conventions/karpathy.md`, which `/code-check` reads in full.*

### "It can only be answered by testing" is a claim with an author

An issue or a colleague saying a question needs a field season, a device or a deploy
is stating a claim, not a property of the problem. Spend the cheap probe first.

rfp#186 opened with "three questions decide whether this is viable, and none can be
answered by reading." Two fell in about twenty minutes — one to reading a call
graph, one to re-reading a file already on disk — turning "run a field season, then
decide what to build" into "build it, then confirm one thing."

The claim is usually made by someone who knows the domain, at a moment before they
looked. Not wrong so much as **unexamined**, which is what lets it survive into the
plan. Then **bound what the probe closed**: reading a desktop plugin says nothing
about the mobile app. An over-claimed probe is worse than none.

### A real bug is not necessarily the reported bug

A defect found while investigating a symptom is **evidence, not the answer**. Before
offering it as the cause, check that it produces *exactly* the symptom described,
including the details that sound incidental.

Two confident wrong causes in a row on rfp#196 — a layer missing from a map theme
(a real bug, fixed) and a sub-pixel geometry (a real measurement). Both true;
neither explained the report. The actual cause was draw order, and the user named it
himself. The discriminating fact was in his words all along: *"as soon as I stop
tracking I can't see the track"* rules out both theories in one line.

Finding a genuine defect feels like finding *the* defect — the relief of having an
explanation is what stops the check. Write the reported symptom out and ask whether
the proposed cause produces **all** of it. Say which parts are still unexplained:
"this is a real bug and it may not be your bug" is honest and cheap.

### An enumeration is not a checklist

A probe listing what exists — subkeys present, columns found, files listed — answers
"what is here", never "what do we want". Scope arriving this way looks
evidence-backed, so it survives review.

On rfp#68, "the two Mergin subkeys that exist" became "the settings to verify",
then an item on a field checklist a human had to walk outdoors to complete. Nothing
in the codebase read or wrote `PhotoNaming`. Before a probe's output becomes work,
grep for each item and ask whether anything consumes it. When it duplicates
something already done another way, name the comparison — the existing approach
usually wins for a reason worth stating.


### A relative descriptor is meaningless without its anchor

"Upstream", "downstream", "above", "below", "before", "after", "parent" — each is
relative to something named **elsewhere in the document**, often paragraphs away and
sometimes only in a table. Resolve the anchor before drawing any inference from the
term.

Getting it wrong does not produce uncertainty, it produces a confident and specific
wrong answer — and it fails in the worst direction, because you now believe you have
*evidence* against a claim rather than merely lacking evidence for it.

Measured 2026-09-02. A field report read *"downstream sampling confirmed the presence
of coho"*. Taken as downstream of the crossing under discussion, it appeared to
disprove the user's recollection that coho were present above that crossing. The
sampling site was actually at a road crossing 1.5 km further up the stream, so its
"downstream" was still **1.1 km above** the crossing in question — the claim was true
and the correction nearly removed it from an email to the infrastructure owner, on the
one point the email existed to make.

**Where a source describes a sequence — crossings on a stream, releases in a
changelog, stages in a pipeline, commits on a branch — write the order out before
interpreting a single relative term in it.** The ordering is usually one sentence in
the source and takes seconds to find; the inference built on the wrong anchor survives
every later check, because nothing downstream re-examines it.


### A safeguard whose mechanism is a human reading a diff is not a control

When a design says "the writes are uncommitted, so the diff is the review", check
whether anyone reads diffs. Here nobody does — the user says "commit" without opening
one, stated plainly and confirmed 2026-08-28 — so every per-action confirmation loop
built on that premise was latency wearing the costume of a control. Two skills had one.

Gate on **blast radius** instead, because that fires without anyone reading anything: a
write that reaches one repo just happens; a write that reaches every repo (a soul
convention) may be appended to freely but edited or removed only through an issue. Where
a real check is needed, make it mechanical — a grep for a contradicting rule, an
assertion that nothing above the `CLAUDE.md` marker moved, a guard that resolves every
heading against a base SHA. Those are the controls; a prompt is not.

The user still wants a short, honest account of what was written. That is a report, not a
review, and confusing the two is how the loops got built.

### Not finding it is not evidence it does not exist

Before building a fetcher, harvester, backup or sourcing routine, **search the sibling
packages for the verb**. One command, and it is the difference between adding a function
and adding a second copy of one.

```bash
# Enumerate the org's installed packages rather than listing them: a hardcoded list
# named four packages; thirteen other org packages were installed on the machine this
# was measured on (2026-09-05), and the gap will grow again. Match
# on any URL-ish field, case-insensitively: RemoteUsername is set only by GitHub
# installs (a package installed from a local checkout has none) and the org name is
# not always cased the same. Forks of upstream packages come along; that is fine.
# `collapse` matters: paste() over fields that are all NULL is character(0), and
# `if` on a zero-length grepl() aborts the whole enumeration (measured, soul#171).
for p in $(Rscript -e 'for (p in rownames(installed.packages())) {
  d <- packageDescription(p)
  u <- paste(c(d$URL, d$BugReports, d$RemoteUrl, d$RemoteUsername), collapse = " ")
  if (grepl("newgraphenvironment", u, ignore.case = TRUE)) cat(p, "\n") }'); do
  echo "== $p"; grep -E "^export" "$(Rscript -e "cat(system.file(package='$p'))")/NAMESPACE" \
    | grep -iE "source|fetch|harvest|backup|manifest|download|ingest|store|snapshot|read|write|conform"
done
ls ~/Projects/repo/rtj/scripts/gis/     # operational drivers live here, not in a package
```

**Then read the README ownership table and the above-marker `CLAUDE.md` of any package
plausibly adjacent — exports understate remit.** A package README can state a remit no
export names: that it exists so a report does not have to harvest its own copy, that it
pins per-snapshot sources, schema, md5 and row count. The grep finds functions; the README
is the load-bearing artifact, and it is the one nothing prompts you to open.

The failure is not carelessness — it is that **a decision is invisible from where the work
is happening**. The tool exists, is correct, and is three repos away in a directory you had
no reason to open. So the path of least resistance builds it again, and the duplicate is
plausible precisely because the original was never visible.

**Tell:** you are about to write something whose name is a verb the ecosystem already does
somewhere. Fetch, sync, harvest, backup, source, register, publish.

Two corollaries worth holding:

- **A function existing in two places is worse than it existing in neither.** Two live
  copies drift silently, and the drift is invisible until someone has both installed.
- **Check what the *architecture* says, not just what exists.** Not every instance is
  duplicate code; a wrong-home *proposal* is the same failure, and an issue that already
  assigned the boundary settles it for less than arguing from first principles costs.

Sibling of *"An inventory is only complete relative to a boundary"* in `code-check.md`, one
step earlier: that one is about a search that was complete for the wrong scope, this is
about never having searched the scope where the answer lived.

*25 lines of evidence for this rule are in `conventions/karpathy.md`, which `/code-check` reads in full.*

#### The storage version: one store is not the world

The same error with buckets instead of packages. The shape is a single negative check
reported as a fact.

The most general case: **`aws s3` and `s3cmd` address different clouds and are invisible to
each other.** A repo whose backup script uses `s3cmd` has stores that no `aws s3 ls` will
ever list, so "I checked S3" is not a statement about where the data is.

Two habits, each one command:

- **Enumerate the stores before searching them.** `s3cmd ls` and `aws s3 ls` with no
  argument each list only their own provider's buckets; the backup script names the rest.
- **Prefer the definition to the artifact.** The job that stages data says what exists; a
  bucket only shows what some past run happened to leave.

A negative result is only ever as wide as the store you looked in. Stating it without that
qualifier is how a gap in your own search becomes a fact in an issue body.

And the same shape once more for **checkouts**: a `grep` across `~/Projects/repo` searches
the repos this machine happens to have, not the ecosystem. Repos are cloned per-machine and
the set differs between them, so a local grep that returns clean has answered a question
about this disk. Use `gh api -X GET search/code -f q="org:NewGraphEnvironment <term>"`,
and note it indexes **default branches only**, so a file on a feature branch is invisible to it
and needs `gh api repos/<owner>/<repo>/contents/<path>?ref=<branch>`.

*12 lines of evidence for this rule are in `conventions/karpathy.md`, which `/code-check` reads in full.*

## 8. Decisions Up Front, Then Run

**Ask at the plan gate. After approval, run to the PR. Before a plan exists, a question wants an answer.**

The first three subsections are one rule on one axis — *when* to come back to the
user — and they are only correct as a set; each was learned separately in a different
repo and re-derived, usually by getting one of them wrong first. The rest are
handover rules that belong beside them because they decide what the user is handed
when you do come back.

### After plan approval, run every phase to the PR

Plan approval is the authorization for every mechanical step after it. Run every
phase, commit atomically per phase, archive the PWF, push, open the PR, and report
**once**, at the end. Do not stop between phases to report progress: the decisions
that needed the user were taken at the gate, and a check-in that only reports
spends attention already committed. Under **Always Away** the cautious answer is the
wrong one — the work stalls on a question the user answered by approving the plan.

The instruction arrives as one short message covering many commits, reviews and
repos: *"Go all phases to PR"* (airvine). **The merge is a separate instruction** — *to the PR*
ends at the open PR, and `/gh-pr-merge` runs when the user invokes it or the
instruction says so.

Two things are inside the mandate; these are not:

- **Correcting the plan is inside it.** A review that disproves an approved design
  decision gets fixed mid-run and reported in the summary; that is the run working,
  not a reason to stop — unless the correction is itself a fork of the kind below (a
  key, an identifier, a schema), which goes back to the user. Blockers that cannot be resolved are filed as issues and
  named in the final report rather than held open.
- **Our own repos are inside it.** Filing issues, opening PRs and editing bodies in
  NGE repos is normal work.
- **Outward-facing actions are not** — see "Never post outside our own repos" below.
  Neither is anything a convention names as its own gate: the merge (airvine, 2026-09-05;
  `gh-pr-push/SKILL.md`, "Ask user before merging"), a change to the machine
  (`newgraph.md`, "State the plan before changing the machine"), or a push into an
  artifact a human is testing on (`code-check.md`). A push to the feature branch is
  inside the mandate.

*7 lines of evidence for this rule are in `conventions/karpathy.md`, which `/code-check` reads in full.*

### Before a plan exists, a question wants an answer

The same terseness that means "go" after approval means "answer me" before it. A
turn that ends in a question mark, with no approved plan, gets an answer and a
one-line offer of the work — not the first commit toward it. Twice in one day
(floodplains, 2026-09-02) a question was read as approval and editing started — once
after *"why not fix before publish?"*, and once after a gap had been explained, stopped
with *"do not take on 70. i want to understand"*. When the ask is to understand something, keep it short and concrete; a
worked example beats a taxonomy. *"small answers here"*, *"keep it short"* (airvine).

This is the boundary condition on the rule above, which is why they are one section:
a standing mandate to run autonomously, stated alone, is exactly what reads every
terse message as "go". **The mandate starts at plan approval.**

### What still interrupts, and where it goes

A decision that permanently shapes stored data — a key, an identifier, a schema
choice, a deprecation shim versus a hard rename — is the user's, and it goes to the
**plan gate**, batched, as two or three concrete options with the recommended one
first and the consequence stated. Two such forks put at one gate (flooded#47) were
both load-bearing and neither was derivable from the issue: the rename would also
have broken a production driver in another repo, which only the sweep surfaced.
Asked at the gate a fork costs one round-trip and buys the whole run; discovered
mid-execution it costs a stall with nobody there to answer it. Found mid-run, it is
still not the agent's to decide: ask it the same way — options, recommendation first,
phone-answerable — commit, and continue on the phases that do not depend on it while
the answer is outstanding (`planning.md`, "When Something Keeps Failing" — escalating
is not stopping).

During plan-mode exploration, keep a list of "this changes what I build" forks and
ask them together before `ExitPlanMode`. Questions are welcome; status updates are
not. Mechanism — whether to spawn reviewers, which regex, how to build a fixture — is
never a question (§6, "Spawning is your call"), and anything with a conventional
default is not one either: pick it, say so, move on.

### Never post outside our own repos without approval

Never post to a venue outside NGE's own repositories without the user's explicit
approval for that specific post — upstream GitHub issues and PR comments, mailing
lists, forums, third-party trackers. **Drafting is welcome and expected**: write the
comment, show it, wait. It is the sending that needs the word. *"Never post things
upstream without my explicit approval"* (airvine, 2026-09-02, after an offer to draft
comments on two of a vendor's upstream issues).

**Why:** an upstream comment is published under the organisation's name to a venue we
do not control, is indexed immediately, and cannot be unpublished. It is a
communications act, not an engineering one, and the judgement about tone, timing and
what we are willing to say in public is the user's.

- Our own repos are unaffected; filing and editing issues there is the standing
  disposition and needs no asking.
- **Reading upstream is unrestricted and worth doing.** Checking issue state before
  filing ours has caught a wrong citation in our own roxygen and found an upstream
  issue already proposing the feature we were about to request.
- Offer the draft in the reply, not as a fait accompli, and say plainly that nothing
  has been posted when the work obviously produced something postable.

### Hand the user bare commands

When the user must run a command themselves — an interactive login, a
sudo-needs-TTY operation, anything the Bash tool is blocked from running — give the
**bare command**, in a fenced block, ready to paste. Never prefix it with `!`.
*"Give me the cmd without the ! - that never works btw"* (airvine, 2026-08-21);
*"stop giving me the ! at the start. that doesn't work. i need the raw cmd"* (`cd`, 2026-08).

**Why, twice over.** Default session guidance proposes the `!` prefix as a way to run
a command in-session, so this recurs in every repo unless written down. On this
operator's terminals it either does not run at all, or — where it does — **it ran from
`$HOME` rather than the session's working directory** (one measurement, 2026-09-02), so a
handed-over relative path created the file somewhere nobody was looking. Absolute paths are right whichever
directory it resolves against. So:

- Emit the command plain. Applies to fenced blocks and inline commands alike.
- **Absolute paths** in any handed-over command that touches files
  (`~/Projects/repo/<repo>/…`), whichever form the user ends up running it in.
- Keep it paste-safe: prefer `grep`/`awk` over a nested `python3 -c "…"` inside a
  single-quoted remote command, so the quoting survives the trip.

**A file under `~/Downloads` is unreadable by the agent process, and no retry helps.**
`Read`, `cp` and `pdftotext` on `~/Downloads/*` all fail with `Operation not permitted`.
It is macOS folder protection (TCC) on the process, not a Claude Code permission mode, so
`/permissions` does not change it; Desktop and Documents behave the same. Do not retry
variants — ask for **one** copy into the repo, with absolute source and destination paths,
then continue from the copy. (Granting the terminal app Full Disk Access removes it on one
machine; the fallback stays for the next machine.)

*4 lines of evidence for this rule are in `conventions/karpathy.md`, which `/code-check` reads in full.*

### Link every issue and PR you name to the user

When a message to the user names an issue or a PR, make the number a link the user can
click: `[soul#191](https://github.com/NewGraphEnvironment/soul/issues/191)`,
`[soul PR #192](https://github.com/NewGraphEnvironment/soul/pull/192)`. Terminal output
renders markdown, so a bare `#191` costs the user a browser, a repo, and a click through
several pages to learn what it was — for every number in a report that may carry a
dozen. *"want to be able to follow up without opening new browser and clicking through
mult pages to find"* (airvine, 2026-09-05).

- **Issues under `/issues/N`, pull requests under `/pull/N`.** They are different paths,
  and the type is not always obvious from a number. When unsure, ask `gh` rather than
  guess — it returns the canonical URL for either:
  ```bash
  gh issue view 192 --repo NewGraphEnvironment/soul --json url -q .url \
    || gh pr view 192 --repo NewGraphEnvironment/soul --json url -q .url
  ```
- **Cross-repo references carry the repo**: `rfp#268`, never a bare `#268` from inside
  soul.
- **A bare `#N` is not ambiguous — it is a working link to the wrong repo.** The host
  resolves it against the session's own repo, so a bare number in a discussion *about* a
  different repo silently retargets, and the wrong repo's issue of that number can be close
  enough in subject to read as correct. Naming the collision in prose afterwards does not
  fix it; the link has to be re-qualified.
- **Spot-check a subset, not every link.** Before sending a report with many numbers,
  resolve two or three through `gh` — the ones you typed from memory or whose type you
  inferred — and let the rest ride. Checking all of them would slow every message; checking
  none is how a wrong repo or an issue-path link to a PR ships.
- **Scope is messages to the user** — terminal replies, the compact-prep report, PR and
  issue bodies where a reader lands from outside the repo. Commit messages and issue bodies
  read *on* GitHub autolink `#N` already; do not bloat those.

*5 lines of evidence for this rule are in `conventions/karpathy.md`, which `/code-check` reads in full.*

### Surface upstream defects; do not work around them

When a dependency or an external API misbehaves, surface it and ask rather than
coding around it. *"dont' do workarounds for things like zotero api problems. surface
and ask as there may be simple solution"* (airvine, 2026-09-03).

**Why:** a workaround hides the defect from whoever could fix it properly, and the user
often has upstream context or a simple fix the session lacks. Most of the dependencies
in question are **first-party** — an upstream bug is usually ours — so a local patch
is strictly worse than an issue: it leaves the bug in place for every other consumer
while making this repo look fine. Same instinct as `newgraph.md`'s "install missing
packages, don't workaround", applied to a *broken* dependency rather than a *missing*
one.

**How to apply:** reproduce it minimally, file an issue in the owning repo with the
repro and the exact lines, report it, and carry on if it is not blocking. The rule is
*do not hide it*, not *do not continue*: the day it was recorded, a search function
failed on a list column and broke a documented pipeline step; the local guard would
have taken minutes and hidden a bug affecting every consumer, so it was filed with a
three-line repro and the pipeline continued, since its data path did not use search.

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.


# Planning Conventions

How Claude manages structured planning for complex tasks using planning-with-files (PWF).

## When to Plan

Use PWF when a task has multiple phases, requires research, or involves more than ~5 tool calls. Triggers:
- User says "let's plan this", "plan mode", "use planning", or invokes `/planning-init`
- Complex issue work begins (multi-step, uncertain approach)
- Claude judges the task warrants structured tracking

Skip planning for single-file edits, quick fixes, or tasks with obvious next steps.

## The Workflow

1. **Explore first** — Enter plan mode (read-only). Read code, trace paths, understand the problem before proposing anything. When the work codifies a pattern that already exists in multiple places (reference implementations across repos), read **every** reference in full, not just the canonical one — variation across references surfaces patches before v0.1 instead of as churn later (soul#52: reading all 4 references preempted 5 of the 7 fixes a dry-run would have found). Don't substitute Explore-agent summaries for direct reads; agents sometimes report existing files as absent.
2. **Plan to files** — Write the plan into 3 files in `planning/active/`:
   - `task_plan.md` — Phases with checkbox tasks
   - `findings.md` — Research, discoveries, technical analysis
   - `progress.md` — Session log with timestamps and commit refs
3. **Plan-review with the Plan agent — concurrently, not as a gate** — Once `task_plan.md` is scaffolded, spawn the Plan subagent (`Agent({subagent_type: "Plan", prompt: "..."}`) and ask it to critically review the task_plan against the issue body + actual codebase. Categorize findings as Blocker / Gap / Ordering / Assumption / Scope / Acceptance. The agent reads files fresh — it catches what you miss when you've been thinking about the design too long. Real example: caught 21 issues including hardcoded literals across 4 files not listed in the plan, untested DB column mismatches, and a baseline-cache-shadow that would have produced a 6-second no-op run.

   **Do not wait for it.** Spawn, then start the lowest-risk phase. Background agents have repeatedly returned late — in one case after the entire issue had shipped — so treating the review as a precondition stalls the work for as long as the agent takes (see `karpathy.md` §6). Fold findings in whenever they land: pre-baseline they edit the plan; mid-implementation they become follow-up commits — unless the finding is a stored-data fork of the kind `karpathy.md` §8 reserves for the user. A review that arrives after the code is written is not wasted — the reviewer reads real code instead of a plan, which is how one late review still contributed three fixes that no earlier reading had found. If you genuinely cannot proceed without the result, run it with `run_in_background: false` so the blocking is explicit.

   Verify before acting, in both directions. Findings have been confidently wrong (a "BLOCKER" disproved by a 30-second probe) and confidently right about things nobody suspected. Reproduce the claim first.

   **"Both directions" includes the reviewer's conclusions, not just its findings.**
   A review is wrong in the *alarming* direction loudly — a BLOCKER you probe and
   disprove costs one round-trip. It is wrong in the *reassuring* direction
   silently, because nothing prompts you to check a sentence telling you that you
   are finished. Measured 2026-08-30 in gq#77: round 4 fixed its own finding and
   characterised the residual as "definitional". Two commands showed it was not —
   the leftover axis had exactly one member and no margin, the same shape as the
   instance that reviewer had just fixed. Treat *"this is now terminal / complete /
   definitional"* as a claim with an author, exactly like an issue asserting a
   question can only be answered by testing.

   Corollary on when to stop: **convergence is not a reviewer saying you have
   converged.** Across four rounds on that PR, five instances of one defect class
   were found, and three separate "this is terminal now" claims — two of them mine
   — were wrong. What ended it was enumerating the complete candidate set and
   showing nothing sat above its source, not another round.

   **Spawn review agents UNNAMED.** Passing `name` to the `Agent` tool changes what you get: a named spawn becomes a persistent *teammate* that goes **idle** rather than completing, so there is no final report to auto-deliver and its output must be pulled with `SendMessage`. An unnamed spawn is a fire-and-return subagent whose report arrives on its own in the completion notification. Measured 2026-08-25 on one machine, one session, unchanged settings: the unnamed spawn returned in **6.4s**; three named reviewers returned nothing at all, sending only empty idle pings. Pass `name` only for a collaborator you intend to keep messaging, and shut it down when done — it pings indefinitely otherwise.

   That mis-spawn is what produced the silent-delivery failures below, so check `name` before suspecting settings. Teammate mode (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` + `teammateMode`, merged globally from `soul/settings/defaults.json`) shapes what a *named* spawn becomes; it is not by itself why findings go missing, and an unnamed spawn delivers fine with it enabled.

   **Get the findings into a file — but check who is doing the writing.** Message delivery has silently failed twice: one review arrived as idle notifications with no content, and one was routed to a different session on the user's phone, surfacing only because the user mentioned it. From this side an idle ping is indistinguishable from an agent that had nothing to say, so the loss is invisible. A file (`planning/active/review-<N>.md`) survives routing, survives the agent exiting, and is greppable later.

   **The `Plan` and `Explore` agent types have no Write tool, so they cannot write that file.** Both plan reviews on 2026-08-26 (gq#61, gq#40) were instructed to and were structurally unable to; one said so outright — *"I have no Write/Edit tools and am explicitly barred from creating files; an agent instruction can't lift that"* — and returned the full review as reply text instead. Both arrived intact, ~26 findings each. So:

   - **Read-only agent** (`Plan`, `Explore`): ask for the findings **in the reply**, then write them to `planning/active/review-<N>.md` yourself. The file is still the deliverable; you are just the one creating it.
   - **Agent type that can write**: put the file-path instruction in the first prompt, not as a follow-up.

   Asking for a file the agent cannot produce costs a round-trip, and — worse — sets you up to read an absent file as an absent review. Check the agent type's tools before writing the instruction.

   **A reviewer asked to prove a guard fires will patch your working tree, and that races
   your own test runs.** "Restore the defect and watch it go red" is the right instruction
   (`code-check.md`), and a subagent given it edits the same files the parent is testing.
   From the parent's side the result is a test run that reports failures belonging to
   nobody's code — the reviewer's planted defect, caught mid-flight. Tell reviewers to work
   in a copy (`cp -r` to a temp dir, or a worktree) and say so in the prompt; they honour it
   when asked. Then snapshot the files you care about and `cmp` them before **and after**
   every run whose result you intend to act on, so "the tree was intact for this
   measurement" is a fact rather than an assumption. Same hazard as a mid-flight edit in
   `karpathy.md` §5, arriving from an agent instead of from you.

   **Review the fixes, not just the code.** The second pass is where the value concentrates, because a fix written under a wrong assumption reproduces the same defect. Measured on gq#52: pass 1 found 13 defects, pass 2 found 7 more — including a blocker sitting *inside the fix* for pass 1's blocker, the same class twice (`lty`, then `fill_alpha`) because completeness was reasoned about rather than computed. Pass 3, scoped narrowly to the file edited most, found no new instances; **convergence is the signal to stop, not a fixed number of rounds.**

   Convergence is measured, not felt — a quiet round and an exhausted reviewer look
   identical. The rule that terminated trap#28 (five rounds; each of the first four
   found its best defect *inside the previous round's fix*) was to **enumerate the
   candidate set mechanically and show nothing sits above its source of truth**: parse
   the files and walk every `cli_abort`/`warning`/`stop` rather than recalling them, so
   "all of them are pinned" is a count. For the guards a fix introduced, the equivalent
   instrument is a mutation table (`code-check.md`, "Restore the bug and prove the guard
   fires"). `code-check.md` states the enumeration rule under "A guard's
   scope, escape hatches, and remedies" — terminate by enumeration, not by a reviewer
   saying you have converged. `/code-check` treats three rounds as the floor and keeps
   going while a round finds a defect inside the previous fix.

   Ask for the **mechanism**, not more instances. Pass 3's best finding was that an invariant was enforced by two lists happening to agree — which is what had produced instances two and three.

   The thing reviewers catch that self-probing does not is **interop**: 18 tests inspected a legend object and none handed it to the renderer, which rejected it outright. Ask the consumer.
4. **Lock naming before the baseline** — If naming feedback surfaces during planning (legacy filename, inconsistency with an existing file family), fold the rename into the convention + task_plan BEFORE the baseline commit, not as a follow-up. Pre-baseline it's free; retrofitting after implementation cascades (soul#52: `build_exec_pdf.R` → `run_pagedown_exec_summary.R` locked in pre-baseline meant zero downstream rework).
5. **Commit the plan** — After Plan-agent review + fixes. This is the baseline.
6. **Work in atomic commits** — Each commit bundles code changes WITH checkbox updates in the planning files. The diff shows both what was done and the checkbox marking it done.
7. **Code check before commit** — Run `/code-check` on staged diffs before committing. Don't mark a task done until the diff passes review.
8. **Archive when complete** — Move `planning/active/` to `planning/archive/` via `/planning-archive`. Write a README.md in the archive directory with a one-paragraph outcome summary and closing commit/PR ref — future sessions scan these to catch up fast. Where the work produced measurements, that README is also the evidence record; see below.

## The archive README is the measurement record

Debugging and benchmarking sessions are systematic investigation: a stated unknown, an
experiment, a number, a conclusion, and usually two or three informative dead ends. That
is SRED evidence, and it scatters — into PR bodies, issue comments, and log files whose
names encode a timestamp and nothing else. In six months the chain *we did not know X,
we measured Y, therefore Z* survives only in a chat transcript.

**The archive README is where that chain lives.** Not a separate run record: the PWF
triple already holds every part of it — the question in `task_plan.md`'s frame, the
method in `progress.md`, the numbers in `findings.md`, the dead ends in its "Errors
Encountered" table. A second document would restate all of it and be half-populated.
The README is the index over them.

So an archive README for work that produced measurements carries two more sections:

```markdown
## Measurement

m1 0.0391 vs cypher 0.0872 min/1k segments — hosts are 2.23x apart.
Moved the provincial estimate 5.0 h -> 4.3 h and changed how work packs across machines.

## Evidence

`data-raw/logs/study_area_run/20260831_19*` — four spins, one defect each.
```

Three rules on those sections:

- **Numbers carry units, and say what changed because of them.** A measurement nobody
  acted on is still worth recording if it turned an assumption into a number — say that
  too. "Confirmed the expected" is a real outcome.
- **Cite a prefix or glob, never a file list.** A list rots the moment a run is re-run;
  a prefix survives. This is why campaign subdirectories exist (`newgraph.md`, "Which
  logs to commit").
- **Keep the wrong turns.** A diagnosis made, retracted on a bad inference, then
  confirmed by measurement *is* the evidence of systematic investigation. Sanitising it
  into a tidy conclusion destroys exactly what makes the record worth keeping.

**The case this does not cover.** Measurement that predates an issue has no PWF to
attach to — `/planning-init` takes an issue number, and exploratory runs often *produce*
the issues rather than follow them. That measurement belongs in the issue or PR it
spawned, with the log directory's own README as the index. Do not build a third system
to close this gap. The *finding* it settles goes where every settled finding goes —
`research/`, next section — which is not a third record of the run but the one place its
verdict is kept current.

## `research/` — what is known, outliving the issue that found it

Three homes, one job each: **the PWF archive is the story, committed logs are the
measurements, `research/` is the durable verdict** — floodplains' `research/README.md`
had that framing before this section existed. A research file holds what is now *known*: a
settled method, a measured fact about an external system, a search that established an
absence — so that someone picking the work up months later does not re-derive it.
`planning/archive/<issue>/` holds what was *done*, in order, for one issue, and is rarely
opened by anyone who never saw that issue. The research file is the one they will look for.

What does **not** go there: a work log; a run record (Run / Hardware / Software /
Configuration blocks — that is the archive README's `Measurement` and `Evidence`, above);
the raw numbers (committed logs). Measured 2026-09-06 across the seven repos carrying a
`research/`, 40 topic files: link's `provincial_parity_2026_05_*.md` are four run records in
25 days, each dated by the run it records and carrying that run's setup and metrics, while
its living documents, `bcfishpass_methodology.md`,
`study_area_run.md` and `provincial_run_runbook.md`, are single files revised as the
knowledge moved. The second shape is the one that moves the state of knowledge; the first
duplicates the archive.

### One topic file, revised in place — git is the version record

`research/<topic>.md`, noun-first, **no date in the filename**. A new measurement that
changes what is known revises the topic file; it does not add a dated sibling.
`git log --follow research/<topic>.md` is the dated history, the archive README it cites
is the *why*, and the logs are the numbers — everything an R&D claim needs, with no second
copy of any of it.

Existing dated files — `20260711_…`, `…_2026_05_25.md` — are **not renamed**. They are
cited by path from `CLAUDE.md` files and from other conventions (`bookdown.md`,
`karpathy.md` §7), and a rename breaks the citation the way it breaks log evidence
(`newgraph.md`, "Which logs to commit"). Convergence is forward-only, and the README says
when.

### The header is the provenance, in prose

No research file in any repo carries YAML frontmatter and nothing consumes it, so
provenance is one line under the H1. floodplains' is the shape to adapt — it already carries
the date and the issues, and names its log prefix in the body:

```markdown
**Date opened:** 2026-07-11 · **Issue:** #8 · **drift:** 0.6.0 (`dft_stac_fetch(tile_size=)`,
drift#36) · **Status:** OPEN — design set, runs pending.
```

Three things the line must carry — `**Verified:** <date> · **Issues:** … · **Produced by:** …`
is the minimal form:

- **When it was last true.** The file's date, and a section-level date wherever one
  section is re-verified alone. A research file whose numbers cannot be re-derived ages
  into folklore, and one that states a scope or a quantity drifts silently when the code
  moves — three link documents, two of them research files, asserted a recompute "runs over
  every WSG in the schema" after two commits had changed it (`karpathy.md` §7, "Documents
  that share an ancestor corroborate nothing"). When code changes a behaviour a research
  file describes, grep `research/` for the sentence. Files written before 2026-09-06 gain
  the line when next revised; no fleet sweep is required.
- **What produced it.** The script path or log prefix for a measurement; the source list or
  reference-manager collection for a literature review. Never a number without its producer.
- **Which issues it came from and which it spawned.** The issue body links the research
  file (`feature-workflow.md`, "Issue bodies get edited, not appended"); the research file
  names its issues; and an archive README whose `Measurement` was distilled into a research
  file links it. Both ways, every time — one direction leaves the other end unfindable.

### The directory carries a README

An index: one row per file, what it covers — rfp's is the model. Where other repos hold
related work, a "Related work" list of links. Where two naming patterns coexist, the
cutover line in the form `newgraph.md` uses for logs:

```markdown
Naming: `<topic>.md`, revised in place, from 2026-09-06.
Files dated before that carry a `yyyymmdd_` prefix; they are not being renamed.
```

The README is the index. `CLAUDE.md` links the README once and cites an individual file
only where a rule depends on it. Twenty-three topic files with no README and a `CLAUDE.md`
citing four of them by path — link, measured 2026-09-06 — is the state this prevents.

### R packages and public repos

`research/` is top-level and excluded from the tarball: `^research$` in `.Rbuildignore`
(`code-check-r.md`, "`R CMD build` ships every top-level directory not in
`.Rbuildignore`"). Not `inst/notes/` or `inst/research/`, which ship inside the installed
package — the three packages carrying those (eight files, 2026-09-06) migrate by issue,
forward-only. In a package, `research/` is also where durable reference notes go, because
`docs/` belongs to pkgdown and `inst/` ships. And a public tool repo's `research/` is
public: report findings from internal work aggregated, never by the names of who it was for.

## Atomic Commits (Critical)

Every commit that completes a planned task MUST include:
- The code/script changes
- The checkbox update in `task_plan.md` (`- [ ]` -> `- [x]`)
- A progress entry in `progress.md` if meaningful

This creates a git audit trail where `git log -- planning/` tells the full story. Each commit is self-documenting — you can backtrack with git and understand everything that happened.

## File Formats

### task_plan.md

Phases with checkboxes. This is the core tracking file.

```markdown
# Task: <issue title> (#<N>)

<issue body — Problem section if present, otherwise first paragraph>

## Phase 1: [Name]
- [ ] Task description
- [ ] Another task

## Phase 2: [Name]
- [ ] Task description
```

Mark tasks done as they're completed: `- [x] Task description`

### findings.md

Append-only research log. Discoveries, technical analysis, things learned.

```markdown
# Findings

## [Topic]
[What was found, with source/date]

## Errors Encountered

| Error | Resolution |
|-------|------------|
```

### progress.md

Session entries with commit references.

```markdown
# Progress

## Session YYYY-MM-DD
- Completed: [items]
- Commits: [refs]
- Next: [items]
```

<!-- The Reboot Test and the error ledger below are adapted from -->
<!-- OthmanAdi/planning-with-files (MIT). Soul does not install or invoke that -->
<!-- plugin — the useful parts are carried here as text. Adapted 2026-08-26. -->
<!-- Same precedent as the attribution header in karpathy.md. -->

## The Reboot Test

The planning files exist so the work survives an interruption. Whether they
actually do is checkable: at any point mid-task, these five questions must be
answerable from the files alone, without the conversation.

| Question | Answer source |
|----------|---------------|
| Where am I? | Current phase in `task_plan.md` |
| Where am I going? | Remaining phases in `task_plan.md` |
| What's the goal? | The `# Task: <title> (#N)` frame and problem statement at the top of `task_plan.md` |
| What have I learned? | `findings.md` |
| What have I done? | `progress.md` |

If an answer lives only in the session, **write it down and commit it**. Written
is not sufficient: an uncommitted `findings.md` does not move between machines,
and a repo whose `planning/` is gitignored accepts `git add planning/` with exit
0 while tracking nothing — see Directory Structure below.

This is the operational check for the rule that every interruption should be a
resume point: a session death, sleep, or machine swap should cost a re-run at
most, never lost context. That rule states the goal; this tests it.

Run it before any long wait, before compaction, and before switching machines —
the moments that take a session without warning. `/compact-prep` and
`/planning-update` are where it gets run; this section is what it asks.

## Directory Structure

```
planning/
  active/          <- Current work (3 PWF files)
  archive/         <- Completed issues
    YYYY-MM-issue-N-slug/
```

If `planning/` doesn't exist in the repo, run `/planning-init` first.

**`planning/active/` must be tracked, not gitignored.** The atomic-commit rule
above requires each commit to carry its own checkbox flip in `task_plan.md`; an
ignored `active/` drops it silently, so `git log -- planning/` shows archives
appearing fully-formed with no history behind them. In-flight PWF also stops
surviving a move between machines.

The failure is quiet in both directions. `git add planning/` reports nothing and
exits 0 on an ignored path, and files tracked *before* the rule existed keep
being tracked — including through a `git mv` into the ignored directory. So a
repo can look like it is working right up until the first genuinely new PWF file,
which simply never appears in a commit.

Check rather than assume:

```bash
git check-ignore -v planning/active/task_plan.md   # expect no output
```

Found 2026-08-24 in gq, where the rule dated from the scaffold commit and the
#17 files had only survived because they predated their move into that
directory. gq and roli were the only 2 of 32 repos carrying it; roli still does.

## When Something Keeps Failing

Before a second attempt, name the failure class. A **deterministic** failure
returns the same result to the same inputs, so re-running unchanged only spends a
turn — change the inputs or change the approach. A **transient** failure
(network, a provider read, a rate limit, a resource still settling) is the case
where a re-run *is* the attempt: `code-check-infra.md` prescribes exactly that for a
tofu plan that falsely reports a resource deleted. The rule is not "never retry";
it is never retry unchanged while expecting a different answer.

Escalate rather than iterate once the approach itself is in question. Report what
was tried and the exact error, and hand over the commands to run — the user is
assumed to be away, so a question answerable from a phone beats a retry loop they
cannot see. Escalating is not stopping: commit the current state, then move to
the lowest-risk independent part of the plan while the question is outstanding.

Two classes escalate immediately rather than after retries, because further
attempts make them worse:

- **A clamped session.** Once a live credential has been read, later
  system-mutating commands are refused regardless of route — seven consecutive
  refusals across unrelated routes is the documented case (`newgraph.md`,
  "Reading a secret clamps the rest of the session"). Trying more phrasings is
  the failure mode, not the remedy, and `/permissions` does not clear it.
- **Rate limits.** Retrying extends the block (`ci-monitoring.md`).

### Log the errors that cost a retry

An error that took more than one attempt to get past goes in `findings.md`, so
one task does not hit the same wall twice:

```markdown
## Errors Encountered

| Error | Resolution |
|-------|------------|
| `fatal: Unimplemented pathspec magic '_'` | Long-form `:(exclude)path` |
```

That row is also what graduation looks like: it began as one task's blocker and
now lives in `code-check-shell.md` as a general rule about pathspec magic. Most rows
never make that trip and should not — the ledger's job is to stop one task
repeating itself.

When a failure does generalize, it graduates to the convention that owns its
class: the `code-check*.md` family for a bug class in a diff — `code-check.md` for a
mechanism, `-shell`, `-r`, `-spatial` or `-infra` for a tool quirk — `ci-monitoring.md` for CI
behaviour, the domain convention otherwise.

## Skills

| Skill | When to use |
|-------|-------------|
| `/planning-init` | First time in a repo — creates directory structure |
| `/planning-update` | Mid-session — sync checkboxes and progress |
| `/planning-archive` | Issue complete — archive and create fresh active/ |
