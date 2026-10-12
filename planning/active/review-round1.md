# Code-check round 1 — branch 104-serve-whole-floodplains-keyed-by-blue-li (3e0b943...HEAD)

## Findings

- **[severity: fragile]** scripts/floodplain_lcc/habitat_join-query.R:34 — `%||%` is used, and
  neither this script nor what it sources (`fp_region.R`, `fp_habitat_join.R`) defines it. Base R
  has it only from 4.4.0. Every other entry point in the repo defines it locally for that reason
  (run_area.R:31 says so; also run_region.R, fp_provenance.R and the probes). DESCRIPTION sets no R
  floor. On R < 4.4 the consumer-side query dies with `could not find function "%||%"` before it
  reads anything. It works here on R 4.5.2. Fix: one line, the same local definition run_area.R uses.

Nothing else is a real defect. What I checked, so a later round need not repeat it:

- **Species SQL byte-identity:** I evaluated the 3e0b943 `sprintf` block verbatim for
  (`fresh_default`, `KOTL`, `bt`, 3), and its sha256 equals `GOLDEN_SPECIES_SQL` (`b8a25cd6…`). The
  bcfp reference string is unchanged in the species branch.
- **Mode predicate and validation:** both are reached before any write in 01 and 02. The habitat read
  happens before the network write. A BUILD is refused in whole mode, so the `DROP SCHEMA` path cannot
  run with `species: all`.
- **Region runs:** they refuse `all` before the pre-pass's `access_%s` SQL (run_region.R:77), and
  `fp_region_plan` refuses it both ways. If `FP_SPECIES=all` is inherited by region children, each
  child stops at run_area's primary-scenario guard. That is a per-group soft-fail, not a silent
  run. `region_config-check.R`: PASS.
- **Whole-mode SQL inputs:** `fp_habitat_sql`, `fp_habitat_tables_sql` and `fp_fwa_sql` validate
  schema, group and species before interpolating them. The discovery regex excludes
  `streams_habitat_long_vw`. All 8 `fresh.streams_habitat_<sp>` tables have identical columns, so
  the per-species `rbind` cannot meet a column mismatch. DUNC's `fresh.streams` has a unique
  (blk, drm) key, 26,827 of 26,827.
- **Provenance:**
  - `fp_prov_set` replaces the whole network entry, then the habitat sibling is re-attached. If the
    habitat write fails in between, `viol_habitat` and 7c report the missing record rather than
    leaving a stale one.
  - `KEYS_BODY` picks up `habitat` through `unlist(FP_PROV_SIBLINGS)`.
  - The `^all[0-9]+$` key test cannot match a landcover key like `all_ff04`.
- **Checks run (no files modified):**
  - `whole_network-check.R`: PASS.
  - `provenance-check.R dunc`: PASS, including habitat rows 53,654 and the digest
    `sha256:c89f4eeb…`, recorded equal to the artefact.
- **Log numbers re-derived from data/dunc:**
  - Network: 13,023 segments, 3,493.0 km, 2,236 blue lines, 211 waterbodies. `habitat_link` holds
    bt 26,827 + wct 26,827.
  - Attribution: 1,942 rows, 530.6 km² summed, 137 with a `gnis_name`.
  - Transition: 1,282 patches, 710.1 ha. Tree loss: 271 patches, 119.5 ha (Rangeland 78.6,
    Water 32.0, Built 5.1). Fire 0%, harvest 32.6%.
  - Bridge: 4,088 pairs, 1,280 patches, 188 blue lines.
  - Composition: 743.3 / 710.1 = +4.67%, footprint +8.9%.
  - Join: 91% / 28% of the floodplain read as bt spawning (by blue line / by position), and the
    99.8 / 99.3 / 99.7% km shares follow from the query log's tables.
- **Demo extraction:** `fp_hj_*` match the removed demo bodies line for line, with no behaviour
  change.
