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
- `fp_prov_set()` (`fp_provenance.R:169`) recomputes `inputs_hash` from a JSON round trip, and
  that round trip MOVES it on every live landcover entry (plan review B1: `I()` vectors read back
  as lists). So the re-stamp edits `run` in place and writes via `fp_prov_write()`, the
  `fp_prov_set_sibling()` pattern. `fp_prov_read()` overwrites `area`/`wsg`/`schema_version` from
  `cfg`, so the cfg must carry the true values.
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
- [x] `provenance-check.R`: new offline section (3e or 5g). A landcover entry whose classified or
      transition raster mtime (floored to the second, as stac does) is later than
      `run$datetime_utc` IS reported. Must-fail arm on a fixture with a touched raster; pass arm
      on one written before its stamp. Initially red against the missing helper.
- [x] `fp_provenance.R`: `fp_prov_restamp(cfg, key, datetime_utc, repair)`. Reads the landcover
      entry, sets `run$datetime_utc`, appends `repair` to `run$repairs` (adding
      `previous_datetime_utc`), edits `run` in place and writes via `fp_prov_write()` (review B1).
      Re-reads after writing and compares the parsed file minus that `run` with the pre-write
      parse, restoring the original bytes on mismatch (review G4). Refuses a stamp not later
      than the current one.
- [x] Offline assertions for the helper: hashes and sibling unchanged; `repairs` appends rather
      than replacing; an earlier stamp is refused; must-fail arms (a helper that drops the
      sibling or edits `inputs` IS caught).

## Phase 2: Reconcile step (`fp_prov_reconcile_late()` + `raster_strip-tags.R`)
- [x] `fp_prov_reconcile_late(cfg, key, repaired, backfill, dry)` in `fp_provenance.R` (review G2):
      for landcover[<key>], the late rasters must each re-derive to their recorded digest
      (`inputs.classified_content_sha256[<yr>]`, `outputs.transition_content_sha256`); a missing
      or null digest, or a mismatch, refuses (review G1) and names `run_area.R <area> 3`. Late
      files this invocation did not repair re-stamp only with `backfill = TRUE` and zero stray
      tags (review G3). Stamp = floored newest late mtime (review A2). `repair` entry: kind
      `container_strip`, issue 83, `files` as a list of basenames (A5), `toolchain` only for files
      repaired by this invocation, else `backfilled = TRUE` (A4). `dry` writes nothing.
- [x] 5g arms: digest-matching late files re-stamp; a mismatched or unrecorded digest refuses with
      the file's md5 unchanged; late-but-not-repaired refuses without backfill; dry writes
      nothing; a second call is a no-op.
- [ ] `raster_strip-tags.R`: cfg from the CLI `area` + `config/<area>/area.yml`
      `watershed_group`, asserted non-empty (A3). The reconcile runs for each landcover entry
      BEFORE the final `quit(status = 1)` (O1), with `BACKFILL=1` passed through. Under DRY a
      flagged file is reported as "would re-stamp after repair" (O2). No provenance.json or no
      landcover section: reported and skipped.
- [ ] Floodplain rasters (`floodplain_<scen>.tif`) are out of scope. None has ever been repaired,
      and re-stamping `floodplain[]` later than `landcover[]` would trip the composition guard.
      If one is repaired, the script says so and says the stamp was not moved.
- [ ] Update the header comment: the script now writes provenance (and why it keys on state).

## Phase 3: Backfill necr and kotl (live)
- [ ] Snapshot `data/{necr,kotl}/provenance.json` (byte copies) first.
- [ ] `DRY=1` on both: expect 0 to repair, and a re-stamp of 19:14:08Z -> 22:44:28Z (necr) and
      19:46:31Z -> 22:47:07Z (kotl).
- [ ] `BACKFILL=1` real run on both, then: `provenance-check.R necr` / `kotl` pass (they fail
      before the run, captured in the log, review AC2). Parsed comparison against the snapshot
      with the entry's `run` removed is identical (review A1; not a text diff). A second run
      leaves the file's md5 unchanged (AC1).
- [ ] Check the stac guard reads it: call stac's `fp_prov_rasters_current()` read-only on both
      areas, set up as `01_stage.R:260-264` does (PROV_FIELDS defined, stac root as cwd; review O3). No staging and no publish (one-way coupling).
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
