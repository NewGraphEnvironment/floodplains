# Review round 1 — branch 126 (re-stamp after in-place repair)

Scope: `git diff 92502338...HEAD` minus planning/. Offline `provenance-check.R` was run from a
scratch copy (`cp -r scripts config`): rc 0, 0 FAIL, all 5g arms ok, ending "PASS — all
properties hold". Read-only check of every `data/*/provenance.json`: `area` and `wsg` equal the
directory name and `area.yml`'s `watershed_group` for all 22, so the cfg that
`raster_strip-tags.R` builds cannot trip the on-disk identity check on any existing area.

## Findings

- **[severity: fragile]** scripts/floodplain_lcc/fp_provenance.R:206 (`repair$toolchain <- fp_toolchain()`).
  - **What is wrong.** On the forward path the repair records "the toolchain that ran". But
    `fp_toolchain()` reports **sf's** GDAL, and the repair rewrites through **terra**
    (`fp_rast_write()` → `writeRaster`). Measured on this machine: `terra::gdal()` is 3.13.0,
    `sf_extSoftVersion()["GDAL"]` is 3.8.5, and terra is 1.9.50.
  - **Why it matters.** The next forward repair writes `repairs[[n]].toolchain.gdal = "3.8.5"`
    for bytes that GDAL 3.13.0 encoded. That is a confidently wrong value in a written record.
    It is the field #64 says exists to diagnose a container divergence, and it is the
    terra-vs-sf split that #117 documents. Step 3's own `run.toolchain` has the same
    limitation, which is known. This diff, though, labels the value the repair's toolchain.
  - **Fix.** Record terra's GDAL alongside it (`terra::gdal()`) in the repair record, or drop
    the `gdal` claim there.
  - **Pre-existing, related.** The header of `raster_strip-tags.R` still says the rewrite
    "uses the toolchain that wrote these files (GDAL 3.8.5 via terra)". With terra 1.9.50 that
    is no longer true.

- **[severity: fragile]** scripts/floodplain_lcc/raster_strip-tags.R:626-640, together with fp_provenance.R:155 ("Never stops on a refusal").
  - **What is wrong.** `fp_prov_reconcile_late()` documents that it returns `refused` rather
    than stopping, but several paths inside it raise:
    - `fp_prov_late_rasters()` stops on an unparseable stamp.
    - `fp_prov_restamp()` stops on "not later", on a concurrent mtime change, and on the
      on-disk mismatch, which restores the file first.
    - `fp_rast_stray_tags()` and `fp_raster_content_sha256()` can error on a bad file.

    The loop in the script has no `tryCatch`, so any of these aborts the whole re-stamp pass.
  - **Why it matters.** It does fail loud (the R error gives a non-zero exit), so it does not
    fail toward pass. But on a multi-scenario area (morr: `co_ff04` + `ch_ff06`) an error on
    the first key leaves the second key's freshly repaired rasters unstamped. `repaired_paths`
    exists only in memory, and a re-run finds nothing to strip. So the only way to recover is
    `BACKFILL=1`, which marks that key `backfilled` and drops the toolchain. A transient failure
    therefore permanently degrades the repair record. The "FAILED (left untouched)" /
    "NOT RE-STAMPED" summary lines are also skipped.
  - **Fix.** Wrap each key's call and record an error as `refused`
    (`restamp_failed <- c(restamp_failed, k)`), so every key is attempted and the summary
    always prints.

No other issues found. Checked and clean:
- Floor arithmetic matches the publish guard exactly: new stamp = floor(max late mtime), so
  floor(mtime) > stamp is false afterwards.
- A stamp can only move forward.
- The on-disk `identical()` comparison holds: `read_json`→`toJSON` is stable for ints, empty
  arrays and objects, nulls, and `digits = NA` doubles.
- The `$`-partial-match avoidance holds.
- `files` is always written as a JSON array.
- The `normalizePath` set difference is correct.
- DRY writes nothing.
- The 7c error branch fails rather than passes.
- The CLAUDE.md and log claims match the code and the live records: necr 22:44:28Z, kotl
  22:47:07Z, one `repairs` entry each.
