# Code-check round 3 (#104): the mechanism behind rounds 1-2, and where else it reaches

## Mechanism

Both earlier findings came from one assumption: that an environment the branch does not control
behaves like the one it was written in. Round 1 assumed the runtime's base R (`%||%` is base only
from 4.4.0). Round 2 assumed the publish layer's reader (`all_ff04` was described as working
"without a schema change", but stac_floodplains_bc's reader refuses any scenario key not matching
`^[a-z]{2}_ff[0-9]{2}$`). Each time, code or prose made a claim about a runtime, consumer or caller
that sits outside the diff, and nothing in the diff measured that claim. Below is every place in
the branch where that assumption appears, each measured on 2026-10-11 against the local machine,
the `fresh-db` container and the sibling repo at `40b75ca`.

1. **Base R / runtime version.** Every new use of `%||%` has a local definition in scope:
   `fp_provenance.R:45` covers `provenance-check.R` (`viol_habitat`, line 291) and 01 through
   `run_area.R`, and `habitat_join-query.R:24` defines its own. `fp_region.R` and
   `whole_network-check.R` do not use it. The other base functions the new code calls
   (`sort(method = "radix")`, `tabulate`, `utils::modifyList`, the pipe `|>` in 01, which was
   already there) all exist in older R. Runtime here: R 4.5.2. **Holds.**
2. **Package floors.** 02 refuses whole mode when flooded < 0.6.4. Installed: flooded 0.6.5, sf
   1.1.2, GDAL (through sf) 3.8.5. `packageVersion() < "0.6.4"` compares a package_version with a
   string correctly. **Holds.**
3. **Publish layer: how it discovers areas.** `stac_floodplains_bc/scripts/01_stage.R:130-150`
   builds its WSG list only from `config/regions/*.yml`. DUNC is in no region file, so the stage
   never reads `data/dunc/provenance.json`, and the reader's scenario-key `stop()` at
   `fp_provenance.R:250` cannot abort a publish of the other areas. **Holds.**
4. **Publish layer: the other keys a whole-network record carries.** The reader does not
   regex-check network-section names (`all2` is fine), and it does not whitelist keys inside a
   network entry body (the `habitat` sibling is fine). It requires `inputs$species` in every network
   section, and 01 writes it (`species = "all"`). The top-level whitelist (`area`, `wsg`,
   `schema_version`, `network`, `floodplain`, `landcover`) is not touched, because the sibling is
   nested. #123 names the one blocking regex correctly. **Holds.**
5. **Database: which tables the habitat discovery finds, and of what kind.**
   `information_schema.tables` returns all 8 of `fresh.streams_habitat_{bt,ch,cm,co,pk,sk,st,wct}`.
   All 8 are relkind `r` (no materialized views, which `information_schema.tables` would miss), and
   `streams_habitat_long_vw` is excluded by the pattern. **Holds.**
6. **Database: column names and types the habitat SQL assumes.** Every `streams_habitat_<sp>` in
   every schema in the database (bowr, bulk, fran, fresh, fresh_default, fresh_smoke, kisp, ...) has
   all five flag columns. In `fresh` they are `boolean`, and the join keys are `id_segment integer`
   and `watershed_group_code varchar`. Every `<schema>.streams` has `upstream_route_measure`. A
   `network_source` other than `fresh` therefore cannot fail on a missing column. **Holds.**
7. **Database: the claims about DUNC in area.yml and CLAUDE.md.** fresh.streams has 26,827 DUNC
   rows; fresh.streams_access 0; fresh_default.streams 0; fresh.streams_habitat_bt 26,827;
   streams_habitat_co 0. Joining on `id_segment` alone gives 1,956,822 rows (the "1.96 M" claim).
   **Holds.**
8. **Digest key uniqueness.** `(blue_line_key, downstream_route_measure)` is unique for DUNC in
   fresh.streams (26,827 of 26,827, and still unique at the 3-decimal rounding
   `habitat_join-query.R` keys on) and in fwa_stream_networks_sp (22,627 of 22,627). In any case
   `fp_table_content_sha256` sorts whole lines, not keys, so it does not depend on uniqueness.
   **Holds.**
9. **Driver value shapes.** The `fwapg_sha` path covers every shape `link_log` can take.
   `fp_prov_null_fill` sets an absent key to logical `NA`, which `as.character()` turns into
   `NA_character_` with source `unresolved`. A NULL `link_log` (DUNC) takes the same route through
   the NULL branch. bigint/integer64 columns are made numeric before the digest. **Holds.**
10. **gpkg/GDAL round trip of `habitat_link`.** Verified by an earlier round, not redone. It is an
    attribute table in `aquatic_network.gpkg`, and `gpkg_backfill-wsg.R` touches only
    `floodplain.gpkg` and `floodplain_landcover.gpkg`. Its species values `bt`/`wct` can therefore
    never be rewritten to the item key `all`. **Holds.**
11. **Callers of 01 and 02, which now call `fp_whole_network*()` from `fp_region.R`.** Every
    `source()` of 01 or 02 sources `fp_region.R` first: `run_area.R:186-188`,
    `floodplain_probe-whole-fwa.R:161-162` and `whole_network-check.R:13-15`. Nothing else sources
    them. **Holds.**
12. **The token `"all"` against other uses of the string.** 02's `fp_floodplain(cfg, scenarios =
    "all")` selector is a different argument, compared against `scenarios` and not
    `cfg$species`, and `run_area.R:208` passes the default `"run"`. `yaml.load("species: all")`
    gives the string `"all"`, not a YAML 1.1 boolean. **Holds.**
13. **Region runner.** `fp_region_refuse_whole()` runs at `run_region.R:48`, after
    `fp_region.R` is sourced (line 27) and before the pre-pass SQL. Every group's plan is computed
    (line 122) before any `fp_region_write` (line 142), so a refusal partway through a region writes
    nothing. **Holds.**
14. **Check scripts that default to an area.** `whole_network-check.R` takes no area, and it PASSes
    from a copy of `scripts/` with no `data/`. `provenance-check.R` offline PASSes, section 3d
    included. `habitat_join-demo.R` still hardcodes MORR and passes `st_crs(hab[[1]])`, which is
    defined before `grid_cells()` is first called. `habitat_join-query.R` requires an area and
    refuses one that is not whole-network. **Holds.**
15. **A `stats::aggregate()` trap in the shared join.** `fp_hj_join_blk()` uses the formula
    interface. Spawning and rearing are NA-resolved before the call in both callers, so
    `na.omit` drops nothing. A species with habitat rows but zero segments matching the schema
    would raise "no rows to aggregate" before the match table is logged. That is a loud failure,
    not a silent pass, and `habitat_join-query.R`'s match report covers the partial case. **Holds
    (fails loud at the extreme).**

## Clean

No issues found. Every assumption the branch makes about a runtime, consumer or caller outside it
was measured and holds today.

/Users/airvine/Projects/repo/floodplains/planning/active/review-round3.md
