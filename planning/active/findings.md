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

### The root cause is not tag 42112

Tag 42112 (`GDAL_METADATA`, 382 vs 5396 bytes) is the visible symptom and the reason the *file*
hashes differ. The reason a naive content hash **also** differed is one layer down:

```
m1 terra 1.9.34  readValues -> storage.mode "double",  324,891 missing cells are NaN
m4 terra 1.9.11  readValues -> storage.mode "integer", 324,891 missing cells are NA_integer_
```

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
digest agrees. So the regression guard needs no second machine — which matters, because a guard that
cannot run in CI is an absent guard.

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
