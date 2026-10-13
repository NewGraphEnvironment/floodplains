## Outcome

PR #85's in-place repair of necr and kotl's classified rasters (#83) left
`landcover.<scen>.run.datetime_utc` behind the rewritten bytes. stac_floodplains_bc's staging
guard therefore refused both areas, and `nge:produced_datetime` reported a time three hours too
early.

**What changed:**
- `raster_strip-tags.R` now reconciles the record after its sweep (`fp_prov_reconcile_late`). A
  late raster must still match its recorded content digest. The stamp then moves to its floored
  mtime, and `run.repairs` records the repair with the stamp it replaced (the user's decision at
  the plan gate).
- A late file that the current run did not repair needs `BACKFILL=1`.
- `provenance-check.R` gains an offline section (5g) and a live 7c arm, so the class is caught
  in this repo first.

**What was learned:**
- `fp_prov_set()`'s JSON round trip moves `inputs_hash` on every live entry, so a re-stamp has
  to edit `run` in place.
- `fp_prov_hash()` cannot tell `2017L` from `2017`.
- `$toolchain` partial-matched a `toolchain_recorded` sibling.
- `run.datetime_utc` turned out to have two meanings. `fp_composition.R` reads it as "when step 3
  ran". Code-check round 2 found that a re-stamp could have switched off its step-2-re-run guard,
  so the re-stamp now refuses against the step-3 time.

## Measurement

| area / scenario | stamp before | stamp after |
|---|---|---|
| necr `ch_ff04` | 19:14:08Z | 22:44:28Z |
| kotl `bt_ff04` | 19:46:31Z | 22:47:07Z |

The new stamp is the newest repaired raster's mtime (22:44:28.047 and 22:47:07.600), floored to
the second, and matches the issue's table exactly. In all 14 late rasters, the content digest
matched the record and no stray tags were left.

Each entry is identical to its snapshot once `run` is removed (parsed comparison). A second run
left the md5 unchanged. `provenance-check.R` passes on both areas after the backfill; before it,
each failed on exactly the late-raster arm.

stac's `fp_prov_rasters_current()`, run read-only, passes on necr, kotl and bulk, and stops on the
pre-backfill necr record.

Code-check took 3 rounds:
- **Round 1:** the repair recorded sf's GDAL, not terra's; one entry's error aborted the loop.
- **Round 2:** the composition guard bypass, plus a raising call one line outside round 1's
  `tryCatch`.
- **Round 3:** an unparseable floodplain stamp read as "no floodplain".

The loop ended on two enumerations: the 11 readers of `run.datetime_utc` across both repos, and
every NA branch in the new code.

## Evidence

- `scripts/floodplain_lcc/logs/20261013_provenance_restamp_necr-kotl.md`
- `review-plan.md` and `review-round*.md` in this directory.

Closed by: PR for #126 (branch `126-pr-85-s-in-place-repair-left-run-datetim`)
