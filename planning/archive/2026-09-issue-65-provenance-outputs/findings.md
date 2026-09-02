# Findings — Provenance records the recipe, not the cake (#65)

## Pre-implementation measurements (2026-09-02)

Run before any code was written, in plan mode.

### fp_raster_content_sha256 generalizes to a SpatRaster

Probed on a 900x800 FLT8S fixture. `terra::readStart`/`readValues` work on an in-memory
SpatRaster. Path form, file-backed object and forced-in-memory object all produced
`sha256:f9ce11ec2004eb67...` — identical — and the path form matched the SHIPPED
`fp_raster_content_sha256()` byte for byte, so existing landcover digests stay valid.
720,000 cells digested in 0.04 s.

### The network key

`data/neexdzii/aquatic_network.gpkg` layer `streams_co3`: 1915 rows, `id_segment` integer
with no duplicates, `(blue_line_key, downstream_route_measure)` also unique (1915/1915),
no NAs in blk / drm / length_metre / id_segment, total 673.5 km (the parity contract).
`blue_line_key` is integer (max 360886524), `downstream_route_measure` double.

`id_segment` is REJECTED as the key: CLAUDE.md flags it by name as numbered per watershed
group during generation, so a link rebuild that renumbers would churn the digest on every
BUILD and break the byte-stability the field exists to provide. The composite is FWA-native
and generation-independent, and is already what `cfg$subset` keys on.

### The floodplain raster is on a WARPED grid, unlike the landcover

`data/neexdzii/floodplain_co_ff04.tif`:

```
crs code : 3005                (an authority code — the WKT fallback is unreachable)
datatype : FLT4S               (chosen by terra; 02 pins no datatype, 03 pins INT1U)
res      : 30.469843851964     (warped, not a declared round grid)
ncell    : 6533563
```

Two consequences. The digest header formats res/ext at `%.9f`, which absorbs ULP-level warp
noise (a double near 30 has eps ~3.6e-15) but is a tolerance worth stating rather than
discovering. And an unpinned `datatype` means a terra version choosing a different on-disk
type changes the nodata sentinel and moves the digest with zero cell changes — the #64
failure with a new cause.

### The wrong config name is live

```
inputs.link_config_name = default
link_log.config_name    = bcfishpass
inputs.network_source   = GRAB from fresh
inputs.read_schema      = fresh
```

Exactly as the issue states. `link_log` carries 30 columns, `config_name` among them, so the
fix has a source in the record already being read wholesale.

### schema_version is asserted nowhere

`grep -rn schema_version scripts/` finds it only in `fp_provenance.R` (skeleton, unconditional
overwrite at `:58`) and in `provenance-check.R:221`s fixture. No property reads it. The
overwrite means a bump plus a partial re-run stamps the new version on old sections.

### flooded.sha_source puts a $HOME path inside hashed inputs

```
floodplain[co_ff02..06].inputs.flooded.sha_source =
  "unresolved (checkout at /Users/airvine/Projects/repo/flooded is 0.6.0, installed is 0.5.0)"
landcover[co_ff04].inputs.drift.sha_source =
  "unresolved (checkout at /Users/airvine/Projects/repo/drift is 0.10.0, installed is 0.8.0)"
```

A machine-local path AND a sibling repos checkout version, in the half that must be
byte-stable across machines. #63 measured this differing between m1 and m4 on otherwise
identical input. Left in place, the issues own cross-machine criterion cannot be read: a DEM
digest mismatch and a checkout mismatch produce the same observation.

### neexdzii and bulk are a free falsifiable test of the split

Both are `network_source: fresh` GRABs on watershed group **BULK**, species co, min_order 3.
neexdzii subsets to blk 360873822 @ drm 166030.4; bulk is the whole group. So their
PRE-subset (`inputs`) network digest must be IDENTICAL while their POST-subset (`outputs`)
digest must DIFFER. Nothing had to be built to get that test.

## Errors Encountered

| Error | Resolution |
|-------|------------|

## Issue context

Provenance records the recipe and not the cake. Two of the three sections hash a *description of
the job* and call it evidence about the result.

Found by #63's cross-machine run, which is also what made it concrete: that run proved the landcover
digest was measuring the wrong thing (#64, fixed), and the same audit showed the network and
floodplain sections measure nothing at all.

## The two holes

### 1. The network hashes nothing about the network it read

`fp_prov_set` hashes `value$inputs` only, and `link_log` is a **sibling** of `inputs` — so
`config_hash`, `run_uid` and `link_sha` are all excluded from the hash. What is left is:

```
watershed_group, species, min_order, network_source ("GRAB from fresh"), read_schema,
subset, link_config_name, link, fresh
```

None of it derived from the network's content. **Rebuild `fresh` with a different config, a
different link, or different data, and the network `inputs_hash` does not move.**

It also makes #63's headline cross-machine result weaker than it reads: `network[co3]`'s hash matched
on both machines, which is real and welcome — but it would have matched even if the two had read
different networks.

### 2. The floodplain is pinned only by its parameters

Every key in `KEYS_FLOODPLAIN` is a setting — `flood_factor`, `slope_threshold`, `max_width`,
`cost_threshold`, `dem_ncell`, `dem_res_m`, the `flooded` stamp. There is no measurement of the
output, and none of the input elevations.

Concretely: NRCan re-derives MRDEM. Same tile, same footprint, same 30 m grid, same 6,533,563 cells
— different heights. We re-run, get a different floodplain, and every character of the hashed string
is unchanged. `dem_ncell` and `dem_res_m` pin the **grid**, not the elevations.

The DEM URL is deliberately not recorded either (`fl_dem_aoi()` builds it in its body, and
`terra::sources()` on a cropped-and-projected return is `""` or a random temp path), so **nothing**
in the record describes the elevation data the published floodplain was cut from.

### 3. And a wrong value, independent of the hashing

`01_network_extract.R` hardcodes `link_config_name = "default"`. Correct on a BUILD, where this repo
deliberately uses the `default` bundle (natural barriers = gradient + falls only, `subsurfaceflow`
OFF). **Wrong on a GRAB**: the log row for BULK says `config_name = bcfishpass`, and every row in
`fresh.log` does. So the published provenance claims the NewGraph default methodology for a network
built under the config this repo explicitly chose not to use, and the two differ in the
natural-barrier set.

Nothing catches it: `provenance-check.R` asserts the key is *present*, which it is, and the
contradicting value sits in the same section of the same file one level down with nothing comparing
them. Corroborated independently — CLAUDE.md records a `default` build running a median **+0.7%**
over the bcfp reference; this GRAB measured **0.006%**, consistent with a bcfishpass build.

## The design this needs — a third block

**Superseded 2026-09-02:** an earlier version of this issue said to add the output digest to
`inputs`. That is wrong. A digest of the thing we produced is not an input to producing it, and
putting it in `inputs` makes `inputs_hash` cover the output — which muddles the single clean
question `inputs_hash` exists to answer.

Two different questions need two different hashes, and today we can answer neither for this section:

- *Did the ingredients change?* → a digest of the **input data**, inside `inputs`.
- *Did the answer change?* → a digest of what we **produced**, in a new `outputs` block.

You want both, because "same answer from different data" is worth knowing (the change fell outside
our AOI, or we got lucky) and "different answer" is worth knowing louder. One hash cannot tell you
which happened.

```
<section>[<key>]
  ├─ inputs        + a digest of the actual input DATA, not just its shape
  ├─ inputs_hash     "same ingredients?"
  ├─ outputs       ← NEW: a digest of what this step produced
  ├─ outputs_hash    "same answer?"
  └─ run             the run event; still not hashed
```

`outputs` is parallel to `inputs`: byte-stable, hashed into `outputs_hash`, and **never folded into
`inputs_hash`**.

### What this costs

Compute is noise. Measured under #64: **1.16 s for 28.3M cells**, against a step 2 that runs for
minutes and a step 3 for ten. A DEM or floodplain raster (~6.5M cells) is ~0.3 s.

The real cost is **one re-run of every area**, because provenance is forward-only — a field does not
exist until the step that writes it runs again. That is why the network and floodplain halves are ONE issue: separately they
would cost two full re-runs of every area for one idea. (#70 was folded in here on 2026-09-02.)

### What it touches

- `schema_version` bumps — this is a schema change, not an added field.
- `provenance-check.R`: a declared key set for `outputs`, the same present-with-null rule, and an
  assertion that no `outputs` key leaks into `inputs_hash` (the mirror of the existing split check).
- `provenance_ab-compare.R`: compare `outputs_hash` per entry alongside `inputs_hash`.
- `stac_floodplains_bc` reads this file and validates the **top-level** key set, so it needs to know
  a section can carry `outputs`. Its own change, filed there — the coupling stays one-way.

### Deliberately not in scope

**Vector outputs.** Hashing a raster is easy — fixed grid, read in order. A GeoPackage layer has no
guaranteed row order and carries floating-point coordinates, so a naive digest churns for reasons
that are not real changes. It needs a row-ordering and coordinate-precision contract that we would
then have to keep forever. Rasters first, vectors in their own issue.

## What to do

**(a) The wrong config name** — independent of the hashing, and cheap:

- [ ] On a GRAB, take `link_config_name` from the log row rather than asserting `"default"`, or
      record it as null with a note. Never state a config that was not used.
- [ ] Assert that `inputs.link_config_name` and `link_log$config_name` agree, or that the
      disagreement is recorded deliberately. A cross-check between two fields in one file costs
      nothing and is the only thing that would have caught it.

**(b) Network digests:**

- [ ] **Input.** Digest the accessible network actually read — the segment set keyed on
      `id_segment`, with `length_metre`. Promoting `config_hash`/`run_uid` out of `link_log` is not
      sufficient alone: that pins the build link recorded, not the rows we read, and on a GRAB those
      are separated by whatever happened to the schema in between. Promote them too if useful, but
      the digest is the thing that measures.
- [ ] **Output.** `streams_<sp><order>` is a **vector** layer, so it belongs with #72 unless the
      digest is taken over the same non-geometric key the input digest uses. Prefer input digest
      now, output digest with the vector work.

**(c) Floodplain digests:**

- [ ] **Input.** Digest the **cropped DEM** into `inputs` — the closest thing to a fingerprint of the
      elevation data this pipeline can obtain, and the field that would have caught an MRDEM
      re-derivation. It is Float32 with `NoData = nan`, so #64's NaN normalization matters more here
      than it did for the Int8 landcover.
- [ ] **Output.** Digest `floodplain_<scenario>.tif` into the new `outputs` block.

**(d) Shared:**

- [ ] `fp_raster_content_sha256()` must accept a **SpatRaster** as well as a path. `fl_dem_aoi()`
      returns the DEM in memory and never writes it, so a path-only digest would mean writing 6.5M
      cells out just to read them back — putting the encoder back in the path #64 removed.
      (Prototyped: path and in-memory forms give identical digests.)
- [ ] Declared key sets for `outputs`, each **pinned to its producer**. Every literal in that guard
      is now matched against the code that writes it (#64 closed the last one); a new one must not
      be the exception.
- [ ] Re-run every area. Forward-only — the fields do not exist until the steps run again.

## Verification

- Assert the floodplain `inputs_hash` moves when the DEM changes and not otherwise.
- GRAB the same watershed group from `fresh` and from `fresh_default` and assert the two network
  hashes **differ**. Those are genuinely different networks — CLAUDE.md records a median +0.7%
  divergence — and today they hash identically. That is the bug, stated as a test.
- Cross-machine, the way #63 did: the digests must agree on two machines that agree on the data.

Found by #63. #70 folded in here 2026-09-02 — it was the same idea seen from the floodplain side.
Vector outputs carved out as #72. Full measurement in
`scripts/floodplain_lcc/logs/20260902_provenance_live-verify_neexdzii.md`.

