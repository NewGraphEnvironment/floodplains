# Task: Annual IO LULC series (2017-2023) for bulk, necr, lnth, kotl (#79)

## Problem

`scripts/floodplain_lcc/03_lulc_classify.R:49` fetches three snapshots by construction:
`years <- sort(unique(c(yrs[1], round(mean(yrs)), yrs[2])))` — endpoints plus midpoint. So every
area's `rasters/<scenario>/classified_<year>.tif`, the `classified_<sp>_<scen>_<year>` gpkg layers
and the provenance `years` field carry 2017 / 2020 / 2023 only, and the catalogue publishes the
same three. drift's `dft_rast_break_class()` needs every year: on BULK it found only ~20% of the
published 2017->2023 change is a switch sustained two years each side, and 44% flickers.

Downstream: `stac_floodplains_bc#59` publishes the seven years, `drift#62` analyses them.

## Scope corrections established during planning

1. **PINE dropped** (user decision). `data/pine/` has no `provenance.json` and its
   `rasters/bt_ff04/*.tif` are 2026-07-12 — pre-`flooded` 0.5.0, the bankfull-units vintage
   CLAUDE.md calls dead rather than superseded. PINE and MCGR are the only 2 of 23 area dirs in
   that state; both are tracked by #76. Four areas: bulk, necr, lnth, kotl.
2. **The originally-proposed A/B gate could not fail** — drift's `stac_cache_key()` excludes
   `years`, and the STAC query range is `min(years)..max(years)` either way. See findings.md.
3. **Acceptance restated** as a `provenance_ab-compare.R` expected-failure set.
4. **Cost figure corrected** — no area sets `tile_size`, so 23.6 min describes an untaken path.
5. **gdalcubes recorded nowhere** and differs across the two machines the run is split over.

## Phase 1: Level m4 and prove it (blocking for the split)

- [ ] Probe m4 capabilities before upgrading; record the result
- [ ] `drift` -> v0.13.0 pinned (>= 0.10.0 mandatory: 0.8.0 truncates a multi-page item set)
- [ ] `sf` -> 1.1-2, `gdalcubes` -> 0.7.4, `terra` -> current (content digest is container-invariant)
- [ ] Re-probe and diff against the pre-upgrade record
- [ ] rsync `data/{neexdzii,kotl,necr}` and `~/Library/Caches/drift/io-lulc/` from m1
- [ ] Point m4 `PGHOST` at m1; verify with a real query, not a port check
- [ ] Control: m4 runs `run_area.R neexdzii 3` unchanged and reproduces m1's landcover `outputs_hash`

## Phase 2: The code change

- [ ] `run_area.R`: `lulc_annual` optional key beside `tile_size`, plus `FP_LULC_ANNUAL` env twin
- [ ] Logical type guard (a quoted `"true"` is a character vector and `isTRUE()` reads it as off)
- [ ] `03_lulc_classify.R:49` — the one line
- [ ] Record `gdalcubes` in `fp_toolchain()` + `KEYS_TOOLCHAIN` + `TOOLCHAIN_FIXTURE`
- [ ] Extend `region_config-check.R` area-owned-survival assertion to `lulc_annual`
- [ ] Config comment: `lulc_annual` is a one-way door per area (#55 orphan class)
- [ ] Prose: `README.Rmd`, `README.md`, `scripts/floodplain_lcc/README.md`, two stale code comments
- [ ] Turn it on for the four areas' `area.yml`

## Phase 3: Acceptance harness, before any area is overwritten

- [ ] Per area: back up `provenance.json` and assert the baseline is real (v2 + three digests)
- [ ] Write down the expected `provenance_ab-compare.R` failure set and grep for it
- [ ] Element-wise: 2017/2020/2023 `classified_content_sha256` unchanged
- [ ] `outputs.transition_content_sha256` and `transition_patches` unchanged
- [ ] Exactly seven `classified_<scen>_*` layers and no eighth
- [ ] `provenance-check.R <area>` green

## Phase 4: The split runs

- [ ] m4: `STEPS=3 scripts/run_areas.sh kotl necr`
- [ ] m1: `STEPS=3 scripts/run_areas.sh bulk lnth`
- [ ] Gate on in-band markers and output mtime, never the wrapper exit
- [ ] Record wall-clock and peak RSS per area

## Phase 5: Reconcile, evidence, PR

- [ ] rsync m4's outputs back to m1
- [ ] Committed evidence log under `scripts/floodplain_lcc/logs/`
- [ ] PR body: timings, RSS, expected-failure set, gpkg-bytes and `nge:landcover_key` notes
- [ ] Flag both on `stac_floodplains_bc#59`

## Issues to write

- [ ] Edit #79 body: four areas, PINE reason, corrected cost, restated acceptance
- [ ] New issue: the m1 run half, so m1 can `/planning-init` on it
- [ ] Comment on #76: PINE's annual run belongs in its acceptance
- [ ] New issue: `item_ids_complete` is dead on drift >= 0.10

## Validation

- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
