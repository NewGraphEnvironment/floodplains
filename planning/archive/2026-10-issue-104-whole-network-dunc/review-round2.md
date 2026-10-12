# Code-check round 2 (#104) — branch diff 3e0b943...HEAD

## Findings

- **[fragile]** scripts/floodplain_lcc/fp_region.R:27-30 (and CLAUDE.md "Whole-network mode (#104)" bullet: "item key species `all`") — the comment says the token sits in the species slot "so every species-keyed name downstream carries it **without a schema change** (… all_ff04, network[all2], item key species = "all")". The publish layer does not accept it: `stac_floodplains_bc/scripts/fp_provenance.R` `fp_prov_sections()` refuses any `floodplain`/`landcover` key not matching `^[a-z]{2}_ff[0-9]{2}$` with `stop()`, so `all_ff04` (three letters) aborts the reader for that area. Latent today and not a bug in this repo's code: DUNC is in no region file, region runs refuse `all` in both directions, and stac stages only region-roster groups (`01_stage.R`), so nothing reads DUNC's provenance. But the sentence will be wrong the day regions learn the mode, and a reader planning that work would take "without a schema change" at its word. The claim should say the publish side needs a change (the same regex also excludes 3-letter species such as `wct_ff04`, pre-existing).

Nothing else found. Checked and clean:

- `habitat_link` digest is stable across the gpkg round trip: recomputed from `data/dunc/aquatic_network.gpkg` (flags read back `logical`, keys `numeric`, no integer64) equals the recorded `sha256:c89f4eeb…`; 0 duplicate `(species, blue_line_key, downstream_route_measure)` keys.
- Habitat sibling JSON shape survives later read-modify-writes: `fp_prov_read` uses `simplifyVector = FALSE`, so `species` round-trips as an unnamed list (always a JSON array, including a one-species group) and `fwapg_sha` as `null`; the on-disk file (rewritten by steps 2 and 3 after step 1) shows both intact.
- `provenance-check.R dunc`, `whole_network-check.R`, `region_config-check.R` all PASS (run in a scratch copy of the repo with a copy of `data/dunc`).
- `FP_PROV_SIBLINGS` consumers: `fp_prov_set_sibling`, `viol_body` whitelist (`unlist()`), `viol_composition`, `viol_habitat` — all consistent with the new `network = "habitat"` entry. `provenance_ab-compare.R` compares section entries only and ignores siblings (pre-existing for `composition`; not introduced here).
- Other scripts meeting an `all` area: `gpkg_backfill-wsg.R` parses `[a-z]{2,4}_ff` (matches `all_ff04`, including inside `patch_watercourse_all_ff04_…`); `fire_tag.R` uses `[a-z0-9_]+`; `composition_build.R`/`composition-check.R`/`attribute_tag.R` derive names from `cfg$species`; `gpkg_prune-legacy.R`, `raster_strip-tags.R`, `readme_functions.R` do not touch `aquatic_network.gpkg` or species tokens. `aquatic_network.gpkg` (hence `habitat_link`) is not staged by stac.
- Sourcing: `run_area.R` and `floodplain_probe-whole-fwa.R` source `fp_region.R` before 01/02, so `FP_SPECIES_WHOLE` / `fp_whole_network_validate` resolve.
- `run_region.R`: the region-file refusal precedes `dbConnect`; the per-group refusal (in `fp_region_plan`) runs while building `plans`, before `fp_region_write`, so it cannot leave half-written configs.
- `FP_SPECIES` / `FP_ATTRIBUTE_BY` / `FP_NETWORK_SOURCE` overrides on `dunc` either fail the primary-scenario guard or `fp_whole_network_validate` before any write.
- All `link` habitat tables in the database carry the five flag columns the habitat SQL selects, as `boolean`.
- Log/research/CLAUDE.md numbers spot-checked against `data/dunc` and the query log: 1,282 patches, 99.8% spawning / 99.3%–99.7% rearing on floodplain blue lines, 91% vs 28% bt spawning by blue line vs nearest.
