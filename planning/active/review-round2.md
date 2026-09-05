# Review — round 2, issue #83 staged diff

Reviewed: `git diff --cached` — `scripts/floodplain_lcc/raster_strip-tags.R` (new),
`scripts/floodplain_lcc/logs/20260905_raster-tags_strip_necr-kotl.md` (new),
`planning/active/findings.md`, `planning/active/task_plan.md`.

Everything measured below was measured against the tree at
`/Users/airvine/Projects/repo/floodplains` on 2026-09-05, terra 1.9.34.

**The data is in good shape.** Independently re-derived, not read back from the script's own
output:

| check | result |
|---|---|
| `fp_rast_stray_tags()` over all 184 `.tif` under `data/` | **0 dirty** |
| necr 7 + kotl 7 `classified_content_sha256` vs each area's `provenance.json` | **14 match, 0 mismatch** |
| `terra::is.factor()` / `cats()` on all 14 repaired rasters | TRUE, 7–9 rows each — class names intact |
| stale `.*strip*` temp files under `data/` | none |
| `scripts/floodplain_lcc/logs/20260905_...md` tracked by git | yes |

So the repair itself landed correctly. The findings below are about the script as a committed
tool that will be run again, and about two numbers in the committed evidence log.

## Findings

- **[bug] `scripts/floodplain_lcc/raster_strip-tags.R:175-178` — `file.rename()` returns FALSE on
  failure and both return values are discarded. The one destructive step is the only unchecked
  one, and it fails toward "ok".**

  Every check in this script (lines 111, 113, 132, 159, 170) aborts, records `failed`, and leaves
  the original untouched. Then lines 175–176 move both files fire-and-forget, line 177 increments
  `repaired`, and line 178 prints `ok: N tags removed, content sha unchanged`. Three states, none
  detected:

  1. **Rename #1 fails, #2 runs anyway.** The original `.tif` keeps its 30 stray tags, and line
     176 still overwrites the *original's* `.aux.xml` with the temp's. The script reports the file
     repaired. This is the exact fail-toward-pass shape on the single claim the script exists to
     make.
  2. **Rename #1 succeeds, #2 fails.** New `.tif` beside the stale sidecar, plus an orphaned
     hidden `.<name>.strip<pid>.tif.aux.xml` left in a published raster directory. Reported `ok`.
  3. Either way the summary at line 181 and the exit status are both success.

  Measured, not reasoned — `Rscript`, two failing renames in a loop:

  ```
  iter 1 returned: FALSE
  iter 2 returned: FALSE
  Warning messages:
  1: In file.rename(...) : cannot rename file ... reason 'No such file or directory'
  ...
  SUMMARY: Repaired 2 of 2
  exit=0
  ```

  The warnings are deferred to the end of the enclosing top-level expression (the `for` loop), so
  they print *above* the summary line and the exit code stays 0 — CLAUDE.md's "A wrapper's exit is
  not the work", in-process.

  It also makes line 185's `FAILED (left untouched)` a claim nothing can contradict: the one state
  in which the original is *not* left untouched is the one state that never enters `failed`.

  Note this is the only place where the acceptance evidence stops being about the artefact. All
  four checks run on `tmp`; verifying `tmp` is verifying `f` **only if the rename succeeded**, and
  that is precisely the untested conditional.

  Fix: test both renames, record `failed` and `next` on either, and re-assert
  `fp_rast_stray_tags(f)` (or at least `file.exists`) on the *target* after the move — a
  post-rename read of `f` is the one check that reads the file the script actually changed. Order
  the sidecar rename so a half-move is recoverable rather than silent.

- **[bug] `scripts/floodplain_lcc/raster_strip-tags.R:170-174` — the `aux_tmp` existence guard makes
  the script structurally unable to repair any raster that has no category names, and aborts with a
  message that is false for exactly those files.**

  Measured, writing through this repo's own `fp_rast_write()` at the datatype the script reads off
  the source:

  ```
  floodplain_ch_ff04.tif  dt=FLT4S -> aux.xml written: FALSE
  transition.tif          dt=INT4S -> aux.xml written: TRUE
  ```

  `data/necr/floodplain_ch_ff04.tif` has no `.aux.xml` on disk and `terra::cats()[[1]]` is `NULL`
  for it. **72 of the 184 files this sweep enumerates are `floodplain_*.tif`** (88 classified, 72
  floodplain, 24 transition — counted). If any one of them is dirty, the script writes a correct
  temp, passes all four acceptance checks (`sha`, `cats` — vacuously, `NULL == NULL` — band diff,
  stray tags), then aborts at line 170 with

  > `terra wrote no .aux.xml -- the category names would be lost`

  …on a raster that has no category names to lose, deletes the good temp, marks the file FAILED,
  and exits 1. CLAUDE.md, "A guard that fires correctly and then points at the wrong fix", plus "A
  fixture that cannot reach the failure mode" — all 14 files the guard was exercised against were
  categorical, so the non-categorical branch has never run.

  It fails toward abort, so it is not data loss; it is a repair tool that refuses 39% of the
  population it advertises sweeping, with a wrong diagnosis. The condition wanted is *"the source
  had categories ⇒ the temp must too"*, e.g. gate the abort on
  `!is.null(cats_before) || file.exists(paste0(f, ".aux.xml"))`.

- **[fragile] `scripts/floodplain_lcc/raster_strip-tags.R:125-126, 82-84` — a temp file orphaned by a
  kill between the write and the rename is never swept, never reported, and invisible to the
  script's own enumeration.**

  The log records this happening (the kotl pass killed by a 2-minute timeout); it left no temp only
  because the kill landed between files. `list.files()` defaults to `all.files = FALSE`, so a
  leading-dot temp is excluded from `tifs` — which is what keeps a stale temp from being swept as
  if it were an output, and is also what makes it permanently invisible. The leading dot is
  well-reasoned for the publish side (`catalogue_release.sh` excludes `.*` / `*/.*`), so this is not
  a publish hazard; it is #55's orphan class in a directory the repo says nothing cleans. One line
  at start-up — `list.files(adir, pattern = "\\.strip[0-9]+\\.tif$", all.files = TRUE, recursive =
  TRUE)` — turns it into a reported state.

- **[fragile] `scripts/floodplain_lcc/logs/20260905_raster-tags_strip_necr-kotl.md:24-26` — the
  "116 files / understated by 68" figures do not reconcile against the glob the sentence names.**

  The log says the earlier sweep *"reported 116 files because it globbed `data/*/rasters/*/*.tif`"*
  and that *"the clean population was understated by 68"*. Measured now:

  ```
  ls data/*/rasters/*/*.tif | wc -l   -> 112
  find data -name '*.tif' | wc -l     -> 184
  ```

  112, not 116; and 184 − 112 = **72**, not 68 — which is exactly the `floodplain_*.tif` count, so
  72 is the number that is self-consistent with the log's own explanation ("step 2 writes one
  directory up"). 68 is derived from 116, so both move together. The 184 / 88 / 72 / 24 / 23-areas
  figures elsewhere in the log all verify exactly, as do "7 match, 0 mismatch", "7 of 7 class names
  present", "0 stray tags across all 184", and `Repaired 0 of 11` (necr has 11 tifs). This is the
  one row that does not.

  Note `scripts/fp_raster.R:72` carries the same `116` (pre-existing, not in this diff) — one fact
  restated in two places, so fixing only the log leaves the other reading as corroboration.

- **[fragile] `scripts/floodplain_lcc/logs/...md:59` and `planning/active/findings.md:126` — "all 512
  category rows" / "all 512 category rows, all 256 palette entries" overstates what the artefact
  contains.**

  Measured on `data/necr/rasters/ch_ff04/classified_2017.tif`:

  ```
  <Category> entries in the .aux.xml     : 256
  gdalinfo "Categories:" block lines     : 256
  gdalinfo colour-table entries          : 256
  ```

  256 categories and 256 palette entries; 512 is the two blocks added together. findings.md's
  phrasing ("512 category rows, **all 256 palette entries**") then implies 768. Minor, but this is
  the committed evidence record for a repair whose whole thesis is that the RAT survived, so the
  number should be the one the file actually holds.

## Checked and clean

Recording these so a later round does not re-open them.

- **DRY genuinely previews.** `if (dry) next` at line 104 precedes every write, and the only file
  access before it is `fp_rast_stray_tags()`, which reads with `GDAL_PAM_ENABLED=NO` and so cannot
  provoke a PAM sidecar write. The `flagged` / `repaired` split is right, and the counts close in
  both modes: DRY `flagged + clean == length(tifs)`; live `repaired + length(failed) + clean ==
  length(tifs)`.
- **`band_section()` fails toward abort, not toward "no difference".** With `gdalinfo` absent,
  `system2(stdout = TRUE)` returns `character(0)` under the `suppressWarnings`; line 113 then
  aborts on `!length(band_before)`, and an empty `band_after` trips the length compare at line 140.
  Both directions covered.
- **`dt <- terra::datatype(terra::rast(f))[1]`** measured correct for all three kinds — INT1U
  (classified), INT4S (transition), FLT4S (floodplain) — and every raster under `data/` is
  single-band, so `[1]` is not hiding a per-layer mismatch. A bad datatype would error inside the
  `tryCatch`, and truncation would move the content digest; both abort.
- **`terra::cats(...)[[1]]` does not error on a non-categorical raster** — `cats()` returns a
  length-1 list whose element is `NULL`. No subscript-out-of-bounds risk. (The comparison is
  vacuous there, which is what puts all the weight on the broken `aux_tmp` guard above.)
- **The temp name cannot be picked up by the sweep** (dot-file, `all.files = FALSE`), cannot
  collide between concurrent runs (pid), and sits on the same filesystem as the target.
- **`PALETTE_NODATA` is unambiguous** — `grep -nE '^ *255: (0,0,0,0|255,255,255,0) *$'` matches
  exactly one line in a full `gdalinfo` dump.
- **No circular verification.** `sha_before` (from `f`) vs `sha_after` (from `tmp`) are two files
  through one function, with `NA` rejected on both sides; `provenance.json` was written by the #79
  run, before this repair existed, so the digest reconciliation is a genuinely independent
  reference. `fp_rast_stray_tags(tmp)` at line 157 duplicates the check `fp_rast_write()` already
  performs internally — redundant, not circular.
- **The `cats_before` read at line 149 happens after the temp write but reads `f`, which is
  untouched at that point** — correct, not a stale-key hazard.
- Log claims verified against the tree: 184 tifs / 23 areas / 88+72+24 split; necr's 7 digests;
  class names present on all 7 (and all 7 kotl); 0 stray tags fleet-wide; `Repaired 0 of 11`.

/Users/airvine/Projects/repo/floodplains/planning/active/review-round2.md
