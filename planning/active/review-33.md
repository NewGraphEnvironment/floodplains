# Plan review — #33 (Plan agent, 2026-09-01)

Full review text preserved below. Verification of each blocker, and the disposition taken, is in
`findings.md` under "Plan review: what was verified and what was done".

Categories used: Blocker / Gap / Ordering / Assumption / Scope / Acceptance.

## Blockers raised

- **B1** — item ids cannot detect an upstream reprocess: the id is `<tile>-<year>`, deterministic
  in tile and year, with no `created`/`updated` property. Swaps one request-side fingerprint for
  another. Suggests digesting the cached raster instead.
- **B2** — `terra::sources(dem)` returns `""` (in memory) or a random per-run temp path (todisk),
  never the `/vsicurl` URL, because `fl_dem_aoi()` always crops and reprojects.
- **B3** — jsonlite `null = "list"` emits `{}` not `null`; default `digits = 4` rounds, and
  read-modify-write re-rounds earlier steps' numbers.
- **B4** — one JSON per area with read-modify-write: concurrent species runs lose updates
  silently; poisoned read; orphan sections.
- **B5** — `run_region.R`'s resume cache skips the child entirely, so provenance goes stale while
  the group reports `ok(cached)`.
- **B6** — guard assertions that fail toward pass: disjointness passes when `run` is absent;
  `item_ids_complete` presence-only; denylist rather than whitelist for credentials.
- **B7** — on a cache hit the recorded items describe today's query, not the raster that was read.

## Notable non-blocker points

- 16 of 19 areas GRAB from `fresh`, not `fresh_default` — the issue's §4/§5 premise is wrong for
  most areas, including the neexdzii parity fixture and morr.
- The `~/Projects/repo/<pkg>` SHA tier can fabricate provenance and makes `inputs` host-dependent.
- `link_log` is an unclassified third bucket the inputs/run split does not describe.
- `run_area.R:21-23` still states the dead parity contract (678.2 / 171.0 / 943).
- An `inputs_hash` would make issue acceptance criterion 2 testable at all.
- `years` is user-settable via `change_interval`, so `years ⊆ available_years` should be checked
  BEFORE the 30-minute fetch, not asserted after it.
