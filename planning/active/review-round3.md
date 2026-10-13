# Code-check round 3 (#126)

Reviewed: `git diff 92502338...HEAD` (excluding planning/), HEAD 2b75578. The offline
`provenance-check.R` was run from a `git archive HEAD` copy in the scratchpad: PASS, all 33 checks
in 5g green, 1 "FAIL" string in the log and it is the word inside a check name. Nothing under the
repo was written except this file.

## Verdict

No bug or security finding. Two fragile findings below, neither reachable by today's data.

## Findings

- **[fragile] scripts/floodplain_lcc/fp_provenance.R:348-349.** The R2 floodplain guard fails
  toward pass on an unparseable floodplain stamp.
  `fp_t <- fp_prov_ts(prov$floodplain[[key]]$run$datetime_utc %||% NA)` followed by
  `if (!is.na(fp_t) && fp_t > step3_t)` treats a PRESENT floodplain entry whose stamp is absent or
  not in `FP_PROV_TS_FMT` the same as "no floodplain record". The re-stamp then proceeds. This is
  the rule `fp_prov_late_rasters()` (lines 286-297) rejects for the landcover stamp: "nothing is
  late from a stamp that could not be read is the guard failing toward pass".
  `fp_composition.R:187-191` has the same shape (`isTRUE(NA > x)`), so it was inherited rather
  than introduced. It is not reachable through `fp_prov_run()`, which always writes the format, and
  `viol_split` flags a missing `run.datetime_utc`. A hand-edited or v1 record would still slip
  through. Fix: refuse when `!is.null(prov$floodplain[[key]])` and `is.na(fp_t)`.

- **[fragile] The stamp is also read as "did upstream re-run?", and a re-stamp now answers yes.**
  These readers are listed in the enumeration below. They skip rather than fail, and none of them
  covers necr or kotl, so nothing breaks today.
  - `stac_floodplains_bc/scripts/stage_years-check.R:164-168` (ufra PIN_STAMP).
  - `stac_floodplains_bc/scripts/fp_provenance-check.R:371-375` (neexdzii PIN_STAMP).
  - `scripts/floodplain_lcc/provenance_ab-compare.R:150-186` (LIVENESS).

  If either pinned area is ever repaired in place, its pin is skipped with the message "upstream
  re-ran -- re-take the pin". The landcover_key fold pin is content-only and would still hold, so
  that skip discards a valid assertion. An A/B with a repair between its passes reads as live even
  if pass 2 never reached step 3, because the hashes stay identical and the stamp moves.

## The mechanism

R1 (toolchain), R2a (`datetime_utc`) and this round's second finding are one mechanism. **`run`
was designed as ONE event, step 3's.** `fp_prov_set` replaces the whole entry, and `fp_prov_run`
writes one `datetime_utc` and one `toolchain`. Every reader of a `run` field therefore reads it as
"the step-3 event". The re-stamp makes `run` a record of several events (step 3 plus repairs)
while those readers stay in place. Each `run` field is now one of two kinds:

- **Moved to the repair:** `datetime_utc`. Its readers split into "when step 3 ran" and "when the
  bytes were last written" (below).
- **Left at step 3:** `toolchain` (R1). Nothing outside floodplains reads it. `viol_split`
  requires it to be present and populated, and the re-stamp keeps it, so that check still passes.
  Its meaning is now "the step-3 toolchain", stated in CLAUDE.md.

There are no other `run` fields on landcover entries. necr's `run` holds only `datetime_utc`,
`repairs` and `toolchain`, measured from `data/necr/provenance.json`. Nothing whitelists keys
inside `run`: `viol_split` checks names for overlap with `inputs`/`outputs`, and stac's
`fp_prov_leaf` reads explicit paths. So `repairs` is inert to every reader.

R1b and R2b (the `tryCatch` scope) are a separate, smaller mechanism. The raising calls were
enumerated by memory rather than by walking the block. I walked the block in
`raster_strip-tags.R:241-693`:
- `yaml` read: caught.
- `fp_prov_read`: caught.
- `fp_prov_reconcile_late`: caught.
- `normalizePath` at line 673: default `mustWork = NA`, so it only warns, on files that exist.
- `fp_prov_lc_rasters`: `list.files`, which cannot raise.
- `switch` and `message`: cannot raise.

Nothing in the block can still abort before the summary.

## Every reader of `run.datetime_utc`, both repos

Grepped for `datetime_utc|produced_datetime|[["run"]]|$run|run$` across `floodplains/scripts`,
`README.Rmd` and `stac_floodplains_bc/scripts` (stac HEAD d097436). Fixtures and writers are
excluded.

| # | reader | section | reads it as | does the re-stamp break it? |
|---|---|---|---|---|
| 1 | `floodplains/scripts/floodplain_lcc/fp_composition.R:187-191` (also via `composition_build.R`) | floodplain vs landcover | **when step 3 ran**: the rasters were masked to the floodplain current at that time | Would have, and it is closed by R2a's refusal in `fp_prov_restamp` (compared with `repairs[[1]]$previous_datetime_utc`). After a re-stamp, any later step-2 run is stamped later than the repair time, so the guard still fires. A step-2 run between step 3 and the repair is refused at re-stamp time; tested in 5g. Residual: the fail-toward-pass above. |
| 2 | `floodplains/scripts/run_region.R:174-178` | landcover (max over keys) | display only: "[provenance <date>]" on a cached SKIP line | No. The cache decision does not read it. It now shows the repair time. |
| 3 | `floodplains/scripts/floodplain_lcc/provenance_ab-compare.R:150-186` | every section | **a run happened**: LIVENESS means the stamp moved between A and B | Only if a repair falls between the two passes. It would then mask a pass 2 that never reached step 3, since the hashes stay identical. Not part of any workflow. Fragile, above. |
| 4 | `floodplains/scripts/floodplain_lcc/provenance-check.R:208-209, 249-250, 303-304` (`viol_split` / composition / habitat) | all | presence only | No. |
| 5 | `floodplains/scripts/floodplain_lcc/provenance-check.R:2135-2144` (new 7c arm, `fp_prov_late_rasters`) | landcover | **when the bytes were last written** | It is what the re-stamp satisfies. |
| 6 | `floodplains/scripts/floodplain_lcc/fp_provenance.R:286-297, 315-378, 397-454` (the new helpers) | landcover, floodplain | both, kept apart: `old` = current (bytes) stamp, `step3` = the original | No. |
| 7 | `stac_floodplains_bc/scripts/fp_provenance.R:67` → `nge:produced_datetime` (`01_stage.R:62`, `item_create.py:172`, `02_raster_tag.py:86` as a COG tag, `item_validate.py:450` key presence) | landcover | "the timestamp that describes what was published" (comment :40-43) | Accepted design: it now carries the repair time. Already-published COGs keep the old tag until stac#59 rebuilds them. |
| 8 | `stac_floodplains_bc/scripts/fp_provenance.R:468-490` `fp_prov_rasters_current` (via `01_stage.R:256-264`) | landcover | **when the bytes were last written**: refuses a raster newer than it | It is what the re-stamp fixes. The raster set and floor rule match `fp_prov_lc_rasters` and `fp_prov_late_rasters`: the anchored `^classified_[0-9]{4}\.tif$` (01_stage.R:240) plus `transition.tif`, both floored. That agreement is held by a comment, not by a check (two lists that agree). |
| 9 | `stac_floodplains_bc/scripts/test_pipeline.R:189` | landcover | equality of the published value against the producer file | No. Both sides move together. |
| 10 | `stac_floodplains_bc/scripts/stage_years-check.R:164-168` | landcover (ufra) | **build identity**: "upstream re-ran" gates the meta.json pin | Skips with a misleading reason if ufra is ever re-stamped. The pin would move anyway, because meta.json carries produced_datetime. Fragile, above. |
| 11 | `stac_floodplains_bc/scripts/fp_provenance-check.R:371-375` | landcover (neexdzii) | **build identity**: gates the landcover_key fold pin | Skips a still-valid content assertion if neexdzii is ever re-stamped. Fragile, above. |

No other reader exists:
- the landcover_accuracy module, step scripts 01-03, `fire_tag.R`, `composition-check.R` and
  `readme_functions.R` read no `run` field;
- `composition-check.R` reads only digests;
- step 3 writes its stamp (`03_lulc_classify.R:487`) and `fp_prov_set` replaces the whole entry,
  so a step-3 re-run clears `repairs` and the step-3/repair split resets correctly;
- `composition_build.R` (`fp_prov_set_sibling`) keeps `run.repairs`.

The floodplain section's `run.datetime_utc` has one reader, #1. This branch does not move it.
`raster_strip-tags.R` repairs `floodplain_<scen>.tif` in place without moving it, and it prints a
NOTE when it does. That is safe for #1: moving it would be the hazard. Nothing compares a
floodplain raster's mtime with its stamp in either repo.
