# Task: nge:landcover_key hashes the GeoTIFF container, not the landcover (#64)

## Problem

#63's cross-machine leg measured two machines running the identical commit against the same
database producing **identical rasters and different digests**: 28,291,615 cells per year, zero
differing, and a `classified_sha256` that disagreed. `fp_file_sha256()` hashes the GeoTIFF *file*,
so it moves with whatever the writer's version puts in the container.

## Two things found while planning that change what this issue is

**1. #64's stated consequence is wrong, and the real one is worse.** The body says
`classified_sha256` is "published as `nge:landcover_key`". It is not. The publisher maps
`landcover_key` to `inputs$item_hash` (`stac_floodplains_bc/scripts/fp_provenance.R:50`) — a hash
over the **STAC item ids**. #33 established that item ids cannot detect an upstream in-place
reprocess (io-lulc ids are `<tile>-<year>`, no `created`/`updated` property), and CLAUDE.md says
outright that `nge:landcover_key` *should* be the raster digest. So the published key is the one
field that structurally cannot fail, and the field that could is both unpublished and broken.

**2. The mechanism is not the metadata block.** #64 blamed TIFF tag 42112, the visible symptom. The
cause is one layer down and would have defeated a naive content hash too:

```
m1 (terra 1.9.34)  readValues -> double,  missing cells are NaN
m4 (terra 1.9.11)  readValues -> integer, missing cells are NA_integer_
storage.mode(v) <- "double"      # NA_integer_ -> NA_real_, but NaN stays NaN  -> STILL DIFFERS
v[is.na(v)] <- NA_real_          # collapses both to NA_real_                  -> agrees
```

Both normalizations are required, and the second is invisible unless compared with `identical()`
rather than `all.equal()` — 324,891 NaN-vs-NA cells in one 64-row block, `n differing = 0` by every
value comparison.

## Prototype, measured before planning

Block-streaming digest over values + geometry, `block_rows = 512`:

| property | result |
|---|---|
| cost | **1.16 s** for 28.3M cells (~3.5 s per scenario, against a ~10 min step 3) |
| cross-machine agreement, all 3 years | **TRUE** (file hash: FALSE) |
| one cell value changed | hash moves |
| one cell → nodata | hash moves |
| repeatable at fixed block size | TRUE |
| different block size | different hash — **`block_rows` is part of the contract** |

An **offline fixture reproduces the whole failure**: write a raster, re-write with extra
`terra::metags()`, bytes differ (2080 → 2444) while values do not. The regression guard needs no
second machine.

## Phase 1: Correct #64's body

- [x] Rewrite "Why it matters": `classified_sha256` is **not** published; the published
      `nge:landcover_key` is `item_hash`, which cannot detect the drift it exists to catch
- [x] Replace the tag-42112 root cause with the measured one (double/NaN vs integer/NA), keeping
      42112 as the symptom that surfaced it

## Phase 2: The content digest

- [x] `fp_provenance.R` — replace `fp_file_sha256()` (one call site) with
      `fp_raster_content_sha256(path, block_rows = 512L)`: header (`dim`, `ext`, EPSG, `res`) at
      fixed precision, then streamed 512-row blocks with **both** normalizations
- [x] Pin `block_rows` as a documented contract, not derived from `terra::blocks()` or free memory
- [x] `03_lulc_classify.R:126,408` — write it as **`classified_content_sha256`** (renamed, so an old
      and a new record are distinguishable and the declared-key drift check catches the change)

## Phase 3: Record the toolchain — in `run`, not `inputs`

- [x] Add `terra`, `sf` and GDAL (`sf::sf_extSoftVersion()[["GDAL"]]`) to the landcover and
      floodplain sections' **`run`** block
- [x] **Not `inputs`** — a version that legitimately differs between machines would reintroduce
      exactly the churn this issue removes. `run` is not hashed; this is #33's split doing its job

## Phase 4: Guards

- [x] Rename through `KEYS_LANDCOVER`, the §5 coverage check, and the two perturb fixtures together;
      confirm the declared-key drift check goes red first if any is missed
- [x] **New regression assertion**: two writes of identical values with different `metags()` — assert
      file hashes **differ** (the premise, inline) and content digests **agree** (the property)
- [x] Exercise it against the restored defect (swap back to `fp_file_sha256`) and watch it go red

## Phase 5: Verify against the real cross-machine evidence

- [x] `Rscript scripts/run_area.R neexdzii 3`, gated on the **in-band error count and output mtime**
- [x] New digest per year equals the digest of **m4's copy** of the same raster (still in scratchpad)
- [x] One changed cell and one cell→nodata each still move it
- [x] `provenance-check.R neexdzii` exits 0; parity unmoved (673.5 / 142.8 / 770.0)

## Phase 6: Downstream and close

- [x] File an issue in `stac_floodplains_bc` to point `nge:landcover_key` at the raster digest.
      **File it, do not wire it** — the coupling is one-way by design
- [x] CLAUDE.md: name which digest, and record that the published key is still `item_hash`
- [ ] Note in #64 that #33 is forward-only, so an area picks the new field up on its next run
- [ ] `/code-check` per commit, `/planning-archive`, `/gh-pr-push`

## Validation

- [x] Cross-machine agreement demonstrated against m4's actual rasters, not a fixture
- [x] Sensitivity demonstrated in both directions (value change, nodata change)
- [x] The new guard shown red against the restored defect
- [x] Parity unmoved; `provenance-check.R neexdzii` exits 0
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
