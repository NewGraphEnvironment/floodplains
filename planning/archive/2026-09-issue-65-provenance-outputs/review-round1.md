# Review round 1 — #65 Phase 1 (digest primitives + the `outputs` sibling)

**Target.** The staged diff as it stood at review time. It was committed mid-review; blob hashes
confirm the review target is exactly **`4740702` "#65 Phase 1: digest primitives and the `outputs`
sibling, offline"**:

```
check.R  at 4740702: 823a60b2be1371bd995755279b3163ad3923f579  == the blob I reviewed
fp_prov  at 4740702: d5fa78c92eada341f2066488474f73b58878546c  == the blob I reviewed
```

All line numbers below are in that commit's blobs. `29b0c00` (Phases 2–5) landed on top during the
review and is **not** covered here, except where noted that it makes a finding live.

**Method.** Every claim below was reproduced, not read off the page. Baseline: the reviewed guard
run against a mirror of the staged tree **PASSES** (0 FAILs). Each finding is a mutation applied to
that mirror, or a direct probe. Mutation results that came back *clean* are listed at the end as
positive evidence, since a guard nobody has seen go red is decoration.

---

## Findings

### 1. **[bug]** `fp_provenance.R:403` — the table digest sorts by `key` only, so a duplicate composite key makes it a function of database row order

```r
line <- paste(key, val, sep = "\x1f")[order(key, method = "radix", na.last = TRUE)]
```

The sort key is `key`, not `line`. `order()` is stable, so two rows sharing a composite key keep
their **input order**, and the value halves then hash in whatever order the query returned them.
`01_network_extract.R` reads the network with no `ORDER BY` and asserts no uniqueness, so that order
is not guaranteed by anything.

Measured:

```
df: blue_line_key = 1,1,2   downstream_route_measure = 0,0,5   (rows 1 & 2 share the key)
    length_metre  = 100,999,300

fp_table_content_sha256(df)            sha256:5e0566f7...
fp_table_content_sha256(df[c(2,1,3),]) sha256:32e58ecc...     DIGEST MOVES
```

The function's own comment cites the uniqueness measurement on **one** area — "Measured on
neexdzii: 1915 rows, 1915 distinct composites" — which is the shape CLAUDE.md flags as *"a
per-tenant key looks global whenever your test data has one tenant"*. `29b0c00` wires this digest
into `network.inputs.network_content_sha256` **and** `network.outputs.streams_content_sha256`, so
the byte-stability the field exists to provide rests on a property nothing checks.

§5e cannot see it: the fixture's three rows have three distinct keys, so `df[c(3,1,2), ]` is
reordered by a *total* order either way. Mutation-tested — dropping the sort entirely, or replacing
the key with a constant, both go red on "row order does NOT move the digest", so the assertion works;
it just never meets a tie.

**Fix is free and total:** sort `line`, not `key`. The digest then becomes a function of the multiset
of rows regardless of key uniqueness, and the composite-key claim stops being load-bearing.

```r
line <- sort(paste(key, val, sep = "\x1f"), method = "radix")
```

---

### 2. **[bug]** `fp_provenance.R:52` + `:77` — the schema bump to `2` relabels stale v1 records on any partial re-run, and the guard the comment names does not exist

`fp_prov_read()` stamps the current version on every read (`got$schema_version <-
FP_PROV_SCHEMA_VERSION`), and `fp_prov_set()` rewrites the whole file. So a single-step run
(`run_area.R morr 3`, which CLAUDE.md calls normal) relabels the **untouched** sections v2 while they
still carry v1 shape.

Measured against the real `data/neexdzii/provenance.json` (a copy), simulating a step-3-only re-run:

```
BEFORE schema_version: 1     5 sections
AFTER  schema_version: 2     network section untouched: no `outputs`, v1 free-text sha_source
```

`stac_floodplains_bc` is downstream of that label. The header comment at `fp_provenance.R:47–51`
states this exact hazard and points at a control:

> "Bumping this is only half of a schema change -- see provenance-check.R, which **asserts the
> version and the field set TOGETHER**."

That control does not exist. `schema_version` appears in `provenance-check.R` exactly once, at line
284, and it is the *fixture constructor* — nothing reads `prov$schema_version` from a parsed file,
and §7 has no version arm at all:

```
$ grep -n "schema_version" provenance-check.R
284:    area = "fixture", wsg = "TEST", schema_version = FP_PROV_SCHEMA_VERSION,
```

This is the class CLAUDE.md calls out directly — a comment asserting a guarantee that ships without
its guard reads as verified. Either add the §7 arm the comment promises (assert v2 ⇒ every entry
carries the v2 field set, or at minimum that no entry carries a pre-v2 `sha_source`), or make
`fp_prov_read()` preserve a lower version and let the guard fail on the mix.

Note the vocabulary check *does* work once you point it at a real file — it just isn't part of the
offline suite:

```
$ Rscript provenance-check.R neexdzii
FAIL floodplain[co_ff02].inputs.flooded.sha_source is free text, not one of {...}
FAIL floodplain[co_ff04].inputs.flooded.sha_source is free text, not one of {...}
FAIL floodplain[co_ff06].inputs.flooded.sha_source is free text, not one of {...}
FAIL landcover[co_ff04].inputs.drift.sha_source is free text, not one of {...}
```

Worth stating in the PR body that every existing area fails §7 until re-run (correct, forward-only)
— per the CLAUDE.md rule that tightening a field is a change to every producer and to every record
already written.

---

### 3. **[fragile]** `fp_provenance.R:168` — the new outputs-only refusal uses `$`, which partial-matches `inputs_hash`, so it can be walked straight past

```r
if (is.null(value$inputs)) { stop("... was written with no `inputs` block ...") }
```

`$` on a list partial-matches. `value$inputs` resolves to `value$inputs_hash` whenever `inputs` is
absent and `inputs_hash` is present — the one sibling pair this entry shape actually has.

Measured, end to end through `fp_prov_set()`:

```r
v <- list(inputs_hash = "sha256:zz", outputs = list(a = 1), run = list(datetime_utc = "z"))
v$inputs            # "sha256:zz"   <- the NOTE answered
is.null(v$inputs)   # FALSE         <- the refusal does not fire
is.null(v[["inputs"]])  # TRUE

fp_prov_set(cfg, "floodplain", "co_ff04", v)   -> WROTE (no refusal)
written body keys: inputs_hash, outputs, outputs_hash, run
has `inputs`?      FALSE
```

The record that lands has **no `inputs` block** and an `inputs_hash` that is a digest of the string
`"sha256:zz"`. Line 182 (`value$inputs_hash <- fp_prov_hash(value$inputs)`) and line 193
(`value$outputs`) have the same exposure.

Not reachable from today's three producers — none passes `inputs_hash`. Reported because
`provenance-check.R:103–107` documents this exact trap at length ("Both were live here and the first
cost a confusing failure three checks away from its cause") and pins the `[[` convention with a
premise assertion at line 515, while the writer half of the same feature uses `$` on precisely the
`_hash`-sibling keys. Fix: `value[["inputs"]]` / `value[["outputs"]]` at 168, 182, 193.

---

### 4. **[fragile]** `fp_provenance.R:395` and `:333` — `sprintf("%.Nf", ...)` is LC_NUMERIC-dependent, which is the one session axis the function did not close

Both digests format floats with `sprintf`. `%f` honours `LC_NUMERIC`:

```
default / LC_NUMERIC=de_DE.UTF-8 / LC_ALL=de_DE.UTF-8   ->  LC_NUMERIC: C     sprintf: 1.500000
.Rprofile: Sys.setlocale("LC_NUMERIC", "de_DE.UTF-8")   ->  LC_NUMERIC: de_DE sprintf: 1,500000
```

R forces `LC_NUMERIC = "C"` at startup and ignores the environment, so this is **not**
env-reachable — but it *is* `.Rprofile`-reachable, which is the exact reachability argument the file
uses to justify pinning `serializeVersion` ("a base option any .Rprofile can set") and to reject
`as.character` in favour of `sprintf` ("`options(scipen)` ... a .Rprofile"). The comment at
`fp_provenance.R:377–382` enumerates the closed set as *two* session options; this is a third, and it
reaches the shipped implementation rather than the rejected one.

Cheap close: set `LC_NUMERIC` to `"C"` for the duration of the format, or assert it once at the top
of each digest function and abort if it is not `"C"`.

---

### 5. **[fragile]** `fp_provenance.R:395` — the `is.character()` branch means `RPostgres bigint = "character"` still moves the digest

```r
out <- if (is.character(v) || is.factor(v)) as.character(v) else sprintf("%.6f", as.numeric(v))
```

The comment claims the branch is closed: *"RPostgres' `bigint=` decides whether an int8 column
arrives as integer, double or integer64 -- three different as.character() paths for one value. One
rule for every numeric, `"%.6f"`, so there is no integer-vs-double branch to get wrong."*

`bigint` has a **fourth** mode, `"character"`, and it selects the other arm of `fmt`. Measured on the
same value:

```
blue_line_key = 356364175   (double)     vs   "356364175" (character)   -> DIFFERENT DIGEST
blue_line_key = 356364175   (double)     vs   integer64                 -> SAME digest  (good)
```

The two modes that are plausible today agree, so this is latent, not live. But the comment states a
closure it does not have, and `01_network_extract.R` does not pin `bigint` on the connection. Either
pin `bigint` where the connection is made, or coerce in `fmt` on the column *name*/declared type
rather than on its runtime class.

---

### 6. **[fragile]** `fp_provenance.R:283–291` — the measured failure counts in the comment are wrong, and the comment stakes the file's credibility on them

The comment reads:

> "deleting it fails **2** of §5d's checks, deleting the cast fails **none**, and deleting both fails
> **3**. (Measured -- an earlier version of this comment said "three" for the second line alone,
> which is the both-deleted figure. The file's persuasiveness rests on its numbers being checkable.)"

Re-measured against this commit, one line at a time, on the staged mirror:

| mutation | comment says | measured |
|---|---|---|
| drop `v <- as.double(v)` alone | none | **0** ✓ |
| drop `v[is.na(v)] <- NA_real_` alone | 2 | **3** ✗ |
| drop both | 3 | **3** ✓ |

The three that fire for the single-line deletion:

```
FAIL  both normalizations together make the two shapes identical
FAIL  fully normalized, they digest the same
FAIL  float: NaN and NA_real_ collapse (the Float32 nodata case the DEM actually hits)
```

The third is #65's **own** new float assertion (`provenance-check.R:785`). So the correction the
comment describes — walking "three" back to "two" — was made against the pre-#65 suite and this
commit invalidated it in the same change. Numbers stated as measured and falsifiable in one command
should be right; fix to 3 / 0 / 3, or note that the single-line and both-deleted figures now coincide.

---

### 7. **[fragile]** `provenance-check.R:839–846` — the two §5e assertions that name the header pass with the header deleted

```r
hdr <- paste0("n=", nrow(df), "|cols=", paste(cols, collapse = ","))
```

Mutation `hdr <- ""` → **0 FAILs across the whole suite.** Both assertions that cite it survive,
because in these fixtures the *lines* already carry what the header is credited with:

- `"must-fail: a different COLUMN SET digests differently (the header carries it)"` — dropping two
  value columns also shortens every value line, so the digest moves with or without a header.
- `"an EMPTY table digests distinguishably from a one-row table"` — `character(0)` lines vs one line
  differ regardless.

What the header uniquely buys is the case neither fixture reaches: **an empty table under two
different column sets.** Verified that the shipped header does separate them (`distinct`), and that
nothing asserts it. One line closes it:

```r
check(!identical(fp_table_content_sha256(df[0, ], K, V),
                 fp_table_content_sha256(df[0, ], K, V[1:2])),
      "an EMPTY table under two column sets does not collide (only the header separates them)")
```

Same family as the "detect and explain use different predicates" rule — here the *label* names a
mechanism the *predicate* does not test.

---

## What I could not break (positive evidence)

Mutation-tested against the staged mirror; each of these went red exactly where it should, which is
what makes the "0 FAILs" results above meaningful rather than a broken harness.

| mutation to `fp_provenance.R` | FAILs | assertion that caught it |
|---|---|---|
| `inputs_hash <- fp_prov_hash(value)` (fold outputs in) | 1 | "a changed OUTPUT does NOT move inputs_hash" |
| unconditional `outputs_hash` assignment | 1 | "an entry with no `outputs` gets NO outputs_hash key at all" |
| `outputs_hash <- fp_prov_hash(value$inputs)` | 1 | "a changed OUTPUT DOES move outputs_hash" |
| remove the outputs-only refusal | 1 | "must-fail: an outputs-only write IS refused" |
| drop `v[which(v == 0)] <- 0` (the new signed-zero line) | 1 | "float: normalized, a signed zero does NOT move the digest" |
| drop `serializeVersion = 2L` | 1 | "the digest is pinned to serializeVersion 2" |
| drop the sort / constant key | 1 | "row order does NOT move the digest" |
| `sprintf` → `as.character` | 1 | "the digest is scipen-immune" |
| remove the `SpatRaster` dispatch | 2 | the two #65 object-form properties |

Also checked and clean:

- **`fp_norm_block` edge shapes.** `numeric(0)`, `integer(0)`, all-`NA_integer_`, all-`NaN`, logical,
  integer, and `-0` all normalize to a double vector of the right length with no error or warning.
  `which()` (rather than a logical index) correctly avoids the `NA`-subscript abort. Logical and
  integer twins normalize `identical()`.
- **No new `on.exit()` at script top level.** §5e restores `options(scipen)` explicitly, matching the
  §5c precedent.
- **`paste(character(0), character(0), sep=)` returns `character(0)`**, not `""` — the zero-length
  `paste0` trap does not fire in `fp_table_content_sha256`.
- **`NA` vs `NA_character_` in a package stamp hash to the same value** (`toJSON(na = "null")`
  normalizes both), so `fp_pkg_stamp`'s tier-4 `sha = NA` and `fp_git_state`'s `sha = NA_character_`
  cannot split `inputs_hash` across machines. Likewise `3L` vs `3`.
- **`outputs` does not break any existing enumerator.** `viol_keys` reads only `names(body$inputs)`,
  `viol_sha_source` walks only `inputs`, `viol_creds` scans the raw text (so it does cover
  `outputs`), and `viol_body` was extended to whitelist both new keys. `outputs` *contents* are
  unwhitelisted in this commit — deliberate and stated in the comment at `provenance-check.R:445`,
  and closed by `29b0c00`.

## Notes, not findings

- **Pre-existing gap, unchanged by this diff:** §5c does not guard the raster header's geometry.
  Replacing `crs_id` with a constant, or dropping `dim(r)` from `hdr`, both give **0 FAILs** — so the
  comment's "Geometry is part of the content: the same values on a different grid are not the same
  landcover" is unasserted. Two rasters with identical values on different grids would be worth one
  fixture.
- `method = "radix"` is likewise unguarded (mutation → 0 FAILs), but the code says so honestly
  ("Currently DEFENSIVE rather than reachable"), so no action.
- `provenance-check.R:1074` is `check(TRUE, "real file checked against all properties")`, which
  prints `ok` after a failing §7. Cosmetic only — `FAILS` is counted correctly and the exit status is
  right.

## Process note

Two things bit during this review and are worth knowing:

1. **`diff` is a shell function here** (delegating to `git diff`). `diff staged/x.R worktree/x.R`
   reported **no difference** between two files that differ by 175 lines. Use `command diff` or
   `cmp`. This is the exact trap already recorded in CLAUDE.md.
2. **The working tree moved during the review** — `provenance-check.R` went 1080 → 1239 → committed
   twice while I was reading it, and the guard run against the *worktree* reported `FAIL — 2` for
   changes that were not in scope. Reviewing `git show :<path>` / a fixed commit is the only stable
   target when another session is live in the same checkout.
