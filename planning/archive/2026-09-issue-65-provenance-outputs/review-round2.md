# Review round 2 — #65, full branch diff (`main...HEAD`)

**Path note — read this first.** The task named `planning/active/review-round1.md` as the
deliverable. That file **already existed** when I started (16,088 bytes, written 11:50, untracked),
and it is a different reviewer's round-1 review of `4740702`. Overwriting it would have destroyed a
peer review whose findings were still being applied. This file is written beside it instead.

**Moving target.** The branch changed twice while I was reading it:

| time | event |
|---|---|
| 11:50 | `review-round1.md` written by another session |
| 11:52 | `fp_provenance.R` modified in the working tree (round-1 fixes, uncommitted) |
| 11:55 | committed as **`d51de16`** "#65 Round-1 review fixes" |

So the diff I was given (`main...HEAD` at `29b0c00`) is not the tree I reviewed. **Everything below
is against `d51de16`**, the current HEAD. Two things I had independently reproduced — the table
digest sorting by `key` alone (duplicate composite key ⇒ digest is a function of DB row order) and
the `is.character` fallback in `fmt()` — were fixed in `d51de16` before I could report them, and I
re-verified both fixes hold. They are not listed as findings.

**Method.** Every finding below was measured against the live tree, not read off the page.
Baseline: `Rscript scripts/floodplain_lcc/provenance-check.R` **PASSES** (0 FAILs), and
`... provenance-check.R neexdzii` against the record the in-flight run wrote also **PASSES**. No
file was modified and nothing under `scripts/run_area.R` was run.

---

## Findings

### 1. **[bug]** `03_lulc_classify.R:424` — `transition_patches` counts transition **classes**, not patches. Measured 48 where the answer is 2032.

```r
outputs = list(
  transition_raster         = basename(trans_tif),
  transition_content_sha256 = transition_sha,
  transition_patches        = nrow(trans_all$summary)),
```

`trans_all$summary` is not a patch table. From `drift::dft_rast_transition`'s own `\value`:

> `summary`: A tibble with columns `from_class`, `to_class`, `n_cells`, `area`, `pct`.

One row per **(from_class → to_class) pair**. The patch count is a different number, and this same
script already computes it 200 lines later as `nrow(trans_polys)`, printing it as
`"... change patches >= X ha"`.

Measured on the record the in-flight run has already written, plus the gpkg it describes:

```
data/neexdzii/provenance.json  landcover[co_ff04].outputs.transition_patches   48
ogrinfo transition_co_ff04_2017_2023  Feature Count:                         2032
```

2032 is corroborated independently — CLAUDE.md records neexdzii's bridge table as "2032 rows".
So the published field is low by **42×**, and it is not a rounding or definition quibble: 48 is a
count of *classes* and the field name asserts *patches*.

Why it matters beyond the number:

- It is inside `outputs`, so it is inside `outputs_hash` and is one of the three things
  `provenance_ab-compare.R` now compares. A class count barely moves between runs where a patch
  count moves a lot, so the field weakens the very signal `outputs_hash` was added to carry.
- `stac_floodplains_bc` (#17) publishes these as item properties. A consumer reading
  `transition_patches` gets a wrong number with no way to tell.
- **No guard can see it.** `viol_keys` checks the key is *present*; `viol_split` checks it is not a
  run-event field; §6 checks the producer writes the declared name. Every property is about the
  key, none about the value — this is exactly the "a value nothing reads is wrong silently" class,
  and the guard passing on the live file (verified above) is the evidence.

Fix is either `nrow(trans_polys)` (moved after the vectorize, which is where that number exists) or
renaming the field to what it measures, e.g. `transition_classes`. The two are not equivalent and
the choice should be deliberate — but the current pairing of name and value is wrong either way.

---

### 2. **[bug]** `03_lulc_classify.R:136-140` — on a zero-patch run the digest and the filename describe a **stale** `transition.tif` from a previous run

```r
trans_tif <- file.path(fp_dir, "transition.tif")
if (nrow(trans_all$summary) > 0) {
  terra::writeRaster(trans_all$raster, trans_tif, overwrite = TRUE, datatype = "INT4S")
}
transition_sha <- fp_raster_content_sha256(trans_tif)
```

The comment above it says:

> It is written only when there is a transition to write; the path form of the digest returns NA for
> an absent file, so the empty case records an honest absence rather than erroring or fabricating a
> hash.

That holds only for a **first** run into a clean directory. `fp_dir` is created with
`dir.create(fp_dir, recursive = TRUE, showWarnings = FALSE)` (line 119) and **nothing ever removes
its contents** — there is no `unlink` anywhere in the file. So on a re-run of the same
`(area, scenario)` that yields no transitions, the write is skipped, the previous run's
`transition.tif` is still on disk, and the record publishes:

```
transition_raster         = "transition.tif"          # a file this run did not write
transition_content_sha256 = <digest of the OLD raster>
transition_patches        = 0                         # ...beside a hash of 48 classes of change
```

An internally contradictory `outputs` block — a populated content hash next to a zero count — and
`outputs_hash` then reports "same answer" against a run that produced no answer at all. Reachable
without anything exotic: narrowing `change_interval`, raising `patch_area_min`, or a small AOI.

This is the same family as CLAUDE.md's #55 ("legacy layers do not clean themselves up") and its
"a fix to code that writes data is not done until the written data is reconciled" rule, arriving in
the provenance record rather than in a gpkg.

Two fixes, and only the second is complete: gate the digest on the same condition as the write
(`transition_sha <- if (nrow(...) > 0) fp_raster_content_sha256(trans_tif) else NA_character_`, and
set `transition_raster` to `NA` too), **or** `unlink(trans_tif)` before the `if`, so the absence on
disk matches the absence in the record. The first leaves a stale file for the next reader of
`data/<area>/rasters/<scenario>/`; the second makes the directory honest as well.

---

### 3. **[fragile]** `02_floodplain_model.R:241` — `dem_content_sha256` puts a **GDAL/PROJ-reprojected** raster inside the hashed `inputs` half, one file away from a comment refusing to do exactly that

`01_network_extract.R:160-163` states the rule this branch is built on:

> The subset must NOT be inside this digest. It is st_transform + st_intersects — PROJ and GEOS —
> so a post-subset digest would make `inputs_hash` a function of the sf build, reintroducing one
> field over exactly the cross-machine churn #64 removed.

`fp_provenance.R:686-691` states it again for terra/sf/GDAL, which are kept in `run` for the same
reason. But `02` digests the object returned by `flooded::fl_dem_aoi()` into `inputs`, and that
object is a reprojection. From flooded's source (measured, `deparse(fl_dem_aoi)`):

```r
r_clip <- terra::crop(r, terra::vect(aoi_buf_in_r), snap = "out")
if (r_crs != target_crs) {
  r_clip <- terra::project(r_clip, target_crs$wkt)     # <- always taken here
}
```

MRDEM-30 is not in BC Albers and `target_crs` is the streams CRS, so the branch fires on every run
of this pipeline. Both halves of `fp_raster_content_sha256` are then products of the toolchain:

- the **cells** are GDAL warp output (resampled), and
- the **header** — `dim(r)`, `sprintf("%.9f", ext(r))`, `res(r)` — is GDAL's suggested warp output,
  computed from a **PROJ-rendered** `target_crs$wkt` string.

So `floodplain[*].inputs_hash` is now a function of the local GDAL/PROJ/terra build. That is the
primary property `provenance_ab-compare.R` asserts (`inputs_hash` IDENTICAL per entry) and the one
#63 verified live across m1 and m4.

**Bounding this honestly:** I have not reproduced a cross-toolchain difference — I have one GDAL
here. The precedent cuts the other way too: `classified_content_sha256` has been in `inputs` since
#64 and #63 measured it agreeing across two machines, though both were on **GDAL 3.8.5**, so that
measurement does not test the axis. What is certain is that the branch now applies two opposite
rules to the same question in the same commit, with no note saying which one governs. Either the
DEM digest belongs in `outputs` alongside the floodplain raster (where 01 says toolchain variation
is diagnostic rather than fatal), or 01's rationale needs amending to say why a warped DEM is
admissible in `inputs` where a GEOS-selected segment set is not.

Cheap way to settle it rather than argue it, and it needs no pipeline run:

```r
# on two machines with different GDAL/PROJ, same streams layer
dem <- flooded::fl_dem_aoi(streams, buffer = 2000, target_crs = sf::st_crs(streams))
fp_raster_content_sha256(dem)
```

---

### 4. **[fragile]** `provenance_ab-compare.R:160-171` — an `outputs_hash` difference is a hard FAIL for all three sections, which contradicts what `01` says `outputs` is for

The new arm is symmetric with `inputs_hash`:

```r
if (wants_outputs) {
  ...
  else if (!osame) bad(sprintf("%s: outputs_hash DIFFERS (%s vs %s)", k, ox, oy))
}
```

`wants_outputs` is `sect %in% FP_SECTIONS_WITH_OUTPUTS`, which is all three sections, so every
entry is held to it. Meanwhile `01_network_extract.R:163` describes the network's `outputs` digest
as the place where toolchain variation "is diagnostic rather than fatal" — and that digest is taken
**post-subset**, i.e. after `sf::st_transform` + `sf::st_filter(st_intersects)`. On a subset area
(neexdzii is the only one) two machines with different GEOS can legitimately select a different
segment set, and the A/B then reports FAIL with the operator given no way to separate
"the toolchain re-cut the boundary" from "the network content changed" — which is precisely the
unreadable-criterion problem #65 removed from `sha_source`.

Same-machine determinism runs are unaffected; this only bites the documented cross-machine use
(#63). Whichever way it is resolved, the script's header (property "2b. STABILITY") and 01's
comment currently say opposite things about the same field, and one of them will be read as the
contract.

Note also that the `else if (ox_ok || oy_ok)` arm — "carries an outputs_hash but the section is not
declared to publish one" — is currently unreachable, since `FP_SECTIONS_WITH_OUTPUTS` names every
section `fp_prov_set` accepts. Harmless, but it is not a guard yet.

---

## Checked and clean (positive evidence, so a clean result is not confused with an unrun check)

Recorded because a review that only lists problems does not say what was actually exercised.

**The moved block in `01`.** The `lnk_log_read()` / config-name resolution now runs before the
`lnk_stamp` sidecar. `lnk_cfg_read` is defined at line 80, above both; `conn` is opened at 43 and
closed only by `on.exit` inside `fp_network()` (a real function frame, so it does fire); nothing
after the move reads a variable the move made undefined; `link_config_name` /
`link_config_name_source` are defined before both their consumers (the sidecar at 356 and
`fp_prov_set` at 374). Message ordering changes, nothing else. The one residual risk I could not
close without touching the busy database is whether a failing `lnk_log_read` (missing `log` table
in a GRAB schema) could leave the connection unusable for the subsequent `lnk_stamp` — under
RPostgres' default autocommit it cannot, and the call is `tryCatch`-wrapped, so I did not pursue it.

**`fp_table_content_sha256` after `d51de16`.** Re-probed directly:

| probe | result |
|---|---|
| duplicate composite key, two row orders | digests **identical** (whole-line sort) — the round-1 bug is fixed |
| zero rows | returns a hash, distinct from a one-row table; `paste(character(0), character(0))` is `character(0)`, so no phantom row |
| text column | **refused** with a named error, not rendered by a second branch |
| `integer64` (RPostgres' default `bigint` mode) | `is.numeric()` is **TRUE**, `as.numeric()` renders — so the new refusal does *not* abort step 1 on a bigint key |
| `%.6f` under a non-C locale | R forces `LC_NUMERIC = "C"`; not reachable |

**`outputs` does not break any enumerator.** `prov_sections()` (check), `entries()` (A/B),
`fp_prov_sort`, `fp_prov_assert_unique`, `fp_prov_assert_serializable` and `run_region.R`'s
cache-invalidation read all key on section names or walk generically. §6's `prov_keys(..., part =)`
resolves `outputs` correctly for all three producers (verified by the guard's own
`drift1("... outputs", ...)` rows going green with the right counts, 3/3/3).

**`on.exit()` at script top level.** Both new top-level fixture blocks (§5c, §5e's `scipen`
restore) clean up explicitly and assert the cleanup, and §5b asserts the `TZ` restore. No new
top-level `on.exit` was introduced. The one `on.exit` in `fp_provenance.R:105` is inside
`fp_prov_write()`, a real frame.

**Assertions I tried to break and could not.** `block_rows` default pinned by value not by
comparison; the `outputs_hash` separation routed through `fp_prov_set` and read back off disk (so
it can see a `fp_prov_hash(value)` mutant); the two scope-moving mutants (`SECTIONS_WITH_RASTERS`,
`KEYS_OUTPUTS_BY_SECTION`) which exercise the exemption rather than a section that happens to be
empty; §6's `assign_lit` / `lit` pair, which is a genuine external reference for the BUILD branch
(a raw `lnk_config("default")` reappearing at a call site shows up as a second value and fails).
The one weak assertion is §5e's radix premise, whose `|| identical(Sys.getenv("LC_COLLATE"), "C")`
disjunct makes it unfalsifiable in a C locale — documented as such in the comment, so not reported
as a finding.

**Empty/zero cases in the new digest calls.** A species with no accessible segments → `streams` is
a 0-row sf, `fp_table_content_sha256` returns a distinguishable hash (probed). A scenario with no
valley cells → the raster is still written and digested. The zero-patch landcover case is
**finding 2** above and is the only one that misbehaves.

**No credential, path or secret leakage introduced.** `sha_source` closing to a vocabulary removes
the `$HOME` path that was previously interpolated into a hashed field; §4's `CRED_RE` still matches
a real SAS token (must-fail arm green) and rejects a `sig`-prefixed word.

---

## Summary

| # | severity | file:line | one line |
|---|---|---|---|
| 1 | bug | `03_lulc_classify.R:424` | `transition_patches` is a class count — 48 measured where the patch count is 2032 |
| 2 | bug | `03_lulc_classify.R:136-140` | zero-patch run digests and names a **stale** `transition.tif`; `fp_dir` is never cleaned |
| 3 | fragile | `02_floodplain_model.R:241` | a GDAL/PROJ-warped DEM digest sits in the hashed `inputs`, against 01's own stated rule |
| 4 | fragile | `provenance_ab-compare.R:160-171` | `outputs_hash` mismatch is fatal, where `01` documents that half as diagnostic |

1 and 2 are already live in `data/neexdzii/provenance.json` (finding 1 measured there directly), and
both are invisible to `provenance-check.R`, which passes on that file.
