# Review — round 2 (#64: reviewing the round-1 fixes)

Branch `64-nge-landcover-key-hashes-the-geotiff-con`, commits `0e0d726..21f5557`.
Reviewed `git diff main...HEAD` plus the full current contents of
`fp_provenance.R`, `provenance-check.R`, `02_floodplain_model.R`, `03_lulc_classify.R`.

Every claim below is measured; the commands are included. The working tree carries one
uncommitted, comment-only edit to `fp_provenance.R` (the WKT-fallback tradeoff note) — I reviewed
the committed state and restored the tree after every probe (`git status` is back to that one
modification).

**Verdict: the core fix is correct and proven end-to-end on real production data. Two of the eight
round-1 fixes are incomplete, and one of them is a new fail-toward-pass.**

---

## The core property, verified on the real trigger (not just the fixture)

§5c and §5d exercise synthetic inputs. I ran the shipped function against the actual raster whose
PAM sidecar caused the split — `data/ufra/rasters/ch_ff04/classified_2017.tif`, copied to a temp
dir with and without its `.aux.xml`:

```
WITH sidecar     storage=double   NaN=100589313  NA=100589313  digest=sha256:6a3549f2…3afe7
WITHOUT (PAM=NO) storage=integer  NaN=0          NA=100589313  digest=sha256:6a3549f2…3afe7
WITHOUT, PAM on  storage=integer  NaN=0          NA=100589313  digest=sha256:6a3549f2…3afe7
```

Identical digest across the exact storage-type divergence the issue is about, on 100M+ nodata
cells. That is the property #64 exists to establish, measured on production input.

---

## Findings

### 1. [bug] `provenance-check.R:548-554` — the `serializeVersion` guard cannot detect removal of the pin it names, and is in fact re-testing the normalization

Round-1 fix #3 added `serializeVersion = 2L` to `fp_provenance.R:275`. The check added to protect
it is:

```r
options(serializeVersion = 3L)
check(identical(digest::digest(fp_norm_block(vd), algo = "sha256", serializeVersion = 2L),
                digest::digest(fp_norm_block(vi), algo = "sha256", serializeVersion = 2L)),
      "digest is pinned to serializeVersion 2 -- a session option cannot move it")
```

Two problems, and they compound:

- **It never calls the function under test.** Both digests are computed by hand with
  `serializeVersion = 2L` hardcoded in the check itself, so nothing about
  `fp_raster_content_sha256()` is observed.
- **Both sides are the same vector.** §5d proved four lines earlier that
  `identical(fp_norm_block(vi), fp_norm_block(vd))`. Two identical vectors digest the same under
  *any* serialization version, so `options(serializeVersion = 3L)` moves neither side and the
  assertion holds unconditionally.

**Restored the defect** — stripped the `serializeVersion = 2L` argument from
`fp_provenance.R:275` and re-ran the guard:

```
$ perl -0pi -e 's/,\n\s*# Pin the serialization format.*?serializeVersion = 2L\)\)/))/s' fp_provenance.R
$ Rscript scripts/floodplain_lcc/provenance-check.R
  ok    digest is pinned to serializeVersion 2 -- a session option cannot move it
PASS — all properties hold, and each was shown able to fail.
```

Green with the pin gone. And the pin is genuinely load-bearing — same raster, four combinations:

```
PINNED   opt=NULL: sha256:0d90d215…743b
PINNED   opt=3   : sha256:0d90d215…743b      <- stable
UNPINNED opt=NULL: sha256:0d90d215…743b
UNPINNED opt=3   : sha256:c0c09d97…b69f05    <- moves
```

So an `.Rprofile` setting `serializeVersion = 3L` would silently churn every recorded
`classified_content_sha256`, and the guard written specifically to prevent that would stay green.

**Worse, the check's label is wrong about what it does test.** When I restored round-1 defect #1
instead (deleted `v[is.na(v)] <- NA_real_`), this check went red alongside the two normalization
checks:

```
  FAIL  both normalizations together make the two shapes identical
  FAIL  fully normalized, they digest the same
  FAIL  digest is pinned to serializeVersion 2 -- a session option cannot move it
```

It is a third copy of the normalization assertion wearing the pin's name. If the pin is ever
removed, the failure that eventually surfaces will point at normalization.

**Fix — assert the pin by exercising the function across the option**, which is what makes the two
answers differ:

```r
sv <- getOption("serializeVersion")
options(serializeVersion = 3L); h3 <- fp_raster_content_sha256(a)
options(serializeVersion = 2L); h2 <- fp_raster_content_sha256(a)
if (is.null(sv)) options(serializeVersion = NULL) else options(serializeVersion = sv)
check(identical(h3, h2), "the raster digest is unmoved by options(serializeVersion)")
```

Verified against both known answers: `ok` against the shipped function, `FAIL` against the same
function with the pin stripped. It needs a raster, so it belongs inside the §5c `if
(requireNamespace("terra"))` block, next to the `block_rows` contract assertion.

---

### 2. [fragile] `provenance-check.R:57-62` — the comment claims the toolchain guard closes producer-side drift; it does not, and cannot

The block comment introducing `KEYS_TOOLCHAIN` / `SECTIONS_WITH_RASTERS` states the motivation
explicitly:

> *"So an edit dropping `toolchain = fp_toolchain()` would be silent and the record would quietly
> return to the state #64 calls undiagnosable."*

`viol_split` guards the **record**, not the **producer**. §6's `prov_keys()` parses
`cl[[5]][["inputs"]]` and never looks at `run`, so it cannot see the argument either.

**Measured** — removed `toolchain = fp_toolchain()` from *both* producers and re-ran:

```
$ sed -i '' 's/run = fp_prov_run(toolchain = fp_toolchain())))/run = fp_prov_run()))/' \
    02_floodplain_model.R 03_lulc_classify.R
$ Rscript provenance-check.R            -> PASS — all properties hold
$ Rscript provenance-check.R neexdzii   -> PASS — all properties hold
```

Green in both modes. §7 passes too, because the on-disk `data/neexdzii/provenance.json` still
carries `toolchain` from the previous run — so the regression stays invisible until an area is
re-run *and* someone happens to check it, at which point the diagnostic field is already missing
from the new record. This is the exact "silent" failure the comment says is closed.

**Fix — extend §6's existing scanner to `run`.** `cl[[5]][["run"]]` is the `fp_prov_run(...)` call,
so its named arguments parse the same way `inputs` does. Verified working against the real step
scripts:

```
01 network    run args: freshness network_guard
02 floodplain run args: toolchain
03 landcover  run args: toolchain
```

`check(all(c("floodplain","landcover") %in% sections_whose_run_names_toolchain))` fails the moment a
producer drops it.

---

### 3. [fragile] `provenance-check.R:64` — `SECTIONS_WITH_RASTERS` is a literal set with no source of truth

```r
SECTIONS_WITH_RASTERS <- c("floodplain", "landcover")
```

This is the scope of the entire toolchain guard, and nothing ties it to the producers. It matches
today by coincidence — 02 and 03 are the sections that call `fp_toolchain()`. A future section that
writes rasters, or step 01 gaining one, is silently uncovered, and the `b9` must-fail case only
guards the *opposite* direction (that `network` is not wrongly required).

The set is derivable from the same parse as finding 2 — "the sections whose `fp_prov_run()` call
names `toolchain`" — which turns a coincidence into a declare-or-fail. Both findings close with one
check.

---

## Answered with measurements — each question in the brief, closed

| Question | Answer |
|---|---|
| `fp_norm_block()` on LOGICAL | `c(TRUE,FALSE,NA)` → `c(1,0,NA)` double. Correct, no warning. Unreachable from `readValues`. |
| `fp_norm_block()` on CHARACTER | `as.double(c("1","2","x"))` warns *"NAs introduced by coercion"* and yields `NA`. **Unreachable** — `readValues()` returns integer or double only, never character; and a silent wrong value cannot arise because the warning fires. Not a finding. |
| `fp_norm_block()` on a FACTOR | returns the integer codes as double, no warning. Unreachable. |
| `fp_norm_block()` on an EMPTY vector | `integer(0)` and `double(0)` both → `numeric(0)`, and `identical()` on the two results is **TRUE**. Correct. |
| `fp_norm_block()` on an ALL-NA vector | `c(NA_integer_,NA_integer_)` and `c(NA,NA)` (logical) both → `c(NA_real_,NA_real_)`, identical. Correct. |
| `as.double()` dropping attributes | It drops `dim`, so a matrix normalizes to a plain vector. `readValues(mat = FALSE)` (the default, and what the code uses) never returns a matrix, so this is not reachable. Dropping names/attrs is *desirable* here — it removes another machine-dependent axis. |
| `crs_id` fallback: does the WKT reintroduce machine dependence? | The fallback string is real and large — measured **1439 chars, 38 lines**, PROJ-rendered, for a code-less Albers definition. So yes, in principle a PROJ upgrade could move it. **Unreachable in this pipeline**: every `classified_*.tif` carries an explicit authority ID (checked `data/ufra`, `data/neexdzii`). The uncommitted working-tree comment already names this tradeoff and says the right close is to make it an error — agreed, and I am not re-flagging it. I did *not* measure PROJ-version stability of the WKT string (would need two PROJ builds), so neither the risk nor its absence should be asserted as measured. |
| Multi-line string inside `paste(collapse = "\|")` | Safe. It is one element; embedded newlines survive into the digested payload verbatim. No delimiter collision (`\|` cannot appear in a WKT ID). Verified: `fp_raster_content_sha256()` returns a normal digest for a code-less-CRS raster. |
| `crs_id` drops the *authority* (`paste0("EPSG:", code)`) | Confirmed the label can be wrong — an `OGC:CRS84` raster records `EPSG:CRS84`, an `ESRI:102008` records `EPSG:102008`. I looked for an actual numeric collision between EPSG and ESRI in this PROJ build (14 candidate codes) and **found none resolvable**, so I am not reporting a collision I cannot demonstrate. Mislabel only. |
| `tc_problem`: does the non-raster path return NULL, and does `c()` drop it? | Yes. R's `if` with no `else` returns `NULL` invisibly; `c(x, NULL)` drops it. Confirmed behaviourally by the `b9` case and by the network section passing on the real file. The inner `if/else if/else if` chain also returns `NULL` when all arms are false. |
| `tc[KEYS_TOOLCHAIN]` on a partially-named list | Safe — the `setdiff(KEYS_TOOLCHAIN, names(tc))` arm returns first, so the subset only runs when all five names are present. An unnamed list, a character vector, or a non-list `tc` all take the "missing" arm rather than erroring. |
| `is.na(x[1])` for a NULL / length-0 element | `is.null(x) \|\| is.na(x[1])`: `NULL` → TRUE via the short-circuit; `character(0)` → `x[1]` is `NA_character_` → TRUE; `NA_character_` → TRUE; `"1.9"` → FALSE; `list(1,2)` → FALSE. All length-1 logical, so `vapply(..., logical(1))` is safe. `NULL[["toolchain"]]` returns `NULL` rather than erroring, so a section with no `run` block is handled. |
| `options(serializeVersion = NULL)` — valid unset? | **Yes**, measured: after `options(serializeVersion = NULL)` the name is absent from `names(options())` and `getOption()` returns `NULL`. The §5d restore is correct (the bug is what it asserts, finding 1, not how it restores). |
| §5b TZ restore | **Correct and complete.** `Sys.getenv("TZ", unset = NA)` + `Sys.unsetenv()` round-trips exactly, and `format(Sys.time())` returns local time afterwards (verified: `America/Vancouver` both before and after). The added `check()` asserts it. |
| Round-1 fix #1 — does §5d actually catch the deleted normalization? | **Yes.** Deleting `v[is.na(v)] <- NA_real_` turns 3 checks red (see finding 1's transcript). Deleting `as.double()` alone turns 0 red — known, documented, accepted per the brief. |
| Round-1 fix #7 — the `[[` perturb + existence premise | **Correct.** The premise `!is.null(g$landcover$co_ff04$inputs[["classified_content_sha256"]][["2017"]])` fires before the perturbation, and `[[<-` on a present key cannot degrade to "adding an arbitrary key". `$inputs` here is safe despite the `inputs_hash` sibling — `$` partial-matches only when there is no exact match. |
| Round-1 fix #6 — top-level `on.exit()` | **Both sites fixed** (§5c `unlink` + assertion, §5b explicit TZ restore) and both assert the cleanup happened. Correct. |
| Rename completeness / stale records | **Complete.** No live code references `classified_sha256` or `fp_file_sha256` — only `planning/archive/` prose and one log. `data/neexdzii/provenance.json` is the only provenance file on disk; it carries `classified_content_sha256` and a populated `toolchain` in all 4 raster-writing sections, and `provenance-check.R neexdzii` → PASS. The other seven `data/<area>/` dirs have no `provenance.json` at all, which §7 correctly reports as `bad()` (forward-only). |
| Producers affected by the newly-mandatory field | Only three `fp_prov_set` call sites exist (01/02/03). No CLI (`gpkg_backfill-wsg.R`, `fire_tag.R`) writes provenance. Nothing else to update. |
| `fp_toolchain()` partial-NA (e.g. GDAL resolves, PROJ does not) | The guard rejects only an *entirely* NA block. Reachable only if `sf::sf_extSoftVersion()` drops a key, which it does not in sf ≥ 1.0 (`GEOS`, `GDAL`, `PROJ` all present — confirmed on the real file: `gdal 3.8.5 / geos 3.13.0 / proj 9.5.1`). Not reporting. |
| Partial-NA `classified_content_sha256` (one year NA, others populated) | `all(is.na(unlist(...)))` passes. Reachable only if `writeRaster` succeeded and left a 0-byte file, since `fp_raster_content_sha256` is called on the line after the write and any real failure throws. Not reporting. |
| §6 scanner vs the new `run = fp_prov_run(toolchain = ...)` argument | Unaffected — `prov_keys()` reads `cl[[5]][["inputs"]]` by name, and all three drift checks pass with the correct declared counts (9 / 20 / 19). |
| Full guard run, as committed | `Rscript scripts/floodplain_lcc/provenance-check.R neexdzii` → **PASS**, exit 0, 60 checks across §1–§7. |

## CLAUDE.md "Code Check Conventions" sweep

Walked the checklist against the diff. Hits:

- ***"A proxy assertion does not guard the thing it stands for"*** and ***"Restore the bug and
  confirm the test fails"*** → **finding 1**. The check asserts vector equality as a stand-in for a
  serialization pin, and stays green on the restored defect.
- ***"A guard's scope is usually a coincidence, and it will not announce itself"*** and ***"A drift
  guard must cover every input it claims to"*** → **findings 2 and 3**. `SECTIONS_WITH_RASTERS` is a
  literal filter with no source of truth, and the guard's own comment overstates its coverage.
- ***"Review the fixes at least as hard as the original"*** → all three findings are inside round-1
  fixes, none in the original change.

No hits on: shell guards (no shell in this diff); pathspec magic; quoting/heredocs; `wc -l` /
`grep -c`; `git add -A` side effects (the commits touch only `CLAUDE.md`, `planning/`, and the four
scripts); secrets (§4 exercised, pattern proven able to match); `$` partial matching (all
parsed-JSON reads use `[[`, and the one `$code` read is on a **data.frame**, which is exact-match);
zero-length values in row builders; `system2()` quoting; `on.exit()` at top level (both fixed);
`paste0()` on a zero-length vector (§7b already guards `run_ids`); empty-result-as-pass (§7 branches
on `n == 0`, §5c's `else` calls `bad()`).
