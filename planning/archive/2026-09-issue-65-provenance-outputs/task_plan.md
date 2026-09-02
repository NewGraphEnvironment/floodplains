# Task: Provenance records the recipe, not the cake: hash the real inputs and outputs of the network and floodplain steps (#65)

`data/<area>/provenance.json` splits every entry into `inputs` (byte-stable, summarised by
`inputs_hash`) and `run` (the run event, unhashed). Two of the three sections hash a *description of
the job* and nothing about the data:

- **network** — `fp_prov_set` hashes `value$inputs` only, and `link_log` is a **sibling** of
  `inputs`, so `config_hash`/`run_uid`/`link_sha` are outside the hash. Rebuild `fresh` with
  different data and `network.inputs_hash` does not move.
- **floodplain** — every key in `KEYS_FLOODPLAIN` is a parameter. `dem_ncell`/`dem_res_m` pin the
  **grid**, not the elevations; NRCan re-deriving MRDEM changes nothing in the record.
- **a wrong value** — `01_network_extract.R` hardcodes `link_config_name = "default"`. Verified live
  in `data/neexdzii/provenance.json`: `inputs.link_config_name = "default"` beside
  `link_log.config_name = "bcfishpass"`.

Outcome: a digest of the input **data** inside `inputs`, and a new `outputs` block — parallel to
`inputs`, hashed into `outputs_hash`, **never** folded into `inputs_hash`.

## Measured before planning

| probe | result |
|---|---|
| `fp_raster_content_sha256` on a SpatRaster | `readStart/readValues` work in memory; path / file-backed / in-memory forms give an **identical** digest, and the path form is byte-identical to today's |
| neexdzii `streams_co3` | 1915 rows; `(blue_line_key, downstream_route_measure)` unique, no NAs; 673.5 km |
| `floodplain_co_ff04.tif` | CRS code **3005** present (WKT fallback unreachable), datatype **FLT4S**, res `30.469843851964` — a warped, non-round grid |
| `schema_version` | asserted **nowhere**, and `fp_provenance.R:58` overwrites it on every read |
| `link_log` | 30 columns, **including `config_name`** — the fix has a source |
| `flooded.sha_source` | `"unresolved (checkout at /Users/airvine/... is 0.6.0, installed is 0.5.0)"` — a `$HOME` path and a sibling checkout version, **inside hashed `inputs`** |

## Four deviations from the issue text

1. Network key is `(blue_line_key, downstream_route_measure)`, not `id_segment` — the latter is
   numbered per group during generation, so it would churn on every BUILD.
2. The network gets an `outputs` block too: the reach subset is PROJ + GEOS, so a post-subset digest
   in `inputs` would make `inputs_hash` a function of the sf build. **Pre-subset → `inputs`,
   post-subset → `outputs`.**
3. Landcover's `transition.tif` gets an `outputs` block (user-approved widening — one rollout, not
   two). The transition *vector* stays in #72.
4. `fp_pkg_stamp`'s free-text `sha_source` is fixed here — otherwise the issue's own cross-machine
   criterion is uninterpretable.

## Phase 1: Digest primitives + guard scaffolding (offline)

- [x] `fp_raster_content_sha256()` accepts a SpatRaster or a path; type dispatch before the
      `file.exists()` guard; object-form NA contract defined
- [x] `fp_table_content_sha256()` — fixed-format text digest, `na.last = TRUE`, row-count and
      column-name prefix, no `paste`/`as.character` on numerics
- [x] `fp_prov_set()` assigns `outputs_hash` only when `outputs` is present; `stopifnot` on `inputs`
- [x] `fp_pkg_stamp()` `sha_source` becomes a closed vocabulary; detail to `message()`
- [x] `FP_PROV_SCHEMA_VERSION` → 2
- [x] `KEYS_BODY` body-level whitelist in `provenance-check.R`
- [x] `viol_split` gains all four `outputs` arms
- [x] §1 gains the outputs/inputs hash independence assertion, routed through `fp_prov_set`
- [x] §5c SpatRaster-vs-path agreement + object NA contract; §5d float premises
- [x] §5e table digest, with must-fails
- [x] `fp_pkg_stamp` closed-vocabulary assertion

## Phase 2: Network section (01) — every `inputs` change in one commit

- [x] `network_content_sha256` in `inputs`, on the full-WSG read **before** the subset
- [x] `outputs = list(streams_layer, network_content_sha256)` — the post-subset set
- [x] `link_config_name` derived on the `grab` predicate; `link_config_name_source` closed vocabulary
- [x] `config_name` added to 01's null-fill list and `KEYS_LINK_LOG`
- [x] `.stamp.md` sidecar states the same resolved config name
- [x] `KEYS_NETWORK_INPUTS` / `KEYS_NETWORK_OUTPUTS`; §6 pins the BUILD literal from 01's own
      `lnk_config()` call; a GRAB may never report `link_config_name_source = "built_literal"`

## Phase 3: Floodplain section (02)

- [x] `dem_content_sha256` in `inputs`, computed once before the scenario loop
- [x] `outputs = list(floodplain_raster, floodplain_content_sha256)` — digest of the written file
- [x] Pin `datatype` on 02's `writeRaster`; verify the pin is byte-identical
- [x] `KEYS_FLOODPLAIN` + `KEYS_FLOODPLAIN_OUTPUTS`; `SECTIONS_WITH_OUTPUTS` as a declare-or-fail pair

## Phase 4: Landcover outputs (03)

- [x] `outputs = list(transition_raster, transition_content_sha256)`, guarding the empty-summary case
- [x] `KEYS_LANDCOVER_OUTPUTS`

## Phase 5: A/B compare + schema-version assertability

- [x] `provenance_ab-compare.R` compares `outputs_hash` with a per-hash detail column
- [x] Outputs expectation derived per section, not from what the two files share
- [x] `schema_version` 2 tied to the outputs field set

## Phase 6: Live verification (neexdzii + bulk)

- [x] Steps 1–3 on each, sequentially, gated on in-band errors + output mtime
- [x] `provenance-check.R neexdzii` and `... bulk` pass
- [x] A/B two passes on neexdzii: hashes identical, `datetime_utc` moved
- [x] Split test: neexdzii and bulk share a network `inputs` digest and differ on `outputs`
- [x] The issue's test: BULK from `fresh` vs `fresh_default` — network `inputs_hash` differs
- [x] Parity unmoved: 673.5 km / 142.8 km² / 770.0 ha
- [x] DEM digest cross-machine decision point recorded
- [x] Evidence log under `scripts/floodplain_lcc/logs/`

## Phase 7: Bookkeeping

- [x] Edit #65's body for the four deviations
- [x] File the 18-area rollout issue
- [x] Note `stac_floodplains_bc`'s own change (schema_version 2 + `outputs`)

## Validation

- [x] `provenance-check.R` passes with every new property shown able to fail
- [x] `/code-check` clean on each commit
- [x] PWF checkboxes match landed work
- [x] CLAUDE.md updated
- [ ] `/planning-archive` on completion
