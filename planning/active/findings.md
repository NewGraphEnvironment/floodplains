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
