# Task: PR #85's in-place repair left run.datetime_utc behind the rasters: re-stamp it, so necr and kotl can be staged (#126)

PR #85 repaired the necr and kotl classified rasters in place and left `landcover.<scen>.run.datetime_utc` untouched, so the files are now newer than the record that describes them and stac_floodplains_bc's freshness guard refuses to stage both areas (blocks stac_floodplains_bc#68). The record is what is wrong: `nge:produced_datetime` is published from this field. Remedy: re-stamp the section as part of any in-place repair.

## Context

PR #85 (`raster_strip-tags.R`, #83) rewrote the seven `classified_<yr>.tif` files in necr and
kotl in place, but left `landcover.<scen>.run.datetime_utc` unchanged. The rasters are now newer
than the stamp that describes them, so stac_floodplains_bc's freshness guard
(`fp_prov_rasters_current`, stac `scripts/fp_provenance.R:462-490`) refuses to stage both areas.
That blocks stac#68. The same field is published as `nge:produced_datetime`, so the record is
currently wrong, not the guard. Fix: re-stamp as part of the repair, backfill necr and kotl, and
add the guard here so this class of error is caught before it reaches the publish layer.

**Decided (user, plan gate):** the stamp moves to the repair time, and `run.repairs` (an array
under `run`) records each repair with `{datetime_utc, kind: "container_strip", issue: 83, files,
toolchain, previous_datetime_utc}`. `run` is unhashed and not whitelisted, and stac reads only
`run.datetime_utc` (stac `fp_provenance.R:67,472`), so this is inert downstream.

**Exploration that shaped this:**
- `raster_strip-tags.R` never touches `provenance.json`, and it is idempotent: on necr and kotl
  it now finds 0 stray tags. So a re-run cannot backfill **unless the re-stamp is keyed on state**
  (raster mtime > stamp AND content digests match the record), not on "I just repaired something".
  A single reconcile step therefore covers both the forward fix and the backfill.
- `fp_prov_set()` (`fp_provenance.R:169`) replaces the whole entry and recomputes
  `inputs_hash`/`outputs_hash` from `inputs`/`outputs`. Passing the read-back entry with only
  `run` edited leaves both hashes byte-identical and keeps the `composition` sibling (necr has
  one). `fp_prov_path(cfg)` needs only `cfg$dir_out`, while `fp_prov_read()` also reads `area`
  and `watershed_group`.
- Measured: necr `ch_ff04` stamp 19:14:08Z vs newest classified 22:44:28Z; kotl `bt_ff04` stamp
  19:46:31Z vs 22:47:07Z. `transition.tif` predates both stamps. necr's composition sibling is
  stamped 2026-10-02, so re-stamping landcover to 2026-09-05 22:44 does not trip
  `fp_composition.R:187`'s floodplain/landcover ordering.
- Other readers of the stamp: `run_region.R:176` (display only), `fp_composition.R:187` (ordering
  against floodplain: moving landcover later can only relax it), `provenance_ab-compare.R:150`
  (the A/B diff, expected to move).
- `provenance-check.R` 7c already re-derives every `classified_content_sha256` against its raster
  (~line 1915) but never compares mtime to the stamp. That is the gap.

## Phase 1: Offline guard + helper (tests first)
- [ ] `provenance-check.R`: new offline section (3e or 5g). A landcover entry whose classified or
      transition raster mtime (floored to the second, as stac does) is later than
      `run$datetime_utc` IS reported. Must-fail arm on a fixture with a touched raster; pass arm
      on one written before its stamp. Initially red against the missing helper.
- [ ] `fp_provenance.R`: `fp_prov_restamp(cfg, key, datetime_utc, repair)`. Reads the landcover
      entry, sets `run$datetime_utc`, appends `repair` to `run$repairs` (adding
      `previous_datetime_utc`), and writes through `fp_prov_set()`. Asserts afterwards that
      `inputs_hash`, `outputs_hash` and any `composition` sibling are byte-identical to before,
      and refuses if they moved. Refuses a stamp earlier than the current one.
- [ ] Offline assertions for the helper: hashes and sibling unchanged; `repairs` appends rather
      than replacing; an earlier stamp is refused; must-fail arms (a helper that drops the
      sibling or edits `inputs` IS caught).

## Phase 2: Reconcile step in `raster_strip-tags.R`
- [ ] After the sweep, for each `landcover[<scen>]` entry: if any `classified_*`/`transition.tif`
      under `rasters/<scen>/` has mtime > stamp, re-derive each one's content digest against the
      record (`classified_content_sha256`, transition digest). All match: re-stamp to the newest
      raster mtime, with `kind = "container_strip"`, `issue = 83`, the late files and
      `fp_toolchain()`. Any mismatch: refuse and name `run_area.R <area> 3`, because the content
      moved and a re-stamp would bless it. `DRY=1` reports the would-be stamp and writes nothing.
- [ ] Build the minimal cfg (`dir_out`, `area`, `watershed_group`) from `config/<area>/area.yml`.
      No provenance.json or no landcover section: report it and skip.
- [ ] Floodplain rasters (`floodplain_<scen>.tif`) are out of scope. None has ever been repaired,
      and re-stamping `floodplain[]` later than `landcover[]` would trip the composition guard.
      If one is repaired, the script says so and says the stamp was not moved.
- [ ] Update the header comment: the script now writes provenance (and why it keys on state).

## Phase 3: Backfill necr and kotl (live)
- [ ] Snapshot `data/{necr,kotl}/provenance.json` (byte copies) first.
- [ ] `DRY=1` on both: expect 0 to repair, and a re-stamp of 19:14:08Z -> 22:44:28Z (necr) and
      19:46:31Z -> 22:47:07Z (kotl).
- [ ] Real run on both, then: `provenance-check.R necr` / `kotl` pass (they fail before the run,
      which is the live must-fail). `inputs_hash`/`outputs_hash`/composition unchanged versus the
      snapshot (diff only under `run`). A second run is a no-op.
- [ ] Check the stac guard reads it: in a scratch dir, call stac's `fp_prov_rasters_current()`
      read-only on both areas. No staging and no publish (one-way coupling).
- [ ] Commit the run log: `scripts/floodplain_lcc/logs/<yyyymmdd>_provenance_restamp_necr-kotl.md`.

## Phase 4: Docs
- [ ] CLAUDE.md #83 bullet: the repair re-stamps `landcover.run.datetime_utc` and records
      `run.repairs`, necr and kotl are re-stamped, and stac#68 can now stage (stac#59's COG
      rebuild is still the stac side's job).
- [ ] Edit the issue body if anything measured differs from its table.

## Validation

- [ ] Tests pass: `provenance-check.R` (offline) passes, and passes for necr, kotl, bulk and lnth
- [ ] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
