# Task: Serve whole floodplains keyed by blue_line_key; join habitat and query species afterwards (#104)


Today the floodplain is delineated from a **pre-filtered** network. Step 1 keeps the segments with `access_<species>` at `order >= min_order`, and step 2 delineates around those only. The question being asked ("which floodplain, for what fish, doing what") is baked into the geometry. The served collection (`stac_floodplains_bc`) inherits that, one species-and-threshold cut per item (`co_ff04`, `ch_ff06`, …), and nothing on a polygon says what habitat it is.

The network already carries the attributes to answer those questions after the fact. Per segment, `fresh.streams_vw_bcfp` has `access_*`, `spawning_*` and `rearing_*` for bt / ch / cm / co / pk / sk / st / wct, plus `stream_order` and `blue_line_key`.

Piloted on DUNC (#120). Plan approved 2026-10-11 at the plan gate; its body follows.

Decisions taken at the gate (2026-10-11):
- **Key:** a reserved species token, `species: all`. Layers `streams_all2` / `waterbodies_all2`,
  scenarios `all_ff02/04/06`, attribution `all_ff04_by_blue_line_key`, provenance
  `network[all2]`, item key `(DUNC, all, all_ff04)`. All of the #23/#30 machinery carries through.
- **Scope:** steps 1–3 plus a habitat table. GeoParquet and the other publish formats go to a
  follow-up issue.
- **DUNC:** a standalone `config/dunc/`, whole network only, kept out of `columbia.yml`. #120's bt
  item is not built, and #120's body is updated to say so.

Measured state of the database (2026-10-11):
- **`fresh.streams` holds DUNC:** 26,827 segments, 13,023 at order ≥ 2, 2,236 blue lines.
- **link's habitat tables hold DUNC** (`fresh.streams_habitat_bt` etc.). They are keyed
  `(id_segment, watershed_group_code)`, and joining on `id_segment` alone over-counts.
- **DUNC is absent from `fresh.streams_access`, `fresh_default.streams` and `fresh.log`.** The
  whole network needs no access join, so this does not block. The link log row is recorded as
  absent, via the existing `link_log_note` path.
- **Installed flooded is 0.6.0.** v0.6.5 is tagged.

## Phase 0: Toolchain
- [x] Install flooded v0.6.5 (`pak::pak("NewGraphEnvironment/flooded@v0.6.5")`) and confirm
      `packageVersion("flooded") == "0.6.5"`. This changes the machine and is covered by approving
      this plan.
- [x] In whole mode, 02 asserts flooded ≥ 0.6.4: without #71, attribution at order ≥ 2 costs hours.

## Phase 1: Whole-network mode in step 1
- [x] One predicate, defined once: `fp_whole_network(cfg)` ⇔ `identical(cfg$species, "all")`
      (constant `FP_SPECIES_WHOLE <- "all"`). It lives in a file `run_area.R` already sources
      (`fp_region.R`) and is used by 01, 02 and the checks.
- [x] Lift 01's network SELECT into `fp_network_sql(read_schema, wsg, species, min_order)`.
      - **Species mode:** byte-identical to today (pinned by a golden string in the check).
      - **Whole mode:** no `streams_access` join, no `access_` predicate, `stream_order >= min_order`
        only.
      - Leave the probe's `fp_wf_network_sql()` copy alone: its anchor depends on it.
- [x] Freshness guard in whole mode compares order ≥ min_order km against `fresh.streams_vw_bcfp`
      with **no** access predicate. Species mode is unchanged.
- [x] Region files refuse `species: all`, since the pre-pass would query `access_all`. Do this in
      `fp_region_plan`/the pre-pass, with an arm in `region_config-check.R`.
- [x] Offline check `scripts/floodplain_lcc/whole_network-check.R`, with must-fail arms:
      - species SQL unchanged;
      - whole SQL has no `access_` and no `streams_access`;
      - a non-`all` species never takes the whole path;
      - the region refusal fires.

## Phase 2: Habitat table (step 1, whole mode)
- [x] Write a non-spatial `habitat_link` table into `aquatic_network.gpkg`, long form:
      - one row per (segment, species) for every `fresh.streams_habitat_<sp>` table with rows in
        the group;
      - columns `blue_line_key, downstream_route_measure, upstream_route_measure, stream_order,
        length_metre, species, accessible, spawning, rearing, lake_rearing, wetland_rearing`, plus
        `wsg` and `model = "link:<read_schema>"`;
      - joined on `(id_segment, watershed_group_code)`.
      - All orders are kept, because habitat on order-1 lines is what the integrity check counts as
        outside the floodplain. Keyed by FWA position, never `id_segment`.
- [x] **FWA version beside the key:** `fwapg_sha` from the link log row when present, else NA
      (`fwapg_sha_source: unresolved`); plus `fwa_content_sha256`, a digest over the group's
      `fwa_stream_networks_sp` (blk, drm, length_metre) a consumer can recompute (review 1 #8).
- [x] Provenance: a `habitat` SIBLING inside `network[all<order>]` (`fp_prov_set_sibling`, the #108
      pattern), not new `outputs` keys: inputs model/read_schema/watershed_group/species/fwapg_sha/
      fwapg_sha_source/fwa_content_sha256, outputs layer/rows/table_content_sha256
      (`fp_habitat_content_sha256`: one table digest per species, flags as 0/1). `provenance-check.R`:
      `KEYS_HABITAT_*`, `viol_habitat` (network-only, whole entries only, a whole entry WITHOUT one
      fails), 3d fixtures with must-fail arms, a producer-scan of 01's sibling call, 7c reconcile
      against the gpkg table. Species-mode areas are unaffected.
- [x] Review 1 fixes: habitat read before any write; `I()` on species; whole mode requires
      `attribute_by: blue_line_key` and `network_source` (`fp_whole_network_validate`, 01 + 02).

## Phase 3: DUNC steps 1–2
- [x] Create `config/dunc/area.yml`:
      `species: all, min_order: 2, schema: dunc, network_source: fresh` (guard left strict: 0.0% dev),
      attribute_by: blue_line_key, primary_scenario: all_ff04`, with a header comment on #104/#120.
      No `lulc_annual`, since it is a one-way door.
- [x] Create `config/dunc/flood_scenarios.csv`: rows `all_ff02/04/06` (`run = TRUE`) modelled on
      KOTL's parameters, `min_order = 2`.
- [x] `caffeinate -s Rscript scripts/run_area.R dunc 1,2 > log 2>&1`, gated on the in-band error
      count and output mtimes.
- [x] Record per-stage timings, peak RSS, the area per scenario, blue lines attributed and the
      fallback cells in `scripts/floodplain_lcc/logs/<date>_whole_network_dunc.md`.

## Phase 4: DUNC step 3
- [x] `run_area.R dunc 3`: LULC, transition, disturbance tags, composition and the
      `patch_watercourse_all_ff04_*` bridge on the whole floodplain.
- [x] Verify classified coverage ≈ floodplain area, then run `bridge-check.R dunc all_ff04`,
      `composition-check.R dunc` and `provenance-check.R dunc`, and record the results in the log.

## Phase 5: The habitat join on DUNC
- [x] Extract the demo's join functions (`grid_cells`, `join_range`, nearest/any) into
      `fp_habitat_join.R`, sourced by both scripts. Re-run `habitat_join-demo.R` and confirm its MORR
      log numbers are unchanged.
- [x] Add `habitat_join-query.R <area> <species>`. It reads the published artefacts (the
      `_by_blue_line_key` layer, the floodplain tif and `habitat_link` for the flags) plus segment
      geometry from the model's own `<schema>.streams` (all orders, as the demo), matched to
      `habitat_link` on (blk, drm) with the match rate reported (review 1 #1). It reports:
      - integrity: every floodplain cell attributed, none outside;
      - the share of habitat km on blue lines with floodplain;
      - spawning and rearing floodplain ha under nearest and any, for **bt** on DUNC (plus wct if
        it has rows).
- [x] Log the results into the same DUNC log.

## Phase 6: Docs and issues
- [x] `research/whole_fwa_floodplain.md`: add a "Pipeline pilot: DUNC" section (cost, area, join)
      and revise the header line.
- [x] `CLAUDE.md`: a Layout bullet on whole-network mode (`species: all`, habitat table, region
      refusal) and DUNC under Areas.
- [ ] #104 body: add the DUNC pilot results. Spin off a follow-up issue for GeoParquet/Parquet
      publish formats and region support for `species: all`.
- [ ] #120 body: DUNC lands under the #104 model and the bt item is not built.
- [ ] Note the stac_floodplains_bc implication (item species `all`) in the PR body only. The
      coupling stays one-way.

## Validation
- [x] Offline checks pass: `whole_network-check.R`, `region_config-check.R`, `provenance-check.R`
      (offline sections), `floodplain_probe-check.R`
- [x] Live: `provenance-check.R bulk` and `neexdzii` still pass (species mode untouched)
- [ ] `/code-check branch` (three-round floor)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive`, then `/gh-pr-push`

