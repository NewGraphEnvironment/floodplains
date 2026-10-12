# Plan review 1 (#104) — Plan agent, returned 2026-10-12 ~01:24 UTC

Reviewed task_plan.md plus the uncommitted Phase 0-2 diff. 23 findings; condensed, with disposition.

| # | Kind | Finding | Disposition |
|---|---|---|---|
| 1 | Blocker | `habitat_link` has no geometry; the position join needs segment lines, and 2,211 of 2,236 DUNC order>=2 blue lines also have order-1 segments, which `streams_all2` lacks | Query script takes segment geometry from the model's own `<schema>.streams` (all orders, as the demo does), matched to `habitat_link` on (blk, drm), and reports the key-match rate. Plan text fixed. Publishing geometry for the join goes to the follow-up (Parquet) issue |
| 2 | Blocker | Plan's digest spec (key-only, text species) is refused by `fp_table_content_sha256`; plan text stale | Already implemented per species with flags 0/1, as a `habitat` sibling; plan text updated |
| 3 | Gap | `inputs$species` auto-unboxes to a scalar for one species | Fixed: `I()` |
| 4 | Gap | habitat no-rows refusal runs after streams and the network record are written | Fixed: habitat read before any write |
| 5 | Gap | "whole entry with no habitat" checked live only | Fixed: in `viol_habitat`, must-fail arm in 3d |
| 6 | Gap | whole mode does not require `attribute_by` | Fixed: `fp_whole_network_validate()` requires `attribute_by: blue_line_key` |
| 7 | Gap | area.yml spec missing keys | Already full in config/dunc/area.yml |
| 8 | Gap | `fwapg_sha` will be NA for DUNC | Added `fwa_content_sha256`, a digest over the group's `fwa_stream_networks_sp` (blk, drm, length_metre) a consumer can recompute |
| 9 | Gap | no species-mode area re-checked live | Added `provenance-check.R bulk` / `neexdzii` to Validation |
| 10 | Gap | `bridge-check.R dunc` defaults to co_ff04 | Pass `all_ff04` |
| 11 | Gap | no-log-row path never run live | DUNC step 1 ran it live (link_log null + note, source `unresolved`); `provenance-check.R dunc` validates it |
| 12 | Ordering | region refusal placement | Already in run_region.R before the pre-pass and in fp_region_plan; arms in whole_network-check.R |
| 13 | Ordering | demo re-run overwrites committed log/PNGs | Ran a copy into scratch: log identical except timestamp/run time; fig2 bytes differ, figures not replaced |
| 14 | Ordering | sourcing of the predicate | Done (provenance-check and whole_network-check source fp_region.R) |
| 15 | Assumption | flooded already 0.6.5 | Reviewer saw it after Phase 0's install. `field =` deprecation: out of scope (changes every area's call); noted |
| 16 | Assumption | guard should be strict | Already strict (0.0% dev). Noted guard checks FWA coverage only |
| 17 | Assumption | wct has rows | Include wct |
| 18 | Assumption | discovery regex | Kept; per schema |
| 19 | Scope | only the primary scenario is keyed | Recorded in #104 as a known limit, not widened here |
| 20 | Scope | publish hint misleading for DUNC | PR body + DUNC log say DUNC is not staged by stac (no region) |
| 21 | Scope | DUNC moves when flooded#67 lands | Caveat in the DUNC log |
| 22 | Scope | CLAUDE.md lines false for `all` | Phase 6 edits both |
| 23 | Scope | BUILD in whole mode untested | Refused: whole mode requires `network_source` |
