# Review round 3 — #83 branch `83-classified-tif-carry-30-stray-gdalcube`

Scope: whole-branch diff `git diff origin/main...HEAD` (7 commits, 13 files). Every factual
claim in `CLAUDE.md`, the committed log and `fp_raster.R`'s header was checked against the code
and against `data/` by running commands, not by reading. Measured 2026-09-05 on m1,
terra 1.9.34 / sf 1.1.2 / GDAL 3.8.5.

---

## The mechanism behind the eight earlier findings

They are not eight unrelated slips. **On this machine three genuinely different states of a
raster produce one observation, and every one of the eight lives in the gap between two of
them.** The states are:

| # | state | what m1 shows |
|---|---|---|
| A | no dataset metadata at all (`metags()` is `NULL`) | "clean" |
| B | exactly `AREA_OR_POINT` | "clean" |
| C | stray tags, but in a `.aux.xml` sidecar rather than tag 42112 | "dirty", and unfixable by a TIFF rewrite |

m1's read of a gdalcubes `.nc` yields A, m1's write yields B, and any QGIS open produces C. So
"the strip worked", "there was nothing to strip" and "the tags are not in the subject at all"
are the same reading here, and the code was written against the one state actually in hand —
a populated `metags()` table on a `.tif` treated as the whole artefact.

Map the eight onto it:

- **A vs B** — `!nrow(tg)` on a `NULL` (1) and `metags(r) <- NULL` erroring on the empty case
  (2). Both are the A state, which no file on disk can produce, so no fixture reached it.
- **B vs C** — a sidecar making a clean file read dirty (5), and the repair deleting the
  sidecar as a "regenerable cache" and taking the published RAT with it (7). Both are the
  subject boundary: the artefact is `.tif` + `.aux.xml`, and the content digest agrees either
  way, so nothing else could see it.
- **the same collapse one level out, in the CALLERS** — a remedy that assumes a completed run
  (3), a write site left out because its input happens to be clean (4), a preview counter that
  reports the repaired count in a mode that repairs nothing (8), and a source line in a runner
  that writes no rasters (6). Each is a caller state — aborted / second site / DRY / no-op —
  that the one observed caller state does not produce.

The remedy the branch already applies well is enumeration: `§5f` explicitly writes the A case
(`bare`), the C case (the PAM sidecar arm) and the absent-file case, and the fixture *sets* the
tags rather than reading a real cube. **Where the mechanism still reaches is listed below**, and
the first item is the important one.

---

## Findings

### 1. **[bug]** `scripts/floodplain_lcc/provenance-check.R:1219-1230` — §5f's must-fail arm does not exercise `fp_rast_write()`'s refusal; deleting that refusal leaves the whole section green

The comment says *"MUST-FAIL, through the function that is actually called in production …
this proves the guard inside `fp_rast_write` fires."* The code below it does not call
`fp_rast_write` at all — it calls `terra::writeRaster`, then `fp_rast_stray_tags`, then raises
its own `stop("guard would fire on N tags")`. So the assertion is a property of
`fp_rast_stray_tags` (which is already covered three lines up by the *premise* arm), not of the
refusal.

**Measured, by restoring the bug.** Copied the tree to a scratch dir and replaced the guard
body in `fp_rast_write`:

```r
  bad <- character(0)   # RESTORED BUG: guard removed
  if (length(bad)) {
```

Result — §5f reports **14 of 14 ok**, including `must-fail: an unstripped write IS reported
(the guard can go red)`, and the script exits **0**:

```
5f. The written raster container carries only the allowlist (#83)
  ok    ... (all 14)
rc=0
```

For contrast, removing the *strip* instead (`writeRaster(r, …)` in place of
`writeRaster(fp_rast_strip_tags(r), …)`) goes red on 4 arms, correctly. So the strip is pinned
and the refusal is not.

**Why it matters more than the usual coverage gap.** `planning/active/findings.md:198-201` and
`CLAUDE.md:314-316` both state that on m1 the strip is a measured no-op and *"what carries the
assurance is `fp_rast_write()` re-reading the file it just wrote and refusing to continue,
which does not require trusting the strip."* The single line the branch nominates as carrying
the assurance is the one line §5f cannot see disappear. It is also the only guard that would
ever fire in production — the strip cannot fail on m1, so the refusal is the entire live
behaviour of the pin.

Fix is one line: drive the must-fail through `fp_rast_write` with the strip bypassed. e.g.
write `dirty` unstripped, then assert `fp_rast_write` refuses a raster whose tags it is handed
in a form the strip cannot remove — or simplest, temporarily rebind `fp_rast_strip_tags` to
`identity` in a local environment and assert `fp_rast_write` errors with a message matching
`outside the allowlist`. Grep the *message*, not the status (the file already makes that point
correctly for the wrong assertion).

Related, same block: `check(grepl("guard would fire on 10 tags", …))` hardcodes `10` where the
line above derives it as `length(gc_tags)`. That fails loud if `gc_tags` grows, so it is the
safe direction — but it is the second literal in the same two lines that is really about the
fixture rather than about the guard.

---

### 2. **[fragile]** `scripts/floodplain_lcc/provenance-check.R:1160-1161` — §5f is skipped silently when terra/sf are absent, where §7 for the identical condition says "a skip is not a pass"

```r
if (requireNamespace("terra", quietly = TRUE) && requireNamespace("sf", quietly = TRUE) &&
    requireNamespace("jsonlite", quietly = TRUE)) {
```

There is no `else`. The block ends at line 1295 and the script continues. §7 at line 1548 has
the same predicate and *does* handle it:

```r
} else {
  bad("terra/sf unavailable -- `outputs` values were NOT reconciled (a skip is not a pass)")
}
```

So on a host without terra, `provenance-check.R` prints `PASS — all properties hold, and each
was shown able to fail.` while the section that is the entire point of #83 never ran. This is
the same class as finding 6 in the last round (`a fix lands in one of two callers`), between
two sections of one file. (`requireNamespace("jsonlite")` in that predicate can never be FALSE
— `library(jsonlite)` runs at line 25 — so it is decoration, not a real arm.)

§5c at line 845 has the same shape, and it predates this branch; it is worth the same `else`.

---

### 3. **[fragile]** `scripts/floodplain_lcc/provenance-check.R:1678-1690` — the per-year loop iterates `names(csha)` but reports `length(csha)`, so an unnamed digest object passes vacuously while claiming a count

```r
for (yr in names(csha)) { ... }
check(n_bad_sha == 0L,
      sprintf("landcover[%s] all %d classified_content_sha256 re-derive from their .tif%s",
              e$key, length(csha), ...))
```

`!length(csha)` catches `NULL` and the empty object. It does not catch a `csha` with
**length > 0 and no names** — jsonlite returns an unnamed list for a JSON *array*. The loop
then runs zero times, `n_bad_sha` stays `0L`, and the line prints
`all 7 classified_content_sha256 re-derive from their .tif` having checked none of them. Same
for the container arm beside it.

Today's producer writes a named object (verified: `data/necr/provenance.json` →
`['2017'…'2023']`), so this is latent rather than live — but it is exactly the
zero-length/empty/unset shape the last round's findings 1 and 2 were, one layer up, and the
count in the message is derived from a different object than the loop. One line closes both:
`if (!length(names(csha))) bad(...)`, or iterate `seq_along` and require
`length(names(csha)) == length(csha)`.

---

### 4. ~~**[fragile]** `scripts/fp_raster.R:72` — "all 116 tifs under data/"~~ — **FIXED on disk while this review was running** (uncommitted)

Recorded because the *class* is worth the note, not because it still needs action. The header
cited **116**, which this branch's own log identifies as the understated sweep. It now reads
184, and `logs/20260905_…:20` was rewritten to *"An earlier sweep reported **112** —
`data/*/rasters/*/*.tif` — and prose around it said 116"*, which reconciles: measured, that
glob yields exactly **112** and `184 − 112 = 72` `floodplain_*.tif`. Both numbers now hold.

**One restatement was missed**: `planning/active/findings.md:67` still carries the superseded
version — *"The first count written here was **116**, because the glob was
`data/*/rasters/*/*.tif`"* — which the log now says was 112, not 116. Two committed documents
in one branch, disagreeing about the same measurement, in a repo whose `planning/` is served
publicly from Pages.

The adjacent claim at `fp_raster.R:102` (*"none of the 112 under data/ carries a dataset-level
block"*) **is correct**: 112 `.aux.xml` files, 0 with a `<Metadata>` element (checked with
ElementTree over all of them).

---

### 5. **[fragile]** `scripts/floodplain_lcc/logs/20260905_raster-tags_strip_necr-kotl.md:105-107` and `planning/active/findings.md:325-326` — "after four files … the remaining four" does not add up on a 7-file area, and the file mtimes say three

**Still live** — the surrounding paragraph was edited on disk during this review (the orphan
sweep was added to `raster_strip-tags.R` on the back of it) but the count was not.

> The kotl pass was killed by a 2-minute command timeout **after four files**. It left no temp
> file, **the four completed files** were intact, and re-running picked up at
> `classified_2020.tif` and finished **the remaining four**.

kotl has 7 `classified_*.tif`. 4 + 4 = 8. The mtimes are the record (`data/` is gitignored, so
they are the only evidence left):

```
15:44:45  classified_2017.tif   \
15:45:07  classified_2018.tif    > first pass, 22 s apart
15:45:29  classified_2019.tif   /
15:46:02  classified_2020.tif   <- 33 s gap: the resume
15:46:24  classified_2021.tif
15:46:46  classified_2022.tif
15:47:07  classified_2023.tif
```

**Three** files completed before the timeout, four after. The resumability conclusion is
unaffected and correct; the count is wrong in a committed evidence log, which is where numbers
are read later without being re-derived.

---

### 6. **[note]** `scripts/floodplain_lcc/raster_strip-tags.R:99-105` — the orphan sweep added mid-review is correct; checked because a silent no-match is the failure mode it would have

New code, so it was verified rather than read. The concern was whether `list.files(pattern=)`
matches the **basename** or the relative path under `recursive = TRUE` — if the latter,
`^\\.` never matches a temp inside `rasters/<scen>/` and the sweep reports nothing forever,
which reads as "nothing to clean". Measured:

```
list.files("/tmp/lfx", pattern="^\\..*\\.strip[0-9]+\\.tif(\\.aux\\.xml)?$",
           recursive=TRUE, full.names=TRUE, all.files=TRUE)
#> "/tmp/lfx/rasters/sc/.classified_2020.strip1234.tif"
#> "/tmp/lfx/rasters/sc/.classified_2020.strip1234.tif.aux.xml"
```

Matches on the basename, picks up both halves, and leaves `classified_2020.tif` alone. The
pattern is explicit rather than a wildcard, and `DRY=1` reports without deleting — both right.
Two edges, neither worth changing: two *concurrent* runs on one area would have run B delete
run A's in-flight temp (A then fails its verify and leaves the original untouched — fails
safe), and `unlink()`'s return value is not checked, so a permission failure is silent but
harmless (the next run re-reports it).

---

## Verified — claims that hold

Run, not read. Everything below was measured on this tree.

| claim | where | result |
|---|---|---|
| `terra::rast(<gdalcubes .nc>)` yields zero metags on 1.9.34 | CLAUDE.md, findings | **holds** — `metags()` is `NULL` on `~/Library/Caches/drift/io-lulc/2017_6a3c08954de0.nc` |
| `crop`/`mask`/`deepcopy` preserve metags; `classify`/`app`/`ifel`/arithmetic/`patches` drop them | CLAUDE.md, findings table | **holds exactly** — 2/2/2 vs 0/0/0/0/0 |
| the band category names are not in the TIFF | CLAUDE.md, log, `raster_strip-tags.R` | **holds** — `GDAL_PAM_ENABLED=NO gdalinfo` shows 0 `Category` lines; 256 `<Category>` live in the `.aux.xml` |
| "all 512 rows survive" → now "256 category rows and 256 palette entries" | log, `raster_strip-tags.R`, CLAUDE.md | **holds** — 256 `<Category>` in the sidecar, 256 colour-table entries, band section 525 lines. The split into the two named counts (edited on disk mid-review) is the more checkable form |
| 184 tifs across 23 areas, 0 dirty | CLAUDE.md, log acceptance table | **holds** — full Python/GDAL sweep, `dirty: 0`; every one of the 184 carries `AREA_OR_POINT` and nothing else |
| 88 classified / 72 floodplain / 24 transition | log | **holds** |
| the 14 files in necr and kotl are repaired | CLAUDE.md | **holds** — 7 + 7 classified, all clean |
| the guard reads with `GDAL_PAM_ENABLED=NO` | CLAUDE.md | **holds**, and §5f's sidecar arm proves it both ways (premise: PAM merge is real; property: guard unaffected) |
| the strip does not alias the caller's raster | `fp_raster.R` doc, findings | **holds** — `lst[[1]]` stays at 2 tags, the return has 0 |
| §7 digests are an independent reference | log | **holds** — `provenance-check.R necr` and `kotl` PASS, so the repair moved the container and not one cell |
| every entry path sources `fp_raster.R` | round 2 | **holds** — `run_region.R` invokes `run_area.R` as a subprocess (line 180/184); `run_areas.sh` likewise; `fire_tag.R` / `gpkg_backfill-wsg.R` write no rasters; `raster_strip-tags.R` and `provenance-check.R` source it themselves |

## Guards proven able to fail (restore-the-bug, in a scratch copy)

| mutation | result |
|---|---|
| `fp_rast_strip_tags` removed from `fp_rast_write` | §5f **4 FAIL** (correct) |
| the refusal removed from `fp_rast_write` | §5f **0 FAIL, rc=0** — finding 1 |
| one recorded `classified_content_sha256` corrupted in `necr/provenance.json` | §7 `FAIL … (1 MISMATCH)` (correct), container arm stayed green |
| two stray tags injected into `necr/classified_2019.tif` via `gdal_edit.py` | §7 `FAIL … (1 of 7 dirty, e.g. data#type, NC_GLOBAL#source)` (correct), digest arm stayed green — the two arms are genuinely independent |

## Checked and not a problem

- **`tryCatch` around `fp_rast_write` (line 1198)** swallows nothing it should not: the message
  is surfaced verbatim in the `check()` label on failure (seen in the strip-removed run), and
  the reason for wrapping — an uncaught `stop()` would take §6 and §7 down and read as a crash
  — is real.
- **§5f's fixture does reach the failure mode.** Setting `metags()` explicitly is the only
  route that can, since a real cube read on 1.9.34 yields nothing; the premise arm asserts the
  10 tags actually land, so a future terra that stops writing them reddens the premise rather
  than silently emptying the property.
- **§7's new loop handles the states it meets**: missing file → counted as a mismatch;
  `csha` `NULL`/empty → `bad()`; missing `rasters/<scen>/` → `bad()`; `years` absent → the
  year-set check goes red. `if (!is.na(np) && np > 0L)` would error on a length-0
  `transition_patches`, but the pre-existing `if (is.na(np) || np == 0L)` above it already
  would, so the new line adds no exposure.
- **`fp_rast_stray_tags` selects the default domain by position**, not `md[[""]]` — correct,
  and the findings record the jsonlite key-renaming trap that makes it necessary.
- **No verification reads its own output.** §7 compares a digest recorded during the #79 run
  against one re-derived now; §5f's `all_clean` reads through sf/GDAL, not through the terra
  that wrote the file.
- **`raster_strip-tags.R`**: temp file in the same directory + atomic rename, verify-before-
  rename, `NA` digest treated as a hard error, `cats()` asserted directly rather than inferred
  from the band diff, sidecar renamed with the `.tif`. The DRY counter now reports `flagged`.
  A missing `gdalinfo` on PATH makes `band_section()` return `character(0)` and the file aborts
  — fails toward abort, which is the right direction.
- **`02`'s routing** is a measured no-op today (all 72 `floodplain_*.tif` carry only
  `AREA_OR_POINT`) and is right to be wired anyway.

---

## Suggested order

1. Finding 1 — the must-fail arm. It is the only one that changes what the suite can catch, and
   it is the guard the branch's own prose says carries the assurance.
2. Finding 2 — one `else bad(...)` at line 1161 (and the same at 845).
3. Finding 3 — one `names()` length check.
4. Finding 5 — three→four in the log and `findings.md`, and finding 4's leftover restatement at
   `findings.md:67`.

## Note on tree state

Three tracked files were edited on disk **while this review ran** (`CLAUDE.md`,
`scripts/fp_raster.R`, `scripts/floodplain_lcc/raster_strip-tags.R`,
`logs/20260905_raster-tags_strip_necr-kotl.md`, `planning/active/findings.md` — all
uncommitted at the time of writing). Findings 1, 2, 3 and 5 were re-verified against the
current on-disk state after those edits; `fp_raster.R`'s change is comment-only
(`git diff` filtered to non-comment lines is empty), so the restore-the-bug result in finding 1
still stands, and `provenance-check.R` with no argument still reports
`PASS — all properties hold, and each was shown able to fail.`
