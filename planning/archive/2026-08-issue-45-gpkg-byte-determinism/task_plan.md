# Task: Deterministic GeoPackage writes (#45) + correct the documented collection id (#41)

Two defects in how this repo's published outputs are compared and described.

**#45** — `sf::st_write()` to GeoPackage is not byte-deterministic: GDAL stamps
`gpkg_contents.last_change` with wall-clock time at write, so two writes of identical data differ.
A rerun is indistinguishable from a change, and `file:checksum` on published assets would churn per
build regardless of content. GeoPackage is 40 of 141 objects in the published bucket and 72% of it
by size. `stac_floodplains_bc/scripts/01_stage.R:148-151` publishes these files with `file.copy`, so
the producer is the right layer to fix — nothing downstream changes.

**#41** — `README.md:60` and `:100` name the collection `stac_floodplains_bc`; the id is
`stac-floodplains-bc`. The underscore form is the *repository* name. A consumer querying the
documented id gets a clean `NotFoundError`, which reads as "not published" rather than "wrong name".

## Phase 1 — Pin the stamp
- [x] `scripts/fp_gpkg.R` (new) — `fp_gpkg_pin_date()` sets `OGR_CURRENT_DATE` to the fixed epoch
- [x] Call it at the four entry points that write a published gpkg: `run_area.R`, `run_region.R`,
      `gpkg_backfill-wsg.R`, `fire_tag.R` (the latter two do NOT source `packages.R` — verified)
- [x] Leave all 13 `st_write` call sites untouched — the env route covers every one, including
      any added later

## Phase 2 — Establish the guarantee, and its limit
- [x] Replay all layers of the real `data/morr/floodplain_landcover.gpkg` (79 MB) twice and `cmp -s`
- [x] Measure whether `VACUUM` closes probe D (partial rerun). Adopt if cheap; document if not
- [x] Record what the guarantee actually is: a full rebuild from an absent file is byte-reproducible
- [x] If VACUUM does not close D, state the content-hash route as a pointer, not an implementation

## Phase 3 — Assert it
- [x] `scripts/floodplain_lcc/gpkg_determinism-check.R` (new) — replay twice, fail loud on mismatch
- [x] Verify it FAILS without the pin and passes with it (cold path, not only the warm no-op)

## Phase 4 — #41
- [x] `README.md:60,100` -> `stac-floodplains-bc`; say the repo name and collection id differ
- [x] File the asset-split in `stac_floodplains_bc` with #41's size table carried over
- [x] Edit #41's body to record the split

## Phase 5 — Docs + close
- [x] `CLAUDE.md`: the pin, where it is set, the bounded guarantee
- [x] `README.md`: determinism under the publish section
- [x] Comment on `stac_floodplains_bc` that `file:checksum` is unblocked for a clean rebuild
- [x] `soul` issue: geometry canonicalization before hashing -> `code-check.md` cache-key section
- [x] Follow-up issue here: content-hash identity on transition patches (links #27, #30)
- [ ] `/planning-archive`, `/gh-pr-push`

## Validation
- [x] `data/morr/floodplain_landcover.gpkg`: two full replays -> `cmp -s` identical
- [x] `gpkg_determinism-check.R` fails with the pin removed, passes with it
- [x] `Rscript scripts/run_area.R neexdzii 2` -> parity fixture still 171.0 km2
- [x] `curl -s https://images.a11s.one/collections/stac-floodplains-bc | jq -r .id` resolves
- [ ] `/code-check` clean on each commit
