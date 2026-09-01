# Task: Record run provenance per area: link config hash + package versions + run date + landcover source fingerprint (#33)

Nothing in a produced floodplain product records **what produced it**. Given
`data/<wsg>/rasters/<scenario>/*.tif` and the GeoPackages, there is no way to recover which link
config was in effect, which `link`/`flooded`/`drift` versions ran, when the run happened, or
**which landcover raster** the LULC and transition layers were derived from.

The last one is the sharp edge. The config lives in git, so a version recovers the content. The
landcover does not: `io-lulc-annual-v02` on Planetary Computer is a remote collection that can be
silently reprocessed upstream, and `dft_stac_fetch()` caches by request hash — so a stale local
cache keeps serving the old raster while a fresh machine gets the new one. Two machines, same
code, different answers, no error.

`NewGraphEnvironment/stac_floodplains_bc#17` is blocked on this: that repo does no modelling and
can only publish what it is handed.

## Decisions taken at plan time

| decision | choice |
|---|---|
| landcover fingerprint | resolved **STAC item ids**, not drift's `stac_cache_key()` |
| file shape | one merged `data/<area>/provenance.json` per area |
| scope vs #52 | JSON only; #52 later *consumes* this block rather than producing a second one |
| existing areas | **forward-only** — no backfill CLI; stac#17 treats the block as optional |

`stac_cache_key()` hashes AOI WKB + request parameters and **nothing about the items returned**
(`drift/R/dft_stac_fetch.R:210-227`). It is a fingerprint of the *request*, so an upstream
reprocess leaves it unchanged — exactly the failure this issue exists to catch. It is also
`@noRd`. `attr(result, "stac_items")` has been attached since drift's first commit and is the
content pin.

## Phase 1: Writer + guard

- [x] `scripts/floodplain_lcc/fp_provenance.R` — `fp_prov_set()` (atomic read-modify-write),
      `fp_prov_null_fill()`, `fp_pkg_stamp()` (three-tier SHA, `sha_source` names the tier,
      `dirty` never collapses `NA` to `FALSE`)
- [x] `scripts/floodplain_lcc/provenance-check.R` — determinism, declared keys, credential-leak
      grep, `item_ids_complete`, `inputs`/`run` disjoint. Runs with no database.
- [x] Prove each assertion can fail: restore a run-event field into `inputs`, feed the leak grep a
      fixture that contains a SAS token, drop a declared key
- [x] `jsonlite` added to `pkgs_cran` in `scripts/packages.R`
- [x] `fp_provenance.R` sourced from `scripts/run_area.R`

## Phase 2: Step 1 — network section

- [x] Construct `lnk_config("default")` on **both** GRAB and BUILD branches (today it exists only
      in the BUILD branch, `01:85-86`), with `$pipeline$schema <- read_schema`
- [x] `lnk_log_read()` read **wholesale** (`SELECT *`, so it works against the installed link
      0.47.3 even though the checkout is 0.49.0), `tryCatch` → `null` + `link_log_note`
- [x] Null-fill the declared key set: `run_uid`, `config_hash`, `link_sha`, `link_dirty`,
      `fwapg_sha`, `bcfp_model_version`, `bcfp_pin_source`, `date_start`, `date_end`
- [x] Write `network[<species><min_order>]` with `inputs` / `link_log` / `run`

## Phase 3: Step 2 — floodplain section

- [x] `inputs`: item key, VCA scenario parameters, `dem_buffer_m`, `attribute_by`,
      `subbasin_source`, `crs_epsg`, `fp_pkg_stamp("flooded")`
- [x] `dem_source` from `terra::sources(dem)` — measure the output, do not hardcode the MRDEM-30
      URL (it is built inside `fl_dem_aoi()`'s body, not a formal default). Empty ⇒ `null` + note.
- [x] Write `floodplain[<scenario_id>]`, one per scenario in the loop

## Phase 4: Step 3 — landcover section

- [x] Read `attr(rasters_all, "stac_items")` immediately after the fetch — the attribute is on the
      list and is lost by any subsetting
- [x] Group ids by **`start_datetime`**, not `datetime` (io-lulc items carry `datetime = NULL`;
      grouping by it yields empty groups silently). Assert every requested year resolves to ≥1 id.
- [x] Keep only the requested years — the query spans `min(years)`–`max(years)`, so unused years
      come back and must not be recorded as inputs
- [x] `item_ids_complete` from the presence of a `rel="next"` link (Planetary Computer returns no
      `numberMatched`, so that is the only honest test)
- [x] `item_hash` = sha256 over the sorted flattened ids
- [x] Resolved fetch parameters from `dft_stac_config()` + `formals(dft_stac_fetch)`; `cache_key`
      declared as `null`
- [x] **No hrefs** — `items` arrives `items_sign()`ed, so every asset href carries a SAS token

## Phase 5: Verify and hand off

- [x] `provenance-check.R` green on a real area
- [x] A/B: two full runs through the real writer + live STAC, `inputs_hash` identical per section,
      `run.datetime_utc` differs. Gated on the in-band error count, not the wrapper's exit code.
- [ ] **BLOCKED** — neexdzii end-to-end A/B needs postgres, which is not running on this machine
- [ ] **BLOCKED** — parity fixture numbers unmoved (673.5 km / 142.8 km² / 770.0 ha); needs postgres
- [x] `CLAUDE.md` updated
- [x] Correction note to stac#17 (`nge:landcover_key` should be the item-id hash) and to #33
      (forward-only)

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
