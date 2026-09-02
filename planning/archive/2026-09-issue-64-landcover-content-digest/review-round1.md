# Review — round 1 (#64: content digest replaces the container digest)

Reviewed the **staged** diff (`git diff --cached`) plus the full current contents of
`scripts/floodplain_lcc/fp_provenance.R`, `provenance-check.R`, `02_floodplain_model.R`,
`03_lulc_classify.R`. Every claim below was measured, not reasoned about; the commands are
included.

Verdict: the change is sound and the guard runs green
(`Rscript scripts/floodplain_lcc/provenance-check.R neexdzii` → `PASS`, exit 0). Five findings,
one of which is a real hole in the new guard.

---

## Findings

### 1. [bug] `provenance-check.R` §5c (staged lines 378–448) — the section cannot detect removal of EITHER normalization, which is the actual #64 fix

`fp_provenance.R:233-234` carries the two lines the issue is about, with the comment
*"Do not simplify either line away."* **Nothing enforces that.**

Measured — deleted **both** lines from a copy of `fp_provenance.R` and re-ran the guard:

```
$ perl -0pi -e 's/^    storage\.mode\(v\) <- "double"\n    v\[is\.na\(v\)\] <- NA_real_\n//m' fp_provenance.R
$ Rscript provenance-check.R

5c. Content digest is invariant to the container
  ok    premise: the two containers really do differ in bytes
  ok    premise: the two rasters carry identical cell values
  ok    content digest AGREES across differing containers (the #64 property)
  ok    must-fail: ONE changed cell value MOVES the content digest
  ok    must-fail: ONE cell becoming nodata MOVES the content digest
  ok    restored defect: the OLD file hash disagrees on the same values
  ok    block_rows defaults to 512 ...
  ok    premise: block_rows really does change the digest ...
```

All green with the fix removed. **Why:** the fixture varies exactly one axis — container metadata,
via `terra::metags()` — and then reads *both* files with the *same* terra. The storage-type axis
that the normalizations exist for (`double`+`NaN` vs `integer`+`NA_integer_`) is never varied, so
the section is structurally incapable of reaching the failure it was written for. This is
`code-check.md`'s *"a fixture set that cannot reach the failure mode is not validation"*, and the
restored-defect exercise that IS present (`old_file_sha`) covers only the other half of the change.

The section therefore claims coverage it does not have. §5c would have passed before this fix's
normalization lines existed, exactly as happily as after.

**It is constructible offline in four lines** — the toolchain difference is a property of the
*vector shapes*, not of the files, so no second terra is needed. Measured:

```r
vi <- c(1L, 2L, NA_integer_, 4L)   # terra 1.9.11 shape
vd <- c(1,  2,  NaN,         4)    # terra 1.9.34 shape
s  <- vi; storage.mode(s) <- "double"
nrm <- function(v) { storage.mode(v) <- "double"; v[is.na(v)] <- NA_real_; v }

identical(vi, vd)                                #> FALSE
identical(s,  vd)                                #> FALSE  <- storage.mode ALONE is not enough
identical(digest(s), digest(vd))                 #> FALSE
identical(digest(nrm(vi)), digest(nrm(vd)))      #> TRUE   <- both lines together
isTRUE(all.equal(s, vd)); sum(s != vd, na.rm=TRUE)  #> TRUE ; 0   (the invisible-gap premise)
```

Adding those as four `check()` calls in §5c makes both normalizations guarded, pins the
`all.equal`/`!=` blindness the header comment asserts, and costs nothing.

---

### 2. [fragile] `fp_provenance.R:235` — `digest::digest(v, algo = "sha256")` hashes R's *serialization*, whose version is a settable session option

`digest()` defaults `serializeVersion = .getSerializeVersion()`, which is:

```r
function () getOption("serializeVersion", .pkgenv[["serializeVersion"]])
```

`serializeVersion` is a **documented base R option** (it is what `save()`/`saveRDS()` consult), so
any `.Rprofile`, package, or `R_DEFAULT_SERIALIZE_VERSION`-style site config can set it. Measured
on a real raster through the shipped function:

```
default            : sha256:c739fbf97339a134c0629a2d7db0e59eda96060a4dd49dc264e6c0a4c20771ce
serializeVersion=3 : sha256:87568020133d4c869c98bea6784a5c1825666062eb35f77f889338baf5e80396
```

Same file, same cells, different digest — the exact churn #64 exists to remove, one layer down.

It gets worse under v3, because digest's `skip = "auto"` is a fixed **14 bytes**, which is exactly
the v2 header and *not* the v3 one:

```
v2 first 20: 58 0a 00 00 00 02 00 04 05 02 00 02 03 00 | 00 00 00 0e ...   <- skip covers header
v3 first 30: 58 0a 00 00 00 03 00 04 05 02 00 03 05 00 | 00 00 00 05 55 54 46 2d 38 ...
                                                          ^^^^^^^^^^^^^^^^^^^^^^^ "UTF-8" HASHED
```

So under v3 the digest additionally embeds the native encoding and the shifted writer-R-version
bytes — machine- and locale-dependent. Under v2 (today's default) the 14-byte skip does cover the
writer's R version, which is why the cross-machine measurement in `findings.md` came out clean; the
guarantee is real but it is resting on an option nobody pinned.

Fix is one argument: `digest::digest(v, algo = "sha256", serializeVersion = 2L)`. (Hashing the raw
bytes — `writeBin(v, raw())` — removes the dependency on R serialization entirely, but changes
every digest already recorded, so the explicit pin is the cheaper move.)

---

### 3. [fragile] `fp_provenance.R:223` — the header's CRS field is `NA` for any CRS with no EPSG authority code, so two different CRSs collide

`terra::crs(r, describe = TRUE)$code` returns a length-1 `NA_character_` (not `character(0)` — I
checked, so the field does not silently vanish from the `paste`) whenever the CRS has no authority
code. `paste` then renders it as the literal string `"NA"`. Measured, two rasters with identical
grid and identical values under two genuinely different Albers definitions:

```
p1 code: NA  digest: sha256:fb70b33e1efe1192da8abd1632d5f3ca712a35cff72f0e8bc234f5fcac2f8d1a
p2 code: NA  digest: sha256:fb70b33e1efe1192da8abd1632d5f3ca712a35cff72f0e8bc234f5fcac2f8d1a
```

Identical. The header comment says *"the same values on a different grid are not the same
landcover"*, and for a code-less CRS that does not hold.

**Not currently reachable in this pipeline** — I checked the real output
(`data/lchl/rasters/ch_ff04/classified_2020.tif`): its WKT carries an explicit `ID["EPSG",32610]`,
so `describe = TRUE` reads the code off the file rather than reverse-identifying it, and every
`classified_*.tif` this repo writes will be the same. It is a latent gap, not a live bug. One-line
close: fall back to the WKT when the code is NA, e.g.
`code <- terra::crs(r, describe = TRUE)$code; if (is.na(code)) code <- terra::crs(r)`.

(Related but *not* a problem: `describe = TRUE` on a WKT lacking an `ID[]` node would depend on the
PROJ database version, so the digest would move with PROJ. Confirmed not reachable here for the
same reason.)

---

### 4. [fragile] `provenance-check.R:391` (staged) — `on.exit()` at the top level of a script never fires

You asked about this specifically. Confirmed by probe:

```
$ cat /tmp/t7.R
d <- file.path("/tmp", paste0("ontest_", Sys.getpid())); dir.create(d)
on.exit(unlink(d, recursive = TRUE), add = TRUE)
quit(status = 0)
$ Rscript /tmp/t7.R && ls -d /tmp/ontest_*
/tmp/ontest_37189        <- LEAKED: on.exit did NOT fire
```

The registration is on the global environment, which never exits. Impact is **bounded**, because
`d` lives under `tempdir()` and R removes that at session end — so it is a guard that does nothing
rather than a real leak.

**This is already fixed in the working tree but is NOT staged.** `git diff` (unstaged) replaces it
with an explicit `unlink(d, recursive = TRUE)` plus a `check(!dir.exists(d), ...)`. That is the
right fix — stage it, or the committed version carries the trap the repo's own CLAUDE.md documents.

Note while you are there: **the same trap is live and unfixed one section up**, at
`provenance-check.R:359` in §5b — `tz <- Sys.getenv("TZ"); on.exit(Sys.setenv(TZ = tz), add = TRUE)`
also never fires, so `TZ` is left set to `"UTC"` for the remainder of the process. Pre-existing, not
in this diff, and harmless for §5c/6/7 (nothing after it formats a time), but it is the same class
and one line to fix.

---

### 5. [fragile] `fp_toolchain()` fails silently to `NA` in all three fields, and no guard asserts it is populated

```r
ver  <- function(p) tryCatch(as.character(utils::packageVersion(p)), error = function(e) NA_character_)
gdal <- tryCatch(unname(sf::sf_extSoftVersion()[["GDAL"]]), error = function(e) NA_character_)
```

Every arm swallows to `NA`. On the guard side, `viol_split()` requires only that `run` exists and
carries `datetime_utc`; `viol_keys()` whitelists `inputs` only; §6's producer/guard drift check
(`drift1`) reads `cl[[5]][["inputs"]]` and so cannot see `run` at all. So a `run.toolchain` of
`{terra: null, sf: null, gdal: null}` — or a future edit dropping the argument entirely — passes
everything.

That reproduces #64's own root symptom in miniature: *the one difference that explained the
divergence was the one thing provenance did not carry.* Low severity, because terra and sf must be
installed for step 3 to run at all, so NA is close to unreachable — but the field is diagnostic-only
and currently unguarded, which is the state that lets it rot unnoticed.

Cheapest close: one line in `viol_split` or a new §5c assertion that
`fp_toolchain()` returns three non-NA character scalars.

---

## Checked and clean — stated so the questions in the brief are closed with measurements

| Question | Answer |
|---|---|
| `parts <- c(parts, ...)` in a loop at scale | **Non-issue, measured.** Largest raster in `data/` is `lchl/.../classified_2020.tif`, 7566×7037 = **53.2M cells → 15 blocks, 2.85 s total**. A hypothetical 100k-row raster is ~200 iterations of copying a ≤200-element character vector: microseconds. |
| `on.exit(terra::readStop(r))` if `readStart` throws | **Correct.** `readStart` runs *before* the registration, so a throw there leaves nothing registered and nothing that needs stopping. A later throw in `readValues` is covered. |
| Multi-layer raster (`nlyr > 1`) | **Correct.** `readValues(r, row=, nrows=)` returns **all layers** (measured: 40 values for a 2-layer 4×5 block). A change confined to layer 2 moves the digest (measured TRUE). `nlyr` is carried in `dim(r)` in the header. |
| 0-row raster | Loop body never runs, `parts` stays `character(0)`, returns a header-only digest with no error. Unreachable for a GeoTIFF. |
| Path that is a directory | `file.exists`/`file.size` pass, then `terra::rast()` **throws loudly** (`[rast] cannot open this file as a SpatRaster`). Correct direction — it aborts rather than recording a wrong digest. |
| `sprintf("%.9f", ...)` — enough precision? could it lose a real difference? | **Enough.** At UTM/Albers magnitudes (~1e6–6e6 m) the double ULP is ~1e-9, so 9 decimals is already at the representable limit; nothing physically meaningful is lost, and `%f` rounding is correctly-rounded on both glibc and macOS libc so it does not itself churn. |
| Does the header actually enter the final hash? | **Yes** — `paste0(hdr, "|", paste(parts, collapse=""))` is what gets digested. Verified behaviourally: two rasters with identical values and a different extent produce different digests. |
| `terra::crs(r, describe=TRUE)$code` NA/NULL? | Returns length-1 `NA_character_` (never `character(0)`, never NULL), so the zero-length-drop trap does not fire. See finding 3 for the collision it does cause. |
| `sf::sf_extSoftVersion()` — is `sf::` enough? | **Yes**, measured: returns `3.8.5` with `"package:sf" %in% search()` FALSE. Called only from steps 2 and 3, both of which use sf directly. |
| Does `toolchain` in `run` violate `RUN_FIELDS` / `viol_split`? | **No.** `RUN_FIELDS` governs what may appear in `inputs`; `toolchain` is not in `inputs`, `run` still carries `datetime_utc`, and the two key sets do not intersect. Confirmed by the guard running green on the real `data/neexdzii/provenance.json`, whose `run` is `{datetime_utc, toolchain}`. |
| `else bad(...)` when terra unavailable | **Correct direction** — a skip is reported as a failure, per the repo's own rule. |
| Rename completeness / stale records | **Complete.** No live code references `classified_sha256` or `fp_file_sha256` (only planning/archive prose and a log). The only `provenance.json` on disk is `data/neexdzii/`, and it has **already been re-run** — it carries `classified_content_sha256` and `run.toolchain`. So no area is left failing the newly-tightened `viol_keys`/`viol_coverage`, and the forward-only surprise the brief asked about does not exist yet. |
| Full guard run | `Rscript scripts/floodplain_lcc/provenance-check.R neexdzii` → **PASS**, exit 0, all sections including §5c, §6 drift, §7 real area. |

## CLAUDE.md "Code Check Conventions" sweep

Walked the checklist against the diff. Relevant hits are findings 1 (*a fixture set that cannot
reach the failure mode*, *restore the bug and confirm the test fails*), 4 (*`on.exit()` at a
script's top level never fires*), 5 (*a drift guard must cover every input it claims to*), and 2/3
(*cache keys must cover every output-affecting input* — inverted: the digest is affected by inputs
outside the raster). No hits on: shell guards, pathspec magic, quoting/heredocs, `wc -l`/`grep -c`,
`git add -A`, secrets, `$` partial matching (the new code uses `$code` on a **data.frame**, which is
exact-match, and the parsed-JSON reads all use `[[`), zero-length values in row builders, or
`system2()` quoting.

