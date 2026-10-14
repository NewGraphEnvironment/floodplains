# Code review, round 1: branch 125 (`git diff 71c0378...HEAD`)

Both offline checks run green on the branch (`region_config-check.R`: all PASS; `whole_network-check.R`: PASS).
`disturbance-check.R` (which now sources `fp_region.R` via `readme_functions.R`) also passes from the repo root.

## Findings

- **[severity: bug]** scripts/floodplain_lcc/fp_region.R:85 — `net <- reg$network` partial-matches
  `network_source`. `$` on a list partial-matches when the exact key is absent, so a species region
  that has `network_source:` and no `network_guard:` is read as `network: <its source>` and refused.
  Reproduced:
  `fp_region_mode(list(species = c("ch","bt"), network_source = "fresh"))` stops with
  "`network:` must be `whole` or absent, got: fresh". The pre-#125 `config/regions/fraser.yml`
  (from `git show 71c0378:`) fails the same way. That file is the documented species-region shape:
  fraser, peace and skeena all had `network_source: fresh` and no guard.
  A file with BOTH `network_source` and `network_guard` (the old columbia) works only by accident,
  because the partial match is then ambiguous and returns NULL.
  So species mode, which this branch says it keeps ("Species regions keep their pre-pass"; the
  CLAUDE.md "add a SECOND region file" route for wct), is unusable for the ordinary shape. The
  failure is loud, so no data is at risk, but it hits every species-mode entry point:
  - `run_region.R:49`;
  - `fp_region_owned`/`fp_region_min_order`, both of which call `fp_region_mode`;
  - `readme_functions.R` `fp_readme_roster`, so the README render stops too.

  The checks cannot see it: every species-mode fixture is built without `network_source`
  (`owned_for(..., extra)` only ever passes `attribute_by`; `fp_region_mode(list(species = ...))`).
  Fix: `reg[["network"]]`. Add a must-pass arm, a species list plus `network_source` and no
  `network_guard`.

- **[severity: fragile]** scripts/run_region.R:206-207 (with :156) — the "region moved a
  region-owned key ⇒ re-run" rule reads `plans[[i]]$area_set`/`area_remove`. Those are computed
  against the area.yml on disk BEFORE `fp_region_write`, and line 156 writes every group's config
  up front, before any child runs. So the signal lives only in the invocation that made the change.
  If that run is interrupted, a resume (the documented recovery: idle-sleep kills,
  `caffeinate`/resumable runner) re-plans. The configs are already written, so `area_set` is empty
  and `moved` is FALSE. Every group not yet reached whose `lulc_summary_<sp>_ff04.rds` and current
  (≥0.7.0) provenance exist is then reported `ok(cached)`, with outputs made under the OLD
  `network_source`/`min_order`. That is exactly what the comment says this prevents ("Re-run rather
  than report the old outputs as this config's").

  No live case triggers it today:
  - DUNC is also caught by the flooded-version rule.
  - Converting species groups have no `all_ff04` summary yet.
  - The rule is wrong for the next `network_source` or `min_order` edit to a region whose groups
    already have current whole-network outputs.

  The fact is persisted: `provenance.json` `network[<sp><order>].inputs.read_schema` and
  `min_order` are recorded (DUNC: `read_schema: fresh`, `min_order: 2`). So staleness can be
  derived from disk, by comparing them with the reconciled area.yml, rather than from the
  one-shot diff.

## Checked and not flagged

- `fp_region_cache_stale`'s path `floodplain.<scen>.inputs.flooded.version` matches real
  provenance (dunc 0.6.5, bulk all_ff02 0.7.0).
- `n_whole` reads the same `<network_source>.streams` / `stream_order >= min_order` /
  `watershed_group_code` that `fp_network_sql`'s whole branch reads. Its schema-name regex
  guards the interpolation.
- The coverage-summary SKIP row now carries `provenance`, so `rbind` columns match.
- Post-verify layer names `streams_all2` / `all_ff04` match whole-mode naming.
- The citation carry only fills empty appended rows, from a unique non-empty citation at the
  same flood factor. Existing rows are not rewritten. The appended block follows the on-disk
  header.
- `targets` refusal: no live area.yml carries `targets` any more (morr's was removed).
- CLAUDE.md claims checked:
  - stac `01_stage.R` reads only `region` + `watershed_groups` from region files.
  - 23 region groups (13 + 3 + 3 + 4).
  - `fp_region_owned` is used by the runner and both checks.
  - DRY reports `fp_whole_network_validate` refusals.
