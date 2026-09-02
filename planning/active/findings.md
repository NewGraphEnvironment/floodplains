# Findings — nge:landcover_key hashes the GeoTIFF container, not the landcover (#64)

## Issue context

Filed from #63's cross-machine leg. Two machines, identical commit, same database, same GDAL 3.8.5:

```
2017  geometry_identical=TRUE  cells=28291615  differing=0  bytes m1=969220 m4=979248  delta=+10028
2020  geometry_identical=TRUE  cells=28291615  differing=0  bytes m1=981296 m4=991324  delta=+10028
2023  geometry_identical=TRUE  cells=28291615  differing=0  bytes m1=974362 m4=984390  delta=+10028
```

## Measured during planning, before any code was written

### The premise in #64's body is wrong

`classified_sha256` is **not** published. `stac_floodplains_bc/scripts/fp_provenance.R:50` maps
`landcover_key = list(section = "landcover", path = c("inputs", "item_hash"))` — a hash over the
resolved **STAC item ids**. Its own comment explains the choice was made over drift's
`stac_cache_key()`, and never revisited to use the raster digest.

So the state is worse than #64 says: the published key is the field #33 established *cannot* detect
an upstream in-place reprocess, and the field that could is unpublished and broken. CLAUDE.md
already says `nge:landcover_key` should be the raster digest — that sentence has never been true.

Consequence for scope: fixing the digest here does **not** change what is published. A second,
separate change in the publish layer is needed, and it is that repo's call (one-way coupling).

### The root cause is not tag 42112 — and it is not the terra version either

Tag 42112 (`GDAL_METADATA`, 382 vs 5396 bytes) is the visible symptom and the reason the *file*
hashes differ. The reason a naive content hash **also** differed is one layer down. My first
explanation attributed it to the terra versions:

```
m1 terra 1.9.34  readValues -> storage.mode "double",  324,891 missing cells are NaN
m4 terra 1.9.11  readValues -> storage.mode "integer", 324,891 missing cells are NA_integer_
```

**That attribution was wrong, and review caught it.** The trigger is the PAM `.aux.xml` sidecar.
Measured on ONE terra (1.9.34), the SAME file, changing nothing but whether GDAL may read it:

```
GDAL_PAM_ENABLED unset -> storage.mode "double",  NaN 324891, NA 324891
GDAL_PAM_ENABLED=NO    -> storage.mode "integer", NaN 0,      NA 324891
```

m1's raster directory carries `classified_2017.tif.aux.xml`; the m4 copies were `scp`'d without it.
So the two sides differed in the sidecar, not demonstrably in terra — and whether the version
matters *as well* was never isolated. The fix is unchanged and the case for it is stronger: the
storage type depends on who has opened the file.

`storage.mode(v) <- "double"` converts `NA_integer_` to `NA_real_` but leaves `NaN` as `NaN`, so the
vectors remain non-`identical()` and the digests still disagree — on all three years. Only
`v[is.na(v)] <- NA_real_` collapses the two, because `is.na()` is TRUE for NaN.

**This is invisible to every value comparison.** `all.equal()` says TRUE, `sum(va != vb, na.rm=TRUE)`
is 0, and `sum(is.na(va)) == sum(is.na(vb))`. Only `identical()` separates them.

### Prototype measurements

| property | result |
|---|---|
| cost | 1.16 s for 28,291,615 cells; stable on re-run |
| cross-machine, 2017/2020/2023 | content digest **agrees**; file digest disagrees |
| one cell value +1 | digest moves |
| one cell → nodata | digest moves |
| same block size twice | identical |
| 512 vs 256 block rows | different — `block_rows` is part of the contract |

### An offline fixture reaches the failure

40×50 raster, written twice, second time with `terra::metags()` set to the NetCDF-ish attributes the
older terra carries through: file size 2080 → 2444, bytes differ, `terra::values()` identical, content
digest agrees. So the regression guard needs no second machine — which matters because the only way
to run this check otherwise is to have two differently-provisioned laptops to hand. (Not "because it
must run in CI": this repo has no `.github/workflows` at all. Review caught that premise.)

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `[readValues] the file is not open for reading` | `terra::readValues()` needs `terra::readStart()` first; pair with `readStop()` via `on.exit` |
| First content-digest prototype disagreed across machines anyway | `storage.mode()` alone is not enough — NaN vs NA_real_ survives it. Both normalizations required |

## Implementation results

### The declared-key drift check caught the rename before anything else did

Renaming the producer's field without touching the guard made `provenance-check.R` go red
immediately and name both sides:

```
FAIL  landcover producer writes exactly the 19 declared key(s)
      -- differs: classified_sha256, classified_content_sha256
```

That is #33's key-drift guard doing exactly its job, and it is the reason a rename here is a
*deliberate* change rather than a silent redefinition.

### Cross-machine agreement, on the real evidence

Not a fixture — m4's actual rasters from the #63 run:

```
2017  old file-hash agrees: FALSE   NEW content-hash agrees: TRUE
2020  old file-hash agrees: FALSE   NEW content-hash agrees: TRUE
2023  old file-hash agrees: FALSE   NEW content-hash agrees: TRUE
```

The digests written by the live step-3 run match the ones computed independently from m1's rasters
(`sha256:1938fb7d…` for 2017), so the wiring and the prototype agree.

### The toolchain is recorded and is NOT hashed

```
landcover run keys : ['datetime_utc', 'toolchain']
run.toolchain      : {"gdal": "3.8.5", "sf": "1.1.2", "terra": "1.9.34"}
toolchain in inputs: False
```

That placement is the whole point: a terra version legitimately differs between two machines that
agree on every cell, so hashing it would reintroduce the churn this issue removes, one field over.

Parity unmoved after the re-run: **673.5 km / 142.8 km² / 770.0 ha**.

### A dead assertion in my own guard, caught by running it

The first draft of §5c asserted `block_rows` changes the digest by comparing 512 against 256 — on a
**40-row** fixture, where both yield a single block and the two are equal by construction. It went
red immediately. Replaced with a direct assertion on the default
(`identical(formals(...)$block_rows, 512L)`) plus a comparison at 8 vs 16 rows, which actually
splits a 40-row raster. Same class as the fixture rule in `code-check.md`, met in a test written
specifically to honour it.

## Errors Encountered (cont.)

| Error | Resolution |
|-------|------------|
| §5c `premise: block_rows really does change the digest` FAILED | 512 and 256 both exceed a 40-row fixture, so the premise was unreachable. Assert the default directly; compare block sizes that actually split the raster |

## Review round 1 — what two independent reviewers found, and what held up

Both a Plan review and a code-check reviewer independently found the same critical gap, which is
the strongest signal either produced.

### The guard passed with the fix deleted

`provenance-check.R` §5c writes two fixtures and reads **both with the same terra in the same
process**, so the storage-type axis never varies. Measured by the reviewer and reproduced here:
delete both normalization lines from the digest and all nine §5c assertions still pass. The two
lines the whole issue turns on had no test, in a file whose header says a guard nobody has seen go
red is decoration.

Closed by factoring the normalization into `fp_norm_block()` and adding **§5d**, which asserts the
property on plain vectors with no GDAL at all — `c(1L, 2L, NA_integer_, 4L)` against
`c(1, 2, NaN, 4)`, the two shapes `readValues()` actually returns.

### And then restoring the defect found a second thing

With §5d in place, deleting `v[is.na(v)] <- NA_real_` fails 3 checks. Deleting
`storage.mode(v) <- "double"` fails **none** — because assigning a double promotes the vector
whatever the index selects, so the NA line coerces an integer vector even when there is nothing to
assign:

```
vi <- c(1L,2L,NA_integer_,4L); vi[is.na(vi)] <- NA_real_   -> storage.mode "double"
vn <- c(1L,2L,3L);             vn[is.na(vn)] <- NA_real_   -> storage.mode "double"  (empty index!)
```

So the cast is genuinely subsumed. Rather than pretend two independent guards exist, the code says
so: the cast stays because the invariant should not depend on a subassignment side effect (change
the sentinel to a logical `NA` and the coercion vanishes with it), and §5d carries an assertion for
the case where it *would* be load-bearing.

### Other findings, all fixed

| finding | resolution |
|---|---|
| `on.exit()` at a script's top level never fires — the §5c fixture dir leaked | explicit `unlink()` + an assertion that it happened. **The same trap was live and pre-existing in §5b**, leaving `TZ=UTC` set for the rest of the process; fixed too |
| `digest()` hashes R's serialization, and `serializeVersion` is a settable option | pinned to `2L`. Version 3 embeds the native encoding, making the hash locale-dependent |
| `crs(describe=TRUE)$code` is `NA` for a CRS with no authority code, so two different CRSs collide | fall back to the full WKT rather than hashing the string `"NA"` |
| `run$toolchain` had **no drift protection** — §6 parses only the `inputs` argument | `KEYS_TOOLCHAIN` asserted in `viol_split` for raster-writing sections, with four must-fail cases including "present but entirely NA" |
| the §1 perturb check had degraded to "adding an arbitrary key moves the hash" (`$<-` creates a missing key) | `[[` plus an existence premise asserted first |
| the memory comment cited neexdzii (226 MB), the smallest whole-WSG case | cites BULK: 11552 × 14651 = 169.3M cells, 1.35 GB whole, ~47 MB per block |
| GEOS and PROJ come free from the same `sf_extSoftVersion()` call | added; the floodplain section's outputs *are* geometry |
| "a guard that cannot run in CI is an absent guard" | this repo has no CI at all. Premise dropped |
| `floodplain_<scenario>.tif` has no content digest — pinned only by parameters | out of scope, **filed as #70** so the deferral is a decision |

### A fixture that could not reach its own property, twice

The first §5c draft asserted `block_rows` changes the digest by comparing 512 against 256 — on a
**40-row** raster, where both are a single block. Then the first §5d all-NA toolchain fixture set
three members while `KEYS_TOOLCHAIN` had five, so the "missing member" arm fired and the "entirely
NA" arm it named was never reached. Both went red immediately and both are now derived from the key
set rather than written out.

## Errors Encountered (cont.)

| Error | Resolution |
|-------|------------|
| Guard green with the fix deleted | The fixture varied the container but not the storage type. Assert the property on vectors, not through a raster |
| `must-fail: an all-NA toolchain` FAILED | Fixture listed 3 of 5 keys, so a different arm fired first. Derive the fixture from `KEYS_TOOLCHAIN` |
| `provenance-check.R neexdzii` exit 1 after adding geos/proj | The on-disk record predated the new keys. A change to code that writes data is not done until the data is reconciled — re-ran steps 2,3 |

## Review round 2 — three findings, all inside round 1's fixes

### The serializeVersion guard could not fail

Round 1 added a check for the pin. It hardcoded `serializeVersion = 2L` in its **own** two
`digest()` calls, never touched `fp_raster_content_sha256()`, and compared two vectors §5d had
already proved identical. Measured: **strip the pin from the function and the guard stays green.**
Worse, it went red when the *other* normalization was removed — it was a third copy of the §5d
assertion wearing the pin's name.

Moved into §5c, where a raster fixture exists, and written to call the function across the option.
Verified both ways: green as shipped, **red with the pin stripped**.

The pin is genuinely load-bearing — measured on the production raster, `options(serializeVersion=3)`
moves an unpinned digest, because version 3 embeds the native encoding in the header.

### The toolchain guard did not close what its comment claimed

The comment said an edit dropping `toolchain = fp_toolchain()` "would be silent" and that the new
check closed it. It did not: §6's producer scanner reads only the `inputs` argument of
`fp_prov_set`, so removing the toolchain from **both** producers left the guard passing offline
*and* against the real area (whose on-disk record still carried the field from an earlier run).

Fixed by extending `prov_keys()` to take a `part` argument and scan `run` as well, then asserting
the derived set of raster-writing producers against `SECTIONS_WITH_RASTERS`. Exercised against both
shapes:

```
both producers stripped -> FAIL ... (found: NONE)
one producer stripped   -> FAIL ... (found: landcover)
```

### `SECTIONS_WITH_RASTERS` was a literal scope with no source of truth

It matched the producers by coincidence — the scope-by-coincidence shape `code-check.md` warns
about, in the guard for the one field that has no other protection. The `setequal` assertion above
now pins the literal against the parse, so the two cannot drift apart silently.

### And a limitation named rather than hidden

The WKT fallback for a code-less CRS is a ~1.4 kB, 38-line string PROJ renders, so it *could* make
the digest PROJ-version-dependent — the machine dependence this function exists to remove. It is
still strictly better than a silent collision between two different projections, and it is
unreachable for the rasters this pipeline writes (gdalcubes attaches an authority code; EPSG:32609
measured on every classified raster). Said so in the code, with the right fix if it ever is reached:
make it an error, not more text.

## Review round 3 — the same class, one axis over

Round 3 found five, and the headline one is the class round 2 had just fixed, **moved one axis**:

- Round 2 pinned `SECTIONS_WITH_RASTERS` (which sections write a toolchain) against the producers.
- Round 3 found `KEYS_TOOLCHAIN` on the **line above** was still matched by coincidence — nothing
  pinned it to `fp_toolchain()`. Measured: renaming `gdal` to `gdal_version`, or deleting it
  outright, left the **whole offline suite green**. `viol_split`'s "toolchain missing" arm only
  fires against a parsed file, so the loss surfaces only *after* an area has been re-run and the
  record written without it — and GDAL is the field the whole #64 investigation turned on.

This is the `gq#77` recurrence pattern in CLAUDE.md exactly: each fix correct, the class reappearing
one axis over. It terminated the same way — by enumerating the closed candidate set rather than
asserting completeness. `fp_prov_set`'s own `stopifnot` closes the section set to three, so the
candidate list now names all three and the residual is gone rather than documented.

| finding | resolution |
|---|---|
| `KEYS_TOOLCHAIN` unpinned | `setequal(names(fp_toolchain()), KEYS_TOOLCHAIN)`; verified red on both mutants |
| the digest coverage arm could not see ONE missing year — `all()` needs every year, and `unlist()` **drops a JSON null outright**, so even `any()` would miss what `fp_prov_write` writes | per-year arm plus a year-set check against `years`; four must-fail cases |
| `prov_sections_writing_toolchain()`'s **argument** was itself a hand-written literal — scope moved, not removed | candidate list now covers all three sections `fp_prov_set` accepts |
| the network-exemption check was a **no-op mutation** (the fixture never had a toolchain, so the mutant was `identical()` to the clean one) | exercise the exemption by moving the scope, which is the thing that grants it |
| "§5d fails three checks without it" — three is the both-deleted figure; the second line alone gives two | corrected, with all three figures stated |

Two of my own fixtures had to be corrected in the same pass, both the same shape: a `list(a=1, b=NULL)`
keeps its name (length 2), so a NULL-valued year is caught by the per-year arm and **not** the
year-set arm — the fixture was asserting the wrong arm's message. And the clean fixture's `years`
was `NA` while its digests named 2017/2023, so the new year-set assertion fired on the good input.

Final state: **74 assertions**, offline and against the real area, both green; cross-machine
agreement holds on m4's rasters; parity unmoved; `bridge-check`, `region_config-check` and
`gpkg_determinism-check` all unaffected.
